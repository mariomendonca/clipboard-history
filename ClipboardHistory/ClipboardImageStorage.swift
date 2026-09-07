import Foundation

struct ClipboardImageStorage {
    struct StoredImagePaths {
        let imageRelativePath: String
        let thumbnailRelativePath: String
    }

    static let shared = ClipboardImageStorage()

    private let fileManager: FileManager
    private let directoryURLOverride: URL?

    init(fileManager: FileManager = .default, directoryURLOverride: URL? = nil) {
        self.fileManager = fileManager
        self.directoryURLOverride = directoryURLOverride
    }

    /// The directory where full-size clipboard images and their thumbnails are kept.
    func imageDirectoryURL() throws -> URL {
        if let directoryURLOverride {
            try fileManager.createDirectory(at: directoryURLOverride, withIntermediateDirectories: true)
            return directoryURLOverride
        }

        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// Resolves a path previously stored on a `ClipboardEntry` without exposing an absolute user path in SwiftData.
    func imageURL(forRelativePath relativePath: String) throws -> URL {
        try imageDirectoryURL().appendingPathComponent(relativePath)
    }

    func removeImageFile(atRelativePath relativePath: String) throws {
        let fileURL = try imageURL(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func storeImage(pngData: Data, thumbnailPNGData: Data) throws -> StoredImagePaths {
        let identifier = UUID().uuidString
        let imageRelativePath = "\(identifier).png"
        let thumbnailRelativePath = "\(identifier)-thumbnail.png"

        do {
            try pngData.write(to: imageURL(forRelativePath: imageRelativePath), options: .atomic)
            try thumbnailPNGData.write(to: imageURL(forRelativePath: thumbnailRelativePath), options: .atomic)
            return StoredImagePaths(
                imageRelativePath: imageRelativePath,
                thumbnailRelativePath: thumbnailRelativePath
            )
        } catch {
            try? removeImageFile(atRelativePath: imageRelativePath)
            try? removeImageFile(atRelativePath: thumbnailRelativePath)
            throw error
        }
    }

    func imageData(atRelativePath relativePath: String) -> Data? {
        guard let fileURL = try? imageURL(forRelativePath: relativePath) else { return nil }
        return try? Data(contentsOf: fileURL)
    }
}
