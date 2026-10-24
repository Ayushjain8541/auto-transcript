import Foundation
/// Owns callback shutdown; the capture service awaits this after stopping its stream.
public final class CaptureDelivery: @unchecked Sendable {
    public let queue = DispatchQueue(label: "LectureRecorder.audio", qos: .userInitiated)
    private let lock = NSLock()
    private var stopped = false
    private let sink: @Sendable (CaptureEvent) -> Void
    public init(_ sink: @escaping @Sendable (CaptureEvent) -> Void) { self.sink = sink }
    public func deliver(_ event: CaptureEvent) { lock.withLock { if !stopped { sink(event) } } }
    public func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { self.lock.withLock { self.stopped = true }; continuation.resume() }
        }
    }
}
