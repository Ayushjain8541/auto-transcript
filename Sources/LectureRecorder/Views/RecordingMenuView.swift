import SwiftUI
import LectureCore
struct RecordingControls: View {
    let app: AppDependencies
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let coordinator = app.coordinator
            let now = ChromeCaptureService.hostSeconds
            let presentation = RecordingPresentation(modelReady: app.modelReady, permissionGranted: app.permissionGranted, phase: coordinator.phase, lastAudio: coordinator.lastAudibleHostSeconds, startedAt: coordinator.recordingStartedAt, now: now)
            VStack(alignment: .leading, spacing: 10) {
                Button(presentation.primaryTitle, systemImage: coordinator.phase == .recording ? "stop.fill" : "record.circle") { Task { await app.primaryAction() } }
                    .buttonStyle(.borderedProminent).disabled(!presentation.canStart && !presentation.canFinish)
                if coordinator.phase == .recording {
                    Text(Duration.seconds(max(0, now - (coordinator.recordingStartedAt ?? now))).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit()
                    ProgressView(value: Double(coordinator.audioLevel)).accessibilityLabel("Chrome audio level")
                }
                if presentation.quietHintVisible { Text("No audio detected for 30 seconds. Check that your lecture is playing in Chrome.").font(.callout).foregroundStyle(.orange) }
                if coordinator.phase == .transcribing {
                    ProgressView("Transcribing on this Mac…")
                    Button("Cancel transcription") { Task { await coordinator.cancelTranscription() } }
                    Text("Your audio is saved. You can close this window.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = coordinator.errorMessage { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
    }
}
struct RecordingMenuView: View {
    let app: AppDependencies
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lecture Recorder").font(.headline)
            RecordingControls(app: app)
            Divider()
            Button("Open library") { app.showSetup = false; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Setup") { app.showSetup = true; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Quit Lecture Recorder") { NSApp.terminate(nil) }
        }.padding(18).frame(width: 320)
    }
}
