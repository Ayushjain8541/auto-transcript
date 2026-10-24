import LectureCore
import SwiftUI

@main struct LectureRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var loaded: Result<AppDependencies, Error> = Result { try AppDependencies() }
    var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            switch loaded {
            case .success(let app):
                VStack {
                    if app.showSetup { SetupView(app: app) }
                    else { RecordingControls(app: app).padding(30) }
                }
                .task { delegate.coordinator = app.coordinator; await app.initialize() }
                .toolbar { Button("Setup", systemImage: "gearshape") { app.showSetup.toggle() } }
            case .failure(let error): Text("Lecture Recorder could not start: \(error.localizedDescription)").padding(30).textSelection(.enabled)
            }
        }.defaultSize(width: 820, height: 580)
        MenuBarExtra("Lecture Recorder", systemImage: "waveform") {
            if case .success(let app) = loaded { RecordingMenuView(app: app).task { await app.initialize() } }
        }.menuBarExtraStyle(.window)
    }
}
