import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var globalShortcutMonitor: GlobalShortcutMonitor?
    private let historyPickerPanelController = HistoryPickerPanelController()
    private let settingsPanelController = SettingsPanelController()
    private var shortcutPreferenceObserver: NSObjectProtocol?
    private var settingsRequestObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = ClipboardMonitor(modelContainer: ClipboardHistoryStore.sharedContainer)
        monitor.start()
        clipboardMonitor = monitor

        configureGlobalShortcut()
        shortcutPreferenceObserver = NotificationCenter.default.addObserver(
            forName: .globalShortcutPreferenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureGlobalShortcut()
        }
        settingsRequestObserver = NotificationCenter.default.addObserver(
            forName: .showClipboardHistorySettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.settingsPanelController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        globalShortcutMonitor?.stop()
        if let shortcutPreferenceObserver {
            NotificationCenter.default.removeObserver(shortcutPreferenceObserver)
        }
        if let settingsRequestObserver {
            NotificationCenter.default.removeObserver(settingsRequestObserver)
        }
    }

    private func configureGlobalShortcut() {
        globalShortcutMonitor?.stop()
        globalShortcutMonitor = GlobalShortcutMonitor(option: .current) { [weak self] in
            self?.historyPickerPanelController.show()
        }
    }
}

extension Notification.Name {
    static let globalShortcutPreferenceDidChange = Notification.Name("globalShortcutPreferenceDidChange")
    static let showClipboardHistorySettings = Notification.Name("showClipboardHistorySettings")
}
