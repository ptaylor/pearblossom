import AppKit
import CoreImage

/// The AppKit NSView that renders the collage canvas with drag-drop, CIImage compositing,
/// layer selection, move, and delete support.
final class CanvasNSView: NSView {

    // MARK: - Properties

    private let ciContext = CIContext()
    private var cachedComposite: CGImage?
    private var cachedCompositeExtent: CGRect = .zero  // Position of cached composite in CIImage space
    private var sourceImageCache: [UUID: CIImage] = [:]  // Cache loaded source images
    private var isDragging = false  // Skip full rebuild during drag

    var project: CollageProject? {
        didSet {
            cachedComposite = nil   // Always invalidate composite (fast rebuild with cached sources)
            cachedCompositeExtent = .zero
            if !isDragging {
                sourceImageCache = [:]  // Only clear source cache on non-drag changes
            }
            needsDisplay = true
        }
    }

    var onPhotosDropped: (([String], CGPoint) -> Void)?
    var onLayersChanged: (() -> Void)?

    private var selectedLayerIDs = Set<UUID>()
    private var dragOffset: CGPoint = .zero

    private var currentBackground: CGColor {
        project?.backgroundColor.cgColor ?? .white
    }

    // MARK: - Lifecycle

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .string, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }

        if let proj = project, !proj.layers.isEmpty {
            if proj.showBoundingBox {
                // Normal mode: entire canvas uses the background color
                cgContext.setFillColor(currentBackground)
                cgContext.fill(bounds)
            } else {
                // Fit Content / preview mode: margins show complementary greyscale,
                // bounding box area shows the actual background.
                let bb = proj.effectiveBoundingBox()
                cgContext.setFillColor(currentBackground.complementaryGreyscale)
                cgContext.fill(bounds)
                cgContext.setFillColor(currentBackground)
                cgContext.fill(bb)
            }

            renderLayers(proj, in: cgContext)

            if proj.showBoundingBox {
                drawBoundingBox(proj.effectiveBoundingBox(), on: currentBackground, in: cgContext)
            }
        } else if let proj = project {
            // No layers: fill entire canvas with background
            cgContext.setFillColor(currentBackground)
            cgContext.fill(bounds)
            if proj.showBoundingBox {
                drawBoundingBox(proj.effectiveBoundingBox(), on: currentBackground, in: cgContext)
            }
        } else {
            cgContext.setFillColor(currentBackground)
            cgContext.fill(bounds)
            drawPlaceholder(in: cgContext)
        }

        if let proj = project {
            for layer in proj.layers where selectedLayerIDs.contains(layer.id) {
                drawSelectionBorder(for: layer, in: cgContext)
            }
        }
    }

    private func renderLayers(_ proj: CollageProject, in cgContext: CGContext) {
        // Use cached composite if available
        if let cached = cachedComposite {
            drawCGImageFlipped(cached, extent: cachedCompositeExtent, canvasH: bounds.height, in: cgContext)
            return
        }

        let sorted = proj.layers.sorted { $0.zOrder < $1.zOrder }
        let canvasH = bounds.height
        var composite: CIImage?

        Logger.debug("renderLayers: rendering \(sorted.count) layers, canvasBounds=\(bounds), canvasH=\(canvasH)")

        for (idx, layer) in sorted.enumerated() {
            let resolvedPath = layer.resolvedPhotoPath()

            // Use cached source image or load with reduced resolution for display
            let sourceImage: CIImage
            let wasLoadedFromCache: Bool
            if let cached = sourceImageCache[layer.id] {
                sourceImage = cached
                wasLoadedFromCache = true
            } else {
                let url = URL(fileURLWithPath: resolvedPath)
                if let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
                    let originalExtent = img.extent
                    // Display at reduced size for performance
                    let maxDim: CGFloat = 1024
                    let extent = img.extent
                    if extent.width > maxDim || extent.height > maxDim {
                        let ds = min(maxDim / extent.width, maxDim / extent.height)
                        sourceImage = img.transformed(by: CGAffineTransform(scaleX: ds, y: ds))
                        Logger.debug("renderLayers: layer[\(idx)] id=\(layer.id) loaded ciExtent=\(originalExtent.size) downscale=\(ds) workingExtent=\(sourceImage.extent.size) sourceResolution=\(layer.sourceResolution) displaySize=\(layer.size)")
                    } else {
                        sourceImage = img
                        Logger.debug("renderLayers: layer[\(idx)] id=\(layer.id) loaded ciExtent=\(originalExtent.size) (no downscale) sourceResolution=\(layer.sourceResolution) displaySize=\(layer.size)")
                    }
                    sourceImageCache[layer.id] = sourceImage
                } else {
                    Logger.warn("renderLayers: layer[\(idx)] id=\(layer.id) failed to load CIImage from \(resolvedPath)")
                    continue
                }
                wasLoadedFromCache = false
            }

            let halfW = layer.size.width / 2
            let halfH = layer.size.height / 2

            var t = sourceImage

            // Scale to display size — use working CIImage extent (not sourceResolution)
            // because the CIImage may have been downscaled for performance (max 1024).
            let workingExtent = sourceImage.extent
            let sx = layer.size.width / max(workingExtent.width, 1)
            let sy = layer.size.height / max(workingExtent.height, 1)
            Logger.debug("renderLayers: layer[\(idx)] id=\(layer.id) scaleFactors sx=\(sx) sy=\(sy) (displaySize=\(layer.size) / workingExtent=\(workingExtent.size)) sourceResolution=\(layer.sourceResolution) cached=\(wasLoadedFromCache)")

            t = t.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            Logger.debug("renderLayers: layer[\(idx)] id=\(layer.id) after scaleToDisplay: extent=\(t.extent)")

            // Rotate around center
            t = t.transformed(by: CGAffineTransform(translationX: -halfW, y: -halfH))
            t = t.transformed(by: CGAffineTransform(rotationAngle: layer.rotation))
            t = t.transformed(by: CGAffineTransform(translationX: halfW, y: halfH))

            // CIImage (bottom-left origin) → flipped canvas (top-left origin) via CGContext flip
            // Layer bottom in CIImage = canvasH - (pos.y + halfH) = canvasH - pos.y - halfH
            t = t.transformed(by: CGAffineTransform(
                translationX: layer.position.x - halfW,
                y: canvasH - layer.position.y - halfH
            ))

            Logger.debug("renderLayers: layer[\(idx)] id=\(layer.id) finalPlacement: position(center)=\(layer.position) rotation=\(layer.rotation) finalExtent=\(t.extent)")

            // Opacity
            if layer.opacity < 1.0 {
                let f = CIFilter(name: "CIColorMatrix")!
                f.setValue(t, forKey: kCIInputImageKey)
                f.setValue(CIVector(x: 0, y: 0, z: 0, w: layer.opacity), forKey: "inputAVector")
                t = f.outputImage ?? t
            }

            // Composite
            if let existing = composite {
                let f = CIFilter(name: "CISourceOverCompositing")!
                f.setValue(t, forKey: kCIInputImageKey)
                f.setValue(existing, forKey: kCIInputBackgroundImageKey)
                composite = f.outputImage
            } else {
                composite = t
            }
        }

        // Generate and cache the CGImage, then draw at the correct canvas position
        if let final = composite, let cgImage = ciContext.createCGImage(final, from: final.extent) {
            cachedComposite = cgImage
            cachedCompositeExtent = final.extent
            drawCGImageFlipped(cgImage, extent: final.extent, canvasH: canvasH, in: cgContext)
        }
    }

    /// Draw a CGImage (built in CIImage bottom-left coords) into the flipped CGContext
    /// at the correct canvas position derived from the extent.
    private func drawCGImageFlipped(_ cgImage: CGImage, extent: CGRect, canvasH: CGFloat, in cgContext: CGContext) {
        // CIImage extent.origin is bottom-left in CIImage space.
        // Map to flipped canvas (top-left origin): canvas y = canvasH - ciY - height
        let drawRect = CGRect(
            x: extent.origin.x,
            y: canvasH - extent.origin.y - extent.height,
            width: extent.width,
            height: extent.height
        )
        cgContext.saveGState()
        // Position the flip anchor at the drawRect origin, then flip Y
        cgContext.translateBy(x: drawRect.origin.x, y: drawRect.origin.y + drawRect.height)
        cgContext.scaleBy(x: 1.0, y: -1.0)
        cgContext.draw(cgImage, in: CGRect(origin: .zero, size: drawRect.size))
        cgContext.restoreGState()
        Logger.debug("drawCGImageFlipped: extent(ci)=\(extent) drawRect(canvas)=\(drawRect)")
    }

    private func drawSelectionBorder(for layer: PhotoLayer, in context: CGContext) {
        let rect = CGRect(
            x: layer.position.x - layer.size.width / 2,
            y: layer.position.y - layer.size.height / 2,
            width: layer.size.width,
            height: layer.size.height
        )
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [4, 2])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawBoundingBox(_ rect: CGRect, on background: CGColor, in context: CGContext) {
        let bgBrightness = (background.components?[0] ?? 1) + (background.components?[1] ?? 1) + (background.components?[2] ?? 1)
        let dashColor: CGColor = bgBrightness > 1.5
            ? NSColor.black.withAlphaComponent(0.5).cgColor
            : NSColor.white.withAlphaComponent(0.5).cgColor
        context.setStrokeColor(dashColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [8, 4])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawPlaceholder(in context: CGContext) {
        let text = "Drag photos here"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .light),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: point, withAttributes: attrs)
    }

    // MARK: - Hit Testing

    private func layerAt(point: CGPoint) -> PhotoLayer? {
        guard let proj = project else { return nil }
        for layer in proj.layers.sorted(by: { $0.zOrder > $1.zOrder }) {
            let rect = CGRect(x: layer.position.x - layer.size.width / 2,
                              y: layer.position.y - layer.size.height / 2,
                              width: layer.size.width, height: layer.size.height)
            if rect.contains(point) { return layer }
        }
        return nil
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        let point = convert(event.locationInWindow, from: nil)
        if let layer = layerAt(point: point) {
            if event.modifierFlags.contains(.shift) {
                if selectedLayerIDs.contains(layer.id) { selectedLayerIDs.remove(layer.id) }
                else { selectedLayerIDs.insert(layer.id) }
            } else { selectedLayerIDs = [layer.id] }
            dragOffset = CGPoint(x: point.x - layer.position.x, y: point.y - layer.position.y)
            needsDisplay = true
        } else {
            selectedLayerIDs = []
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !selectedLayerIDs.isEmpty, var proj = project else { return }
        let point = convert(event.locationInWindow, from: nil)
        for id in selectedLayerIDs {
            if let index = proj.layers.firstIndex(where: { $0.id == id }) {
                proj.layers[index].position = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
            }
        }
        project = proj
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        cachedComposite = nil  // Rebuild clean composite on next draw
        if let proj = project {
            for id in selectedLayerIDs {
                if let layer = proj.layers.first(where: { $0.id == id }) {
                    Logger.debug("mouseUp: layer id=\(id) finalPosition=\(layer.position) size=\(layer.size) rotation=\(layer.rotation)")
                }
            }
        }
        needsDisplay = true
        onLayersChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), !selectedLayerIDs.isEmpty, var proj = project {
            proj.layers.removeAll { selectedLayerIDs.contains($0.id) }
            selectedLayerIDs = []
            proj.modifiedAt = Date()
            project = proj
            needsDisplay = true
            onLayersChanged?()
        } else { super.keyDown(with: event) }
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        var paths: [String] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            paths = urls.map { $0.path }
        }
        if paths.isEmpty, let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            // Support newline-separated paths (multi-select drag from collection browser)
            paths = strings.flatMap { $0.components(separatedBy: "\n").filter { !$0.isEmpty } }
        }
        guard !paths.isEmpty, let window = window else { return false }
        let mouseScreen = NSEvent.mouseLocation
        let mouseWindow = window.convertPoint(fromScreen: mouseScreen)
        let dropPoint = convert(mouseWindow, from: nil)
        Logger.debug("performDragOperation: paths=\(paths.count) files, mouseScreen=\(mouseScreen), mouseWindow=\(mouseWindow), dropPoint(in canvas)=\(dropPoint), canvasFrame=\(frame), isFlipped=\(isFlipped)")
        onPhotosDropped?(paths, dropPoint)
        return true
    }

    override var isFlipped: Bool { true }
    override func layout() { super.layout(); layer?.frame = bounds }
}

// MARK: - CGColor Complementary Greyscale

private extension CGColor {
    /// Returns the complementary greyscale: inverts the luminance.
    /// White → black, black → white, 40% grey → 60% grey, etc.
    var complementaryGreyscale: CGColor {
        guard let comps = components, comps.count >= 3 else { return self }
        let r = comps[0]
        // Invert the grey: 1.0 - grey, then clamp to a visible range
        // so 50% grey doesn't map to itself (invisible).
        let inv = 1.0 - r
        // Push mid-greys away from center so there's always contrast
        let adjusted: CGFloat
        if inv > 0.45 && inv < 0.55 {
            adjusted = inv >= 0.5 ? 0.7 : 0.3
        } else {
            adjusted = inv
        }
        return CGColor(red: adjusted, green: adjusted, blue: adjusted, alpha: 1.0)
    }
}
