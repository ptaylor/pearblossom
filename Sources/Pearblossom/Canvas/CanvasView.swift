import SwiftUI
import AppKit
import Combine

// MARK: - Zoomable Scroll View

/// NSScrollView subclass that supports Cmd+scroll-wheel zoom.
private class ZoomableScrollView: NSScrollView {
    var onMagnificationChanged: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            // Non-precise scroll wheels (mice) use large deltas; trackpads use smaller,
            // but we only handle mice here since trackpads use pinch-to-zoom.
            let newMag = magnification * (1 + delta / 400)
            let clamped = min(max(newMag, minMagnification), maxMagnification)
            setMagnification(clamped, centeredAt: convert(event.locationInWindow, from: nil))
            onMagnificationChanged?(clamped)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// SwiftUI wrapper for the AppKit canvas view with NSScrollView zoom/pan and drop support.
struct CanvasView: NSViewRepresentable {

    @Binding var project: CollageProject?
    @Binding var magnification: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(project: $project, magnification: $magnification)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let canvasSize = project?.canvasWidth ?? 2000
        let canvasHeight = project?.canvasHeight ?? 1500
        let canvas = CanvasNSView(frame: NSRect(x: 0, y: 0, width: CGFloat(canvasSize), height: CGFloat(canvasHeight)))

        // Wire up drop handling
        canvas.onPhotosDropped = { [weak canvas] paths, point, collID, pIDs in
            guard let canvas = canvas else { return }
            context.coordinator.handleDrop(paths: paths, at: point, canvas: canvas,
                                           collectionID: collID, photoIDs: pIDs)
        }

        // Listen for deferred drops (after new collage created from blank canvas)
        context.coordinator.canvasView = canvas
        context.coordinator.deferredDropObserver = NotificationCenter.default.addObserver(
            forName: .deferredDrop, object: nil, queue: .main
        ) { [weak canvas] notif in
            guard let canvas = canvas,
                  let paths = notif.userInfo?["paths"] as? [String],
                  let px = notif.userInfo?["pointX"] as? CGFloat,
                  let py = notif.userInfo?["pointY"] as? CGFloat else { return }
            let point = CGPoint(x: px, y: py)
            let collID = notif.userInfo?["collectionID"] as? UUID
            let photoIDs = notif.userInfo?["photoIDs"] as? [UUID] ?? []
            context.coordinator.handleDrop(paths: paths, at: point, canvas: canvas,
                                           collectionID: collID, photoIDs: photoIDs)
        }

        // Wire up auto-save on canvas mutations.
        // Since CollageProject is an ObservableObject, mutations are in-place
        // and @Published properties trigger SwiftUI updates automatically.
        canvas.onLayersChanged = { [weak canvas] in
            guard let canvas = canvas, let proj = canvas.project else { return }
            proj.modifiedAt = Date()  // triggers @Published → SwiftUI observes change
            context.coordinator.scheduleAutoSave()
        }

        let scrollView = ZoomableScrollView(frame: .zero)
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 5.0
        scrollView.backgroundColor = NSColor.controlBackgroundColor
        scrollView.magnification = magnification

        // Sync Cmd+scroll and pinch-to-zoom back to the binding
        scrollView.onMagnificationChanged = { mag in
            context.coordinator.magnificationBinding.wrappedValue = mag
        }

        context.coordinator.scrollView = scrollView
        context.coordinator.registerMagnificationObserver()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? CanvasNSView else { return }
        let previousProjectID = canvas.project?.id
        canvas.project = project
        if let proj = project {
            let newSize = NSSize(width: proj.canvasWidth, height: proj.canvasHeight)
            if canvas.frame.size != newSize {
                canvas.setFrameSize(newSize)
            }
        }
        // When a different collage is loaded (import or sidebar open),
        // re-subscribe for auto-save and auto-fit to the bounding box.
        if project?.id != previousProjectID {
            context.coordinator.observeProject(project)
            if project != nil {
                let coordinator = context.coordinator
                DispatchQueue.main.async {
                    coordinator.performFit()
                }
            }
        }
        // Sync magnification from binding → scroll view (for slider changes).
        // Save the document-space center, apply magnification, then re-center
        // so the canvas stays anchored on the same content.
        if abs(scrollView.magnification - magnification) > 0.001 {
            let oldCenter = CGPoint(
                x: scrollView.contentView.documentVisibleRect.midX,
                y: scrollView.contentView.documentVisibleRect.midY
            )
            scrollView.magnification = magnification
            scrollView.layout()
            let newVisible = scrollView.contentView.documentVisibleRect
            let newOrigin = CGPoint(
                x: oldCenter.x - newVisible.width / 2,
                y: oldCenter.y - newVisible.height / 2
            )
            scrollView.contentView.scroll(to: newOrigin)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var projectBinding: Binding<CollageProject?>
        var magnificationBinding: Binding<CGFloat>
        weak var scrollView: NSScrollView?
        weak var canvasView: CanvasNSView?
        private var autoSaveWorkItem: DispatchWorkItem?
        private var projectObserver: AnyCancellable?
        var deferredDropObserver: NSObjectProtocol?

        init(project: Binding<CollageProject?>, magnification: Binding<CGFloat>) {
            self.projectBinding = project
            self.magnificationBinding = magnification
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(fitToBoundingBox),
                name: .fitToBoundingBox, object: nil
            )
        }

        @objc private func magnificationDidChange(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView else { return }
            magnificationBinding.wrappedValue = scrollView.magnification
        }

        func registerMagnificationObserver() {
            guard let scrollView = scrollView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(magnificationDidChange(_:)),
                name: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView
            )
        }

        @objc private func fitToBoundingBox() {
            guard let proj = projectBinding.wrappedValue else { return }

            if !proj.showBoundingBox {
                // Already in fit mode — exit: reset zoom and show bounding box.
                exitFitMode()
                return
            }
            performFit()
        }

        /// Resets zoom to 1.0 and shows the bounding box guide.
        private func exitFitMode() {
            guard let scrollView = scrollView,
                  let proj = projectBinding.wrappedValue else { return }
            scrollView.animator().magnification = 1.0
            magnificationBinding.wrappedValue = 1.0
            proj.showBoundingBox = true
            Logger.debug("fitToBoundingBox: exit fit mode, reset zoom to 1.0")
        }

        /// Zooms the canvas so the collage's bounding box fits the viewport,
        /// then centers it and hides the bounding box guide (export preview).
        func performFit() {
            guard let scrollView = scrollView,
                  let proj = projectBinding.wrappedValue else { return }

            let bb = proj.effectiveBoundingBox()
            let viewSize = scrollView.contentSize
            guard bb.width > 0, bb.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }

            // Fit bounding box with 10% margin so the content doesn't touch the edges.
            let margin: CGFloat = 0.10
            let usableWidth = viewSize.width * (1 - margin * 2)
            let usableHeight = viewSize.height * (1 - margin * 2)
            let mag = min(usableWidth / bb.width, usableHeight / bb.height)

            // Apply magnification, then read the resulting visible rect to compute scroll.
            scrollView.magnification = mag
            magnificationBinding.wrappedValue = mag
            scrollView.layout()  // let the scroll view settle the new magnification

            let visibleRect = scrollView.contentView.documentVisibleRect
            let scrollX = bb.midX - visibleRect.width / 2
            let scrollY = bb.midY - visibleRect.height / 2
            scrollView.contentView.scroll(to: NSPoint(x: scrollX, y: scrollY))

            // Hide the bounding box guide when zoomed to content — this is the export preview.
            proj.showBoundingBox = false
            Logger.debug("performFit: bb=\(bb) viewSize=\(viewSize) mag=\(mag) scrollTo=(\(scrollX), \(scrollY))")
        }

        func handleDrop(paths: [String], at point: CGPoint, canvas: CanvasNSView,
                        collectionID: UUID? = nil, photoIDs: [UUID] = []) {
            guard let proj = projectBinding.wrappedValue else {
                let settings = AppSettings.shared
                NotificationCenter.default.post(name: .blankCanvasDrop, object: nil, userInfo: [
                    "paths": paths,
                    "pointX": point.x,
                    "pointY": point.y,
                    "name": settings.activeCollectionName ?? "",
                    "description": settings.activeCollectionDescription ?? "",
                    "collectionID": collectionID as Any,
                    "photoIDs": photoIDs
                ])
                return
            }

            let settings = AppSettings.shared
            let scalePercent = settings.defaultPhotoScalePercent / 100.0
            let canvasSize = canvas.frame.size
            let targetDim = min(canvasSize.width, canvasSize.height) * scalePercent
            let maxZ = proj.layers.map(\.zOrder).max() ?? -1
            var cascadeOffset: CGFloat = 0

            Logger.debug("handleDrop: \(paths.count) file(s), dropPoint=\(point), canvasSize=\(canvasSize), targetDim=\(targetDim) (scalePercent=\(scalePercent)), maxZ=\(maxZ)")

            for (_, path) in paths.enumerated() {
                let nsImage = NSImage(contentsOfFile: path)
                let nsImageSize = nsImage?.size ?? .zero

                let sourceSize = nsImageSize
                let scale = sourceSize.width > 0
                    ? min(targetDim / sourceSize.width, targetDim / sourceSize.height)
                    : 1.0
                let displaySize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

                let centerPos = CGPoint(x: point.x + cascadeOffset, y: point.y + cascadeOffset)

                let storedPath = relativePath(from: path)

                // Resolve collectionID and photoID by matching the path against
                // the active collection's photos
                let settings = AppSettings.shared
                let collID: UUID?
                let pid: UUID?
                if let activeID = settings.activeCollectionID,
                   let collection = PhotoCollection.find(by: activeID) {
                    collID = activeID
                    // Match by resolved path
                    let matching = collection.photos.first { photo in
                        photo.resolvedPath(relativeTo: collection.folderPath) == path
                    }
                    pid = matching?.id
                } else {
                    collID = nil
                    pid = nil
                }

                let layer = PhotoLayer(
                    photoPath: storedPath,
                    collectionID: collID,
                    photoID: pid,
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
            scheduleAutoSave()
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

        /// Subscribes to the current project's changes so any edit (canvas or
        /// inspector) schedules a debounced auto-save.
        func observeProject(_ project: CollageProject?) {
            projectObserver = project?.objectWillChange.sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
        }

        func scheduleAutoSave() {
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
