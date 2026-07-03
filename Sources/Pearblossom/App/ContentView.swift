import SwiftUI
import UniformTypeIdentifiers

/// Data passed to the New Collage sheet when dropping on a blank canvas.
struct BlankCanvasPrefill: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let paths: [String]
    let point: CGPoint
    let collectionID: UUID?
    let photoIDs: [UUID]
}

/// The main content view with the three-column layout.
struct ContentView: View {

    @State private var currentProject: CollageProject? = nil
    @State private var selectedSidebarItem: String? = nil
    @State private var canvasMagnification: CGFloat = 1.0
    @State private var blankCanvasPrefill: BlankCanvasPrefill? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedProject: $currentProject)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 350)
                .frame(minWidth: 220)
        } content: {
            CanvasView(project: $currentProject, magnification: $canvasMagnification)
                .frame(minWidth: 600)
                .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers, _ in
                    handleCanvasDrop(providers: providers)
                    return true
                }
        } detail: {
            InspectorView(project: $currentProject, magnification: $canvasMagnification)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
                .frame(minWidth: 220)
        }
        .onChange(of: currentProject?.name) { _, _ in updateWindowTitle() }
        .onChange(of: currentProject?.description) { _, _ in updateWindowTitle() }
        .onChange(of: currentProject?.id) { _, _ in updateWindowTitle() }
        .onChange(of: currentProject != nil) { _, _ in updateWindowTitle() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateWindowTitle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blankCanvasDrop)) { notif in
            guard let paths = notif.userInfo?["paths"] as? [String],
                  let px = notif.userInfo?["pointX"] as? CGFloat,
                  let py = notif.userInfo?["pointY"] as? CGFloat else { return }
            let name = notif.userInfo?["name"] as? String ?? ""
            let desc = notif.userInfo?["description"] as? String ?? ""
            let collID = notif.userInfo?["collectionID"] as? UUID
            let pIDs = notif.userInfo?["photoIDs"] as? [UUID] ?? []
            blankCanvasPrefill = BlankCanvasPrefill(
                name: name, description: desc,
                paths: paths, point: CGPoint(x: px, y: py),
                collectionID: collID, photoIDs: pIDs
            )
        }
        .sheet(item: $blankCanvasPrefill) { prefill in
            NewCollageDialog(initialName: prefill.name, initialDescription: prefill.description) { newCollage in
                currentProject = newCollage
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        let userInfo: [AnyHashable: Any] = [
                            "paths": prefill.paths,
                            "pointX": prefill.point.x,
                            "pointY": prefill.point.y,
                            "collectionID": prefill.collectionID as Any,
                            "photoIDs": prefill.photoIDs
                        ]
                        NotificationCenter.default.post(name: .deferredDrop, object: nil, userInfo: userInfo)
                    }
                }
            }
        }
    }

    private func handleCanvasDrop(providers: [NSItemProvider]) {
        var allPaths: [String] = []
        var parsedCollectionID: UUID?
        var parsedPhotoIDs: [UUID] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL { allPaths.append(url.path) }
                    else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { allPaths.append(url.path) }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let str = item as? String {
                        let parts = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                        // Parse collection metadata from first line
                        if let meta = parts.first, meta.hasPrefix("COLLID:") {
                            for segment in meta.components(separatedBy: "|") {
                                if segment.hasPrefix("COLLID:"),
                                   let uuid = UUID(uuidString: String(segment.dropFirst(7))) {
                                    parsedCollectionID = uuid
                                } else if segment.hasPrefix("PHOTOIDS:") {
                                    let idStrings = String(segment.dropFirst(9)).components(separatedBy: ",")
                                    parsedPhotoIDs = idStrings.compactMap { UUID(uuidString: $0) }
                                }
                            }
                            allPaths.append(contentsOf: parts.dropFirst())
                        } else {
                            allPaths.append(contentsOf: parts)
                        }
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !allPaths.isEmpty else { return }
            let mouseLocation = NSEvent.mouseLocation
            guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
            let point = window.convertPoint(fromScreen: mouseLocation)

            if currentProject != nil {
                NotificationCenter.default.post(name: .deferredDrop, object: nil, userInfo: [
                    "paths": allPaths, "pointX": point.x, "pointY": point.y,
                    "collectionID": parsedCollectionID as Any,
                    "photoIDs": parsedPhotoIDs
                ])
            } else {
                let settings = AppSettings.shared
                blankCanvasPrefill = BlankCanvasPrefill(
                    name: settings.activeCollectionName ?? "",
                    description: settings.activeCollectionDescription ?? "",
                    paths: allPaths, point: point,
                    collectionID: parsedCollectionID,
                    photoIDs: parsedPhotoIDs
                )
            }
        }
    }

    private func updateWindowTitle() {
        let window = NSApp.mainWindow ?? NSApp.windows.first
        if let proj = currentProject {
            if !proj.description.isEmpty {
                window?.title = "Pearblossom: \(proj.name) — \(proj.description)"
            } else {
                window?.title = "Pearblossom: \(proj.name)"
            }
        } else {
            window?.title = "Pearblossom: <Blank Canvas>"
        }
    }
}
