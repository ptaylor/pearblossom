import SwiftUI

/// Lists collages from the Collages/ subdirectory, with toolbar for creating, renaming, deleting.
struct CollagesListView: View {

    @ObservedObject private var settings = AppSettings.shared
    @Binding var selectedProject: CollageProject?

    @State private var collages: [CollageProject] = []
    @State private var selectedCollageID: UUID? = nil
    @State private var showNewCollageSheet = false
    @State private var showRenameSheet = false
    @State private var collageToRename: CollageProject? = nil
    @State private var showDeleteAlert = false
    @State private var collageToDelete: CollageProject? = nil
    @State private var sortOrder: CollageSortOrder
    @State private var sortAscending: Bool

    init(selectedProject: Binding<CollageProject?>) {
        let settings = AppSettings.shared
        _selectedProject = selectedProject
        _sortOrder = State(initialValue: CollageSortOrder(rawValue: settings.collageSortOrder) ?? .dateModified)
        _sortAscending = State(initialValue: settings.collageSortAscending)
    }

    // MARK: - Sort

    enum CollageSortOrder: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
        case dateModified = "Date Modified"
    }

    private var sortedCollages: [CollageProject] {
        let result: [CollageProject]
        switch sortOrder {
        case .name:
            result = collages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated:
            result = collages.sorted { $0.createdAt > $1.createdAt }
        case .dateModified:
            result = collages.sorted { $0.modifiedAt > $1.modifiedAt }
        }
        return sortAscending ? result.reversed() : result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 6) {
                Button {
                    showNewCollageSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Collage")

                Button {
                    loadCollages()
                    Logger.debug("Collages list refreshed")
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Collages")

                Menu {
                    ForEach(CollageSortOrder.allCases, id: \.self) { order in
                        Button {
                            if sortOrder == order {
                                sortAscending.toggle()
                                AppSettings.shared.collageSortAscending = sortAscending
                            } else {
                                sortOrder = order
                                AppSettings.shared.collageSortOrder = order.rawValue
                            }
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        sortAscending.toggle()
                        AppSettings.shared.collageSortAscending = sortAscending
                    } label: {
                        HStack {
                            Text(sortAscending ? "Ascending" : "Descending")
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .menuIndicator(.hidden)
                .help("Sort Collages")

                Button {
                    sortAscending.toggle()
                    AppSettings.shared.collageSortAscending = sortAscending
                } label: {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                }
                .help(sortAscending ? "Sort Ascending" : "Sort Descending")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // Content
            if collages.isEmpty {
                emptyState
            } else {
                collageList
            }
        }
        .onAppear {
            loadCollages()
            Logger.debug("CollagesListView appeared, loaded \(collages.count) collage(s)")
        }
        .sheet(isPresented: $showNewCollageSheet) {
            NewCollageDialog { newCollage in
                collages.append(newCollage)
                selectedCollageID = newCollage.id
                selectedProject = newCollage
            }
        }
        .sheet(item: $collageToRename) { collage in
            RenameCollageDialog(collage: collage) { newName, newDescription in
                if let index = collages.firstIndex(where: { $0.id == collage.id }) {
                    collages[index].name = newName
                    collages[index].description = newDescription
                    // Update filePath if name changed (dialog already wrote new file + removed old)
                    let newPath = AppSettings.shared.collageFileURL(named: newName).path
                    collages[index].filePath = newPath
                    collages[index].modifiedAt = Date()
                    saveCollage(collages[index])
                    // Update selected project if it was renamed
                    if selectedProject?.id == collage.id {
                        selectedProject = collages[index]
                    }
                }
            }
        }
        .alert("Delete Collage", isPresented: $showDeleteAlert, presenting: collageToDelete) { collage in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // Defer to next run loop so the alert sheet finishes dismissing
                // before we modify state (prevents SwiftUI hang/crash).
                DispatchQueue.main.async {
                    deleteCollage(collage)
                }
            }
        } message: { collage in
            Text("\"\(collage.name)\" will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
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
                showNewCollageSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Collage List

    private var collageList: some View {
        List(selection: $selectedCollageID) {
            ForEach(sortedCollages) { collage in
                CollageRow(
                    collage: collage,
                    onEdit: {
                        collageToRename = collage
                        showRenameSheet = true
                    },
                    onDelete: {
                        collageToDelete = collage
                        showDeleteAlert = true
                    }
                )
                .contentShape(Rectangle())
                .listRowBackground(
                    selectedCollageID == collage.id
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
                .onTapGesture {
                    selectedCollageID = collage.id
                    selectedProject = collage
                    Logger.debug("Selected collage '\(collage.name)'")
                }
                .padding(.vertical, 2)
                .tag(collage.id)
                .contextMenu {
                    Button("Edit…") {
                        collageToRename = collage
                        showRenameSheet = true
                    }

                    Divider()

                    Button("Delete…") {
                        collageToDelete = collage
                        showDeleteAlert = true
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Data Management

    private func loadCollages() {
        let dir = settings.collagesDir
        let fm = FileManager.default

        // Ensure directory exists
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else {
            collages = []
            return
        }

        collages = contents.compactMap { fileURL in
            guard fileURL.pathExtension == "json",
                  fileURL.lastPathComponent.hasSuffix(".collage.json") else {
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL),
                  var project = try? JSONDecoder().decode(CollageProject.self, from: data) else {
                return nil
            }

            // Update file path if it moved
            if project.filePath != fileURL.path {
                project.filePath = fileURL.path
                project.modifiedAt = Date()
                saveCollage(project)
            }

            return project
        }
    }

    private func saveCollage(_ project: CollageProject) {
        guard let path = project.filePath else { return }
        let url = URL(fileURLWithPath: path)
        guard let data = try? JSONEncoder().encode(project) else { return }
        try? data.write(to: url)
    }

    private func deleteCollage(_ project: CollageProject) {
        Logger.debug("Deleting collage '\(project.name)'")
        let fm = FileManager.default

        // Remove the .collage.json file
        if let path = project.filePath {
            let url = URL(fileURLWithPath: path)
            // Safety: only delete files within the root directory
            if url.path.hasPrefix(settings.collectionsRoot.path) {
                try? fm.removeItem(at: url)
            }
        }

        // If this was the selected project, clear it
        if selectedProject?.id == project.id {
            selectedProject = nil
        }

        // Remove from list
        collages.removeAll { $0.id == project.id }
        selectedCollageID = nil
    }
}

// MARK: - Collage Row

/// A single collage row in the sidebar, with hover-revealed edit and delete buttons.
private struct CollageRow: View {

    let collage: CollageProject
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack {
            Image(systemName: "doc.richtext")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(collage.name)
                    .font(.body)

                Text("\(collage.layers.count) layer\(collage.layers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !collage.description.isEmpty {
                    Text(collage.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Edit Collage")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Delete Collage")
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}
