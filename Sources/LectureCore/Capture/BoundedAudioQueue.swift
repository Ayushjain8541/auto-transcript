import Foundation

/// Lock protects only queue bookkeeping; callbacks never wait for disk IO.
public final class BoundedAudioQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Double
    private var queuedSeconds: Double = 0
    private var events: [CaptureEvent] = []
    private var failed = false
    public init(capacitySeconds: Double = 2) { capacity = capacitySeconds }
    public func enqueue(_ event: CaptureEvent) -> Bool {
        lock.withLock {
            guard !failed else { return false }
            if case .audio(let audio) = event {
                guard audio.duration.isFinite, audio.duration >= 0, audio.duration + queuedSeconds <= capacity + 0.000001 else {
                    failed = true; events.append(.interrupted(.overflow)); return false
                }
                queuedSeconds += audio.duration
            }
            if case .interrupted = event { failed = true }
            events.append(event); return true
        }
    }
    public func dequeue() -> CaptureEvent? {
        lock.withLock {
            guard !events.isEmpty else { return nil }
            let event = events.removeFirst()
            if case .audio(let audio) = event { queuedSeconds = max(0, queuedSeconds - audio.duration) }
            return event
        }
    }
}
