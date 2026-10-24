import Foundation
public struct RecordingPresentation {
    public let primaryTitle: String
    public let canStart: Bool
    public let canFinish: Bool
    public let quietHintVisible: Bool
    public init(modelReady: Bool, permissionGranted: Bool, phase: SessionState?, lastAudio: Double?, startedAt: Double?, now: Double) {
        canStart = modelReady && permissionGranted && phase == nil
        canFinish = phase == .recording
        switch phase {
        case .starting: primaryTitle = "Starting…"
        case .recording: primaryTitle = "Finish"
        case .finalizing: primaryTitle = "Saving audio…"
        case .transcribing: primaryTitle = "Transcribing…"
        default: primaryTitle = "Start recording"
        }
        quietHintVisible = phase == .recording && (lastAudio ?? startedAt).map { now - $0 >= 30 } == true
    }
}
