import SwiftUI
import LectureCore
struct SetupView: View {
    @Bindable var app: AppDependencies
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Set up Lecture Recorder", systemImage: "waveform").font(.title2.bold())
            Text("Record lecture audio from Chrome, then transcribe it on this Mac after you click Finish. Keep other Chrome tabs quiet.")
            VStack(alignment: .leading, spacing: 8) {
                Label("1. Allow Chrome audio capture", systemImage: app.permissionGranted ? "checkmark.circle.fill" : "circle")
                Text("macOS calls this Screen & System Audio Recording. The app saves audio only and does not use your microphone.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Allow capture") { app.grantPermission() }.disabled(app.permissionGranted)
                    Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                    Button("Check again") { app.refreshPermission() }
                }
                if !app.permissionGranted { Text("If you just changed permission in Settings, quit and reopen this app if macOS asks.").font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("2. Prepare the local speech model", systemImage: app.modelReady ? "checkmark.circle.fill" : "circle")
                Text("One free download of about 630 MB; allow 3 GB of free space for setup. After preparation, recording and transcription work offline. Audio stays on your Mac.").font(.callout).foregroundStyle(.secondary)
                if app.setupBusy {
                    switch app.setupProgress {
                    case .downloading(let completed, let total):
                        ProgressView(value: Double(completed), total: Double(total))
                        Text("Downloading \(completed / 1_000_000) of \(total / 1_000_000) MB").font(.caption)
                    default: ProgressView("Preparing for this Mac… This can take a few minutes.")
                    }
                }
                Button(app.modelReady ? "Verify model" : "Download and prepare") { Task { await app.prepare() } }.disabled(app.setupBusy || app.coordinator.phase != nil)
                if let error = app.setupError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            Text("English • One job at a time • Timestamps follow the recording, including playback pauses.").font(.caption).foregroundStyle(.secondary)
            if app.permissionGranted && app.modelReady { Button("Open library") { app.showSetup = false }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(maxWidth: 650, alignment: .leading)
    }
}
