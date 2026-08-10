import AppKit
import SwiftUI
import CoreServices

// Pure AppKit status-item app so a single click on the red icon STOPS the recording.
// (MenuBarExtra always opens a menu on click — it can't do click-to-stop.)
@main
enum Main {
    static func main() {
        signal(SIGPIPE, SIG_IGN)              // writing to an exited child must not kill us
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let c = RecBurnController()
    private var serviceProvider: ServiceProvider?
    private var statusItem: NSStatusItem!
    private var permWindow: NSWindow?
    private weak var statusLineItem: NSMenuItem?   // the "⏳ Transcribing…" line, updated live
    private var menuTimer: Timer?

    // Register the recburn:// URL handler as early as possible so a launch triggered BY a URL
    // (Shortcut / Service / Siri / `open recburn://…`) is caught. This is the one control seam.
    func applicationWillFinishLaunching(_ note: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        c.handleURL(url)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.action = #selector(statusClicked)
            b.target = self
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        c.onStateChange = { [weak self] in self?.updateUI() }
        updateUI()

        // Services menu: "RecBurn: Toggle/Start/Stop Recording" (assignable to a global hotkey in
        // System Settings ▸ Keyboard ▸ Shortcuts ▸ Services). Routes through the same URL seam.
        serviceProvider = ServiceProvider(c: c)
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        c.refreshPermissions()
        if !c.allGranted { showPermissions() }   // pop the verifier until everything's granted
    }

    // Single click: recording → STOP immediately. Idle → open the settings menu.
    @objc private func statusClicked() {
        if c.isRecording { c.stopRecording(); return }
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)     // show it once…
        statusItem.menu = nil                    // …then detach so the next click hits the action again
    }

    private func updateUI() {
        statusItem.button?.title =
            c.needsPermission ? "⚠️" : c.isRecording ? "🔴" : c.isProcessing ? "⚙️" : "⚪️"
    }

    // While the menu is open during processing, refresh the status line live (Transcribing → Burning)
    // so the user doesn't have to close/reopen to see the stage change.
    func menuWillOpen(_ menu: NSMenu) {
        menuTimer?.invalidate()
        guard c.isProcessing else { return }
        menuTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let item = self.statusLineItem else { return }
                if self.c.isProcessing {
                    item.title = "⏳ \(self.c.processingNote.isEmpty ? "Finalizing…" : self.c.processingNote)"
                } else {
                    item.title = self.c.lastStatus.isEmpty ? "Done" : self.c.lastStatus
                    self.menuTimer?.invalidate()
                }
            }
        }
    }
    func menuDidClose(_ menu: NSMenu) { menuTimer?.invalidate(); menuTimer = nil }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        statusLineItem = nil
        func item(_ title: String, _ sel: Selector?, key: String = "", on: Bool? = nil, enabled: Bool = true) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.target = self
            if let on = on { it.state = on ? .on : .off }
            it.isEnabled = enabled
            return it
        }

        if c.isProcessing {
            let it = item("⏳ \(c.processingNote.isEmpty ? "Finalizing…" : c.processingNote)", nil, enabled: false)
            statusLineItem = it
            m.addItem(it)
        } else if c.needsPermission {
            m.addItem(item("⚠️ Grant Screen Recording, then relaunch", #selector(openPerms)))
        } else {
            m.addItem(item("Start Recording", #selector(start)))
        }

        if !c.lastStatus.isEmpty && !c.isRecording && !c.isProcessing {
            m.addItem(.separator())
            m.addItem(item(c.lastStatus, nil, enabled: false))
            m.addItem(item("Reveal last recording in Finder", #selector(reveal)))
            if c.lastLog != nil { m.addItem(item("Open last log", #selector(openLog))) }
        }

        m.addItem(.separator())
        m.addItem(item("Record Microphone", #selector(toggleMic), on: c.recordMic))
        m.addItem(item("Webcam PiP (circle)", #selector(togglePiP), on: c.webcamPiP))

        let pipMenu = NSMenu()
        for corner in RecBurnController.PiPCorner.allCases {
            let it = NSMenuItem(title: corner.rawValue, action: #selector(setCorner(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = corner; it.state = (c.pipCorner == corner) ? .on : .off
            it.isEnabled = c.webcamPiP
            pipMenu.addItem(it)
        }
        let pipParent = item("Webcam PiP Position", nil, enabled: c.webcamPiP)
        pipParent.submenu = pipMenu
        m.addItem(pipParent)

        m.addItem(item("Click Counter (CLICKS: n, burned in)", #selector(toggleClicks), on: c.clickCounter))

        // Its own corner, chosen separately from the webcam's — you usually want them in
        // opposite corners so the badge doesn't sit under the speaking head.
        let clickMenu = NSMenu()
        for corner in RecBurnController.PiPCorner.allCases {
            let it = NSMenuItem(title: corner.rawValue, action: #selector(setClicksCorner(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = corner; it.state = (c.clicksCorner == corner) ? .on : .off
            it.isEnabled = c.clickCounter
            clickMenu.addItem(it)
        }
        let clickParent = item("Click Counter Position", nil, enabled: c.clickCounter)
        clickParent.submenu = clickMenu
        m.addItem(clickParent)

        m.addItem(item("Burn Subtitles (on-device, on stop)", #selector(toggleBurn), on: c.burnSubtitles))

        m.addItem(.separator())
        m.addItem(item("Edit transcription vocabulary…", #selector(editVocab)))
        m.addItem(item("Permissions…", #selector(openPerms)))
        m.addItem(item("Quit recburn", #selector(quit), key: "q"))
        return m
    }

    // MARK: actions
    @objc private func start()      { c.startRecording() }
    @objc private func toggleMic()  { c.recordMic.toggle() }
    @objc private func togglePiP()  { c.webcamPiP.toggle() }
    @objc private func toggleBurn() { c.burnSubtitles.toggle() }
    @objc private func setCorner(_ sender: NSMenuItem) {
        if let corner = sender.representedObject as? RecBurnController.PiPCorner { c.pipCorner = corner }
    }
    @objc private func toggleClicks() { c.clickCounter.toggle() }
    @objc private func setClicksCorner(_ sender: NSMenuItem) {
        if let corner = sender.representedObject as? RecBurnController.PiPCorner { c.clicksCorner = corner }
    }
    @objc private func reveal()  { c.revealLast() }
    @objc private func openLog() { c.openLastLog() }
    @objc private func quit()    { c.quit() }
    @objc private func editVocab() { c.editVocab() }
    @objc private func openPerms() { showPermissions() }

    private func showPermissions() {
        if permWindow == nil {
            let host = NSHostingController(rootView: PermissionsView(c: c))
            let w = NSWindow(contentViewController: host)
            w.title = "RecBurn Permissions"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            permWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        permWindow?.center()
        permWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Backs the NSServices entries declared in Info.plist. Each no-input service method funnels into
/// the same recburn:// router, so the Services menu, Shortcuts, Siri and the URL all share one path.
@MainActor
final class ServiceProvider: NSObject {
    private let c: RecBurnController
    init(c: RecBurnController) { self.c = c }
    private func route(_ host: String) { if let u = URL(string: "recburn://\(host)") { c.handleURL(u) } }

    @objc func toggleRecording(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>?) { route("toggle") }
    @objc func startRecording(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>?) { route("start") }
    @objc func stopRecording(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>?) { route("stop") }
}
