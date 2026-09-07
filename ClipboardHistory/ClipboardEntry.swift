import Foundation
import SwiftData

enum ClipboardContentKind: String, Codable, CaseIterable {
    case text
    case image
}

@Model
final class ClipboardEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lastUsedAt: Date
    var isFavorite: Bool
    var contentKindRawValue: String
    var contentHash: String
    var textContent: String?
    var imageRelativePath: String?
    var thumbnailData: Data?
    var thumbnailRelativePath: String?

    var contentKind: ClipboardContentKind {
        get { ClipboardContentKind(rawValue: contentKindRawValue) ?? .text }
        set { contentKindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        isFavorite: Bool = false,
        contentKind: ClipboardContentKind,
        contentHash: String,
        textContent: String? = nil,
        imageRelativePath: String? = nil,
        thumbnailData: Data? = nil,
        thumbnailRelativePath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isFavorite = isFavorite
        self.contentKindRawValue = contentKind.rawValue
        self.contentHash = contentHash
        self.textContent = textContent
        self.imageRelativePath = imageRelativePath
        self.thumbnailData = thumbnailData
        self.thumbnailRelativePath = thumbnailRelativePath
    }
}
