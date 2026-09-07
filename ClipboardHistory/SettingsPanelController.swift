import AppKit
import SwiftUI

final class SettingsPanelController {
    private var panel: NSPanel?
    private let modelContainer = ClipboardHistoryStore.sharedContainer

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 510, height: 500),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Clipboard History Settings"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SettingsView().modelContainer(modelContainer))
            self.panel = panel
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}
