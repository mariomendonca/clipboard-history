import AppKit
import Foundation

enum ClipboardImageCodec {
    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func thumbnailPNGData(from image: NSImage, maximumDimension: CGFloat = 240) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let scale = min(maximumDimension / image.size.width, maximumDimension / image.size.height, 1)
        let thumbnailSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumbnail = NSImage(size: thumbnailSize)

        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnail.unlockFocus()

        return pngData(from: thumbnail)
    }
}
