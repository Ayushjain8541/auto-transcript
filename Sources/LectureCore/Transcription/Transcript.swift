import Foundation
public struct TranscriptSegment: Codable, Sendable, Equatable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String
    public init(startSeconds: Double, endSeconds: Double, text: String) { self.startSeconds = startSeconds; self.endSeconds = endSeconds; self.text = text }
}
public struct Transcript: Codable, Sendable, Equatable {
    public let modelIdentity: String
    public let segments: [TranscriptSegment]
    public let noSpeech: Bool
    public init(modelIdentity: String, segments: [TranscriptSegment], noSpeech: Bool) { self.modelIdentity = modelIdentity; self.segments = segments; self.noSpeech = noSpeech }
}
public enum TranscriptionProgress: Sendable { case preparing, processing(fraction: Double?) }
public protocol Transcribing: Sendable {
    func run(audioURL: URL, model: ModelLocation, progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> Transcript
}
public struct DecodeRequest: Sendable {
    public let language = "en"
    public let translate = false
}
