import CoreImage
import CoreGraphics
import Foundation

/// Renders a `CollageProject` to a `CGImage` for export.
/// Uses the same Core Image compositing pipeline as `CanvasNSView` but at export resolution.
/// Scale multipliers are relative to source image resolution (1× = source pixels, no scaling).
enum ExportRenderer {

    // MARK: - Public API

    /// Renders the collage at the given scale multiplier.
    /// - Parameters:
    ///   - project: The collage project with layers, background, and bounding box.
    ///   - scaleMultiplier: 1.0 = source resolution (each photo at its native pixels),
    ///     0.5 = half source resolution, 2.0 = double source resolution.
    ///   - context: A `CIContext` for the final render (shared for performance).
    /// - Returns: A `CGImage` of the rendered export, or nil on failure.
    static func render(
        project: CollageProject,
        scaleMultiplier: Double,
        context: CIContext
    ) -> CGImage? {
        let bb = project.effectiveBoundingBox()
        guard bb.width > 0, bb.height > 0 else {
            Logger.warn("ExportRenderer: invalid bounding box bb=\(bb)")
            return nil
        }

        // Compute the base ratio: how many export pixels per canvas point.
        // This is derived from the layers' sourceResolution / display-size ratios
        // so that at 1× each photo renders at its native pixel resolution.
        let baseRatio = computeBaseRatio(project: project)
        let exportScale = scaleMultiplier * baseRatio

        // Safety cap at 16384px
        let maxDim: CGFloat = 16384
        let effectiveScale = min(exportScale, maxDim / max(bb.width, bb.height))

        let composite = buildComposite(
            project: project,
            scaleX: effectiveScale,
            scaleY: effectiveScale,
            boundingBox: bb
        )
        guard let final = composite else {
            Logger.warn("ExportRenderer: composite build returned nil (scaleMultiplier=\(scaleMultiplier), baseRatio=\(baseRatio))")
            return nil
        }

        let cgImage = context.createCGImage(final, from: final.extent)
        if cgImage == nil {
            Logger.error("ExportRenderer: context.createCGImage returned nil for extent=\(final.extent)")
        } else {
            let pxW = Int(final.extent.width)
            let pxH = Int(final.extent.height)
            Logger.debug("ExportRenderer: rendered \(pxW)×\(pxH) px (scaleMultiplier=\(scaleMultiplier), baseRatio=\(String(format: "%.2f", baseRatio)))")
        }
        return cgImage
    }

    /// Returns the output pixel dimensions for the given scale multiplier
    /// (without actually rendering). Used by the UI to preview output size.
    static func outputPixelSize(project: CollageProject, scaleMultiplier: Double) -> CGSize {
        let bb = project.effectiveBoundingBox()
        guard bb.width > 0, bb.height > 0 else { return .zero }

        let baseRatio = computeBaseRatio(project: project)
        let exportScale = scaleMultiplier * baseRatio

        let maxDim: CGFloat = 16384
        let effectiveScale = min(exportScale, maxDim / max(bb.width, bb.height))

        return CGSize(
            width: ceil(bb.width * effectiveScale),
            height: ceil(bb.height * effectiveScale)
        )
    }

    // MARK: - Scale Computation

    /// Computes the canvas-points → export-pixels ratio from the layers'
    /// sourceResolution / display-size ratios. Uses the maximum ratio across
    /// all layers so that at 1× every photo renders at ≥ its native resolution.
    private static func computeBaseRatio(project: CollageProject) -> CGFloat {
        let ratios = project.layers.compactMap { layer -> CGFloat? in
            guard layer.sourceResolution.width > 0, layer.sourceResolution.height > 0,
                  layer.size.width > 0, layer.size.height > 0 else { return nil }
            return max(
                layer.sourceResolution.width / layer.size.width,
                layer.sourceResolution.height / layer.size.height
            )
        }
        return ratios.max() ?? 1.0
    }

    /// Reads the DPI from the first source photo with available metadata.
    /// Returns nil if no DPI can be determined (caller should fall back to 72).
    static func detectSourceDPI(project: CollageProject) -> CGFloat? {
        for layer in project.layers {
            let path = layer.resolvedPhotoPath()
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
                continue
            }
            guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
                continue
            }
            // Try DPI width first (most common)
            if let dpi = props[kCGImagePropertyDPIWidth] as? CGFloat, dpi > 0 {
                return dpi
            }
            // Fallback: TIFF dictionary may contain DPI
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let dpi = tiff[kCGImagePropertyTIFFXResolution] as? CGFloat, dpi > 0 {
                return dpi
            }
        }
        return nil
    }

    // MARK: - Compositing

    /// Builds the full CIImage filter graph: background fill + all layers composited in z-order.
    /// The output CIImage extent is `pixelSize` (origin .zero).
    private static func buildComposite(
        project: CollageProject,
        scaleX: CGFloat,
        scaleY: CGFloat,
        boundingBox: CGRect
    ) -> CIImage? {
        let outputWidth = ceil(boundingBox.width * scaleX)
        let outputHeight = ceil(boundingBox.height * scaleY)

        // Fill background
        let bg = CIImage(color: CIColor(cgColor: project.backgroundColor.cgColor))
            .cropped(to: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        var composite: CIImage = bg

        let sorted = project.layers.sorted { $0.zOrder < $1.zOrder }

        for layer in sorted {
            let resolvedPath = layer.resolvedPhotoPath()
            let url = URL(fileURLWithPath: resolvedPath)

            guard let sourceImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                Logger.warn("ExportRenderer: failed to load source image from \(resolvedPath), skipping layer \(layer.id)")
                continue
            }

            // Scale: source pixels → export pixels.
            // Layer occupies `layer.size` points in canvas space.
            // In export space, that becomes layer.size * scale.
            let displayW = layer.size.width * scaleX
            let displayH = layer.size.height * scaleY

            let sourceExt = sourceImage.extent
            let sx = displayW / max(sourceExt.width, 1)
            let sy = displayH / max(sourceExt.height, 1)

            let halfW = displayW / 2
            let halfH = displayH / 2
            let sourceHalfW = sourceExt.width / 2
            let sourceHalfH = sourceExt.height / 2

            var t = sourceImage

            // Rotate around source center at full resolution FIRST,
            // then scale to display size. This preserves source pixel
            // data through the rotation step so Core Image can
            // anti-alias from the full-resolution image.
            t = t.transformed(by: CGAffineTransform(translationX: -sourceHalfW, y: -sourceHalfH))
            t = t.transformed(by: CGAffineTransform(rotationAngle: layer.rotation))
            t = t.transformed(by: CGAffineTransform(translationX: sourceHalfW, y: sourceHalfH))

            // Scale from source space to display space
            t = t.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

            // Position relative to bounding box origin.
            // Canvas uses top-left origin; CIImage uses bottom-left origin.
            // Flip Y: ciY = outputHeight - canvasY.
            // (layer.position.y - bb.origin.y) * scaleY gives canvas-space Y
            // relative to the top of the bounding box.
            // -halfW/-halfH converts from center-based to corner-based positioning.
            let exportX = (layer.position.x - boundingBox.origin.x) * scaleX - halfW
            let exportY = outputHeight - (layer.position.y - boundingBox.origin.y) * scaleY - halfH

            t = t.transformed(by: CGAffineTransform(translationX: exportX, y: exportY))

            // Opacity
            if layer.opacity < 1.0 {
                let f = CIFilter(name: "CIColorMatrix")!
                f.setValue(t, forKey: kCIInputImageKey)
                f.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)), forKey: "inputAVector")
                t = f.outputImage ?? t
            }

            // Composite over background
            let f = CIFilter(name: "CISourceOverCompositing")!
            f.setValue(t, forKey: kCIInputImageKey)
            f.setValue(composite, forKey: kCIInputBackgroundImageKey)
            if let result = f.outputImage {
                composite = result
            }
        }

        return composite
    }
}
