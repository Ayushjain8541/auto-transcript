import Foundation

public struct AudioTimeline {
    public private(set) var frameCount: Int64 = 0
    private var synthesized: [Range<Int64>] = []
    public init() {}
    public mutating func append(_ samples: [Float], atFrame start: Int64) throws -> [Float] {
        guard start >= 0, start <= Int64.max - Int64(samples.count), start - frameCount <= 160_000 else { throw StorageFailure.invalidData("Capture timestamp discontinuity.") }
        let end = start + Int64(samples.count)
        if start < frameCount {
            for range in synthesized where range.lowerBound < end && range.upperBound > start {
                let lower = max(start, range.lowerBound); let upper = min(end, range.upperBound)
                if samples[Int(lower-start)..<Int(upper-start)].contains(where: { abs($0) > 0.0001 }) {
                    throw StorageFailure.invalidData("Audio arrived too late to save at its correct timestamp. Recording was interrupted.")
                }
            }
        }
        var output = silence(untilFrame: start)
        let skipped = min(samples.count, max(0, Int(frameCount - start)))
        output.append(contentsOf: samples.dropFirst(skipped))
        frameCount = max(frameCount, end)
        return output
    }
    /// Each call allocates at most one recovery segment, even after a long gap.
    public mutating func silence(untilFrame target: Int64) -> [Float] {
        let count = max(0, min(160_000, target - frameCount))
        guard count > 0 else { return [] }
        let start = frameCount; frameCount += count
        if let last = synthesized.last, last.upperBound == start { synthesized[synthesized.count-1] = last.lowerBound..<frameCount }
        else { synthesized.append(start..<frameCount) }
        return Array(repeating: 0, count: Int(count))
    }
}
