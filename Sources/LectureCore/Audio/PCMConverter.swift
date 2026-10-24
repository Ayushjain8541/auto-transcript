import Foundation
import AVFoundation

public struct PCMBlock: Sendable { public let startSeconds: Double; public let samples: [Float] }
public final class PCMConverter {
    private var converter: AVAudioConverter?
    private var rate: Double = 0
    private var origin: Double = 0
    private var expectedEnd: Double = 0
    private var outputFrames = 0
    public init() {}
    public func convert(_ audio: CapturedAudio) throws -> [PCMBlock] {
        guard audio.sampleRate.isFinite, (8_000...192_000).contains(audio.sampleRate), (1...32).contains(audio.channels),
              audio.samples.count % audio.channels == 0, audio.presentationSeconds.isFinite, audio.samples.allSatisfy(\.isFinite) else { throw CaptureFailure.invalidAudio }
        var blocks: [PCMBlock] = []
        if rate != audio.sampleRate || abs(audio.presentationSeconds - expectedEnd) > 0.002 {
            blocks += try finish()
            rate = audio.sampleRate; origin = audio.presentationSeconds; outputFrames = 0
            if rate != 16_000 {
                let input = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
                let output = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
                converter = AVAudioConverter(from: input, to: output)
                converter?.primeMethod = .none
                guard converter != nil else { throw CaptureFailure.invalidAudio }
            }
        }
        let count = audio.samples.count / audio.channels
        var mono = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            var sum: Float = 0
            for channel in 0..<audio.channels { sum += audio.samples[frame*audio.channels+channel] }
            mono[frame] = min(1, max(-1, sum / Float(audio.channels)))
        }
        expectedEnd = audio.presentationSeconds + Double(count)/rate
        if let converter {
            let input = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(count))!
            input.frameLength = AVAudioFrameCount(count)
            mono.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: count) }
            let output = try run(converter, input: input, capacity: Int(ceil(Double(count)*16_000/rate))+256)
            blocks += block(output)
        } else { blocks += block(mono) }
        return blocks
    }
    public func finish() throws -> [PCMBlock] {
        guard let current = converter else { return [] }
        let samples = try run(current, input: nil, capacity: 4096)
        converter = nil
        let remaining = max(0, Int(((expectedEnd-origin)*16_000).rounded()) - outputFrames)
        return block(Array(samples.prefix(remaining)))
    }
    private func block(_ samples: [Float]) -> [PCMBlock] {
        guard !samples.isEmpty else { return [] }
        let start = origin + Double(outputFrames)/16_000
        outputFrames += samples.count
        return [.init(startSeconds: start, samples: samples)]
    }
    private func run(_ converter: AVAudioConverter, input: AVAudioPCMBuffer?, capacity: Int) throws -> [Float] {
        let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(capacity))!
        let source = ConverterInput(input)
        let ending = input == nil
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if let next = source.take() { state.pointee = .haveData; return next }
            state.pointee = ending ? .endOfStream : .noDataNow; return nil
        }
        if status == .error { throw error ?? CaptureFailure.invalidAudio as NSError }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}

private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer?) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? { lock.withLock { let value = buffer; buffer = nil; return value } }
}
