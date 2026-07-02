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

    // MARK: - Interaction State

    private enum InteractionMode {
        case none
        case moving
        case rotating
        case resizing(corner: ResizeCorner)
    }

    private enum ResizeCorner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private var interactionMode: InteractionMode = .none
    private var rotationStartAngle: CGFloat = 0      // initial mouse angle when rotation began
    private var rotationStartLayerAngle: CGFloat = 0  // initial layer rotation when rotation began
    private var resizeStartSize: CGSize = .zero       // initial layer size when resize began
    private var resizeStartPosition: CGPoint = .zero  // initial layer position when resize began
    private var resizeOppositeCorner: CGPoint = .zero // anchor corner (doesn't move)
    private var resizeAspectRatio: CGFloat = 1.0      // width/height of layer at resize start

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

        // Only show handles when exactly one layer is selected
        guard selectedLayerIDs.count == 1, let proj = project,
              proj.layers.first(where: { $0.id == layer.id }) != nil else { return }

        // Rotation knob — small circle above top-center
        let knobRadius: CGFloat = 4
        let knobCenter = CGPoint(x: layer.position.x, y: rect.minY - 12)
        let knobRect = CGRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius,
                              width: knobRadius * 2, height: knobRadius * 2)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fillEllipse(in: knobRect)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: knobRect)

        // Line connecting knob to selection border
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: layer.position.x, y: rect.minY))
        context.addLine(to: knobCenter)
        context.strokePath()

        // Rotation symbol — curved arrow centered on the knob, rotated +45°
        let symbolCX = knobCenter.x
        let symbolCY = knobCenter.y
        let symbolR: CGFloat = 10
        let rotOffset: CGFloat = .pi / 4  // +45° rotation
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: symbolCX, y: symbolCY), radius: symbolR,
                       startAngle: -.pi / 3 + rotOffset, endAngle: .pi * 2 / 3 + rotOffset, clockwise: true)
        context.strokePath()
        // Arrowhead
        let arrowAngle: CGFloat = .pi * 2 / 3 + rotOffset
        let arrowTip = CGPoint(x: symbolCX + symbolR * cos(arrowAngle),
                               y: symbolCY + symbolR * sin(arrowAngle))
        let arrowLen: CGFloat = 5
        let a1 = arrowAngle + .pi + 0.5
        let a2 = arrowAngle + .pi - 0.5
        context.move(to: arrowTip)
        context.addLine(to: CGPoint(x: arrowTip.x + arrowLen * cos(a1),
                                     y: arrowTip.y + arrowLen * sin(a1)))
        context.move(to: arrowTip)
        context.addLine(to: CGPoint(x: arrowTip.x + arrowLen * cos(a2),
                                     y: arrowTip.y + arrowLen * sin(a2)))
        context.setLineWidth(1.5)
        context.setLineCap(.butt)
        context.strokePath()

        // Resize handles — small squares at corners with directional arrows outside
        let handleSize: CGFloat = 7
        let arrowOffset: CGFloat = 7  // distance outside the corner
        let handles: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: rect.minX, y: rect.minY), .topLeft),
            (CGPoint(x: rect.maxX, y: rect.minY), .topRight),
            (CGPoint(x: rect.minX, y: rect.maxY), .bottomLeft),
            (CGPoint(x: rect.maxX, y: rect.maxY), .bottomRight),
        ]
        for (pt, corner) in handles {
            let handleRect = CGRect(x: pt.x - handleSize/2, y: pt.y - handleSize/2,
                                    width: handleSize, height: handleSize)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(handleRect)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(handleRect)

            // Directional resize arrows — larger and placed outside the corner
            let dx: CGFloat = 5
            let dy: CGFloat = 5
            let arrows: [(CGPoint, CGPoint)]
            switch corner {
            case .topLeft:
                let base = CGPoint(x: pt.x - arrowOffset, y: pt.y - arrowOffset)
                arrows = [(CGPoint(x: base.x + dx, y: base.y + dy), CGPoint(x: base.x - dx, y: base.y - dy)),
                          (CGPoint(x: base.x - dx, y: base.y - dy), CGPoint(x: base.x - dx*0.3, y: base.y - dy*1.5)),
                          (CGPoint(x: base.x - dx, y: base.y - dy), CGPoint(x: base.x - dx*1.5, y: base.y - dy*0.3))]
            case .topRight:
                let base = CGPoint(x: pt.x + arrowOffset, y: pt.y - arrowOffset)
                arrows = [(CGPoint(x: base.x - dx, y: base.y + dy), CGPoint(x: base.x + dx, y: base.y - dy)),
                          (CGPoint(x: base.x + dx, y: base.y - dy), CGPoint(x: base.x + dx*0.3, y: base.y - dy*1.5)),
                          (CGPoint(x: base.x + dx, y: base.y - dy), CGPoint(x: base.x + dx*1.5, y: base.y - dy*0.3))]
            case .bottomLeft:
                let base = CGPoint(x: pt.x - arrowOffset, y: pt.y + arrowOffset)
                arrows = [(CGPoint(x: base.x + dx, y: base.y - dy), CGPoint(x: base.x - dx, y: base.y + dy)),
                          (CGPoint(x: base.x - dx, y: base.y + dy), CGPoint(x: base.x - dx*0.3, y: base.y + dy*1.5)),
                          (CGPoint(x: base.x - dx, y: base.y + dy), CGPoint(x: base.x - dx*1.5, y: base.y + dy*0.3))]
            case .bottomRight:
                let base = CGPoint(x: pt.x + arrowOffset, y: pt.y + arrowOffset)
                arrows = [(CGPoint(x: base.x - dx, y: base.y - dy), CGPoint(x: base.x + dx, y: base.y + dy)),
                          (CGPoint(x: base.x + dx, y: base.y + dy), CGPoint(x: base.x + dx*0.3, y: base.y + dy*1.5)),
                          (CGPoint(x: base.x + dx, y: base.y + dy), CGPoint(x: base.x + dx*1.5, y: base.y + dy*0.3))]
            }
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.2)
            context.setLineCap(.round)
            for (from, to) in arrows {
                context.move(to: from)
                context.addLine(to: to)
            }
            context.strokePath()
        }
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

    /// Returns the layer if the point hits its rotation knob.
    private func rotationKnobHit(at point: CGPoint) -> PhotoLayer? {
        guard selectedLayerIDs.count == 1,
              let id = selectedLayerIDs.first,
              let layer = project?.layers.first(where: { $0.id == id }) else { return nil }
        let knobCenter = CGPoint(x: layer.position.x, y: layer.position.y - layer.size.height / 2 - 12)
        let hitRadius: CGFloat = 10
        let dx = point.x - knobCenter.x
        let dy = point.y - knobCenter.y
        return (dx*dx + dy*dy) <= (hitRadius * hitRadius) ? layer : nil
    }

    /// Returns the resize corner if the point hits a handle of the selected layer.
    private func resizeHandleHit(at point: CGPoint) -> (PhotoLayer, ResizeCorner)? {
        guard selectedLayerIDs.count == 1,
              let id = selectedLayerIDs.first,
              let layer = project?.layers.first(where: { $0.id == id }) else { return nil }
        let rect = CGRect(x: layer.position.x - layer.size.width / 2,
                          y: layer.position.y - layer.size.height / 2,
                          width: layer.size.width, height: layer.size.height)
        let handleSize: CGFloat = 7
        let halfH = handleSize / 2 + 3  // generous hit zone
        let corners: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: rect.minX, y: rect.minY), .topLeft),
            (CGPoint(x: rect.maxX, y: rect.minY), .topRight),
            (CGPoint(x: rect.minX, y: rect.maxY), .bottomLeft),
            (CGPoint(x: rect.maxX, y: rect.maxY), .bottomRight),
        ]
        for (pt, corner) in corners {
            let hitRect = CGRect(x: pt.x - halfH, y: pt.y - halfH,
                                 width: halfH*2, height: halfH*2)
            if hitRect.contains(point) { return (layer, corner) }
        }
        return nil
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        let point = convert(event.locationInWindow, from: nil)

        // 1. Cmd+click on another layer = reorder
        if event.modifierFlags.contains(.command),
           let clickedLayer = layerAt(point: point),
           let selectedID = selectedLayerIDs.first,
           selectedID != clickedLayer.id,
           var proj = project {
            proj.reorder(layerID: selectedID, relativeTo: clickedLayer.id)
            project = proj
            cachedComposite = nil
            needsDisplay = true
            onLayersChanged?()
            interactionMode = .none
            Logger.debug("mouseDown: Cmd+click reorder layer \(selectedID) relative to \(clickedLayer.id)")
            return
        }

        // 2. Rotation knob hit
        if let layer = rotationKnobHit(at: point) {
            interactionMode = .rotating
            rotationStartLayerAngle = layer.rotation
            let center = layer.position
            rotationStartAngle = atan2(point.y - center.y, point.x - center.x)
            Logger.debug("mouseDown: rotation start, layer angle=\(layer.rotation)")
            return
        }

        // 3. Resize handle hit
        if let (layer, corner) = resizeHandleHit(at: point) {
            interactionMode = .resizing(corner: corner)
            resizeStartSize = layer.size
            resizeStartPosition = layer.position
            resizeAspectRatio = layer.size.width / max(layer.size.height, 1)
            // Compute the opposite (anchor) corner
            let rect = CGRect(x: layer.position.x - layer.size.width / 2,
                              y: layer.position.y - layer.size.height / 2,
                              width: layer.size.width, height: layer.size.height)
            switch corner {
            case .topLeft:     resizeOppositeCorner = CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight:    resizeOppositeCorner = CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft:  resizeOppositeCorner = CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomRight: resizeOppositeCorner = CGPoint(x: rect.minX, y: rect.minY)
            }
            Logger.debug("mouseDown: resize start, corner=\(corner), anchor=\(resizeOppositeCorner)")
            return
        }

        // 4. Layer selection / move
        if let layer = layerAt(point: point) {
            if event.modifierFlags.contains(.shift) {
                if selectedLayerIDs.contains(layer.id) { selectedLayerIDs.remove(layer.id) }
                else { selectedLayerIDs.insert(layer.id) }
            } else {
                selectedLayerIDs = [layer.id]
            }
            dragOffset = CGPoint(x: point.x - layer.position.x, y: point.y - layer.position.y)
            interactionMode = .moving
            needsDisplay = true
        } else {
            selectedLayerIDs = []
            interactionMode = .none
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch interactionMode {
        case .rotating:
            guard let id = selectedLayerIDs.first,
                  var proj = project,
                  let index = proj.layers.firstIndex(where: { $0.id == id }) else { return }
            let center = proj.layers[index].position
            let newAngle = atan2(point.y - center.y, point.x - center.x)
            proj.layers[index].rotation = rotationStartLayerAngle + (newAngle - rotationStartAngle)
            project = proj
            needsDisplay = true

        case .resizing:
            guard let id = selectedLayerIDs.first,
                  var proj = project,
                  let index = proj.layers.firstIndex(where: { $0.id == id }) else { return }
            let anchor = resizeOppositeCorner

            // Compute new size: distance from anchor corner to mouse is the new dimension
            let newW = abs(point.x - anchor.x)
            let newH = newW / resizeAspectRatio
            let newSize = CGSize(width: max(newW, 20), height: max(newH, 20))

            // New position: midpoint between anchor and the dragged corner
            let newCenter = CGPoint(x: (anchor.x + point.x) / 2,
                                    y: (anchor.y + point.y) / 2)

            proj.layers[index].size = newSize
            proj.layers[index].position = newCenter
            project = proj
            needsDisplay = true

        case .moving:
            guard !selectedLayerIDs.isEmpty, var proj = project else { return }
            for id in selectedLayerIDs {
                if let index = proj.layers.firstIndex(where: { $0.id == id }) {
                    proj.layers[index].position = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
                }
            }
            project = proj
            needsDisplay = true

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        cachedComposite = nil  // Rebuild clean composite on next draw

        if let proj = project {
            for id in selectedLayerIDs {
                if let layer = proj.layers.first(where: { $0.id == id }) {
                    Logger.debug("mouseUp: layer id=\(id) position=\(layer.position) size=\(layer.size) rotation=\(layer.rotation)")
                }
            }
        }

        needsDisplay = true
        interactionMode = .none
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

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Select the layer under the cursor if not already selected
        if let clickedLayer = layerAt(point: point) {
            if !selectedLayerIDs.contains(clickedLayer.id) {
                selectedLayerIDs = [clickedLayer.id]
                needsDisplay = true
            }
        }

        // Show context menu if a layer is selected
        guard selectedLayerIDs.count == 1,
              let id = selectedLayerIDs.first,
              let proj = project else {
            super.rightMouseDown(with: event)
            return
        }

        let menu = NSMenu()

        let bringFront = NSMenuItem(title: "Bring to Front", action: #selector(handleContextMenu(_:)), keyEquivalent: "")
        bringFront.representedObject = id
        bringFront.tag = 1
        menu.addItem(bringFront)

        let sendBack = NSMenuItem(title: "Send to Back", action: #selector(handleContextMenu(_:)), keyEquivalent: "")
        sendBack.representedObject = id
        sendBack.tag = 2
        menu.addItem(sendBack)

        menu.addItem(.separator())

        let moveUp = NSMenuItem(title: "Move Up", action: #selector(handleContextMenu(_:)), keyEquivalent: "")
        moveUp.representedObject = id
        moveUp.tag = 3
        if let layer = proj.layers.first(where: { $0.id == id }),
           let maxZ = proj.layers.map(\.zOrder).max(),
           layer.zOrder >= maxZ {
            moveUp.isEnabled = false
        }
        menu.addItem(moveUp)

        let moveDown = NSMenuItem(title: "Move Down", action: #selector(handleContextMenu(_:)), keyEquivalent: "")
        moveDown.representedObject = id
        moveDown.tag = 4
        if let layer = proj.layers.first(where: { $0.id == id }),
           let minZ = proj.layers.map(\.zOrder).min(),
           layer.zOrder <= minZ {
            moveDown.isEnabled = false
        }
        menu.addItem(moveDown)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, var proj = project else { return }
        switch sender.tag {
        case 1: proj.bringToFront(layerID: id)
        case 2: proj.sendToBack(layerID: id)
        case 3: proj.moveUp(layerID: id)
        case 4: proj.moveDown(layerID: id)
        default: return
        }
        project = proj
        cachedComposite = nil
        needsDisplay = true
        onLayersChanged?()
        Logger.debug("handleContextMenu: tag=\(sender.tag) layer=\(id)")
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
