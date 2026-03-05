import AppKit

class ActiveAppMonitor: ObservableObject {
    @Published private(set) var frontmostBundleId: String = "*"

    private var observer: NSObjectProtocol?

    init() {
        frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "*"
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.frontmostBundleId = app.bundleIdentifier ?? "*"
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
