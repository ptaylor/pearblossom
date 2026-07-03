import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Supported export formats.
enum ExportFormat: String, CaseIterable, Codable {
    case png = "png"
    case jpeg = "jpeg"

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

/// Writes a `CGImage` to disk as PNG or JPEG.
enum ExportWriter {

    /// Writes the image to a file at the given URL.
    /// - Parameters:
    ///   - image: The `CGImage` to write.
    ///   - url: The destination file URL.
    ///   - format: `.png` or `.jpeg`.
    ///   - jpegQuality: JPEG compression quality (0.0–1.0), ignored for PNG.
    ///   - dpi: Optional DPI to embed. If nil, no DPI metadata is written.
    ///          Use nil to match the source image's native DPI automatically.
    /// - Throws: If the write fails.
    static func write(
        _ image: CGImage,
        to url: URL,
        format: ExportFormat,
        jpegQuality: Double = 0.92,
        dpi: CGFloat? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            Logger.error("ExportWriter: failed to create CGImageDestination for \(url.path)")
            throw ExportError.cannotCreateDestination
        }

        let formatProperties: [CFString: Any]
        switch format {
        case .png:
            formatProperties = [:]
        case .jpeg:
            formatProperties = [
                kCGImageDestinationLossyCompressionQuality: jpegQuality
            ]
        }

        var options = formatProperties as [CFString: Any]

        // Embed DPI if provided (auto-detected from source images).
        // Without DPI metadata, some viewers default to a different DPI
        // and display the image at an unexpected physical size.
        if let dpi = dpi, dpi > 0 {
            options[kCGImagePropertyDPIWidth] = dpi
            options[kCGImagePropertyDPIHeight] = dpi
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            Logger.error("ExportWriter: CGImageDestinationFinalize failed for \(url.path)")
            throw ExportError.writeFailed
        }

        Logger.debug("ExportWriter: wrote \(format.displayName) to \(url.path) (quality: \(String(format: "%.2f", jpegQuality)))")
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case cannotCreateDestination
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestination:
            return "Could not create the output file."
        case .writeFailed:
            return "Failed to write the exported image to disk."
        }
    }
}
