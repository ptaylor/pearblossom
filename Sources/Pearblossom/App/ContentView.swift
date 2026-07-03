import SwiftUI
import UniformTypeIdentifiers

/// Data passed to the New Collage sheet when dropping on a blank canvas.
struct BlankCanvasPrefill: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let paths: [String]
    let point: CGPoint
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
            blankCanvasPrefill = BlankCanvasPrefill(
                name: name, description: desc,
                paths: paths, point: CGPoint(x: px, y: py)
            )
        }
        .sheet(item: $blankCanvasPrefill) { prefill in
            NewCollageDialog(initialName: prefill.name, initialDescription: prefill.description) { newCollage in
                currentProject = newCollage
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .deferredDrop, object: nil, userInfo: [
                            "paths": prefill.paths,
                            "pointX": prefill.point.x,
                            "pointY": prefill.point.y
                        ])
                    }
                }
            }
        }
    }

    private func handleCanvasDrop(providers: [NSItemProvider]) {
        var allPaths: [String] = []
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
                    if let str = item as? String { allPaths.append(contentsOf: str.components(separatedBy: "\n").filter { !$0.isEmpty }) }
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
                    "paths": allPaths, "pointX": point.x, "pointY": point.y
                ])
            } else {
                let settings = AppSettings.shared
                blankCanvasPrefill = BlankCanvasPrefill(
                    name: settings.activeCollectionName ?? "",
                    description: settings.activeCollectionDescription ?? "",
                    paths: allPaths, point: point
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
