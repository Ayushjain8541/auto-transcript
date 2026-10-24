import AppKit
import LectureCore
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: SessionCoordinator?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.phase != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the current job and quit?"
        alert.informativeText = "Saved audio will remain in your library. You can transcribe it when you reopen the app."
        alert.addButton(withTitle: "Keep Working"); alert.addButton(withTitle: "Stop and Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task {
            if coordinator.phase == .starting || coordinator.phase == .recording { await coordinator.interrupt(reason: "Recording stopped when quitting. Saved audio is available.") }
            // Starting/finalizing may be between awaited operations. Keep the process
            // alive until its owner has reached a cancellable or terminal state.
            while coordinator.phase == .starting || coordinator.phase == .finalizing { try? await Task.sleep(for: .milliseconds(50)) }
            await coordinator.cancelTranscription()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
