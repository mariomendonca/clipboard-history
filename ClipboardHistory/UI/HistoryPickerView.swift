import AppKit
import SwiftData
import SwiftUI

struct HistoryPickerView: View {
    private enum FocusedArea: Hashable {
        case historyList
        case search
    }

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
    @State private var previewedImage: ClipboardEntry?
    @State private var actionError: String?
    @State private var selectedEntryID: ClipboardEntry.ID?
    @FocusState private var focusedArea: FocusedArea?

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

            TextField("Search text history", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedArea, equals: .search)
                .onKeyPress(.downArrow) {
                    selectFirstSearchResult()
                    return .handled
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

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
                ScrollViewReader { scrollProxy in
                    List(selection: $selectedEntryID) {
                        ForEach(displayedEntries) { entry in
                            HistoryEntryListRow(
                                entry: entry,
                                isSelected: selectedEntryID == entry.id,
                                onRestoreText: { text in restoreText(entry, text: text) },
                                onRestoreImage: { restoreImage(entry) },
                                onShowImagePreview: { previewedImage = entry },
                                onToggleFavorite: { toggleFavorite(for: entry) },
                                onDelete: { delete(entry) }
                            )
                            .id(entry.id)
                            .tag(entry.id)
                        }
                    }
                    .listStyle(.plain)
                    .focused($focusedArea, equals: .historyList)
                    .onKeyPress(.upArrow) {
                        moveSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        copySelectedEntry()
                        return .handled
                    }
                    .onChange(of: selectedEntryID) { _, entryID in
                        guard let entryID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            scrollProxy.scrollTo(entryID, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Clear Non-Favorites", role: .destructive) {
                    confirmClearNonFavorites()
                }
                .disabled(!entries.contains(where: { !$0.isFavorite }))

                Spacer()

                Text("\(displayedEntries.count) \(displayedEntries.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 470, idealHeight: 560)
        .onAppear {
            resetForPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyPickerDidShow)) { _ in
            resetForPresentation()
        }
        .onChange(of: searchText) { _, _ in
            selectedEntryID = nil
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "f"), phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            focusedArea = .search
            return .handled
        }
        .onChange(of: globalShortcutRawValue) { _, _ in
            NotificationCenter.default.post(name: .globalShortcutPreferenceDidChange, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .globalShortcutRegistrationDidFail)) { notification in
            let shortcut = (notification.object as? GlobalShortcutOption)?.displayName ?? "selected shortcut"
            actionError = "\(shortcut) is unavailable because another app or macOS is already using it. Your previous shortcut was kept."
        }
        .onExitCommand(perform: closePicker)
        .popover(item: $previewedImage, arrowEdge: .trailing) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text("Image Preview")
                    .font(.headline)

                ClipboardImagePreview(relativePath: entry.imageRelativePath)
                    .frame(width: 460, height: 320)

                Text(entry.lastUsedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard History")
                    .font(.title3.weight(.semibold))

                Text("Use \u{2191}/\u{2193} to select, Return to copy, and \u{2318}F to search")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            .help("Settings")

            Button(action: closePicker) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close clipboard history")
            .help("Close")
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

    private func closePicker() {
        searchText = ""
        filter = .all
        selectedEntryID = nil
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
        let count = entries.filter { !$0.isFavorite }.count
        alert.informativeText = "This removes \(count) \(count == 1 ? "entry" : "entries"). Favorites will be kept. This action cannot be undone."
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

    private func resetForPresentation() {
        searchText = ""
        filter = .all
        selectedEntryID = displayedEntries.first?.id
        previewedImage = nil
        DispatchQueue.main.async {
            focusedArea = .historyList
        }
    }

    private func selectFirstSearchResult() {
        guard !displayedEntries.isEmpty else { return }
        selectedEntryID = displayedEntries[0].id
        focusedArea = .historyList
    }

    private func moveSelection(by offset: Int) {
        guard !displayedEntries.isEmpty else { return }

        guard let selectedEntryID,
              let currentIndex = displayedEntries.firstIndex(where: { $0.id == selectedEntryID }) else {
            self.selectedEntryID = displayedEntries[0].id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), displayedEntries.count - 1)
        self.selectedEntryID = displayedEntries[nextIndex].id
    }

    private func copySelectedEntry() {
        guard let selectedEntryID,
              let entry = displayedEntries.first(where: { $0.id == selectedEntryID }) else { return }

        if entry.contentKind == .text, let text = entry.textContent {
            restoreText(entry, text: text)
        } else {
            restoreImage(entry)
        }
    }
}

private struct HistoryEntryListRow: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let onRestoreText: (String) -> Void
    let onRestoreImage: () -> Void
    let onShowImagePreview: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let text = entry.textContent, entry.contentKind == .text {
                Button { onRestoreText(text) } label: {
                    ClipboardEntryRow(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            } else {
                Button(action: onRestoreImage) {
                    ClipboardEntryRow(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy image to clipboard")
            }

            if entry.contentKind == .image {
                Button(action: onShowImagePreview) {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show image preview")
                .help("Show image preview")
            }

            Button(action: onToggleFavorite) {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.isFavorite ? "Remove from favorites" : "Add to favorites")
            .help(entry.isFavorite ? "Remove from favorites" : "Add to favorites")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete entry")
            .help("Delete entry")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : (isHovered ? Color.accentColor.opacity(0.10) : .clear))
        }
        .onHover { isHovered = $0 }
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ClipboardThumbnail(entry: entry)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.contentKind == .text ? (entry.textContent ?? "Text unavailable") : "Image")
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(entry.lastUsedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if entry.contentKind == .text, let text = entry.textContent {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(text.count) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
        .frame(width: 36, height: 36)
        .background(Color.primary.opacity(entry.contentKind == .image ? 0 : 0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
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
