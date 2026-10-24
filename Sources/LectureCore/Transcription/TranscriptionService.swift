import Foundation
import AVFoundation
@preconcurrency import WhisperKit

public struct TranscriptionService: Transcribing {
    public typealias Decoder = @Sendable (URL, ModelLocation, DecodeRequest, @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> [TranscriptSegment]
    private let decoder: Decoder
    public init(decoder: @escaping Decoder = TranscriptionService.decodeLocal) { self.decoder = decoder }
    public func run(audioURL: URL, model: ModelLocation, progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> Transcript {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: audioURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw StorageFailure.invalidData("No recorded audio to transcribe.") }
        progress(.preparing)
        let segments = try await decoder(audioURL, model, DecodeRequest(), progress)
        try Task.checkCancellation()
        var previousStart = 0.0
        var valid: [TranscriptSegment] = []
        for segment in segments {
            guard segment.startSeconds.isFinite, segment.endSeconds.isFinite,
                  segment.startSeconds >= previousStart, segment.endSeconds >= segment.startSeconds,
                  segment.endSeconds <= duration + 1.0 / 16_000 else { throw StorageFailure.invalidData("Transcription returned invalid timestamps. Audio is retained for retry.") }
            previousStart = segment.startSeconds
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { valid.append(.init(startSeconds: segment.startSeconds, endSeconds: min(duration, segment.endSeconds), text: text)) }
        }
        return .init(modelIdentity: model.identity, segments: valid, noSpeech: valid.isEmpty)
    }
    public static func decodeLocal(_ audioURL: URL, _ model: ModelLocation, _ request: DecodeRequest, _ progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> [TranscriptSegment] {
        let cancellation = CancellationSignal()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            // Whisper can hallucinate text even with noSpeechProb == 0 on digital
            // silence. Check the actual signal before invoking the generative model.
            guard try hasSignal(audioURL) else { return [] }
            let engine = try await LocalWhisper.load(model)
            do {
                try Task.checkCancellation()
                progress(.processing(fraction: nil))
                let options = DecodingOptions(task: .transcribe, language: request.language, detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: false, noSpeechThreshold: 0.6, concurrentWorkerCount: 1, chunkingStrategy: .vad)
                let results = try await engine.transcribe(audioPath: audioURL.path, audioInputOptions: .init(channelMode: .specificChannel(0), audioLoadingMode: .incremental(chunkDurationSeconds: 60, maxBufferedChunks: 1)), decodeOptions: options) { _ in
                    cancellation.isCancelled ? false : nil
                }
                try Task.checkCancellation()
                let segments = results.flatMap(\.segments).filter { $0.noSpeechProb < 0.6 }.map {
                    TranscriptSegment(startSeconds: Double($0.start), endSeconds: Double($0.end), text: $0.text)
                }
                await engine.unloadModels()
                return segments
            } catch { await engine.unloadModels(); throw error }
        } onCancel: { cancellation.cancel() }
    }
    private static func hasSignal(_ url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000)!
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: 16_000)
            guard let channel = buffer.floatChannelData?[0] else { throw CaptureFailure.invalidAudio }
            for index in 0..<Int(buffer.frameLength) where abs(channel[index]) > 1.0 / 32_768 { return true }
        }
        return false
    }

}
private final class CancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
