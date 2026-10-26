import AppKit

@MainActor public final class SessionLifecycle {
    private var observers: [NSObjectProtocol] = []
    public init(coordinator: SessionCoordinator) {
        let notifications = NSWorkspace.shared.notificationCenter
        observers.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak coordinator] _ in
            Task { @MainActor in
                await coordinator?.interrupt(reason: "The Mac went to sleep. Saved audio is available; start a new recording after waking.")
                await coordinator?.cancelTranscription()
            }
        })
        observers.append(notifications.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak coordinator] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.google.Chrome" else { return }
            Task { @MainActor in await coordinator?.interrupt(reason: "Chrome closed. Saved audio is available.") }
        })
    }
    public func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }
}
