import SwiftUI
import LectureCore

@MainActor @Observable final class CaptureDiagnostic {
    var status = "Ready to test Chrome audio capture."
    var recording = false
    var busy = false
    var level: Float = 0
    private let capture = ChromeCaptureService()
    private let store: SessionStore
    private var writer: SegmentWriter?
    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LectureRecorder/Sessions")
        store = SessionStore(root: root)
    }
    func start() async {
        guard !busy, !recording else { return }
        busy = true; defer { busy = false }
        guard ChromeCaptureService.hasPermission || ChromeCaptureService.requestPermission() else {
            status = CaptureFailure.permissionDenied.localizedDescription; return
        }
        do {
            let session = try await store.create()
            let writer = SegmentWriter(store: store)
            self.writer = writer
            let origin = try await capture.start { event in _ = writer.accept(event) }
            try await writer.begin(session: session, origin: origin) { [weak self] event in
                Task { @MainActor in
                    switch event {
                    case .progress(_, let level, _): self?.level = level
                    case .failed(let message): self?.status = message; await self?.stop()
                    }
                }
            }
            recording = true; status = "Recording Chrome. Play the lecture, then Finish."
        } catch { await capture.stop(); status = error.localizedDescription }
    }
    func stop() async {
        guard recording, !busy, let writer else { return }
        busy = true; recording = false
        let end = ChromeCaptureService.hostSeconds
        await capture.stop()
        do {
            let session = try await writer.finish(atHostSeconds: end)
            status = "Saved \(Int(session.duration)) seconds of audio. Capture test ready for review."
        } catch { status = error.localizedDescription }
        self.writer = nil; busy = false
    }
}

struct CaptureDiagnosticView: View {
    @State private var model = CaptureDiagnostic()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lecture Recorder").font(.largeTitle.bold())
            Text("Capture verification").font(.title3)
            Text(model.status).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(model.level)).accessibilityLabel("Chrome audio level")
            HStack {
                Button(model.recording ? "Finish" : "Start recording") { Task { if model.recording { await model.stop() } else { await model.start() } } }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
                Button("Open privacy settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
            }
            Text("Transcription is being added next. This test saves Chrome audio locally and does not use the microphone.").font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(width: 480)
    }
}
