import AppKit
import Observation
import LectureCore

@MainActor @Observable final class AppDependencies {
    let store: SessionStore
    let models: ModelManager
    let library: LibraryModel
    let coordinator: SessionCoordinator
    private let lifecycle: SessionLifecycle
    var modelReady = false
    var permissionGranted = false
    var setupBusy = false
    var setupProgress: ModelSetupProgress?
    var setupError: String?
    var showSetup = false
    private var initialized = false
    init() throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LectureRecorder")
        let store = SessionStore(root: root.appendingPathComponent("Sessions")); self.store = store
        let models = ModelManager(root: root.appendingPathComponent("Models"), manifest: try .bundled()); self.models = models
        let coordinator = SessionCoordinator(capture: ChromeCaptureService(), store: store, models: models, transcriber: TranscriptionService(), power: PowerAssertion(), clock: { CMClockSeconds.now }, writerFactory: { SegmentWriter(store: store) }); self.coordinator = coordinator
        library = LibraryModel(store: store, activeID: { coordinator.activeSessionID })
        lifecycle = SessionLifecycle(coordinator: coordinator)
    }
    func initialize() async {
        guard !initialized else { return }; initialized = true
        permissionGranted = ChromeCaptureService.hasPermission
        do { modelReady = try await models.installed() != nil } catch { setupError = error.localizedDescription }
        showSetup = !modelReady || !permissionGranted
        await coordinator.restore()
    }
    func prepare() async {
        guard !setupBusy, coordinator.phase == nil else { return }
        setupBusy = true; setupError = nil
        defer { setupBusy = false }
        do {
            _ = try await models.prepare { [weak self] stage in Task { @MainActor in self?.setupProgress = stage } }
            modelReady = true
        } catch { modelReady = false; setupError = error.localizedDescription }
    }
    func grantPermission() { permissionGranted = ChromeCaptureService.requestPermission() }
    func refreshPermission() { permissionGranted = ChromeCaptureService.hasPermission }
    func primaryAction() async {
        refreshPermission()
        if coordinator.phase == .recording { await coordinator.finish() }
        else if modelReady && permissionGranted { await coordinator.start() }
        else { showSetup = true }
    }
}
import CoreMedia
private enum CMClockSeconds { static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds } }
