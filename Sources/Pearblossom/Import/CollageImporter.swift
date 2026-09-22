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

        let canvasSize = CXFCanvasGeometry.dimensions(format: collage.format, orientation: collage.orientation)
        let canvasW = canvasSize.width
        let canvasH = canvasSize.height
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
            let halfW = size.width / 2
            let halfH = size.height / 2
            let cosTheta = cos(node.theta)
            let sinTheta = sin(node.theta)

            // Picasa positions the box's centre at the anchor plus the half-extents rotated by
            // `theta` — but it uses the half-WIDTH for both axes (the same class of half-extent
            // mix-up this importer used to have, with halfW instead of halfH):
            //     centre = (x·W + halfW·cosθ − halfW·sinθ, y·H + halfW·sinθ + halfW·cosθ)
            // At θ = 0 that reduces to centre = (x·W + halfW, y·H + halfW), i.e. the box sits
            // (halfW − halfH) lower than the stored y implies — which is why a Picasa panorama's
            // horizon lines up and ours didn't, and why the effect varies per photo.
            //
            // Derived empirically by compositing the real source photos with the CXF geometry
            // and comparing against Picasa's own exports (mean pixel error, lower is better).
            // Files below are a 25:20 landscape, a 297:210 landscape and a 297:210 portrait:
            //     no correction                     29.8 / 25.6 / 10.6
            //     best uniform y shift               5.8 / 13.8 /  4.6
            //     θ=0 offset (halfW−halfH only)      1.3 / 10.6 /  1.9
            //     this rule                          1.3 /  8.3 /  0.9
            // On the shadow-free file it beats a free per-photo (dx, dy) fit (1.3 vs 2.3), which
            // is what identifies it as the rule rather than a fit. Applying the same offset to x
            // as well, or offsetting x alone, both make every file substantially worse — there
            // is no horizontal counterpart.
            //
            // Not yet verified for portrait-aspect photos (where halfW < halfH, so the offset
            // inverts) and left out of `multiexp` for now, since all evidence is picturepile.
            let useHalfExtentOffset = collage.theme == "picturepile"
            // Second half-extent of the rotated offset: halfW for picturepile (see above),
            // halfH for multiexp, which keeps the symmetric behaviour until verified.
            let offsetHalfH = useHalfExtentOffset ? Double(halfW) : Double(halfH)
            let centerX = node.x * Double(canvasW) + Double(halfW) * cosTheta - offsetHalfH * sinTheta
            let centerY = node.y * Double(canvasH) + Double(halfW) * sinTheta + offsetHalfH * cosTheta
            let position = CGPoint(x: centerX, y: centerY)
            let sourceResolution = imageDimensions(at: resolved) ?? .zero
            warnOnAspectMismatch(node: node, size: size, sourceResolution: sourceResolution)

            let layer = PhotoLayer(
                photoPath: resolved,
                collectionID: collection.id,
                photoID: photo.id,
                position: position,
                size: size,
                // Picasa's positive theta is clockwise, matching Pearblossom's renderer.
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
            borderMargin: collage.theme == "multiexp" ? 0 : AppSettings.shared.defaultBorderMargin,
            isMultiExposure: collage.theme == "multiexp",
            createdAt: Date(),
            modifiedAt: Date()
        )

        Logger.debug("Picasa import: parsed '\(name)' — theme=\(collage.theme), \(layers.count) layer(s), \(collection.photos.count) unique photo(s), \(skipped.count) skipped")
        return ImportResult(project: project, collection: collection, skippedSources: skipped, copySources: copySources)
    }

    // MARK: - Helpers

    /// Logs when a node's box aspect diverges from the photo's real aspect ratio.
    ///
    /// Layers are drawn by scaling the source image non-uniformly to fill `size`
    /// (`CanvasNSView.renderLayers`), so any mismatch renders as a visible stretch.
    /// Picasa normally stores boxes matching the photo, so a large delta indicates a stale
    /// or manually-adjusted node — surface it rather than silently distorting the photo.
    private static func warnOnAspectMismatch(node: CXFNode, size: CGSize, sourceResolution: CGSize) {
        guard sourceResolution.width > 0, sourceResolution.height > 0,
              size.width > 0, size.height > 0 else { return }

        let boxAspect = size.width / size.height
        let photoAspect = sourceResolution.width / sourceResolution.height
        let delta = abs(boxAspect / photoAspect - 1)
        guard delta > 0.02 else { return }

        Logger.warn("""
            Picasa import: node '\(node.src ?? "<no src>")' box \(Int(size.width))×\(Int(size.height)) \
            (aspect \(String(format: "%.3f", boxAspect)), theme \(node.theme ?? "default")) does not match \
            photo aspect \(String(format: "%.3f", photoAspect)) — off by \(String(format: "%.1f", delta * 100))%; \
            the photo will be stretched to fill the box
            """)
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
