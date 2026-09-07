import SwiftUI
import UniformTypeIdentifiers

/// Sidebar with tab-style switching between Collections and Collages.
struct SidebarView: View {

    /// Which tab is active in the sidebar.
    enum SidebarTab: String, CaseIterable {
        case collections = "Collections"
        case collages = "Collages"
    }

    @Binding var selectedProject: CollageProject?
    @State private var selectedTab: SidebarTab = .collections
    @State private var showCXFPicker = false
    @State private var cxfImportRequest: CXFImportRequest? = nil

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
        .onReceive(NotificationCenter.default.publisher(for: .triggerImportCollage)) { _ in
            showCXFPicker = true
        }
        .fileImporter(
            isPresented: $showCXFPicker,
            allowedContentTypes: [UTType(filenameExtension: "cxf") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    cxfImportRequest = CXFImportRequest(url: url)
                }
            case .failure(let error):
                Logger.warn("Picasa import file picker failed: \(error.localizedDescription)")
            }
        }
        .sheet(item: $cxfImportRequest) { request in
            ImportCollageDialog(cxfURL: request.url) { project, _, skipped in
                selectedProject = project
                selectedTab = .collages

                if !skipped.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "Import Complete"
                    alert.informativeText = "Imported \"\(project.name)\" with \(project.layers.count) layer(s). \(skipped.count) source file(s) could not be found and were skipped."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }

                NotificationCenter.default.post(name: .collagesDidChange, object: nil)
            }
        }
    }
}

/// Identifies a chosen `.cxf` file for the import sheet.
private struct CXFImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}
