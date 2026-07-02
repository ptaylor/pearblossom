import SwiftUI

/// The main content view with the three-column layout.
struct ContentView: View {

    @State private var currentProject: CollageProject? = nil
    @State private var selectedSidebarItem: String? = nil

    var body: some View {
        NavigationSplitView {
            // Sidebar: Collections and Collages in tabs
            SidebarView(selectedProject: $currentProject)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 350)
                .frame(minWidth: 220)
        } content: {
            // Canvas: the collage editing area
            CanvasView(project: $currentProject)
                .frame(minWidth: 600)
        } detail: {
            // Inspector: canvas config and properties
            InspectorView(project: $currentProject)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
                .frame(minWidth: 220)
        }        .onChange(of: currentProject?.name) { _, _ in updateWindowTitle() }
        .onChange(of: currentProject?.description) { _, _ in updateWindowTitle() }
        .onAppear { updateWindowTitle() }
    }

    private func updateWindowTitle() {
        if let proj = currentProject {
            var title = "Pearblossom — \(proj.name)"
            if !proj.description.isEmpty {
                title += " — \(proj.description)"
            }
            NSApp.mainWindow?.title = title
        } else {
            NSApp.mainWindow?.title = "Pearblossom"
        }    }
}
