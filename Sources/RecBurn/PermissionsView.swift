import SwiftUI
import AppKit

/// A live permission verifier: shows ✅/❌ per permission and lets the user grant each one,
/// re-checking automatically so the badges flip the moment a toggle is flipped in System Settings.
struct PermissionsView: View {
    let c: RecBurnController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RecBurn records your screen, microphone and webcam **locally** — nothing leaves this Mac. Grant the three below. Screen Recording needs a relaunch after granting.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            row("Screen Recording", granted: c.screenGranted,
                note: "Required to record the screen. After you grant it, click “Relaunch RecBurn”.",
                request: c.requestScreen, settings: c.openScreenSettings)
            row("Microphone", granted: c.micGranted,
                note: "Records your voice into the video and drives auto-subtitles.",
                request: c.requestMic, settings: c.openMicSettings)
            row("Camera", granted: c.camGranted,
                note: "Only needed if you use Webcam PiP.",
                request: c.requestCam, settings: c.openCamSettings)

            Divider()

            HStack(spacing: 12) {
                Button("Re-check now") { c.refreshPermissions() }
                Button("Relaunch RecBurn") { c.relaunch() }
                    .disabled(c.screenGranted)          // only needed while screen is still pending
                Spacer()
                if c.allGranted {
                    Label("All set — you're good to go", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).bold()
                } else {
                    Text("Waiting for grants…").foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { c.refreshPermissions(); NSApp.activate(ignoringOtherApps: true) }
        .task {
            // Live-poll so the badges update as the user toggles switches in System Settings.
            while !Task.isCancelled {
                c.refreshPermissions()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, granted: Bool, note: String,
                     request: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title2).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).bold()
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(granted ? "Granted" : "Not granted")
                    .font(.caption).foregroundStyle(granted ? .green : .orange)
                if !granted { Button("Request") { request() } }
                Button("Open Settings") { settings() }.buttonStyle(.link).font(.caption)
            }
            .frame(width: 130, alignment: .trailing)
        }
    }
}
