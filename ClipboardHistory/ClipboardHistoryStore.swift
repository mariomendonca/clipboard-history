import SwiftData

enum ClipboardHistoryStore {
    static let sharedContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ClipboardEntry.self)
        } catch {
            fatalError("Unable to create the clipboard history store: \(error.localizedDescription)")
        }
    }()
}
