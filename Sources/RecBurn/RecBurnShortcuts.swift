import AppIntents
import AppKit
import Foundation

// First-class Shortcuts / Siri / Spotlight actions for RecBurn.
//
// Control verbs (Record / Stop / Toggle) are thin shims over the app's own recburn:// URL — the
// ONE control seam. The value verbs turn the pipeline into a COMPOSABLE LINK (Sal's "chain, don't
// monolith"): "Get Latest RecBurn Recording" and "Stop Recording and Return File" hand the finished
// artifact + its manifest metadata to the next action as typed Shortcuts values, and "Publish to
// YouTube" consumes a file. So a civilian builds  Record → (stop) → Publish to YouTube  with no code.
//
// Honest grade: these COMPILE and RUN under `swift build`. Automatic discovery in Shortcuts.app
// relies on the App Intents metadata Xcode's build phase extracts; a raw-swiftc app may not
// auto-surface them. The `recburn-url` Run-Shell-Script path is the guaranteed fallback.

@MainActor private func openRecburn(_ host: String) {
    if let u = URL(string: "recburn://\(host)") { NSWorkspace.shared.open(u) }
}

// MARK: - Shared manifest access

extension RecBurnManifest {
    /// The single source of truth for the last finished recording (written by the app on stop).
    static func latest() -> RecBurnManifest? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        let url = support.appendingPathComponent("RecBurn/last.recburn.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecBurnManifest.self, from: data)
    }
    static var lastManifestURL: URL? {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?
            .appendingPathComponent("RecBurn/last.recburn.json")
    }
}

enum RecBurnIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noRecording, noFileURL, uploadFailed(String), timedOut
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noRecording: return "No finished RecBurn recording found yet."
        case .noFileURL: return "That input isn't a file on disk."
        case .uploadFailed(let m): return "YouTube upload failed: \(m)"
        case .timedOut: return "Timed out waiting for the recording to finish."
        }
    }
}

// MARK: - The recording as a chainable entity

struct RecBurnRecording: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "RecBurn Recording"
    static let defaultQuery = RecBurnRecordingQuery()

    var id: String   // the final video path

    @Property(title: "Video File") var file: IntentFile
    @Property(title: "Duration (seconds)") var durationSeconds: Double
    @Property(title: "Has Subtitles") var hasSubtitles: Bool
    @Property(title: "Subtitle File") var subtitleFile: IntentFile?
    @Property(title: "Microphone Recorded") var micRecorded: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\((id as NSString).lastPathComponent)",
                              subtitle: hasSubtitles ? "subtitled" : "no subtitles")
    }

    init(_ m: RecBurnManifest) {
        id = m.final
        file = IntentFile(fileURL: URL(fileURLWithPath: m.final))
        durationSeconds = m.lengthSeconds
        hasSubtitles = m.subtitled != nil
        subtitleFile = m.srt.map { IntentFile(fileURL: URL(fileURLWithPath: $0)) }
        micRecorded = m.micRecorded
    }
    init?(finalPath: String) {
        guard let m = RecBurnManifest.latest(), m.final == finalPath else { return nil }
        self.init(m)
    }
}

struct RecBurnRecordingQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RecBurnRecording] {
        identifiers.compactMap { RecBurnRecording(finalPath: $0) }
    }
    func suggestedEntities() async throws -> [RecBurnRecording] {
        RecBurnManifest.latest().map { [RecBurnRecording($0)] } ?? []
    }
}

// MARK: - Control verbs (thin URL shims)

struct StartRecBurnIntent: AppIntent {
    static let title: LocalizedStringResource = "Record"
    static let description = IntentDescription("Start recording screen + system audio (+ mic / webcam / burned subtitles per your RecBurn settings).")
    @MainActor func perform() async throws -> some IntentResult { openRecburn("start"); return .result() }
}

struct StopRecBurnIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stop the current recording and run the finalize → flatten → transcribe → burn pipeline.")
    @MainActor func perform() async throws -> some IntentResult { openRecburn("stop"); return .result() }
}

struct ToggleRecBurnIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Recording"
    static let description = IntentDescription("Start a recording if idle, or stop and finalize it if one is running.")
    @MainActor func perform() async throws -> some IntentResult { openRecburn("toggle"); return .result() }
}

// MARK: - Value verbs (make the pipeline a chainable link)

struct GetLatestRecBurnRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest RecBurn Recording"
    static let description = IntentDescription("Return the most recently finished recording — its video file, duration, subtitle file and flags — as chainable values.")
    func perform() async throws -> some IntentResult & ReturnsValue<RecBurnRecording> {
        guard let m = RecBurnManifest.latest(), FileManager.default.fileExists(atPath: m.final) else {
            throw RecBurnIntentError.noRecording
        }
        return .result(value: RecBurnRecording(m))
    }
}

struct StopAndReturnRecBurnRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording and Return File"
    static let description = IntentDescription("Stop the current recording, wait for the full pipeline to finish, and return the finished video + metadata for the next action (e.g. Publish to YouTube).")
    func perform() async throws -> some IntentResult & ReturnsValue<RecBurnRecording> {
        let lastURL = RecBurnManifest.lastManifestURL
        let before = lastURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date } ?? .distantPast
        await MainActor.run { openRecburn("stop") }
        for _ in 0..<1200 {   // up to ~20 min; transcription/burn can be slow
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard let url = lastURL,
                  let mt = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                  mt > before, let m = RecBurnManifest.latest(),
                  FileManager.default.fileExists(atPath: m.final) else { continue }
            return .result(value: RecBurnRecording(m))
        }
        throw RecBurnIntentError.timedOut
    }
}

// MARK: - Publish to YouTube

enum YouTubePrivacy: String, AppEnum {
    case unlisted, `private`, `public`
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "YouTube Privacy"
    static let caseDisplayRepresentations: [YouTubePrivacy: DisplayRepresentation] = [
        .unlisted: "Unlisted", .private: "Private", .public: "Public"]
}

enum YouTubeCategory: String, AppEnum {   // rawValue = YouTube categoryId
    case scienceTech = "28", education = "27", gaming = "20", peopleBlogs = "22"
    case entertainment = "24", howtoStyle = "26", music = "10", filmAnimation = "1"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "YouTube Category"
    static let caseDisplayRepresentations: [YouTubeCategory: DisplayRepresentation] = [
        .scienceTech: "Science & Technology", .education: "Education", .gaming: "Gaming",
        .peopleBlogs: "People & Blogs", .entertainment: "Entertainment",
        .howtoStyle: "Howto & Style", .music: "Music", .filmAnimation: "Film & Animation"]
}

struct PublishToYouTubeIntent: AppIntent {
    static let title: LocalizedStringResource = "Publish RecBurn Recording to YouTube"
    static let description = IntentDescription("Upload a recording to YouTube via recburn-youtube and return the video URL. Requires a one-time Google OAuth client (see README).")

    @Parameter(title: "Video File") var file: IntentFile
    @Parameter(title: "Subtitle File (.srt)") var subtitleFile: IntentFile?
    @Parameter(title: "Title") var videoTitle: String?
    @Parameter(title: "Description") var videoDescription: String?
    @Parameter(title: "Category", default: .scienceTech) var category: YouTubeCategory
    @Parameter(title: "Privacy", default: .unlisted) var privacy: YouTubePrivacy

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let url = file.fileURL else { throw RecBurnIntentError.noFileURL }
        let out = try Self.upload(path: url.path, captions: subtitleFile?.fileURL?.path,
                                  title: videoTitle, description: videoDescription,
                                  category: category.rawValue, privacy: privacy.rawValue)
        return .result(value: out)
    }

    /// Locate + run recburn-youtube; return the video URL it prints on its last line.
    static func upload(path: String, captions: String?, title: String?, description: String?,
                       category: String, privacy: String) throws -> String {
        let fm = FileManager.default
        var candidates: [String] = []
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent().path { candidates.append(dir + "/recburn-youtube") }
        candidates += ["/usr/local/bin/recburn-youtube", "\(NSHomeDirectory())/.local/bin/recburn-youtube",
                       "\(NSHomeDirectory())/bin/recburn-youtube", "\(NSHomeDirectory())/work/apple/bin/recburn-youtube"]
        guard let tool = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            throw RecBurnIntentError.uploadFailed("recburn-youtube not found")
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool)
        var args = ["--file", path, "--privacy", privacy, "--category", category]
        if let t = title, !t.isEmpty { args += ["--title", t] }
        if let d = description, !d.isEmpty { args += ["--description", d] }
        if let c = captions, !c.isEmpty { args += ["--captions", c] }
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { throw RecBurnIntentError.uploadFailed(error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        let urlLine = text.split(separator: "\n").last { $0.contains("youtu") }.map(String.init)
        guard p.terminationStatus == 0, let link = urlLine?.trimmingCharacters(in: .whitespaces) else {
            throw RecBurnIntentError.uploadFailed("exit \(p.terminationStatus)")
        }
        return link
    }
}

// MARK: - Registry

struct RecBurnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecBurnIntent(),
                    phrases: ["Record with \(.applicationName)", "\(.applicationName) record"],
                    shortTitle: "Record", systemImageName: "record.circle")
        AppShortcut(intent: StopRecBurnIntent(),
                    phrases: ["Stop \(.applicationName)", "Stop \(.applicationName) recording"],
                    shortTitle: "Stop Recording", systemImageName: "stop.circle")
        AppShortcut(intent: ToggleRecBurnIntent(),
                    phrases: ["Toggle \(.applicationName) recording"],
                    shortTitle: "Toggle Recording", systemImageName: "record.circle")
        AppShortcut(intent: StopAndReturnRecBurnRecordingIntent(),
                    phrases: ["Stop \(.applicationName) and return the file"],
                    shortTitle: "Stop and Return File", systemImageName: "square.and.arrow.up")
        AppShortcut(intent: GetLatestRecBurnRecordingIntent(),
                    phrases: ["Get the latest \(.applicationName) recording"],
                    shortTitle: "Get Latest Recording", systemImageName: "film")
        AppShortcut(intent: PublishToYouTubeIntent(),
                    phrases: ["Publish \(.applicationName) recording to YouTube"],
                    shortTitle: "Publish to YouTube", systemImageName: "arrow.up.forward.square")
    }
}
