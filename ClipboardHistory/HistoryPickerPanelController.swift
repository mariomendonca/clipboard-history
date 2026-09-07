import AppKit
import SwiftUI

final class HistoryPickerPanelController {
    private var panel: NSPanel?
    private let modelContainer = ClipboardHistoryStore.sharedContainer

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Clipboard History"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: HistoryPickerView(onClose: { [weak panel] in
                panel?.orderOut(nil)
            })
            .modelContainer(modelContainer))
            self.panel = panel
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}
