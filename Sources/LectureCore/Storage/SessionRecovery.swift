import Foundation
import AVFoundation

extension SessionStore {
    public func recover() throws -> [Session] {
        var sessions = try list()
        for index in sessions.indices {
            do {
                var session = sessions[index]
                let audioFolder = folder(for: session.id).appendingPathComponent("audio")
                let files = try FileManager.default.contentsOfDirectory(at: audioFolder, includingPropertiesForKeys: [.isSymbolicLinkKey])
                var recovered: [AudioSegment] = []
                var damaged = false
                for url in files where url.pathExtension == "wav" {
                    do {
                        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw StorageFailure.invalidData("Linked audio file.") }
                        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
                        guard parts.count == 2, let number = Int(parts[0]), number >= 0, let start = Int64(parts[1]), start >= 0 else { throw StorageFailure.invalidData("Invalid audio filename.") }
                        let file = try AVAudioFile(forReading: url)
                        guard file.length > 0, file.length <= 160_000, file.fileFormat.sampleRate == 16_000, file.fileFormat.channelCount == 1 else { throw StorageFailure.invalidData("Invalid audio format.") }
                        recovered.append(.init(index: number, relativePath: "audio/\(url.lastPathComponent)", startFrame: start, frameCount: file.length))
                    } catch { damaged = true }
                }
                recovered.sort { $0.startFrame < $1.startFrame }
                var previousEnd: Int64 = 0; var expectedIndex = 0
                for segment in recovered {
                    if segment.startFrame != previousEnd || segment.index != expectedIndex { damaged = true }
                    previousEnd = segment.startFrame + segment.frameCount; expectedIndex = segment.index + 1
                }
                if session.segments.contains(where: { saved in !recovered.contains(saved) }) { damaged = true }
                session.segments = recovered
                session.capturedFrames = recovered.map { $0.startFrame + $0.frameCount }.max() ?? 0
                if damaged {
                    session.state = .interrupted; session.interruptionReason = "Missing audio or damaged segments were found. Available audio was preserved at its original timestamps."
                } else if [.starting, .recording, .finalizing].contains(session.state) {
                    session.state = .interrupted; session.interruptionReason = "Recording was interrupted before it finished. Saved audio is available."
                } else if session.state == .transcribing {
                    session.state = .recorded
                }
                if !damaged, [.transcribing, .recorded, .complete, .transcriptionFailed].contains(session.state) {
                    do {
                        if let transcript = try transcript(session.id) { session.state = .complete; session.modelIdentity = transcript.modelIdentity }
                        else if session.state == .complete { session.state = .transcriptionFailed }
                    } catch { session.state = .transcriptionFailed; issues.append("\(session.title): \(error.localizedDescription)") }
                }
                if session != sessions[index] { try save(session) }
                sessions[index] = session
            } catch { issues.append("\(sessions[index].title): \(error.localizedDescription)") }
        }
        return sessions
    }
}
