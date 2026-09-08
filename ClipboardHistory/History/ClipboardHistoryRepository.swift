import CryptoKit
import Foundation
import SwiftData

@MainActor
struct ClipboardHistoryRepository {
    private let modelContext: ModelContext
    private let nonFavoriteLimit: Int
    private let nonFavoriteImageStorageLimit: Int
    private let imageStorage: ClipboardImageStorage

    init(
        modelContext: ModelContext,
        nonFavoriteLimit: Int = ClipboardSettings.historyLimit,
        nonFavoriteImageStorageLimit: Int = ClipboardSettings.maximumNonFavoriteImageStorageByteCount,
        imageStorage: ClipboardImageStorage = .shared
    ) {
        self.modelContext = modelContext
        self.nonFavoriteLimit = nonFavoriteLimit
        self.nonFavoriteImageStorageLimit = nonFavoriteImageStorageLimit
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
        let imagePathsToRemove = try pruneNonFavoriteEntriesIfNeeded()
        try modelContext.save()
        removeImageFiles(atRelativePaths: imagePathsToRemove)
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
            let imagePathsToRemove = try pruneNonFavoriteEntriesIfNeeded()
            try modelContext.save()
            removeImageFiles(atRelativePaths: imagePathsToRemove)
            return entry
        } catch {
            modelContext.rollback()
            try? imageStorage.removeImageFile(atRelativePath: storedPaths.imageRelativePath)
            try? imageStorage.removeImageFile(atRelativePath: storedPaths.thumbnailRelativePath)
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
        let imagePaths = imagePaths(for: entry)
        modelContext.delete(entry)
        try modelContext.save()
        removeImageFiles(atRelativePaths: imagePaths)
    }

    func clearNonFavorites() throws {
        let predicate = #Predicate<ClipboardEntry> { entry in
            !entry.isFavorite
        }
        let entries = try modelContext.fetch(FetchDescriptor<ClipboardEntry>(predicate: predicate))

        let imagePaths = entries.flatMap(imagePaths(for:))
        for entry in entries {
            modelContext.delete(entry)
        }
        try modelContext.save()
        removeImageFiles(atRelativePaths: imagePaths)
    }

    func enforceRetention() throws {
        let imagePathsToRemove = try pruneNonFavoriteEntriesIfNeeded()
        try modelContext.save()
        removeImageFiles(atRelativePaths: imagePathsToRemove)
    }

    @discardableResult
    func reconcileImageStorage() throws -> Int {
        let entries = try modelContext.fetch(FetchDescriptor<ClipboardEntry>())
        let referencedPaths = Set(entries.flatMap(imagePaths(for:)))
        return try imageStorage.removeOrphanedImageFiles(referencedRelativePaths: referencedPaths)
    }

    private func pruneNonFavoriteEntriesIfNeeded() throws -> [String] {
        let predicate = #Predicate<ClipboardEntry> { entry in
            !entry.isFavorite
        }
        var descriptor = FetchDescriptor<ClipboardEntry>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\ClipboardEntry.lastUsedAt, order: .forward)]

        let nonFavoriteEntries = try modelContext.fetch(descriptor)
        var entriesToRemove = Array(nonFavoriteEntries.prefix(max(0, nonFavoriteEntries.count - nonFavoriteLimit)))
        var retainedImageStorageSize = nonFavoriteEntries
            .dropFirst(entriesToRemove.count)
            .reduce(0) { $0 + imageStorageSize(for: $1) }

        for entry in nonFavoriteEntries.dropFirst(entriesToRemove.count) where retainedImageStorageSize > nonFavoriteImageStorageLimit {
            entriesToRemove.append(entry)
            retainedImageStorageSize -= imageStorageSize(for: entry)
        }

        for entry in entriesToRemove {
            modelContext.delete(entry)
        }
        return entriesToRemove.flatMap(imagePaths(for:))
    }

    private func imagePaths(for entry: ClipboardEntry) -> [String] {
        Array(Set([entry.imageRelativePath, entry.thumbnailRelativePath].compactMap { $0 }))
    }

    private func imageStorageSize(for entry: ClipboardEntry) -> Int {
        imagePaths(for: entry).reduce(0) { $0 + imageStorage.imageFileSize(atRelativePath: $1) }
    }

    private func removeImageFiles(atRelativePaths paths: [String]) {
        let uniquePaths = Set(paths)
        for path in uniquePaths {
            try? imageStorage.removeImageFile(atRelativePath: path)
        }
    }
}
