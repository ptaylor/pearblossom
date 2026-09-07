import Foundation
import CoreGraphics
import ImageIO

/// Orchestrates importing a Picasa `.cxf` file into a `CollageProject` + `PhotoCollection`.
enum CollageImporter {

    struct ImportResult {
        let project: CollageProject
        let collection: PhotoCollection
        let skippedSources: [String]
        /// For `.copy` mode: absolute source path for each copied photo, keyed by photo id.
        let copySources: [UUID: String]
    }

    /// Parses and converts a `.cxf` file into in-memory models.
    /// - Parameters:
    ///   - cxfURL: The `.cxf` file on disk.
    ///   - name: Display name for the new collage and collection.
    ///   - description: Optional description for both.
    ///   - importMode: Link source photos (`.reference`) or copy them into the collection (`.copy`).
    /// - Returns: The new project + collection (not yet written to disk), plus skipped source paths.
    static func importCollage(from cxfURL: URL, name: String, description: String, importMode: ImportMode = .reference) throws -> ImportResult {
        let data = try Data(contentsOf: cxfURL)
        let collage = try CXFParser.parse(data)

        let (canvasW, canvasH) = canvasDimensions(format: collage.format, orientation: collage.orientation)
        let background = parseBackground(collage.background)

        // Translate node paths and dedupe into one CollectionPhoto per unique source.
        var photosByPath: [String: CollectionPhoto] = [:]
        var photoOrder: [String] = []
        var skipped: [String] = []
        var copySources: [UUID: String] = [:]
        var usedDestinationNames = Set<String>()

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
                let photo: CollectionPhoto
                if importMode == .copy {
                    let destinationName = destinationFilename(for: resolved, used: &usedDestinationNames)
                    photo = CollectionPhoto(path: destinationName)
                    copySources[photo.id] = resolved
                } else {
                    photo = CollectionPhoto(path: resolved)
                }
                photosByPath[resolved] = photo
                photoOrder.append(resolved)
            }
        }

        let collection = PhotoCollection(
            name: name,
            description: description,
            folderPath: nil,
            photos: photoOrder.map { photosByPath[$0]! },
            importMode: importMode,
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
            // Picasa stores (x, y) as the photo's top-left corner. Reproduce its
            // layout: the rotation is negated (Pearblossom positive = clockwise)
            // and the stored center is offset by R_cw(theta) * (w/2, h/2).
            let halfW = size.width / 2
            let halfH = size.height / 2
            let cosTheta = cos(node.theta)
            let sinTheta = sin(node.theta)
            let centerX = node.x * Double(canvasW) + Double(halfW) * cosTheta - Double(halfH) * sinTheta
            let centerY = node.y * Double(canvasH) + Double(halfW) * sinTheta + Double(halfH) * cosTheta
            let position = CGPoint(x: centerX, y: centerY)
            let sourceResolution = imageDimensions(at: resolved) ?? .zero

            let layer = PhotoLayer(
                photoPath: resolved,
                collectionID: collection.id,
                photoID: photo.id,
                position: position,
                size: size,
                // Picasa stores (x, y) as the photo's top-left corner and rotates
                // around it. Pearblossom renders positive rotation clockwise, so
                // the angle is negated and the center offset accordingly.
                rotation: -node.theta,
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
        return ImportResult(project: project, collection: collection, skippedSources: skipped, copySources: copySources)
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

    /// Returns a collision-free destination filename for a copied photo.
    private static func destinationFilename(for source: String, used: inout Set<String>) -> String {
        let sourceURL = URL(fileURLWithPath: source)
        let original = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension
        let base = (original as NSString).deletingPathExtension

        var candidate = original
        var counter = 2
        while used.contains(candidate) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        used.insert(candidate)
        return candidate
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
