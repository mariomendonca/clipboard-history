import SwiftData
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var temporaryDirectoryURL: URL!
    private var imageStorage: ClipboardImageStorage!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ClipboardEntry.self, configurations: configuration)
        modelContext = ModelContext(modelContainer)

        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryTests-\(UUID().uuidString)", isDirectory: true)
        imageStorage = ClipboardImageStorage(directoryURLOverride: temporaryDirectoryURL)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        imageStorage = nil
        modelContext = nil
        modelContainer = nil
    }

    func testNormalizedTextHashesEquivalentClipboardValues() {
        let first = ClipboardHistoryRepository.normalizedText(from: "  cafe\u{301}\r\n")
        let second = ClipboardHistoryRepository.normalizedText(from: "caf\u{e9}\n")

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            ClipboardHistoryRepository.hash(forNormalizedText: first),
            ClipboardHistoryRepository.hash(forNormalizedText: second)
        )
    }

    func testSavingSameTextUpdatesExistingEntry() throws {
        let repository = makeRepository(limit: 10)
        let originalDate = Date(timeIntervalSince1970: 100)
        let updatedDate = Date(timeIntervalSince1970: 200)

        let originalEntry = try repository.saveText("  Hello world  ", at: originalDate)
        let updatedEntry = try repository.saveText("Hello world", at: updatedDate)

        XCTAssertEqual(originalEntry.id, updatedEntry.id)
        XCTAssertEqual(try fetchEntries().count, 1)
        XCTAssertEqual(updatedEntry.lastUsedAt, updatedDate)
    }

    func testPruningKeepsFavorites() throws {
        let repository = makeRepository(limit: 2)
        let favorite = try repository.saveText("favorite", at: Date(timeIntervalSince1970: 1))
        try repository.toggleFavorite(for: favorite)
        _ = try repository.saveText("old", at: Date(timeIntervalSince1970: 2))
        _ = try repository.saveText("newer", at: Date(timeIntervalSince1970: 3))
        _ = try repository.saveText("newest", at: Date(timeIntervalSince1970: 4))

        let entries = try fetchEntries()
        XCTAssertTrue(entries.contains(where: { $0.id == favorite.id && $0.isFavorite }))
        XCTAssertEqual(entries.filter { !$0.isFavorite }.count, 2)
        XCTAssertFalse(entries.contains(where: { $0.textContent == "old" }))
    }

    func testDeletingImageEntryRemovesImageFiles() throws {
        let paths = try imageStorage.storeImage(pngData: Data([1, 2, 3]), thumbnailPNGData: Data([4, 5, 6]))
        let entry = ClipboardEntry(
            contentKind: .image,
            contentHash: "image-hash",
            imageRelativePath: paths.imageRelativePath,
            thumbnailRelativePath: paths.thumbnailRelativePath
        )
        modelContext.insert(entry)
        try modelContext.save()

        try makeRepository(limit: 10).delete(entry)

        XCTAssertNil(imageStorage.imageData(atRelativePath: paths.imageRelativePath))
        XCTAssertNil(imageStorage.imageData(atRelativePath: paths.thumbnailRelativePath))
        XCTAssertTrue(try fetchEntries().isEmpty)
    }

    func testImageStorageBudgetPrunesOldestNonFavoriteImage() throws {
        let repository = ClipboardHistoryRepository(
            modelContext: modelContext,
            nonFavoriteLimit: 10,
            nonFavoriteImageStorageLimit: 10,
            imageStorage: imageStorage
        )
        let firstEntry = try repository.saveImage(
            pngData: Data([1, 2, 3, 4]),
            thumbnailPNGData: Data([5, 6]),
            at: Date(timeIntervalSince1970: 1)
        )
        let firstImagePath = try XCTUnwrap(firstEntry.imageRelativePath)

        _ = try repository.saveImage(
            pngData: Data([7, 8, 9, 10]),
            thumbnailPNGData: Data([11, 12]),
            at: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(try fetchEntries().count, 1)
        XCTAssertNil(imageStorage.imageData(atRelativePath: firstImagePath))
    }

    func testReconciliationRemovesUnreferencedImageFiles() throws {
        let orphanedPaths = try imageStorage.storeImage(
            pngData: Data([1, 2, 3]),
            thumbnailPNGData: Data([4, 5, 6])
        )

        let removedFileCount = try makeRepository(limit: 10).reconcileImageStorage()

        XCTAssertEqual(removedFileCount, 2)
        XCTAssertNil(imageStorage.imageData(atRelativePath: orphanedPaths.imageRelativePath))
        XCTAssertNil(imageStorage.imageData(atRelativePath: orphanedPaths.thumbnailRelativePath))
    }

    func testExcludedApplicationDecision() {
        let exclusions = ["com.example.password-manager"]

        XCTAssertFalse(ClipboardSettings.shouldCapture(
            frontmostApplicationBundleIdentifier: "com.example.password-manager",
            excludedBundleIdentifiers: exclusions
        ))
        XCTAssertTrue(ClipboardSettings.shouldCapture(
            frontmostApplicationBundleIdentifier: "com.example.editor",
            excludedBundleIdentifiers: exclusions
        ))
        XCTAssertTrue(ClipboardSettings.shouldCapture(
            frontmostApplicationBundleIdentifier: nil,
            excludedBundleIdentifiers: exclusions
        ))
    }

    private func makeRepository(limit: Int) -> ClipboardHistoryRepository {
        ClipboardHistoryRepository(
            modelContext: modelContext,
            nonFavoriteLimit: limit,
            imageStorage: imageStorage
        )
    }

    private func fetchEntries() throws -> [ClipboardEntry] {
        try modelContext.fetch(FetchDescriptor<ClipboardEntry>())
    }
}
