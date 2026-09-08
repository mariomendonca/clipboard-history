import AppKit
import SwiftData

@MainActor
final class ClipboardMonitor {
    private static var activeMonitor: ClipboardMonitor?

    private let pasteboard: NSPasteboard
    private let modelContext: ModelContext
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?
    private var timer: Timer?

    init(modelContainer: ModelContainer, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.modelContext = ModelContext(modelContainer)
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        Self.activeMonitor = self
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.captureCurrentPasteboardContentsIfNeeded()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if Self.activeMonitor === self {
            Self.activeMonitor = nil
        }
    }

    func ignoreChange(withCount changeCount: Int) {
        ignoredChangeCount = changeCount
    }

    @discardableResult
    static func copyTextToGeneralPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWriteText = pasteboard.setString(text, forType: .string)

        if didWriteText {
            activeMonitor?.ignoreChange(withCount: pasteboard.changeCount)
        }

        return didWriteText
    }

    @discardableResult
    static func copyImageToGeneralPasteboard(imageData: Data) -> Bool {
        guard let image = NSImage(data: imageData) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWriteImage = pasteboard.writeObjects([image])

        if didWriteImage {
            activeMonitor?.ignoreChange(withCount: pasteboard.changeCount)
        }

        return didWriteImage
    }

    private func captureCurrentPasteboardContentsIfNeeded() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if currentChangeCount == ignoredChangeCount {
            ignoredChangeCount = nil
            return
        }

        let frontmostApplicationBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard ClipboardSettings.shouldCapture(frontmostApplicationBundleIdentifier: frontmostApplicationBundleIdentifier) else {
#if DEBUG
            print("ClipboardHistory skipped capture for an excluded application.")
#endif
            return
        }

        let repository = ClipboardHistoryRepository(modelContext: modelContext)

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
            try repository.saveText(text)
#if DEBUG
            print("ClipboardHistory captured text (\(text.count) characters).")
#endif
            } catch {
#if DEBUG
            print("ClipboardHistory failed to save a captured entry: \(error.localizedDescription)")
#endif
            }
            return
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let pixelCount = ClipboardImageCodec.pixelCount(of: image),
              pixelCount <= ClipboardSettings.maximumCapturedImagePixelCount,
              let pngData = ClipboardImageCodec.pngData(from: image),
              pngData.count <= ClipboardSettings.maximumCapturedImageByteCount,
              let thumbnailPNGData = ClipboardImageCodec.thumbnailPNGData(from: image) else {
#if DEBUG
            print("ClipboardHistory skipped an unreadable or oversized image.")
#endif
            return
        }

        do {
            try repository.saveImage(pngData: pngData, thumbnailPNGData: thumbnailPNGData)
#if DEBUG
            print("ClipboardHistory captured image (\(pngData.count) bytes).")
#endif
        } catch {
#if DEBUG
            print("ClipboardHistory failed to save a captured image: \(error.localizedDescription)")
#endif
        }
    }
}
