import LectureCore
import SwiftUI

@main
struct LectureRecorderApp: App {
    var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            ScaffoldView()
        }
        .defaultSize(width: 480, height: 300)
        .windowResizability(.contentSize)
    }
}
