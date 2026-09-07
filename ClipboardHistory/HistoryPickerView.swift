import AppKit
import SwiftData
import SwiftUI

struct HistoryPickerView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"

        var id: Self { self }
    }

    private let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardEntry.lastUsedAt, order: .reverse) private var entries: [ClipboardEntry]
    @AppStorage(GlobalShortcutOption.defaultsKey) private var globalShortcutRawValue = GlobalShortcutOption.controlOptionV.rawValue
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var expandedImageID: UUID?
    @State private var actionError: String?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private var displayedEntries: [ClipboardEntry] {
        let filterMatches = filter == .all ? entries : entries.filter(\.isFavorite)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filterMatches }

        return filterMatches.filter { entry in
            entry.contentKind == .text && (entry.textContent?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TextField("Search history", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Picker("History filter", selection: $filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if displayedEntries.isEmpty {
                emptyState
            } else {
                List(displayedEntries) { entry in
                    HistoryEntryListRow(
                        entry: entry,
                        isImageExpanded: expandedImageID == entry.id,
                        onRestoreText: { text in restoreText(entry, text: text) },
                        onRestoreImage: { restoreImage(entry) },
                        onToggleImagePreview: { toggleImagePreview(for: entry) },
                        onToggleFavorite: { toggleFavorite(for: entry) },
                        onDelete: { delete(entry) }
                    )
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Button("Clear Non-Favorites", role: .destructive) {
                    confirmClearNonFavorites()
                }
                .disabled(!entries.contains(where: { !$0.isFavorite }))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 380, height: 470)
        .onChange(of: globalShortcutRawValue) { _, _ in
            NotificationCenter.default.post(name: .globalShortcutPreferenceDidChange, object: nil)
        }
        .alert("Clipboard History", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)

            Spacer()

            Menu {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .showClipboardHistorySettings, object: nil)
                }

                Divider()

                Picker("Global Shortcut", selection: $globalShortcutRawValue) {
                    ForEach(GlobalShortcutOption.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }

                Divider()

                Button("Reset to Control + Option + V") {
                    globalShortcutRawValue = GlobalShortcutOption.controlOptionV.rawValue
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Global shortcut settings")

            Button(action: closePicker) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close clipboard history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !query.isEmpty ? "No matching text" : (filter == .all ? "No clipboard history yet" : "No favorites yet")
        let icon = !query.isEmpty ? "magnifyingglass" : (filter == .all ? "clipboard" : "star")
        let description = !query.isEmpty
            ? "Try a different search term. Image-only entries are hidden while searching."
            : (filter == .all ? "Text and images you copy in other apps will appear here." : "Mark important clipboard items as favorites to keep them handy.")

        return ContentUnavailableView(title, systemImage: icon, description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restoreText(_ entry: ClipboardEntry, text: String) {
        guard ClipboardMonitor.copyTextToGeneralPasteboard(text) else {
            actionError = "Clipboard History could not write this item to the macOS clipboard."
            return
        }
        markUsedAndClose(entry)
    }

    private func restoreImage(_ entry: ClipboardEntry) {
        guard let relativePath = entry.imageRelativePath,
              let imageData = ClipboardImageStorage.shared.imageData(atRelativePath: relativePath),
              ClipboardMonitor.copyImageToGeneralPasteboard(imageData: imageData) else {
            actionError = "The image file is unavailable or could not be copied to the macOS clipboard."
            return
        }
        markUsedAndClose(entry)
    }

    private func markUsedAndClose(_ entry: ClipboardEntry) {
        entry.lastUsedAt = .now
        do {
            try modelContext.save()
            closePicker()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleImagePreview(for entry: ClipboardEntry) {
        expandedImageID = expandedImageID == entry.id ? nil : entry.id
    }

    private func closePicker() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func toggleFavorite(for entry: ClipboardEntry) {
        performHistoryAction { try ClipboardHistoryRepository(modelContext: modelContext).toggleFavorite(for: entry) }
    }

    private func delete(_ entry: ClipboardEntry) {
        performHistoryAction { try ClipboardHistoryRepository(modelContext: modelContext).delete(entry) }
    }

    private func clearNonFavorites() {
        performHistoryAction { try ClipboardHistoryRepository(modelContext: modelContext).clearNonFavorites() }
    }

    private func confirmClearNonFavorites() {
        let alert = NSAlert()
        alert.messageText = "Clear all non-favorite clipboard entries?"
        alert.informativeText = "Favorites will be kept. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Non-Favorites")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearNonFavorites()
    }

    private func performHistoryAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct HistoryEntryListRow: View {
    let entry: ClipboardEntry
    let isImageExpanded: Bool
    let onRestoreText: (String) -> Void
    let onRestoreImage: () -> Void
    let onToggleImagePreview: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let text = entry.textContent, entry.contentKind == .text {
                Button { onRestoreText(text) } label: {
                    ClipboardEntryRow(entry: entry, isImageExpanded: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            } else {
                Button(action: onRestoreImage) {
                    ClipboardEntryRow(entry: entry, isImageExpanded: isImageExpanded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy image to clipboard")
            }

            if entry.contentKind == .image {
                Button(action: onToggleImagePreview) {
                    Image(systemName: isImageExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isImageExpanded ? "Hide image preview" : "Show image preview")
            }

            Button(action: onToggleFavorite) {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.isFavorite ? "Remove from favorites" : "Add to favorites")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete entry")
        }
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let isImageExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                ClipboardThumbnail(entry: entry)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.contentKind == .text ? (entry.textContent ?? "Text unavailable") : "Image")
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Text(entry.lastUsedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isImageExpanded, entry.contentKind == .image {
                ClipboardImagePreview(relativePath: entry.imageRelativePath)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ClipboardThumbnail: View {
    let entry: ClipboardEntry

    var body: some View {
        Group {
            if entry.contentKind == .image {
                ClipboardImagePreview(relativePath: entry.thumbnailRelativePath)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
    }
}

private struct ClipboardImagePreview: View {
    let relativePath: String?

    var body: some View {
        if let relativePath,
           let data = ClipboardImageStorage.shared.imageData(atRelativePath: relativePath),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    HistoryPickerView()
        .modelContainer(PreviewModelContainer.container)
}
#endif
