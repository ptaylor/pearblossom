import SwiftUI
import AppKit

/// SwiftUI wrapper for the AppKit canvas view with NSScrollView zoom/pan and drop support.
struct CanvasView: NSViewRepresentable {

    @Binding var project: CollageProject?

    func makeCoordinator() -> Coordinator {
        Coordinator(project: $project)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let canvasSize = project?.canvasWidth ?? 2000
        let canvasHeight = project?.canvasHeight ?? 1500
        let canvas = CanvasNSView(frame: NSRect(x: 0, y: 0, width: CGFloat(canvasSize), height: CGFloat(canvasHeight)))

        // Wire up drop handling
        canvas.onPhotosDropped = { [weak canvas] paths, point in
            guard let canvas = canvas else { return }
            context.coordinator.handleDrop(paths: paths, at: point, canvas: canvas)
        }

        // Wire up auto-save on canvas mutations — also push changes back to binding
        // so Inspector toggles etc. don't overwrite dragged positions with stale data.
        canvas.onLayersChanged = { [weak canvas] in
            guard let canvas = canvas, let proj = canvas.project else { return }
            context.coordinator.projectBinding.wrappedValue = proj
            context.coordinator.scheduleAutoSave(canvas: canvas)
        }

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 5.0
        scrollView.backgroundColor = NSColor.controlBackgroundColor

        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? CanvasNSView else { return }
        canvas.project = project
        if let proj = project {
            let newSize = NSSize(width: proj.canvasWidth, height: proj.canvasHeight)
            if canvas.frame.size != newSize {
                canvas.setFrameSize(newSize)
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var projectBinding: Binding<CollageProject?>
        weak var scrollView: NSScrollView?
        private var autoSaveWorkItem: DispatchWorkItem?

        init(project: Binding<CollageProject?>) {
            self.projectBinding = project
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(fitToBoundingBox),
                name: .fitToBoundingBox, object: nil
            )
        }

        @objc private func fitToBoundingBox() {
            guard let scrollView = scrollView,
                  var proj = projectBinding.wrappedValue else { return }

            if !proj.showBoundingBox {
                // Already in fit mode — exit: reset zoom and show bounding box
                scrollView.animator().magnification = 1.0
                proj.showBoundingBox = true
                projectBinding.wrappedValue = proj
                Logger.debug("fitToBoundingBox: exit fit mode, reset zoom to 1.0")
                return
            }

            let bb = proj.effectiveBoundingBox()
            let viewSize = scrollView.contentSize
            guard bb.width > 0, bb.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }

            // Fit bounding box with 10% margin so the content doesn't touch the edges.
            let margin: CGFloat = 0.10
            let usableWidth = viewSize.width * (1 - margin * 2)
            let usableHeight = viewSize.height * (1 - margin * 2)
            let mag = min(usableWidth / bb.width, usableHeight / bb.height)

            // Apply magnification, then read the resulting visible rect to compute scroll
            scrollView.magnification = mag
            scrollView.layout()  // let the scroll view settle the new magnification

            let visibleRect = scrollView.contentView.documentVisibleRect
            let scrollX = bb.midX - visibleRect.width / 2
            let scrollY = bb.midY - visibleRect.height / 2
            scrollView.contentView.scroll(to: NSPoint(x: scrollX, y: scrollY))

            // Hide the bounding box guide when zoomed to content — this is the export preview
            proj.showBoundingBox = false
            projectBinding.wrappedValue = proj
            Logger.debug("fitToBoundingBox: bb=\(bb) viewSize=\(viewSize) mag=\(mag) visibleRect=\(visibleRect) scrollTo=(\(scrollX), \(scrollY))")
        }

        func handleDrop(paths: [String], at point: CGPoint, canvas: CanvasNSView) {
            guard var proj = projectBinding.wrappedValue else { return }

            let settings = AppSettings.shared
            let scalePercent = settings.defaultPhotoScalePercent / 100.0
            let canvasSize = canvas.frame.size
            let targetDim = min(canvasSize.width, canvasSize.height) * scalePercent
            let maxZ = proj.layers.map(\.zOrder).max() ?? -1
            var cascadeOffset: CGFloat = 0

            Logger.debug("handleDrop: \(paths.count) file(s), dropPoint=\(point), canvasSize=\(canvasSize), targetDim=\(targetDim) (scalePercent=\(scalePercent)), maxZ=\(maxZ)")

            for (index, path) in paths.enumerated() {
                // Source image point size (NSImage)
                let nsImage = NSImage(contentsOfFile: path)
                let nsImageSize = nsImage?.size ?? .zero
                let nsImageRep = nsImage?.representations.first
                let pixelSize: CGSize = {
                    if let rep = nsImageRep {
                        return CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
                    }
                    return nsImageSize
                }()

                // CIImage extent (actual pixel dimensions from the file)
                let ciExtent: CGSize = {
                    if let img = CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true]) {
                        return img.extent.size
                    }
                    return .zero
                }()

                // Use NSImage.size for sourceResolution (matches current behavior)
                let sourceSize = nsImageSize
                let scale = sourceSize.width > 0
                    ? min(targetDim / sourceSize.width, targetDim / sourceSize.height)
                    : 1.0
                let displaySize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

                // Position: center of the placed layer
                let centerPos = CGPoint(x: point.x + cascadeOffset, y: point.y + cascadeOffset)
                // Top-left corner (in flipped canvas coords, where y increases downward)
                let topLeft = CGPoint(x: centerPos.x - displaySize.width / 2,
                                      y: centerPos.y - displaySize.height / 2)

                // Store relative path if photo is inside the Pearblossom root directory
                let storedPath = relativePath(from: path)

                Logger.debug("handleDrop: file[\(index)] path=\(path) storedPath=\(storedPath)")
                Logger.debug("handleDrop: file[\(index)] nsImageSize(points)=\(nsImageSize) pixelSize(w×h)=\(pixelSize) ciExtent(pixels)=\(ciExtent)")
                Logger.debug("handleDrop: file[\(index)] sourceResolution(used)=\(sourceSize) scale=\(scale) displaySize=\(displaySize)")
                Logger.debug("handleDrop: file[\(index)] centerPos=\(centerPos) topLeft=\(topLeft) cascadeOffset=\(cascadeOffset)")

                let layer = PhotoLayer(
                    photoPath: storedPath,
                    position: centerPos,
                    size: displaySize,
                    zOrder: maxZ + 1 + proj.layers.count,
                    sourceResolution: sourceSize
                )
                proj.layers.append(layer)
                cascadeOffset += 40
            }

            proj.modifiedAt = Date()
            projectBinding.wrappedValue = proj
            canvas.project = proj
            canvas.needsDisplay = true
            scheduleAutoSave(canvas: canvas)
            Logger.debug("Dropped \(paths.count) photo(s) onto canvas '\(proj.name)' — total layers now: \(proj.layers.count)")
        }

        /// Converts an absolute path to relative if inside the Pearblossom root directory.
        private func relativePath(from absolute: String) -> String {
            let root = AppSettings.shared.collectionsRoot.path
            if absolute.hasPrefix(root + "/") {
                return String(absolute.dropFirst(root.count + 1))
            }
            return absolute
        }

        func scheduleAutoSave(canvas: CanvasNSView) {
            autoSaveWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let proj = self.projectBinding.wrappedValue,
                      let path = proj.filePath else { return }
                if let data = try? JSONEncoder().encode(proj) {
                    try? data.write(to: URL(fileURLWithPath: path))
                    Logger.debug("Auto-saved collage '\(proj.name)'")
                }
            }
            autoSaveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
        }
    }
}
