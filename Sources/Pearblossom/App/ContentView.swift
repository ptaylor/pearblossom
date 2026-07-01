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
            // Inspector: properties for selected items
            InspectorView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
                .frame(minWidth: 220)
        }
    }
}
