import Foundation
extension SessionStore {
    public func transcript(_ id: SessionID) throws -> Transcript? {
        let path = folder(for: id).appendingPathComponent("transcript.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let transcript = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: path))
        let session = try load(id)
        var previous = 0.0
        for segment in transcript.segments {
            guard segment.startSeconds.isFinite, segment.endSeconds.isFinite, segment.startSeconds >= previous, segment.endSeconds >= segment.startSeconds, segment.endSeconds <= session.duration + 1.0 / 16_000 else { throw StorageFailure.invalidData("Invalid saved transcript timestamps.") }
            previous = segment.startSeconds
        }
        return transcript
    }
    public func commitTranscript(_ transcript: Transcript, session: Session) throws {
        try Task.checkCancellation()
        try writeData(JSONEncoder().encode(transcript), folder(for: session.id).appendingPathComponent("transcript.json"))
        var completed = session; completed.state = .complete; completed.modelIdentity = transcript.modelIdentity
        try save(completed)
    }
}
