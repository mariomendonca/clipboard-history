#if DEBUG
import SwiftData
import SwiftUI

enum PreviewModelContainer {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ClipboardEntry.self, configurations: configuration)
        let context = ModelContext(container)

        context.insert(ClipboardEntry(
            contentKind: .text,
            contentHash: "preview-meeting-notes",
            textContent: "Meeting notes: confirm the launch date with the team."
        ))
        context.insert(ClipboardEntry(
            isFavorite: true,
            contentKind: .text,
            contentHash: "preview-email",
            textContent: "hello@example.com"
        ))
        return container
    }()
}
#endif
