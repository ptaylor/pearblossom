import SwiftUI

/// Sidebar with tab-style switching between Collections and Collages.
struct SidebarView: View {

    /// Which tab is active in the sidebar.
    enum SidebarTab: String, CaseIterable {
        case collections = "Collections"
        case collages = "Collages"
    }

    @State private var selectedTab: SidebarTab = .collections

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
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
                CollagesListView()
            }
        }
    }
}

/// Placeholder view for the collections list.
struct CollectionsListView: View {
    @State private var collections: [PhotoCollection] = []

    var body: some View {
        if collections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)

                Text("No Collections")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Import photos to get started.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                Button("Import Photos…") {
                    // TODO: Implement photo import
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(collections) { collection in
                Label(collection.name, systemImage: "folder")
            }
        }
    }
}

/// Placeholder view for the collages list.
struct CollagesListView: View {
    @State private var collages: [CollageProject] = []

    var body: some View {
        if collages.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)

                Text("No Collages")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Create a new collage to begin.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                Button("New Collage…") {
                    // TODO: Implement new collage
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(collages) { collage in
                Label(collage.filePath ?? "Untitled", systemImage: "doc")
            }
        }
    }
}
