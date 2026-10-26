import Foundation

public typealias SessionID = UUID
public enum SessionState: String, Codable, Sendable {
    case starting, recording, finalizing, recorded, transcribing, complete, interrupted, transcriptionFailed
    public var isActive: Bool { [.starting, .recording, .finalizing, .transcribing].contains(self) }
}
public struct AudioSegment: Codable, Sendable, Equatable {
    public var index: Int
    public var relativePath: String
    public var startFrame: Int64
    public var frameCount: Int64
    public init(index: Int, relativePath: String, startFrame: Int64, frameCount: Int64) {
        self.index = index; self.relativePath = relativePath; self.startFrame = startFrame; self.frameCount = frameCount
    }
}
public struct Session: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var schemaVersion = 1
    public var title: String
    public var createdAt: Date
    public var timeZoneID: String
    public var sourceBundleID = "com.google.Chrome"
    public var state: SessionState = .starting
    public var segments: [AudioSegment] = []
    public var capturedFrames: Int64 = 0
    public var modelIdentity: String?
    public var interruptionReason: String?
    public var duration: Double { Double(capturedFrames) / 16_000 }
    public init(id: UUID = UUID(), title: String, createdAt: Date = Date(), timeZoneID: String = TimeZone.current.identifier) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.timeZoneID = timeZoneID
    }
}
public enum StorageFailure: Error, LocalizedError {
    case invalidData(String), unsupportedSchema(Int), activeSession
    public var errorDescription: String? {
        switch self {
        case .invalidData(let detail): "Recording data could not be read: \(detail)"
        case .unsupportedSchema(let version): "This recording uses a newer format (\(version)). Its files were left untouched."
        case .activeSession: "Finish or cancel the active recording before deleting it."
        }
    }
}
