import Foundation
import LectureCore
@MainActor final class FakeCapture: CaptureService {
    var starts = 0; var stops = 0
    var stopDelay = false
    var stopping = false
    var releaseStop = false
    var failure: CaptureFailure?
    func start(onEvent: @escaping @Sendable (CaptureEvent) -> Void) async throws -> CaptureOrigin {
        starts += 1
        if let failure { throw failure }
        onEvent(.audio(.init(samples: Array(repeating: 0.2, count: 16_000), sampleRate: 16_000, channels: 1, presentationSeconds: 100)))
        return .init(hostSeconds: 100)
    }
    func stop() async {
        stops += 1; stopping = true
        while stopDelay && !releaseStop { try? await Task.sleep(for: .milliseconds(5)) }
    }
}
actor FakeModels: ModelManaging {
    let url: URL
    init(_ url: URL) { self.url = url }
    func installed() async throws -> ModelLocation? { .init(modelFolder: url, tokenizerFolder: url, identity: "fake") }
    func prepare(progress: @escaping @Sendable (ModelSetupProgress) -> Void) async throws -> ModelLocation { try await installed()! }
}
actor FakeTranscriber: Transcribing {
    var calls = 0; var entered = false
    let delay: Bool
    init(delay: Bool = false) { self.delay = delay }
    func run(audioURL: URL, model: ModelLocation, progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> Transcript {
        calls += 1; entered = true
        try expect(FileManager.default.fileExists(atPath: audioURL.path), "Saved audio must precede inference")
        if delay { try? await Task.sleep(for: .seconds(30)) }
        return .init(modelIdentity: model.identity, segments: [.init(startSeconds: 0, endSeconds: 0.5, text: "Hello")], noSpeech: false)
    }
}
@MainActor final class FakePower: PowerManaging {
    var held = false
    func acquire() throws { held = true }
    func release() { held = false }
}
@MainActor func registerCoordinatorTests() {
    Checks.add("Coordinator Finish twice and early capture persist once") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), capture = FakeCapture(), models = FakeModels(temp.url), transcriber = FakeTranscriber(), power = FakePower()
        let coordinator = SessionCoordinator(capture: capture, store: store, models: models, transcriber: transcriber, power: power, clock: { 101 }, writerFactory: { SegmentWriter(store: store, clock: { 100 }) })
        await coordinator.start(); try expect(coordinator.phase == .recording)
        await coordinator.start(); try expect(capture.starts == 1)
        async let first: Void = coordinator.finish()
        async let second: Void = coordinator.finish()
        _ = await (first, second)
        let calls = await transcriber.calls; try expect(calls == 1 && capture.stops == 1)
        let sessions = try await store.list(); try expect(sessions.count == 1 && sessions[0].state == .complete && sessions[0].capturedFrames == 16_000)
        try expect(coordinator.phase == nil && !power.held)
    }
    Checks.add("Coordinator cancellation waits and preserves audio") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), capture = FakeCapture(), transcriber = FakeTranscriber(delay: true), power = FakePower()
        let coordinator = SessionCoordinator(capture: capture, store: store, models: FakeModels(temp.url), transcriber: transcriber, power: power, clock: { 101 }, writerFactory: { SegmentWriter(store: store, clock: { 100 }) })
        await coordinator.start()
        let operation = Task { await coordinator.finish() }
        for _ in 0..<100 { if await transcriber.entered { break }; try await Task.sleep(for: .milliseconds(5)) }
        await coordinator.cancelTranscription(); await operation.value
        let sessions = try await store.list(); try expect(sessions.first?.state == .recorded)
        try expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent(sessions[0].id.uuidString + "/transcript.json").path))
        try expect(coordinator.phase == nil && !power.held)
    }
    Checks.add("Coordinator sleep ends recording and restore stays idle") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), capture = FakeCapture(), power = FakePower()
        let coordinator = SessionCoordinator(capture: capture, store: store, models: FakeModels(temp.url), transcriber: FakeTranscriber(), power: power, clock: { 101 }, writerFactory: { SegmentWriter(store: store, clock: { 100 }) })
        await coordinator.start(); await coordinator.interrupt(reason: "Mac went to sleep")
        await coordinator.restore()
        let sessions = try await store.list(); try expect(sessions.first?.state == .interrupted)
        try expect(capture.starts == 1 && !power.held && coordinator.phase == nil)
    }
    Checks.add("Coordinator sleep during finalization prevents inference") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), capture = FakeCapture(), transcriber = FakeTranscriber(), power = FakePower()
        capture.stopDelay = true
        let coordinator = SessionCoordinator(capture: capture, store: store, models: FakeModels(temp.url), transcriber: transcriber, power: power, clock: { 101 }, writerFactory: { SegmentWriter(store: store, clock: { 100 }) })
        await coordinator.start()
        let finishing = Task { await coordinator.finish() }
        for _ in 0..<100 { if capture.stopping { break }; try await Task.sleep(for: .milliseconds(5)) }
        await coordinator.interrupt(reason: "Mac went to sleep"); await coordinator.cancelTranscription()
        capture.releaseStop = true; await finishing.value
        let calls = await transcriber.calls; try expect(calls == 0)
        let saved = try await store.list(); try expect(saved.first?.state == .recorded || saved.first?.state == .interrupted)
        try expect(coordinator.phase == nil && !power.held)
    }
    Checks.add("Coordinator recovers transcript committed before state") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create(); session.state = .transcribing
        session.segments = [.init(index: 0, relativePath: "audio/0-0.wav", startFrame: 0, frameCount: 16_000)]; session.capturedFrames = 16_000
        let folder = await store.folder(for: session.id)
        try makeWAV(at: folder.appendingPathComponent("audio/0-0.wav"), frames: 16_000)
        try await store.save(session)
        let transcript = Transcript(modelIdentity: "test", segments: [.init(startSeconds: 0, endSeconds: 0.5, text: "Recovered")], noSpeech: false)
        try JSONEncoder().encode(transcript).write(to: folder.appendingPathComponent("transcript.json"))
        let recovered = try await store.recover(); try expect(recovered.first?.state == .complete)
    }
    Checks.add("Coordinator permission error releases job and power") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), capture = FakeCapture(), power = FakePower(); capture.failure = .permissionDenied
        let coordinator = SessionCoordinator(capture: capture, store: store, models: FakeModels(temp.url), transcriber: FakeTranscriber(), power: power, clock: { 101 }, writerFactory: { SegmentWriter(store: store, clock: { 100 }) })
        await coordinator.start()
        try expect(coordinator.errorMessage != nil && coordinator.phase == nil && !power.held)
    }
}
