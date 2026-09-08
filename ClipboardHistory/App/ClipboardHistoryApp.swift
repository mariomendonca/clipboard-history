import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer = ClipboardHistoryStore.sharedContainer

    var body: some Scene {
        MenuBarExtra("Clipboard History", systemImage: "clipboard") {
            HistoryPickerView()
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
