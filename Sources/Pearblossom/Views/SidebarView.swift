import SwiftUI

/// Sidebar with tab-style switching between Collections and Collages.
struct SidebarView: View {

    /// Which tab is active in the sidebar.
    enum SidebarTab: String, CaseIterable {
        case collections = "Collections"
        case collages = "Collages"
    }

    @Binding var selectedProject: CollageProject?
    @State private var selectedTab: SidebarTab = .collections

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            // Content for the selected tab
            switch selectedTab {
            case .collections:
                CollectionsListView()
            case .collages:
                CollagesListView(selectedProject: $selectedProject)
            }
        }
    }
}
