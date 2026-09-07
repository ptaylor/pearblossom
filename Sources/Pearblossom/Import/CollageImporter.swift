import Foundation
import CoreGraphics
import ImageIO

/// Orchestrates importing a Picasa `.cxf` file into a `CollageProject` + `PhotoCollection`.
enum CollageImporter {

    struct ImportResult {
        let project: CollageProject
        let collection: PhotoCollection
        let skippedSources: [String]
    }

    /// Parses and converts a `.cxf` file into in-memory models.
    /// - Parameters:
    ///   - cxfURL: The `.cxf` file on disk.
    ///   - name: Display name for the new collage and collection.
    ///   - description: Optional description for both.
    /// - Returns: The new project + collection (not yet written to disk), plus skipped source paths.
    static func importCollage(from cxfURL: URL, name: String, description: String) throws -> ImportResult {
        let data = try Data(contentsOf: cxfURL)
        let collage = try CXFParser.parse(data)

        let (canvasW, canvasH) = canvasDimensions(format: collage.format, orientation: collage.orientation)
        let background = parseBackground(collage.background)

        // Translate node paths and dedupe into one CollectionPhoto per unique source.
        var photosByPath: [String: CollectionPhoto] = [:]
        var photoOrder: [String] = []
        var skipped: [String] = []

        for node in collage.nodes {
            guard let rawSource = node.src else { continue }
            guard let resolved = WinePathTranslator.translate(rawSource) else {
                skipped.append(rawSource)
                Logger.warn("Picasa import: could not translate path '\(rawSource)'")
                continue
            }
            guard FileManager.default.fileExists(atPath: resolved) else {
                skipped.append(resolved)
                Logger.warn("Picasa import: source file missing '\(resolved)'")
                continue
            }
            if photosByPath[resolved] == nil {
                photosByPath[resolved] = CollectionPhoto(path: resolved)
                photoOrder.append(resolved)
            }
        }

        let collection = PhotoCollection(
            name: name,
            description: description,
            folderPath: nil,
            photos: photoOrder.map { photosByPath[$0]! },
            importMode: .reference,
            createdAt: Date(),
            modifiedAt: Date()
        )

        // Build canvas layers in XML order (first node = bottom, last = top).
        var layers: [PhotoLayer] = []
        var zOrder = 0
        for node in collage.nodes {
            guard let rawSource = node.src,
                  let resolved = WinePathTranslator.translate(rawSource),
                  let photo = photosByPath[resolved] else {
                continue
            }

            let size = CGSize(width: node.w * Double(canvasW), height: node.h * Double(canvasH))
            let position = CGPoint(x: node.x * Double(canvasW), y: node.y * Double(canvasH))
            let sourceResolution = imageDimensions(at: resolved) ?? .zero

            let layer = PhotoLayer(
                photoPath: resolved,
                collectionID: collection.id,
                photoID: photo.id,
                position: position,
                size: size,
                rotation: node.theta,
                zOrder: zOrder,
                opacity: node.alpha ?? 1.0,
                sourceResolution: sourceResolution,
                shadowRadius: shadowRadius(for: collage, node: node)
            )
            layers.append(layer)
            zOrder += 1
        }

        let project = CollageProject(
            name: name,
            description: description,
            filePath: nil,
            canvasWidth: canvasW,
            canvasHeight: canvasH,
            backgroundColor: background,
            layers: layers,
            borderMargin: AppSettings.shared.defaultBorderMargin,
            isMultiExposure: collage.theme == "multiexp",
            createdAt: Date(),
            modifiedAt: Date()
        )

        Logger.debug("Picasa import: parsed '\(name)' — theme=\(collage.theme), \(layers.count) layer(s), \(collection.photos.count) unique photo(s), \(skipped.count) skipped")
        return ImportResult(project: project, collection: collection, skippedSources: skipped)
    }

    // MARK: - Helpers

    /// Derives a point-based canvas size from the `format` ratio. The long side is 2000 pt.
    private static func canvasDimensions(format: String?, orientation: String?) -> (CGFloat, CGFloat) {
        let parts = (format ?? "4:3").split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return (2000, 1500)
        }
        let width = parts[0]
        let height = parts[1]
        let longSide: CGFloat = 2000
        if width >= height {
            return (longSide, (longSide * CGFloat(height / width)).rounded())
        } else {
            return ((longSide * CGFloat(width / height)).rounded(), longSide)
        }
    }

    /// Parses an AARRGGBB background into a `CodableColor`. Defaults to white.
    private static func parseBackground(_ background: CXFBackground?) -> CodableColor {
        guard let hex = background?.color else { return .white }
        return CodableColor(argbHex: hex) ?? .white
    }

    /// Decides whether a node gets a drop shadow. Only picturepile renders shadows.
    private static func shadowRadius(for collage: CXFCollage, node: CXFNode) -> CGFloat {
        guard collage.theme == "picturepile" else { return 0 }
        if node.theme?.lowercased() == "whiteframe" {
            return 10
        }
        if collage.shadows {
            return 8
        }
        return 0
    }

    /// Reads pixel dimensions without fully decoding the image.
    private static func imageDimensions(at path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

extension CodableColor {
    /// Initializes from a Picasa AARRGGBB hex string (e.g. "FFFFFFFF" = opaque white).
    init?(argbHex: String) {
        var string = argbHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") {
            string = String(string.dropFirst())
        }
        guard string.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: string).scanHexInt64(&value) else { return nil }

        let alpha = CGFloat((value >> 24) & 0xFF) / 255.0
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
