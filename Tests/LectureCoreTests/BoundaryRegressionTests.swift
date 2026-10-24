import Foundation
import LectureCore
private final class EventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func add() { lock.withLock { value += 1 } }
}
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 100.0
    func read() -> Double { lock.withLock { value } }
    func set(_ new: Double) { lock.withLock { value = new } }
}
@MainActor func registerBoundaryTests() {
    Checks.add("Capture shutdown drains queued delivery") {
        let count = EventCounter(), blocked = DispatchSemaphore(value: 0)
        let delivery = CaptureDelivery { _ in count.add() }
        delivery.queue.async { blocked.wait(); delivery.deliver(.interrupted(.streamStopped)) }
        let release = Task.detached { try? await Task.sleep(for: .milliseconds(50)); blocked.signal() }
        await delivery.finish(); await release.value
        try expect(count.count == 1, "Shutdown discarded the queued callback")
        delivery.deliver(.interrupted(.streamStopped)); try expect(count.count == 1)
    }
    Checks.add("Writer Finish boundary survives delayed capture teardown") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), clock = MutableClock()
        let session = try await store.create(), writer = SegmentWriter(store: store, clock: { clock.read() })
        try await writer.begin(session: session, origin: .init(hostSeconds: 100)) { _ in }
        try await writer.freeze(atHostSeconds: 101)
        clock.set(104)
        _ = writer.accept(.audio(.init(samples: Array(repeating: 0.2, count: 16_000 * 2), sampleRate: 16_000, channels: 1, presentationSeconds: 100)))
        try await Task.sleep(for: .milliseconds(50))
        let finished = try await writer.finish(atHostSeconds: 101)
        try expect(finished.capturedFrames == 16_000, "Teardown time or samples after Finish extended the recording")
        try expect(finished.state == .recorded)
    }
    Checks.add("Writer long playback pause preserves elapsed silence") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), clock = MutableClock()
        let writer = SegmentWriter(store: store, clock: { clock.read() }), session = try await store.create()
        try await writer.begin(session: session, origin: .init(hostSeconds: 100)) { _ in }
        clock.set(106); try await Task.sleep(for: .milliseconds(30))
        clock.set(112); try await Task.sleep(for: .milliseconds(30))
        _ = writer.accept(.audio(.init(samples: Array(repeating: 0.2, count: 1600), sampleRate: 16_000, channels: 1, presentationSeconds: 112)))
        let saved = try await writer.finish(atHostSeconds: 112.1)
        try expect(saved.state == .recorded && saved.capturedFrames == 193_600)
    }
    Checks.add("Writer forward timestamp jump interrupts before filling") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url), writer = SegmentWriter(store: store, clock: { 100 })
        let session = try await store.create()
        try await writer.begin(session: session, origin: .init(hostSeconds: 100)) { _ in }
        _ = writer.accept(.audio(.init(samples: Array(repeating: 0.2, count: 1600), sampleRate: 16_000, channels: 1, presentationSeconds: 160)))
        do { _ = try await writer.finish(atHostSeconds: 161); throw CheckFailure(description: "Forward suspension became recorded silence") } catch is StorageFailure { }
        let saved = try await store.load(session.id)
        try expect(saved.state == .interrupted && saved.capturedFrames < 160_000)
    }
}
