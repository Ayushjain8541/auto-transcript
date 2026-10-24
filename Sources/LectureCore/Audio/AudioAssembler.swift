import Foundation
import AVFoundation

public enum AudioAssembler {
    public static func assemble(_ session: Session, at folder: URL) async throws -> URL {
        guard !session.segments.isEmpty else { throw StorageFailure.invalidData("No recorded audio is available.") }
        let directory = folder.appendingPathComponent("processing")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("\(UUID().uuidString).partial")
        let destination = temporary.deletingPathExtension().appendingPathExtension("wav")
        do {
            let writer = try PCMFile(url: temporary)
            for segment in session.segments {
                try Task.checkCancellation()
                guard segment.relativePath == "audio/\(segment.index)-\(segment.startFrame).wav" else { throw StorageFailure.invalidData("Invalid segment path.") }
                while writer.frames < segment.startFrame {
                    let count = min(160_000, segment.startFrame-writer.frames)
                    try writer.append(Array(repeating: Float(0), count: Int(count))[...])
                }
                let source = try AVAudioFile(forReading: folder.appendingPathComponent(segment.relativePath))
                guard source.length == segment.frameCount, source.fileFormat.sampleRate == 16_000, source.fileFormat.channelCount == 1 else { throw StorageFailure.invalidData("Audio segment has changed.") }
                let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 16_000)!
                while source.framePosition < source.length {
                    try Task.checkCancellation()
                    try source.read(into: buffer)
                    let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                    try writer.append(samples[...])
                }
            }
            try writer.close()
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
}
