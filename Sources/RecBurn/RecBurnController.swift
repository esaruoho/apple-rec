import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import AVFoundation

/// Typed handoff emitted by the engine (`screen-audio-record` writes `<base-stem>.recburn.json`).
/// Reading this — not scraping the engine's "✓ …" prose off stdout — is how the app learns which
/// artifact is final. Mirror of `RecBurnManifest` in screen-audio-record.swift.
struct RecBurnManifest: Codable {
    var schema: String
    var base: String
    var flat: String?
    var subtitled: String?
    var srt: String?
    var final: String
    var lengthSeconds: Double
    var micRecorded: Bool
}

/// Menu-bar front-end for the PROVEN terminal pipeline: it just drives
/// `~/work/apple/bin/screen-audio-record` — the same ScreenCaptureKit binary that
/// `rec`/`recburn` use (native screen+system-audio, native webcam PiP circle, mic track,
/// YouTube flatten, and --burn = on-device Apple Speech subtitles). No ffmpeg/whisper here.
@MainActor
@Observable
final class RecBurnController {
    enum PiPCorner: String, CaseIterable, Identifiable {
        case topLeft = "Top Left", topRight = "Top Right", bottomLeft = "Bottom Left", bottomRight = "Bottom Right"
        var id: String { rawValue }
        var flag: String {   // screen-audio-record --pip-corner value
            switch self {
            case .topLeft: return "tl"; case .topRight: return "tr"
            case .bottomLeft: return "bl"; case .bottomRight: return "br"
            }
        }
    }

    var isRecording = false
    var isProcessing = false          // after Stop: flatten / transcribe / burn inside the recorder
    var processingNote = ""
    var lastStatus = ""               // persistent result of the last recording (shown in menu)
    var lastLog: URL?                 // per-recording log with the recorder's full output
    var needsPermission = false

    // Live permission state for the verifier window.
    var screenGranted = false
    var micGranted = false
    var camGranted = false
    var allGranted: Bool { screenGranted && micGranted && camGranted }

    // Persisted across launches via UserDefaults (see init + didSet).
    var recordMic = true            { didSet { defaults.set(recordMic, forKey: "recordMic") } }
    var webcamPiP = false           { didSet { defaults.set(webcamPiP, forKey: "webcamPiP") } }
    var burnSubtitles = false       { didSet { defaults.set(burnSubtitles, forKey: "burnSubtitles") } }
    var pipCorner: PiPCorner = .bottomRight { didSet { defaults.set(pipCorner.rawValue, forKey: "pipCorner") } }
    /// Burn a live "CLICKS: n" counter into the video. Its corner is chosen independently
    /// of the webcam's — you generally want them in OPPOSITE corners, so they share the
    /// PiPCorner type but never the value.
    var clickCounter = false        { didSet { defaults.set(clickCounter, forKey: "clickCounter") } }
    var clicksCorner: PiPCorner = .topLeft { didSet { defaults.set(clicksCorner.rawValue, forKey: "clicksCorner") } }
    var lastOutput: URL?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onStateChange: (() -> Void)?   // AppKit status item/menu refresh hook
    private func notify() { onStateChange?() }

    private var recProc: Process?
    private var outURL: URL?

    /// Locate the screen-audio-record engine — bundled inside RecBurn.app first (the shipping
    /// case), then common install dirs, then the dev source tree. No hardcoded single path.
    private func resolveRecorder() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            candidates.append(dir + "/screen-audio-record")          // bundled next to RecBurn
        }
        candidates += ["/usr/local/bin/screen-audio-record",
                       "\(NSHomeDirectory())/bin/screen-audio-record",
                       "\(NSHomeDirectory())/work/apple/bin/screen-audio-record"]  // dev fallback
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    init() {
        if defaults.object(forKey: "recordMic") != nil { recordMic = defaults.bool(forKey: "recordMic") }
        webcamPiP = defaults.bool(forKey: "webcamPiP")
        burnSubtitles = defaults.bool(forKey: "burnSubtitles")
        if let c = defaults.string(forKey: "pipCorner"), let corner = PiPCorner(rawValue: c) { pipCorner = corner }
        clickCounter = defaults.bool(forKey: "clickCounter")
        if let c = defaults.string(forKey: "clicksCorner"), let corner = PiPCorner(rawValue: c) { clicksCorner = corner }
        killStaleCaptures()
    }

    /// A prior force-quit could orphan the recorder (holding screen/webcam). On a fresh launch
    /// nothing is legitimately recording, so reap any leftover.
    private func killStaleCaptures() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-9", "-f", "screen-audio-record.*recburn"]
        try? p.run(); p.waitUntilExit()
    }

    private func downloads() -> URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private func env() -> [String: String] {
        // The recorder shells out to rec-subtitle → speech-transcribe (swiftc/xcrun) and ffmpeg.
        // A /Applications GUI app has a bare PATH, so give children a real one.
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (e["PATH"] ?? "")
        return e
    }

    func startRecording() {
        defer { notify() }
        guard !isRecording, let dir = downloads() else { return }
        guard let recorder = resolveRecorder() else {
            lastStatus = "⚠️ Engine 'screen-audio-record' not found — run ./build.sh"; return
        }
        // Screen Recording must be granted before ScreenCaptureKit starts.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess(); needsPermission = true
            return
        }
        needsPermission = false

        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let out = dir.appendingPathComponent("recburn-\(df.string(from: Date())).mov")

        var args = ["--system-audio", "--auto-flatten"]
        if recordMic { args.append("--mic") }
        if webcamPiP { args += ["--pip", "--pip-corner", pipCorner.flag] }
        if clickCounter { args += ["--clicks", "--clicks-corner", clicksCorner.flag] }
        if burnSubtitles {
            args.append("--burn")
            let bias = loadVocab()          // user-editable vocabulary → whisper --initial_prompt
            if !bias.isEmpty { args += ["--burn-prompt", bias] }
        }
        args += ["--out", out.path]

        let p = Process()
        p.executableURL = URL(fileURLWithPath: recorder)
        p.arguments = args
        p.environment = env()
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        p.standardInput = Pipe()          // keep its 'q'-reader from grabbing anything; we stop via SIGINT
        do { try p.run() }
        catch { lastStatus = "⚠️ Could not start recorder: \(error.localizedDescription)"; return }

        recProc = p; outURL = out; lastOutput = out
        lastStatus = ""; isRecording = true
        NSLog("recburn: recording → %@ (%@)", out.path, args.joined(separator: " "))
        Task.detached { await self.pump(pipe, base: out, args: args, proc: p) }
    }

    /// Route a `recburn://` URL — the single control seam shared by Shortcuts, the Services /
    /// Quick Action, Siri, a Loupedeck/Stream Deck button, and plain `open recburn://…`.
    /// Hosts: `toggle` · `start` · `stop`. On start/toggle, query items override the toggles for
    /// this recording: `?mic=0|1&pip=0|1&burn=0|1&corner=tl|tr|bl|br&clicks=0|1&clickcorner=tl|tr|bl|br`.
    func handleURL(_ url: URL) {
        let host = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func flag(_ n: String) -> Bool? {
            q.first { $0.name == n }?.value.map { ["1", "true", "yes", "on"].contains($0.lowercased()) }
        }
        NSLog("recburn: URL %@ (host=%@)", url.absoluteString, host)
        switch host {
        case "stop":
            if isRecording { stopRecording() }
        case "start", "toggle":
            if isRecording { if host == "toggle" { stopRecording() }; return }
            if let m = flag("mic") { recordMic = m }
            if let p = flag("pip") { webcamPiP = p }
            if let b = flag("burn") { burnSubtitles = b }
            if let c = q.first(where: { $0.name == "corner" })?.value,
               let corner = PiPCorner.allCases.first(where: { $0.flag == c.lowercased() }) { pipCorner = corner }
            if let v = q.first(where: { $0.name == "clicks" })?.value { clickCounter = (v as NSString).boolValue }
            if let c = q.first(where: { $0.name == "clickcorner" })?.value,
               let corner = PiPCorner.allCases.first(where: { $0.flag == c.lowercased() }) { clicksCorner = corner }
            startRecording()
        default:
            NSLog("recburn: ignoring unknown URL host '%@'", host)
        }
    }

    func stopRecording() {
        guard isRecording, let p = recProc else { return }
        isRecording = false
        isProcessing = true
        processingNote = burnSubtitles ? "Finalizing + transcribing…" : recordMic ? "Finalizing (flatten)…" : "Finalizing…"
        p.interrupt()                     // SIGINT = Ctrl-C: recorder finalizes (flatten/transcribe/burn) then exits
        notify()
    }

    /// Read the recorder's output live into a log, and when it exits pick the final artifact + report.
    /// nonisolated → the blocking read runs on a background thread (NOT the main actor), so the
    /// menu-bar app never beachballs while recording. UI updates hop back via MainActor.run.
    nonisolated private func pump(_ pipe: Pipe, base: URL, args: [String], proc: Process) async {
        let fh = pipe.fileHandleForReading
        var lines = ["$ screen-audio-record " + args.joined(separator: " "), ""]
        var buf = Data()
        // Typed handoff: the recorder writes a `<stem>.recburn.json` manifest and prints its path
        // as `RECBURN-MANIFEST: …`. We read that (authoritative). The path scraping below is only a
        // fallback for a pre-manifest engine binary.
        var manifestPath: String?
        var subbedPath: String?, flatPath: String?, savedPath: String?
        func movIn(_ s: String) -> String? {
            guard let start = s.firstIndex(of: "/"), let m = s.range(of: ".mov") else { return nil }
            return String(s[start..<m.upperBound])
        }
        while true {
            let chunk = fh.availableData
            if chunk.isEmpty { break }     // EOF → recorder exited
            buf.append(chunk)
            while let nl = buf.firstIndex(of: 0x0a) {
                let line = String(data: buf[buf.startIndex..<nl], encoding: .utf8) ?? ""
                buf.removeSubrange(buf.startIndex...nl)
                lines.append(line)
                if line.hasPrefix("RECBURN-MANIFEST:") {
                    manifestPath = String(line.dropFirst("RECBURN-MANIFEST:".count)).trimmingCharacters(in: .whitespaces)
                }
                else if line.contains("subtitled:") { subbedPath = movIn(line) }
                else if line.contains("YouTube version:") { flatPath = movIn(line) }
                else if line.contains("✓ saved") { savedPath = movIn(line) }
                // Clean stage label (NOT the raw recorder line — that got chopped mid-word to "audi").
                let low = line.lowercased()
                var note: String?
                if low.contains("making youtube") || low.contains("flatten") { note = "Flattening (YouTube version)…" }
                else if low.contains("transcrib") { note = "Transcribing subtitles…" }
                else if low.contains("burning") || low.contains("subtitled:") { note = "Burning subtitles…" }
                if let note { await MainActor.run { if self.isProcessing { self.processingNote = note } } }
            }
        }
        proc.waitUntilExit()
        let rc = proc.terminationStatus
        lines.append(""); lines.append("[recorder exit \(rc)]")

        let fm = FileManager.default
        func exists(_ s: String?) -> URL? { (s.map { URL(fileURLWithPath: $0) }).flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil } }

        // Tier 1 — the typed manifest (authoritative). Read the sentinel-reported path, then the
        // deterministic sidecar. Decoding a struct is immune to any wording change in the engine.
        var final: URL?
        var gotSubs = false
        var manifest: RecBurnManifest?
        let sidecar = base.deletingPathExtension().path + ".recburn.json"
        for candidate in [manifestPath, sidecar].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: candidate)),
                  let m = try? JSONDecoder().decode(RecBurnManifest.self, from: data) else { continue }
            lines.append("[manifest] \(m.schema) final=\((m.final as NSString).lastPathComponent) mic=\(m.micRecorded) len=\(Int(m.lengthSeconds))s")
            let f = URL(fileURLWithPath: m.final)
            if fm.fileExists(atPath: f.path) { final = f; gotSubs = m.subtitled != nil; manifest = m }
            break
        }

        // Tier 2/3 — fallback for a pre-manifest engine: the printed "✓ …" paths, then a dir-scan.
        if final == nil {
            final = exists(subbedPath) ?? exists(flatPath) ?? exists(savedPath)
            if final == nil {
                let stem = base.deletingPathExtension().lastPathComponent
                let siblings = (try? fm.contentsOfDirectory(at: base.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
                let mine = siblings.filter { $0.lastPathComponent.hasPrefix(stem) && $0.pathExtension == "mov" }
                final = mine.first(where: { $0.lastPathComponent.contains("subtitled") })
                    ?? mine.first(where: { $0.lastPathComponent.contains("flat") })
                    ?? (fm.fileExists(atPath: base.path) ? base : nil)
            }
            gotSubs = final?.lastPathComponent.contains("subtitled") ?? false
        }
        lines.append("[final] \(final?.lastPathComponent ?? "none")")

        // AVAssetExportSession writes audio-track-FIRST, which makes QuickTime show it as "audio"
        // and breaks YouTube (plays only track 1). Remux the chosen file video-first if needed.
        if let f = final { ensureVideoFirst(f, log: &lines) }

        // Persist the completed manifest to ONE stable location so the chainable App Intents
        // ("Get Latest RecBurn Recording" / Publish to YouTube) can return the artifact + metadata
        // without guessing which file is newest. Written only on a real result.
        if let f = final {
            var mm = manifest ?? RecBurnManifest(schema: "recburn/1", base: base.path, flat: nil,
                subtitled: gotSubs ? f.path : nil, srt: nil, final: f.path,
                lengthSeconds: 0, micRecorded: args.contains("--mic"))
            mm.final = f.path      // reflect any video-first remux (same path; defensive)
            if let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let dir = support.appendingPathComponent("RecBurn", isDirectory: true)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? enc.encode(mm) {
                    try? data.write(to: dir.appendingPathComponent("last.recburn.json"))
                    lines.append("[last] wrote last.recburn.json")
                }
            }
        }

        let wantedSubs = args.contains("--burn")
        let logURL = base.deletingPathExtension().appendingPathExtension("log")
        try? lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)

        let result = final
        let gotSubsFinal = gotSubs      // immutable snapshot for the @Sendable MainActor closure
        await MainActor.run {
            self.isProcessing = false; self.processingNote = ""
            self.lastLog = logURL
            if let result = result {
                self.lastOutput = result
                self.lastStatus = gotSubsFinal ? "✅ Saved with subtitles: \(result.lastPathComponent)"
                    : wantedSubs ? "⚠️ Saved, but subtitles FAILED — open log"
                    : "✅ Saved: \(result.lastPathComponent)"
                NSWorkspace.shared.open(result)
            } else {
                self.lastStatus = "⚠️ No recording produced (exit \(rc)) — open log"
            }
            NSLog("recburn: done rc=%d → %@", rc, self.lastOutput?.path ?? "none")
            self.notify()
        }
    }

    /// If a .mov has its audio track first (AVAssetExportSession does this), remux it video-first
    /// (fast, stream-copy) so QuickTime shows the video and YouTube keeps the picture.
    nonisolated private func ensureVideoFirst(_ url: URL, log: inout [String]) {
        let ffprobe = "/opt/homebrew/bin/ffprobe", ffmpeg = "/opt/homebrew/bin/ffmpeg"
        guard FileManager.default.isExecutableFile(atPath: ffprobe),
              FileManager.default.isExecutableFile(atPath: ffmpeg) else { return }
        let pr = Process(); pr.executableURL = URL(fileURLWithPath: ffprobe)
        pr.arguments = ["-v", "error", "-select_streams", "0", "-show_entries", "stream=codec_type", "-of", "csv=p=0", url.path]
        let pp = Pipe(); pr.standardOutput = pp; pr.standardError = Pipe()
        try? pr.run()
        let first = (String(data: pp.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        pr.waitUntilExit()
        guard first == "audio" else { return }        // already video-first — nothing to do
        log.append("[fix] \(url.lastPathComponent) was audio-first → remuxing video-first")
        let tmp = url.deletingPathExtension().path + ".vf.mov"
        let mux = Process(); mux.executableURL = URL(fileURLWithPath: ffmpeg)
        mux.arguments = ["-y", "-i", url.path, "-map", "0:v", "-map", "0:a?", "-c", "copy", "-movflags", "+faststart", tmp]
        let mp = Pipe(); mux.standardError = mp; mux.standardOutput = mp
        try? mux.run(); _ = mp.fileHandleForReading.readDataToEndOfFile(); mux.waitUntilExit()
        if FileManager.default.fileExists(atPath: tmp), mux.terminationStatus == 0 {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.moveItem(atPath: tmp, toPath: url.path)
            log.append("[fix] remuxed video-first OK")
        } else {
            try? FileManager.default.removeItem(atPath: tmp)
            log.append("[fix] remux failed (exit \(mux.terminationStatus)) — leaving original")
        }
    }

    // MARK: - Permissions (drives the verifier window)

    func refreshPermissions() {
        screenGranted = CGPreflightScreenCaptureAccess()
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        camGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if screenGranted { needsPermission = false }
        notify()
    }
    func requestScreen() { CGRequestScreenCaptureAccess(); refreshPermissions() }
    func requestMic() { AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in self.refreshPermissions() } } }
    func requestCam() { AVCaptureDevice.requestAccess(for: .video) { _ in Task { @MainActor in self.refreshPermissions() } } }
    func openScreenSettings() { openPrivacy("Privacy_ScreenCapture") }
    func openMicSettings()    { openPrivacy("Privacy_Microphone") }
    func openCamSettings()    { openPrivacy("Privacy_Camera") }
    private func openPrivacy(_ anchor: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(u) }
    }
    func relaunch() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run(); NSApplication.shared.terminate(nil)
    }

    // MARK: - Editable transcription vocabulary (Whisper bias)

    private var vocabURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RecBurn", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("vocabulary.txt")
    }

    private let vocabSeed = """
    # RecBurn transcription vocabulary — one term or phrase per line.
    # These bias Whisper so it spells your words right instead of guessing
    # phonetically ("Esa Ruoho"→"SFO", "Tom Bearden"→"Tom Biernan").
    # Lines starting with # are ignored. Edit + save; the next recording uses it.
    Paketti
    Renoise
    Esa Ruoho
    Tom Bearden
    energy from the vacuum
    """

    private func seedVocabIfNeeded() {
        if !FileManager.default.fileExists(atPath: vocabURL.path) {
            try? vocabSeed.write(to: vocabURL, atomically: true, encoding: .utf8)
        }
    }

    /// Read the vocab file → a single comma-joined prompt string (skips blanks + # comments).
    private func loadVocab() -> String {
        seedVocabIfNeeded()
        guard let text = try? String(contentsOf: vocabURL, encoding: .utf8) else { return "" }
        let terms = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return terms.joined(separator: ", ")
    }

    func editVocab() { seedVocabIfNeeded(); NSWorkspace.shared.open(vocabURL) }

    func revealLast() { if let u = lastOutput { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
    func openLastLog() { if let u = lastLog { NSWorkspace.shared.open(u) } }

    func quit() {
        recProc?.interrupt()              // let an in-progress recording finalize
        killStaleCaptures()
        NSApplication.shared.terminate(nil)
    }
}
