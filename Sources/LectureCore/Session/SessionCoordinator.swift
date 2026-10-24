import Foundation
import Observation

@MainActor @Observable public final class SessionCoordinator {
    public private(set) var activeSessionID: SessionID?
    public private(set) var activeSession: Session?
    public private(set) var phase: SessionState?
    public private(set) var errorMessage: String?
    public private(set) var elapsedSeconds = 0.0
    public private(set) var audioLevel: Float = 0
    public private(set) var progress: TranscriptionProgress?
    public private(set) var lastAudibleHostSeconds: Double?
    public private(set) var recordingStartedAt: Double?
    public private(set) var revision = 0
    private let capture: any CaptureService
    public let store: SessionStore
    private let models: any ModelManaging
    private let transcriber: any Transcribing
    private let power: any PowerManaging
    private let clock: @Sendable () -> Double
    private let writerFactory: @Sendable () -> SegmentWriter
    private var writer: SegmentWriter?
    private var job: UUID?
    private var inference: Task<Void, Never>?
    private var interruption: String?
    public init(capture: any CaptureService, store: SessionStore, models: any ModelManaging, transcriber: any Transcribing, power: any PowerManaging, clock: @escaping @Sendable () -> Double, writerFactory: @escaping @Sendable () -> SegmentWriter) {
        self.capture = capture; self.store = store; self.models = models; self.transcriber = transcriber; self.power = power; self.clock = clock; self.writerFactory = writerFactory
    }
    public func start() async {
        guard phase == nil else { return }
        phase = .starting; errorMessage = nil; interruption = nil
        let token = UUID(); job = token
        do {
            guard try await models.installed() != nil else { throw StorageFailure.invalidData("Prepare the local model before recording.") }
            try power.acquire()
            let session = try await store.create(); activeSession = session; activeSessionID = session.id
            let folder = await store.folder(for: session.id)
            guard try ModelManager.availableBytes(folder) > 100_000_000 else { throw ModelFailure.insufficientSpace }
            let writer = writerFactory(); self.writer = writer
            let origin = try await capture.start { event in _ = writer.accept(event) }
            recordingStartedAt = origin.hostSeconds; elapsedSeconds = 0; lastAudibleHostSeconds = nil
            try await writer.begin(session: session, origin: origin) { [weak self] event in
                Task { @MainActor in
                    guard let self, self.job == token else { return }
                    switch event {
                    case .progress(let frames, let level, let audible):
                        self.elapsedSeconds = Double(frames) / 16_000; self.audioLevel = level; self.lastAudibleHostSeconds = audible
                    case .failed(let message): await self.interrupt(reason: message)
                    }
                }
            }
            phase = .recording
            if let reason = interruption { await interrupt(reason: reason) }
        } catch {
            await capture.stop()
            if var session = activeSession { session.state = .interrupted; session.interruptionReason = error.localizedDescription; try? await store.save(session) }
            errorMessage = error.localizedDescription; clearJob(token)
        }
    }
    public func finish() async {
        guard phase == .recording, let writer, let token = job else { return }
        phase = .finalizing
        let end = clock()
        await capture.stop()
        do {
            let session = try await writer.finish(atHostSeconds: end)
            activeSession = session; revision += 1
            self.writer = nil
            await beginInference(session, token: token)
        } catch {
            errorMessage = error.localizedDescription; clearJob(token)
        }
    }
    public func transcribe(_ id: SessionID) async {
        guard phase == nil else { return }
        phase = .transcribing; errorMessage = nil; activeSessionID = id
        let token = UUID(); job = token
        do {
            let session = try await store.load(id)
            guard !session.segments.isEmpty else { throw StorageFailure.invalidData("This recording has no saved audio.") }
            activeSession = session; try power.acquire()
            await beginInference(session, token: token)
        } catch { errorMessage = error.localizedDescription; clearJob(token) }
    }
    private func beginInference(_ saved: Session, token: UUID) async {
        phase = .transcribing; progress = .preparing
        let operation = Task { [weak self] in
            guard let self else { return }
            var session = saved
            var temporary: URL?
            defer { if let temporary { try? FileManager.default.removeItem(at: temporary) }; self.clearJob(token) }
            do {
                try Task.checkCancellation()
                guard let model = try await self.models.installed() else { throw StorageFailure.invalidData("The local model needs repair. Open setup and retry.") }
                session.state = .transcribing; try await self.store.save(session); self.activeSession = session; activeSessionID = session.id
                let folder = await self.store.folder(for: session.id)
                guard try ModelManager.availableBytes(folder) > session.capturedFrames * 2 + 100_000_000 else { throw ModelFailure.insufficientSpace }
                let audio = try await AudioAssembler.assemble(session, at: folder); temporary = audio
                let transcript = try await self.transcriber.run(audioURL: audio, model: model) { [weak self] progress in
                    Task { @MainActor in guard self?.job == token else { return }; self?.progress = progress }
                }
                try Task.checkCancellation()
                guard self.job == token else { return }
                try await self.store.commitTranscript(transcript, session: session)
                self.revision += 1
            } catch {
                session.state = Task.isCancelled || error is CancellationError ? .recorded : .transcriptionFailed
                try? await self.store.save(session)
                if session.state == .transcriptionFailed { self.errorMessage = error.localizedDescription }
                self.revision += 1
            }
        }
        inference = operation
        await operation.value
    }
    public func cancelTranscription() async {
        guard phase == .transcribing, let inference else { return }
        inference.cancel()
        await inference.value
    }
    public func interrupt(reason: String) async {
        if phase == .starting { interruption = reason; return }
        guard phase == .recording, let writer, let token = job, let id = activeSession?.id else { return }
        phase = .finalizing
        _ = writer.accept(.interrupted(.streamStopped))
        await capture.stop()
        _ = try? await writer.finish(atHostSeconds: clock())
        if var session = try? await store.load(id) {
            session.state = .interrupted; session.interruptionReason = reason
            try? await store.save(session)
        }
        errorMessage = reason; clearJob(token)
    }
    public func restore() async {
        guard phase == nil else { return }
        do { _ = try await store.recover(); revision += 1 }
        catch { errorMessage = error.localizedDescription }
    }
    private func clearJob(_ token: UUID) {
        guard job == token else { return }
        power.release(); job = nil; inference = nil; writer = nil; activeSession = nil; activeSessionID = nil; phase = nil
        progress = nil; audioLevel = 0; recordingStartedAt = nil; interruption = nil; revision += 1
    }
}
