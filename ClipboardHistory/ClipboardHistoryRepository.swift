import CryptoKit
import Foundation
import SwiftData

struct ClipboardHistoryRepository {
    static let defaultNonFavoriteLimit = 500

    private let modelContext: ModelContext
    private let nonFavoriteLimit: Int
    private let imageStorage: ClipboardImageStorage

    init(
        modelContext: ModelContext,
        nonFavoriteLimit: Int = ClipboardSettings.historyLimit,
        imageStorage: ClipboardImageStorage = .shared
    ) {
        self.modelContext = modelContext
        self.nonFavoriteLimit = nonFavoriteLimit
        self.imageStorage = imageStorage
    }

    @discardableResult
    func saveText(_ text: String, at timestamp: Date = .now) throws -> ClipboardEntry {
        let normalizedText = Self.normalizedText(from: text)
        let contentHash = Self.hash(forNormalizedText: normalizedText)
        let textKind = ClipboardContentKind.text.rawValue
        let predicate = #Predicate<ClipboardEntry> { entry in
            entry.contentKindRawValue == textKind && entry.contentHash == contentHash
        }
        var descriptor = FetchDescriptor<ClipboardEntry>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existingEntry = try modelContext.fetch(descriptor).first {
            existingEntry.lastUsedAt = timestamp
            try modelContext.save()
            return existingEntry
        }

        let entry = ClipboardEntry(
            createdAt: timestamp,
            lastUsedAt: timestamp,
            contentKind: .text,
            contentHash: contentHash,
            textContent: text
        )
        modelContext.insert(entry)
        try pruneNonFavoriteEntriesIfNeeded()
        try modelContext.save()
        return entry
    }

    @discardableResult
    func saveImage(pngData: Data, thumbnailPNGData: Data, at timestamp: Date = .now) throws -> ClipboardEntry {
        let contentHash = Self.hash(for: pngData)
        let imageKind = ClipboardContentKind.image.rawValue
        let predicate = #Predicate<ClipboardEntry> { entry in
            entry.contentKindRawValue == imageKind && entry.contentHash == contentHash
        }
        var descriptor = FetchDescriptor<ClipboardEntry>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existingEntry = try modelContext.fetch(descriptor).first {
            existingEntry.lastUsedAt = timestamp
            try modelContext.save()
            return existingEntry
        }

        let storedPaths = try imageStorage.storeImage(
            pngData: pngData,
            thumbnailPNGData: thumbnailPNGData
        )
        let entry = ClipboardEntry(
            createdAt: timestamp,
            lastUsedAt: timestamp,
            contentKind: .image,
            contentHash: contentHash,
            imageRelativePath: storedPaths.imageRelativePath,
            thumbnailRelativePath: storedPaths.thumbnailRelativePath
        )
        modelContext.insert(entry)

        do {
            try pruneNonFavoriteEntriesIfNeeded()
            try modelContext.save()
            return entry
        } catch {
            try? imageStorage.removeImageFile(atRelativePath: storedPaths.imageRelativePath)
            try? imageStorage.removeImageFile(atRelativePath: storedPaths.thumbnailRelativePath)
            modelContext.delete(entry)
            throw error
        }
    }

    static func normalizedText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    static func hash(forNormalizedText text: String) -> String {
        hash(for: Data(text.utf8))
    }

    static func hash(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func toggleFavorite(for entry: ClipboardEntry) throws {
        entry.isFavorite.toggle()
        try modelContext.save()
    }

    func delete(_ entry: ClipboardEntry) throws {
        try removeAssociatedImageFiles(for: entry)
        modelContext.delete(entry)
        try modelContext.save()
    }

    func clearNonFavorites() throws {
        let predicate = #Predicate<ClipboardEntry> { entry in
            !entry.isFavorite
        }
        let entries = try modelContext.fetch(FetchDescriptor<ClipboardEntry>(predicate: predicate))

        for entry in entries {
            try removeAssociatedImageFiles(for: entry)
            modelContext.delete(entry)
        }
        try modelContext.save()
    }

    private func pruneNonFavoriteEntriesIfNeeded() throws {
        let predicate = #Predicate<ClipboardEntry> { entry in
            !entry.isFavorite
        }
        var descriptor = FetchDescriptor<ClipboardEntry>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\ClipboardEntry.lastUsedAt, order: .forward)]

        let nonFavoriteEntries = try modelContext.fetch(descriptor)
        let overflow = nonFavoriteEntries.count - nonFavoriteLimit
        guard overflow > 0 else { return }

        for entry in nonFavoriteEntries.prefix(overflow) {
            try removeAssociatedImageFiles(for: entry)
            modelContext.delete(entry)
        }
    }

    private func removeAssociatedImageFiles(for entry: ClipboardEntry) throws {
        let paths = Set([entry.imageRelativePath, entry.thumbnailRelativePath].compactMap { $0 })
        for path in paths {
            try imageStorage.removeImageFile(atRelativePath: path)
        }
    }
}
