import Foundation
import AVFoundation
import LectureCore
@MainActor func registerTranscriptionTests() {
    if ProcessInfo.processInfo.environment["LECTURE_REAL_TRANSCRIPTION"] == "1" {
        Checks.add("Transcription real Chrome session local engine") {
            let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LectureRecorder/Sessions")
            let store = SessionStore(root: root)
            guard let session = try await store.list().first else { throw CheckFailure(description: "No user capture found") }
            let folder = await store.folder(for: session.id)
            let audio = try await AudioAssembler.assemble(session, at: folder)
            defer { try? FileManager.default.removeItem(at: audio) }
            let modelRoot = workspace.appendingPathComponent("work/model-freeze")
            let manager = ModelManager(root: modelRoot, manifest: try .bundled())
            guard let model = try await manager.installed() else { throw CheckFailure(description: "Model not prepared") }
            let start = Date()
            let diagnosticService = TranscriptionService { audio, model, request, progress in
                let segments = try await TranscriptionService.decodeLocal(audio, model, request, progress)
                try JSONEncoder().encode(segments).write(to: workspace.appendingPathComponent("work/capture-raw-segments.json"))
                return segments
            }
            let result = try await diagnosticService.run(audioURL: audio, model: model) { _ in }
            try expect(!result.segments.isEmpty, "Expected speech in user capture")
            try JSONEncoder().encode(result).write(to: workspace.appendingPathComponent("work/capture-transcript.json"))
            print("Real transcription: \(session.duration)s audio, \(Date().timeIntervalSince(start))s inference, \(result.segments.count) segments")
            print(result.segments.prefix(3).map(\.text).joined(separator: " "))
        }
        Checks.add("Transcription real silence") {
            let temp = try TemporaryDirectory(); defer { temp.remove() }
            let audio = temp.url.appendingPathComponent("silence.wav"); try makeWAV(at: audio, frames: 16_000 * 15, sample: 0)
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("work/model-freeze")
            let result = try await TranscriptionService().run(audioURL: audio, model: .init(modelFolder: root.appendingPathComponent("model"), tokenizerFolder: root.appendingPathComponent("tokenizer"), identity: "real")) { _ in }
            try expect(result.noSpeech && result.segments.isEmpty)
        }
    }
    Checks.add("Transcription English options preserve silence offsets") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let audio = temp.url.appendingPathComponent("audio.wav"); try makeWAV(at: audio, frames: 16_000 * 15)
        let service = TranscriptionService { _, _, options, _ in
            try expect(options.language == "en" && !options.translate)
            return [.init(startSeconds: 12, endSeconds: 14, text: "Hello")]
        }
        let result = try await service.run(audioURL: audio, model: .init(modelFolder: temp.url, tokenizerFolder: temp.url, identity: "test")) { _ in }
        try expect(result.segments.first?.startSeconds == 12)
    }
    Checks.add("Transcription silence and invalid timestamps") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let audio = temp.url.appendingPathComponent("audio.wav"); try makeWAV(at: audio, frames: 16_000)
        let model = ModelLocation(modelFolder: temp.url, tokenizerFolder: temp.url, identity: "test")
        let empty = TranscriptionService { _, _, _, _ in [] }
        let result = try await empty.run(audioURL: audio, model: model) { _ in }
        try expect(result.noSpeech && result.segments.isEmpty)
        for bad in [TranscriptSegment(startSeconds: .nan, endSeconds: 0.5, text: "bad"), .init(startSeconds: -1, endSeconds: 0.5, text: "bad"), .init(startSeconds: 0.8, endSeconds: 0.3, text: "bad"), .init(startSeconds: 0, endSeconds: .infinity, text: "bad")] {
            let service = TranscriptionService { _, _, _, _ in [bad] }
            do { _ = try await service.run(audioURL: audio, model: model) { _ in }; throw CheckFailure(description: "Invalid timestamp accepted") }
            catch is StorageFailure { }
        }
    }
    Checks.add("Transcription clips model padding at the recording boundary") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let audio = temp.url.appendingPathComponent("audio.wav")
        try makeWAV(at: audio, frames: 16_001)
        let service = TranscriptionService { _, _, _, _ in [
            .init(startSeconds: 0.5, endSeconds: 29.98, text: "Last words"),
            .init(startSeconds: 2, endSeconds: 30, text: "Outside recording")
        ] }
        let result = try await service.run(audioURL: audio, model: .init(modelFolder: temp.url, tokenizerFolder: temp.url, identity: "test")) { _ in }
        try expect(result.segments == [.init(startSeconds: 0.5, endSeconds: 1.0000625, text: "Last words")])
    }
    Checks.add("Transcription removes silent hallucinations without shifting later speech") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let audio = temp.url.appendingPathComponent("audio.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000)!
            buffer.frameLength = 16_000
            // Audible, silence, very quiet speech, silence at EOF.
            for sample: Float in [0.25, 0, 2.0 / 32_768, 0] {
                for index in 0..<16_000 { buffer.floatChannelData![0][index] = sample }
                try file.write(from: buffer)
            }
        }
        let service = TranscriptionService { _, _, _, _ in [
            .init(startSeconds: 0, endSeconds: 1, text: "First"),
            .init(startSeconds: 1, endSeconds: 2, text: "Thank you"),
            .init(startSeconds: 2, endSeconds: 3, text: "Quiet speech"),
            .init(startSeconds: 3, endSeconds: 32.98, text: "Thank you")
        ] }
        let result = try await service.run(audioURL: audio, model: .init(modelFolder: temp.url, tokenizerFolder: temp.url, identity: "test")) { _ in }
        try expect(result.segments == [.init(startSeconds: 0, endSeconds: 1, text: "First"), .init(startSeconds: 2, endSeconds: 3, text: "Quiet speech")])
    }
    Checks.add("Transcription rejects descending segment timestamps") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let audio = temp.url.appendingPathComponent("audio.wav"); try makeWAV(at: audio, frames: 16_000)
        let service = TranscriptionService { _, _, _, _ in [.init(startSeconds: 0.5, endSeconds: 0.8, text: "First"), .init(startSeconds: 0.2, endSeconds: 0.4, text: "Bad order")] }
        do {
            _ = try await service.run(audioURL: audio, model: .init(modelFolder: temp.url, tokenizerFolder: temp.url, identity: "test")) { _ in }
            throw CheckFailure(description: "Invalid ordering accepted")
        } catch is StorageFailure { }
    }
    Checks.add("Transcription cancellation rejects late results") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let audio = temp.url.appendingPathComponent("audio.wav"); try makeWAV(at: audio, frames: 16_000)
        let service = TranscriptionService { _, _, _, _ in try? await Task.sleep(for: .milliseconds(20)); return [.init(startSeconds: 0, endSeconds: 0.5, text: "late")] }
        let task = Task { try await service.run(audioURL: audio, model: .init(modelFolder: temp.url, tokenizerFolder: temp.url, identity: "test")) { _ in } }
        task.cancel()
        do { _ = try await task.value; throw CheckFailure(description: "Cancelled transcript returned") } catch is CancellationError { }
    }
}
