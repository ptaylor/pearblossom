import SwiftUI

/// The main content view with the three-column layout.
struct ContentView: View {

    @State private var currentProject: CollageProject? = nil
    @State private var selectedSidebarItem: String? = nil
    @State private var canvasMagnification: CGFloat = 1.0

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedProject: $currentProject)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 350)
                .frame(minWidth: 220)
        } content: {
            CanvasView(project: $currentProject, magnification: $canvasMagnification)
                .frame(minWidth: 600)
        } detail: {
            InspectorView(project: $currentProject, magnification: $canvasMagnification)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
                .frame(minWidth: 220)
        }
        .onChange(of: currentProject?.name) { _, _ in updateWindowTitle() }
        .onChange(of: currentProject?.description) { _, _ in updateWindowTitle() }
        .onAppear { updateWindowTitle() }
    }

    private func updateWindowTitle() {
        if let proj = currentProject {
            if !proj.description.isEmpty {
                NSApp.mainWindow?.title = "Pearblossom: \(proj.name) — \(proj.description)"
            } else {
                NSApp.mainWindow?.title = "Pearblossom: \(proj.name)"
            }
        } else {
            NSApp.mainWindow?.title = "Pearblossom: <blank canvas>"
        }
    }
}
