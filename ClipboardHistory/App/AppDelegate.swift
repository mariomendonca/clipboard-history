import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var globalShortcutMonitor: GlobalShortcutMonitor?
    private let historyPickerPanelController = HistoryPickerPanelController()
    private let settingsPanelController = SettingsPanelController()
    private var shortcutPreferenceObserver: NSObjectProtocol?
    private var settingsRequestObserver: NSObjectProtocol?
    private var activeShortcutOption = GlobalShortcutOption.current

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = ClipboardMonitor(modelContainer: ClipboardHistoryStore.sharedContainer)
        do {
            let removedFileCount = try ClipboardHistoryRepository(modelContext: ModelContext(ClipboardHistoryStore.sharedContainer))
                .reconcileImageStorage()
#if DEBUG
            if removedFileCount > 0 {
                print("ClipboardHistory removed \(removedFileCount) orphaned image files.")
            }
#endif
        } catch {
#if DEBUG
            print("ClipboardHistory could not reconcile image storage: \(error.localizedDescription)")
#endif
        }
        monitor.start()
        clipboardMonitor = monitor

        configureGlobalShortcut()
        shortcutPreferenceObserver = NotificationCenter.default.addObserver(
            forName: .globalShortcutPreferenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configureGlobalShortcut()
            }
        }
        settingsRequestObserver = NotificationCenter.default.addObserver(
            forName: .showClipboardHistorySettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settingsPanelController.show()
            }
        }

        if let startupErrorDescription = ClipboardHistoryStore.startupErrorDescription {
            presentPersistenceRecoveryAlert(errorDescription: startupErrorDescription)
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
        let requestedOption = GlobalShortcutOption.current
        let replacement = GlobalShortcutMonitor(option: requestedOption) { [weak self] in
            self?.historyPickerPanelController.show()
        }

        guard replacement.isRegistered else {
            UserDefaults.standard.set(activeShortcutOption.rawValue, forKey: GlobalShortcutOption.defaultsKey)
            NotificationCenter.default.post(name: .globalShortcutRegistrationDidFail, object: requestedOption)
            return
        }

        globalShortcutMonitor?.stop()
        globalShortcutMonitor = replacement
        activeShortcutOption = requestedOption
    }

    private func presentPersistenceRecoveryAlert(errorDescription: String) {
        let alert = NSAlert()
        alert.messageText = "Clipboard history is temporarily unavailable"
        alert.informativeText = "The local history database could not be opened. Clipboard History is running without saved history for this session. \(errorDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension Notification.Name {
    static let globalShortcutPreferenceDidChange = Notification.Name("globalShortcutPreferenceDidChange")
    static let globalShortcutRegistrationDidFail = Notification.Name("globalShortcutRegistrationDidFail")
    static let showClipboardHistorySettings = Notification.Name("showClipboardHistorySettings")
}
