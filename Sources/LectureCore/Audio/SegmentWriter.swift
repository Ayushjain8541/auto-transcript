import Foundation
import CoreMedia

public enum WriterEvent: Sendable {
    case progress(committedFrames: Int64, audioLevel: Float, lastAudibleHostSeconds: Double?)
    case failed(message: String)
}
public actor SegmentWriter {
    private let store: SessionStore
    private let clock: @Sendable () -> Double
    private nonisolated let queue = BoundedAudioQueue()
    private var session: Session?
    private var directory: URL?
    private var origin: Double = 0
    private var timeline = AudioTimeline()
    private var converter = PCMConverter()
    private var file: PCMFile?
    private var fileStart: Int64 = 0
    private var totalWritten: Int64 = 0
    private var lastAudible: Double?
    private var end: Double?
    private var sink: (@Sendable (WriterEvent) -> Void)?
    private var worker: Task<Session, Error>?
    public init(store: SessionStore, clock: @escaping @Sendable () -> Double = { CMClockGetTime(CMClockGetHostTimeClock()).seconds }) { self.store = store; self.clock = clock }
    public func begin(session: Session, origin: CaptureOrigin, onEvent: @escaping @Sendable (WriterEvent) -> Void) async throws {
        guard worker == nil else { throw StorageFailure.invalidData("Writer already started.") }
        var session = session; session.state = .recording
        try await store.save(session)
        self.session = session; self.origin = origin.hostSeconds; sink = onEvent
        directory = await store.folder(for: session.id).appendingPathComponent("audio")
        worker = Task { try await self.pump() }
    }
    public nonisolated func accept(_ event: CaptureEvent) -> Bool { queue.enqueue(event) }
    public func finish(atHostSeconds: Double) async throws -> Session {
        if end == nil { end = atHostSeconds }
        guard let worker else { throw StorageFailure.invalidData("Writer has not started.") }
        return try await worker.value
    }
    private func frame(at seconds: Double) throws -> Int64 {
        let value = max(0, (seconds-origin)*16_000)
        guard value.isFinite, value < Double(Int64.max) else { throw CaptureFailure.invalidAudio }
        return Int64(value.rounded())
    }
    private func pump() async throws -> Session {
        do {
            while true {
                while let event = queue.dequeue() {
                    switch event {
                    case .interrupted(let failure): throw failure
                    case .audio(let audio):
                        let level = audio.samples.map { abs($0) }.max() ?? 0
                        if level > 0.0001 { lastAudible = audio.presentationSeconds + audio.duration }
                        for block in try converter.convert(audio) { try await append(block) }
                        sink?(.progress(committedFrames: totalWritten, audioLevel: level, lastAudibleHostSeconds: lastAudible))
                    }
                }
                if let end {
                    for block in try converter.finish() { try await append(block) }
                    try await fill(to: frame(at: end))
                    try await commitSegment()
                    session!.state = .recorded
                    try await store.save(session!)
                    return session!
                }
                let watermark = try frame(at: clock()-0.5)
                // A large unobserved clock jump is suspension, not a normal quiet callback.
                if watermark - timeline.frameCount > 160_000 { throw StorageFailure.invalidData("Capture was suspended. Available audio was saved.") }
                try await fill(to: watermark)
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            try? await commitSegment()
            if session != nil {
                session!.state = .interrupted; session!.interruptionReason = error.localizedDescription
                try? await store.save(session!)
            }
            sink?(.failed(message: error.localizedDescription)); throw error
        }
    }
    private func append(_ block: PCMBlock) async throws {
        let start = try frame(at: block.startSeconds)
        try await fill(to: start)
        let data = try timeline.append(block.samples, atFrame: start)
        try await write(data)
    }
    private func fill(to target: Int64) async throws {
        while timeline.frameCount < target { try await write(timeline.silence(untilFrame: target)) }
    }
    private func write(_ samples: [Float]) async throws {
        var offset = 0
        while offset < samples.count {
            if file == nil {
                fileStart = totalWritten
                let index = session!.segments.count
                file = try PCMFile(url: directory!.appendingPathComponent("\(index)-\(fileStart).partial"))
            }
            let count = min(samples.count-offset, 160_000-Int(file!.frames))
            try file!.append(samples[offset..<offset+count])
            offset += count; totalWritten += Int64(count)
            if file!.frames == 160_000 { try await commitSegment() }
        }
    }
    private func commitSegment() async throws {
        guard let file, file.frames > 0 else { return }
        try file.close()
        let index = session!.segments.count
        let name = "\(index)-\(fileStart).wav"
        try FileManager.default.moveItem(at: file.url, to: directory!.appendingPathComponent(name))
        session!.segments.append(.init(index: index, relativePath: "audio/\(name)", startFrame: fileStart, frameCount: file.frames))
        session!.capturedFrames = totalWritten
        self.file = nil
        try await store.save(session!)
    }
}
