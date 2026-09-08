import SwiftData

enum ClipboardHistoryStore {
    static private(set) var startupErrorDescription: String?

    static let sharedContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ClipboardEntry.self)
        } catch {
            startupErrorDescription = error.localizedDescription
            assertionFailure("Unable to create the clipboard history store: \(error.localizedDescription)")

            do {
                return try ModelContainer(
                    for: ClipboardEntry.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("Unable to create even an in-memory clipboard history store: \(error.localizedDescription)")
            }
        }
    }()
}
