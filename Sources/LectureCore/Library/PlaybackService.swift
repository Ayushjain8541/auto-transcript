import Foundation
import AVFoundation
import Observation

public struct PlaybackPosition: Equatable, Sendable {
    public let segmentIndex: Int
    public let offsetSeconds: Double
    public static func resolve(seconds: Double, segments: [AudioSegment], duration: Double) -> Self? {
        guard seconds.isFinite, seconds >= 0, seconds < duration else { return nil }
        let frame = seconds * 16_000
        guard let segment = segments.first(where: { frame >= Double($0.startFrame) && frame < Double($0.startFrame + $0.frameCount) }) else { return nil }
        return .init(segmentIndex: segment.index, offsetSeconds: seconds - Double(segment.startFrame) / 16_000)
    }
}
@MainActor @Observable public final class PlaybackService {
    public private(set) var position = 0.0
    public private(set) var duration = 0.0
    public private(set) var isPlaying = false
    public private(set) var ready = false
    public private(set) var errorMessage: String?
    public private(set) var segmentPosition: PlaybackPosition?
    private var player: AVPlayer?
    private var observer: Any?
    private var temporary: URL?
    private var segments: [AudioSegment] = []
    private var generation = UUID()
    public init() {}
    public func load(session: Session, folder: URL) async throws {
        clear()
        let token = generation
        do {
            guard try ModelManager.availableBytes(folder) > session.capturedFrames * 2 + 100_000_000 else { throw ModelFailure.insufficientSpace }
            let audio = try await AudioAssembler.assemble(session, at: folder)
            guard token == generation, !Task.isCancelled else { try? FileManager.default.removeItem(at: audio); return }
            temporary = audio; segments = session.segments; duration = session.duration
            let player = AVPlayer(url: audio); self.player = player
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.position = min(self.duration, max(0, time.seconds.isFinite ? time.seconds : 0))
                    self.segmentPosition = PlaybackPosition.resolve(seconds: self.position, segments: self.segments, duration: self.duration)
                    if self.position >= self.duration - 0.02 { self.isPlaying = false }
                    if let error = self.player?.error { self.errorMessage = error.localizedDescription; self.isPlaying = false }
                }
            }
            ready = true
        } catch { if token == generation { errorMessage = error.localizedDescription }; throw error }
    }
    public func play() { guard ready else { return }; if position >= duration - 0.02 { seek(to: 0) }; player?.play(); isPlaying = true }
    public func pause() { player?.pause(); isPlaying = false }
    public func seek(to seconds: Double) {
        guard seconds.isFinite, ready else { return }
        position = min(duration, max(0, seconds)); segmentPosition = PlaybackPosition.resolve(seconds: position, segments: segments, duration: duration)
        player?.seek(to: CMTime(seconds: position, preferredTimescale: 16_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    public func clear() {
        generation = UUID(); pause()
        if let observer { player?.removeTimeObserver(observer) }; observer = nil; player = nil
        if let temporary { try? FileManager.default.removeItem(at: temporary) }; temporary = nil
        duration = 0; position = 0; ready = false; errorMessage = nil; segments = []
    }
}
