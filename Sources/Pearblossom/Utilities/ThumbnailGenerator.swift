import AppKit
import Foundation

/// Generates and caches JPEG thumbnails for collection photos.
enum ThumbnailGenerator {

    /// Name of the hidden subfolder for cached thumbnails.
    static let thumbnailsDirName = ".thumbnails"

    /// The current thumbnail size from app settings.
    static var thumbnailSize: CGFloat {
        AppSettings.shared.thumbnailSize
    }

    // MARK: - Public API

    /// Generates a thumbnail for a photo and saves it in the collection's `.thumbnails/` directory.
    /// - Parameters:
    ///   - photoPath: Absolute path to the source photo.
    ///   - collectionFolder: The URL of the collection folder.
    /// - Returns: The absolute path to the saved thumbnail JPEG, or nil on failure.
    static func generateThumbnail(for photoPath: String, in collectionFolder: URL) -> String? {
        Logger.debug("generating thumbnail for \(photoPath) in \(collectionFolder.path)")
        let sourceURL = URL(fileURLWithPath: photoPath)

        // Ensure thumbs directory exists
        let thumbsDir = collectionFolder.appendingPathComponent(thumbnailsDirName, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: thumbsDir.path) {
            try? fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        }

        // Generate a unique thumbnail filename based on the source filename + UUID
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let thumbFilename = "\(sourceName)_thumb.jpg"
        let thumbURL = thumbsDir.appendingPathComponent(thumbFilename)

        // Load and resize
        guard let sourceImage = NSImage(contentsOf: sourceURL) else { return nil }

        let size = thumbnailSize
        let resized = sourceImage.resizedToFit(size)
        guard let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Write as JPEG
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = resized.size
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            return nil
        }

        do {
            try jpegData.write(to: thumbURL)
            return thumbURL.path
        } catch {
            return nil
        }
    }

    /// Deletes the `.thumbnails/` directory for a collection, if it exists.
    static func deleteThumbnailsDir(in collectionFolder: URL) {
        let thumbsDir = collectionFolder.appendingPathComponent(thumbnailsDirName, isDirectory: true)
        try? FileManager.default.removeItem(at: thumbsDir)
    }
}

// MARK: - NSImage Resize

private extension NSImage {
    /// Resize to fit within `maxDimension` while preserving aspect ratio. Never upscales.
    func resizedToFit(_ maxDimension: CGFloat) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}
