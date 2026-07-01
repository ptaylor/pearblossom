import SwiftUI
import UniformTypeIdentifiers

/// Lists collections from disk, with toolbar for creating new collections and importing photos.
struct CollectionsListView: View {

    @ObservedObject private var settings = AppSettings.shared

    @State private var collections: [PhotoCollection] = []
    @State private var selectedCollectionID: UUID? = nil
    @State private var showNewCollectionSheet = false
    @State private var showImportPicker = false
    @State private var pendingImportURLs: [URL]? = nil
    @State private var showCollectionPickerPopover = false
    @State private var pendingImportTargetID: UUID? = nil
    @State private var showRenameSheet = false
    @State private var collectionToRename: PhotoCollection? = nil
    @State private var showDeleteAlert = false
    @State private var collectionToDelete: PhotoCollection? = nil
    @State private var showDirWarning = false
    @State private var dirWarningMessage = ""
    @State private var expandedCollectionID: UUID? = nil
    @State private var selectedPhotoIDs: Set<UUID> = []
    // Sort prefs are persisted in AppSettings, mirrored here for binding
    @State private var sortOrder: CollectionSortOrder
    @State private var sortAscending: Bool

    init() {
        let settings = AppSettings.shared
        _sortOrder = State(initialValue: CollectionSortOrder(rawValue: settings.collectionSortOrder) ?? .dateModified)
        _sortAscending = State(initialValue: settings.collectionSortAscending)
    }

    /// Image file types the app can import.
    private static let allowedImageTypes: [UTType] = [
        .jpeg, .png, .tiff, .heic, .bmp, .gif
    ]

    // MARK: - Sort

    enum CollectionSortOrder: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
        case dateModified = "Date Modified"
    }

    private var sortedCollections: [PhotoCollection] {
        let result: [PhotoCollection]
        switch sortOrder {
        case .name:
            result = collections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated:
            result = collections.sorted { $0.createdAt > $1.createdAt }
        case .dateModified:
            result = collections.sorted { $0.modifiedAt > $1.modifiedAt }
        }
        return sortAscending ? result.reversed() : result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 6) {
                Button {
                    showNewCollectionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Collection")

                Button {
                    handleImport()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import Photos")

                Button {
                    loadCollections()
                    Logger.debug("Collections list refreshed")
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Collections")

                Menu {
                    ForEach(CollectionSortOrder.allCases, id: \.self) { order in
                        Button {
                            if sortOrder == order {
                                // Toggle direction if same sort field selected
                                sortAscending.toggle()
                                AppSettings.shared.collectionSortAscending = sortAscending
                            } else {
                                sortOrder = order
                                AppSettings.shared.collectionSortOrder = order.rawValue
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
                        AppSettings.shared.collectionSortAscending = sortAscending
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
                .help("Sort Collections")

                Button {
                    sortAscending.toggle()
                    AppSettings.shared.collectionSortAscending = sortAscending
                } label: {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                }
                .help(sortAscending ? "Sort Ascending" : "Sort Descending")

                Spacer()

                // Remove selected button
                if !selectedPhotoIDs.isEmpty {
                    Button {
                        removeSelectedPhotos()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remove \(selectedPhotoIDs.count) Selected Photo\(selectedPhotoIDs.count > 1 ? "s" : "")")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // Content
            if collections.isEmpty {
                emptyState
            } else {
                collectionList
            }
        }
        .onAppear {
            loadCollections()
            Logger.debug("CollectionsListView appeared, loaded \(collections.count) collection(s)")
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerImport)) { _ in
            handleImport()
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewCollectionDialog { newCollection in
                collections.append(newCollection)
            } onCreatedAndImport: { newCollection in
                collections.append(newCollection)
                pendingImportTargetID = newCollection.id
                showImportPicker = true
            }
        }
        .sheet(item: $collectionToRename) { collection in
            RenameCollectionDialog(collection: collection) { newName, newDescription in
                if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                    collections[index].name = newName
                    collections[index].description = newDescription
                    collections[index].folderPath = settings.collectionFolderURL(named: newName).path
                    collections[index].modifiedAt = Date()
                    try? saveCollection(collections[index])
                }
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: Self.allowedImageTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImportResult(result)
        }
        .popover(isPresented: $showCollectionPickerPopover) {
            collectionPickerPopover
        }
        .alert("Delete Collection", isPresented: $showDeleteAlert, presenting: collectionToDelete) { collection in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCollection(collection)
            }
        } message: { collection in
            if collection.importMode == .copy {
                Text("\"\(collection.name)\" contains \(collection.photos.count) photo(s). The collection folder, metadata, and all copied photo files will be permanently deleted.")
            } else {
                Text("\"\(collection.name)\" contains \(collection.photos.count) photo(s). The metadata file will be removed, but photo files on disk will not be deleted.")
            }
        }
        .alert("Directory Not Empty", isPresented: $showDirWarning) {
            Button("OK") {}
        } message: {
            Text(dirWarningMessage)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("No Collections")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Create a collection, then import photos.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Collection List

    private var collectionList: some View {
        List(selection: $selectedCollectionID) {
            ForEach(sortedCollections) { collection in
                CollectionRow(
                    collection: collection,
                    isExpanded: expandedCollectionID == collection.id,
                    onEdit: {
                        collectionToRename = collection
                        showRenameSheet = true
                    },
                    onDelete: {
                        collectionToDelete = collection
                        if collection.photos.isEmpty {
                            deleteCollection(collection)
                        } else {
                            showDeleteAlert = true
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedCollectionID = collection.id
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedCollectionID == collection.id {
                            expandedCollectionID = nil
                            Logger.debug("Collapsed collection '\(collection.name)'")
                        } else {
                            expandedCollectionID = collection.id
                            Logger.debug("Expanded collection '\(collection.name)' — \(collection.photos.count) photo(s)")
                            generateMissingThumbnails(for: collection)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(collection.id)
                .contextMenu {
                    Button("Edit…") {
                        collectionToRename = collection
                        showRenameSheet = true
                    }

                    Divider()

                    Button("Delete…") {
                        collectionToDelete = collection
                        if collection.photos.isEmpty {
                            deleteCollection(collection)
                        } else {
                            showDeleteAlert = true
                        }
                    }
                }

                // Thumbnail grid when expanded
                if expandedCollectionID == collection.id && !collection.photos.isEmpty {
                    thumbnailGrid(for: collection)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Thumbnail Selection

    private func togglePhotoSelection(_ id: UUID) {
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else {
            selectedPhotoIDs.insert(id)
        }
    }

    /// Shift-select: selects all photos from the first selected one up to the given index.
    private func toggleShiftSelection(in collection: PhotoCollection, upTo endIndex: Int) {
        guard !selectedPhotoIDs.isEmpty else {
            // Nothing selected yet — select just this one
            let id = collection.photos[endIndex].id
            selectedPhotoIDs = [id]
            return
        }

        // Find the range of indices to select
        let selectedIndices = collection.photos.enumerated()
            .filter { selectedPhotoIDs.contains($0.element.id) }
            .map { $0.offset }

        guard let firstSelected = selectedIndices.min() else { return }

        let rangeStart = min(firstSelected, endIndex)
        let rangeEnd = max(firstSelected, endIndex)

        for i in rangeStart...rangeEnd {
            selectedPhotoIDs.insert(collection.photos[i].id)
        }
    }

    private func removePhotos(_ ids: Set<UUID>, from collection: PhotoCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }

        var updated = collections[index]
        let count = ids.count
        updated.photos.removeAll { ids.contains($0.id) }
        updated.modifiedAt = Date()
        try? saveCollection(updated)
        collections[index] = updated
        selectedPhotoIDs.subtract(ids)

        Logger.debug("Removed \(count) photo(s) from '\(collection.name)' — \(updated.photos.count) remaining")
    }

    private func removeSelectedPhotos() {
        guard !selectedPhotoIDs.isEmpty,
              let collectionID = expandedCollectionID,
              let collection = collections.first(where: { $0.id == collectionID }) else { return }

        removePhotos(selectedPhotoIDs, from: collection)
    }

    @ViewBuilder
    private func thumbnailGrid(for collection: PhotoCollection) -> some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(collection.photos.enumerated()), id: \.element.id) { index, photo in
                ThumbnailCell(
                    photo: photo,
                    folderPath: collection.folderPath,
                    isSelected: selectedPhotoIDs.contains(photo.id),
                    onTap: {
                        togglePhotoSelection(photo.id)
                    },
                    onShiftTap: {
                        toggleShiftSelection(in: collection, upTo: index)
                    },
                    onRemove: {
                        removePhotos([photo.id], from: collection)
                    }
                )
            }
        }
    }

    // MARK: - Collection Picker Popover

    private var collectionPickerPopover: some View {
        VStack(spacing: 0) {
            Text("Choose Collection")
                .font(.headline)
                .padding()

            Divider()

            if collections.isEmpty {
                VStack(spacing: 12) {
                    Text("No collections yet.")
                        .foregroundColor(.secondary)

                    Button("Create New Collection…") {
                        showCollectionPickerPopover = false
                        showNewCollectionSheet = true
                    }
                }
                .padding()
            } else {
                List(collections) { collection in
                    Button {
                        showCollectionPickerPopover = false
                        importPhotos(into: collection)
                    } label: {
                        Label(collection.name, systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Button {
                    showCollectionPickerPopover = false
                    showNewCollectionSheet = true
                } label: {
                    Label("New Collection…", systemImage: "plus")
                }
                .padding(10)
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280, height: 300)
    }

    // MARK: - Collection Loading

    private func loadCollections() {
        let root = settings.collectionsDir
        let fm = FileManager.default

        // Ensure directory exists
        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else {
            collections = []
            return
        }

        collections = contents.compactMap { folderURL in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }

            let jsonURL = settings.collectionFileURL(for: folderURL)
            guard fm.fileExists(atPath: jsonURL.path) else { return nil }

            guard let data = try? Data(contentsOf: jsonURL),
                  var collection = try? JSONDecoder().decode(PhotoCollection.self, from: data) else {
                return nil
            }

            // Update folder path if it moved
            if collection.folderPath != folderURL.path {
                collection.folderPath = folderURL.path
                collection.modifiedAt = Date()
            }

            // Migrate absolute paths inside the collection folder to relative paths
            var migratedPaths = false
            if let fp = collection.folderPath {
                for i in collection.photos.indices {
                    let photo = collection.photos[i]
                    // Photo path
                    if photo.path.hasPrefix("/"), photo.path.hasPrefix(fp + "/") {
                        collection.photos[i].path = String(photo.path.dropFirst(fp.count + 1))
                        migratedPaths = true
                    }
                    // Thumbnail path
                    if let thumb = photo.thumbnailPath, thumb.hasPrefix("/"), thumb.hasPrefix(fp + "/") {
                        collection.photos[i].thumbnailPath = String(thumb.dropFirst(fp.count + 1))
                        migratedPaths = true
                    }
                }
            }
            if migratedPaths {
                collection.modifiedAt = Date()
                try? saveCollection(collection)
            }

            return collection
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func saveCollection(_ collection: PhotoCollection) throws {
        guard let folderPath = collection.folderPath else { return }
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let jsonURL = settings.collectionFileURL(for: folderURL)
        let data = try JSONEncoder().encode(collection)
        try data.write(to: jsonURL)
    }

    /// Converts an absolute path to a path relative to the given folder.
    private func relativePath(_ absolute: String, from folder: String) -> String {
        if absolute.hasPrefix(folder + "/") {
            return String(absolute.dropFirst(folder.count + 1))
        }
        return absolute
    }

    // MARK: - Missing Thumbnails

    /// Generates thumbnails for photos that don't have one, in the background.
    private func generateMissingThumbnails(for collection: PhotoCollection) {
        guard let folderPath = collection.folderPath,
              let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let photosWithoutThumbnails = collection.photos.filter { $0.thumbnailPath == nil }

        guard !photosWithoutThumbnails.isEmpty else { return }

        Logger.debug("Generating \(photosWithoutThumbnails.count) missing thumbnail(s) for '\(collection.name)'")

        DispatchQueue.global(qos: .utility).async {
            var updated = collections[index]
            var changed = false

            for photo in photosWithoutThumbnails {
                let resolved = photo.resolvedPath(relativeTo: folderPath)
                if let absoluteThumb = ThumbnailGenerator.generateThumbnail(for: resolved, in: folderURL),
                   let photoIndex = updated.photos.firstIndex(where: { $0.id == photo.id }) {
                    // Store relative path so it survives collection renames
                    updated.photos[photoIndex].thumbnailPath = relativePath(absoluteThumb, from: folderPath)
                    changed = true
                }
            }

            if changed {
                updated.modifiedAt = Date()
                try? self.saveCollection(updated)
                DispatchQueue.main.async {
                    self.collections[index] = updated
                }
            }
        }
    }

    // MARK: - Delete Collection

    private func deleteCollection(_ collection: PhotoCollection) {
        Logger.debug("Deleting collection '\(collection.name)' (\(collection.photos.count) photo(s), importMode: \(collection.importMode.rawValue))")
        let fm = FileManager.default
        let collectionsRoot = settings.collectionsRoot.path

        guard let folderPath = collection.folderPath else {
            collections.removeAll { $0.id == collection.id }
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let jsonURL = settings.collectionFileURL(for: folderURL)
        let thumbsDir = folderURL.appendingPathComponent(ThumbnailGenerator.thumbnailsDirName, isDirectory: true)

        // 1. If import mode is copy, delete photo files (only within collections root)
        if collection.importMode == .copy {
            for photo in collection.photos {
                let resolved = photo.resolvedPath(relativeTo: folderPath)
                let photoURL = URL(fileURLWithPath: resolved)
                // Safety: never delete files outside the collections root
                if photoURL.path.hasPrefix(collectionsRoot) {
                    try? fm.removeItem(at: photoURL)
                    Logger.debug("Deleted copied photo: \(resolved)")
                }
            }
        }

        // 2. Delete cached thumbnail files
        for photo in collection.photos {
            if let resolved = photo.resolvedThumbnailPath(relativeTo: folderPath) {
                try? fm.removeItem(at: URL(fileURLWithPath: resolved))
            }
        }

        // 3. Remove .thumbnails/ directory if empty
        var thumbDirWarning: String? = nil
        if fm.fileExists(atPath: thumbsDir.path) {
            if let remaining = try? fm.contentsOfDirectory(at: thumbsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
               remaining.isEmpty {
                try? fm.removeItem(at: thumbsDir)
            } else {
                thumbDirWarning = ".thumbnails directory still contains files and was not removed."
            }
        }

        // 4. Remove the metadata file
        try? fm.removeItem(at: jsonURL)

        // 5. Check if main directory is now empty
        if let remaining = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
           remaining.isEmpty {
            try? fm.removeItem(at: folderURL)
        } else {
            var msg = "The collection directory could not be deleted because it still contains files."
            if let thumbWarn = thumbDirWarning {
                msg += " \(thumbWarn)"
            }
            dirWarningMessage = msg
            showDirWarning = true
        }

        // Remove from list
        collections.removeAll { $0.id == collection.id }
    }

    // MARK: - Import Flow

    private func handleImport() {
        // If a collection is selected, import directly into it
        if let selectedID = selectedCollectionID,
           collections.contains(where: { $0.id == selectedID }) {
            showImportPicker = true
        } else {
            showImportPicker = true
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            pendingImportURLs = urls

            // Check for a pending import target (from "create + import" flow)
            if let targetID = pendingImportTargetID,
               let collection = collections.first(where: { $0.id == targetID }) {
                pendingImportTargetID = nil
                importPhotos(into: collection)
            } else if let selectedID = selectedCollectionID,
                      let collection = collections.first(where: { $0.id == selectedID }) {
                // Import directly into selected collection
                importPhotos(into: collection)
            } else {
                // Show collection picker
                showCollectionPickerPopover = true
            }
        case .failure(let error):
            print("Import failed: \(error.localizedDescription)")
            pendingImportURLs = nil
            pendingImportTargetID = nil
        }
    }

    private func importPhotos(into collection: PhotoCollection) {
        guard let urls = pendingImportURLs,
              let index = collections.firstIndex(where: { $0.id == collection.id }) else {
            Logger.debug("importPhotos: no URLs or collection not found")
            pendingImportURLs = nil
            return
        }

        Logger.debug("importing \(urls.count) files into '\(collection.name)', folderPath: \(collection.folderPath ?? "nil")")

        var targetCollection = collections[index]
        var skippedCount = 0

        for url in urls {
            let sourcePath = url.path

            // Check for duplicates (compare resolved paths)
            let isDuplicate = targetCollection.photos.contains { existing in
                existing.resolvedPath(relativeTo: targetCollection.folderPath) == sourcePath
            }
            if isDuplicate {
                skippedCount += 1
                continue
            }

            // Copy if collection import mode is .copy
            var photoPath: String
            if targetCollection.importMode == .copy,
               let folderPath = targetCollection.folderPath {
                let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
                let destURL = folderURL.appendingPathComponent(url.lastPathComponent)
                if (try? FileManager.default.copyItem(at: url, to: destURL)) != nil {
                    // Store relative path for copied photos (survives renames)
                    photoPath = url.lastPathComponent
                } else {
                    photoPath = sourcePath
                }
            } else {
                photoPath = sourcePath
            }

            var photo = CollectionPhoto(path: photoPath)

            // Generate thumbnail
            if let folderPath = targetCollection.folderPath {
                let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
                let resolved = photo.resolvedPath(relativeTo: folderPath)
                if let absoluteThumb = ThumbnailGenerator.generateThumbnail(for: resolved, in: folderURL) {
                    // Store relative path so it survives collection renames
                    photo.thumbnailPath = relativePath(absoluteThumb, from: folderPath)
                }
            }

            targetCollection.photos.append(photo)
        }

        targetCollection.modifiedAt = Date()
        try? saveCollection(targetCollection)
        collections[index] = targetCollection

        Logger.debug("Import complete: \(urls.count - skippedCount) added to '\(targetCollection.name)', \(skippedCount) skipped")

        // Show skipped notice
        if skippedCount > 0 {
            let alert = NSAlert()
            alert.messageText = "Import Complete"
            alert.informativeText = "\(urls.count - skippedCount) photo(s) imported. \(skippedCount) already in collection, skipped."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        pendingImportURLs = nil
    }
}

// MARK: - Thumbnail Cell

/// A single thumbnail in the collection grid, with selection state and remove button.
private struct ThumbnailCell: View {

    let photo: CollectionPhoto
    let folderPath: String?
    let isSelected: Bool
    let onTap: () -> Void
    let onShiftTap: () -> Void
    let onRemove: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnailView(sourcePath: photo.resolvedPath(relativeTo: folderPath),
                               thumbnailPath: photo.resolvedThumbnailPath(relativeTo: folderPath))
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .opacity(isSelected ? 0.85 : 1.0)

            // ✕ Remove button on hover
            if isHovered {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(2)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        .simultaneousGesture(
            TapGesture(count: 1)
                .modifiers(.shift)
                .onEnded {
                    onShiftTap()
                }
        )
    }
}

// MARK: - Collection Row

/// A single collection row in the sidebar, with hover-revealed edit and delete buttons.
private struct CollectionRow: View {

    let collection: PhotoCollection
    let isExpanded: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack {
            Image(systemName: isExpanded ? "folder" : "folder")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.body)

                Text("\(collection.photos.count) photo\(collection.photos.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !collection.description.isEmpty {
                    Text(collection.description)
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
                    .help("Edit Collection")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Delete Collection")
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

// MARK: - Notification

extension Notification.Name {
    static let triggerImport = Notification.Name("PearblossomTriggerImport")
}
