import AppKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(ClipboardSettings.historyLimitKey) private var historyLimit = ClipboardSettings.defaultHistoryLimit
    @AppStorage(GlobalShortcutOption.defaultsKey) private var globalShortcutRawValue = GlobalShortcutOption.controlOptionV.rawValue
    @State private var excludedBundleIdentifiers = ClipboardSettings.excludedApplicationBundleIdentifiers
    @State private var newBundleIdentifier = ""
    @State private var actionError: String?

    var body: some View {
        Form {
            Section("History") {
                Stepper(value: $historyLimit, in: 1...5_000) {
                    Text("Keep up to \(historyLimit) non-favorite entries")
                }

                Button("Clear Non-Favorites", role: .destructive) {
                    confirmClearNonFavorites()
                }
            }

            Section("Global Shortcut") {
                Picker("Shortcut", selection: $globalShortcutRawValue) {
                    ForEach(GlobalShortcutOption.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }

                Button("Reset to Control + Option + V") {
                    globalShortcutRawValue = GlobalShortcutOption.controlOptionV.rawValue
                }
            }

            Section("Excluded Applications") {
                Text("Clipboard capture is skipped while one of these apps is frontmost. This is best-effort because macOS cannot always identify the app that created clipboard content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Bundle identifier", text: $newBundleIdentifier)
                    Button("Add", action: addExcludedApplication)
                        .disabled(newBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                List {
                    ForEach(excludedBundleIdentifiers, id: \.self) { identifier in
                        Text(identifier)
                    }
                    .onDelete(perform: removeExcludedApplications)
                }
                .frame(minHeight: 140)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 510, height: 500)
        .onChange(of: globalShortcutRawValue) { _, _ in
            NotificationCenter.default.post(name: .globalShortcutPreferenceDidChange, object: nil)
        }
        .onChange(of: historyLimit) { _, _ in
            do {
                try ClipboardHistoryRepository(modelContext: modelContext).enforceRetention()
            } catch {
                actionError = "The history limit was saved, but existing entries could not be pruned: \(error.localizedDescription)"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .globalShortcutRegistrationDidFail)) { notification in
            let shortcut = (notification.object as? GlobalShortcutOption)?.displayName ?? "selected shortcut"
            actionError = "\(shortcut) is unavailable because another app or macOS is already using it. Your previous shortcut was kept."
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

    private func addExcludedApplication() {
        excludedBundleIdentifiers.append(newBundleIdentifier)
        ClipboardSettings.setExcludedApplicationBundleIdentifiers(excludedBundleIdentifiers)
        excludedBundleIdentifiers = ClipboardSettings.excludedApplicationBundleIdentifiers
        newBundleIdentifier = ""
    }

    private func removeExcludedApplications(at offsets: IndexSet) {
        excludedBundleIdentifiers.remove(atOffsets: offsets)
        ClipboardSettings.setExcludedApplicationBundleIdentifiers(excludedBundleIdentifiers)
        excludedBundleIdentifiers = ClipboardSettings.excludedApplicationBundleIdentifiers
    }

    private func confirmClearNonFavorites() {
        let alert = NSAlert()
        alert.messageText = "Clear all non-favorite clipboard entries?"
        alert.informativeText = "Favorites will be kept. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Non-Favorites")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try ClipboardHistoryRepository(modelContext: modelContext).clearNonFavorites()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
