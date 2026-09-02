import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Clipboard History", systemImage: "clipboard") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContentView: View {
    var body: some View {
        Button("Quit Clipboard History") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
