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

    /// Image file types the app can import.
    private static let allowedImageTypes: [UTType] = [
        .jpeg, .png, .tiff, .heic, .bmp, .gif
    ]

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

                Spacer()
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
            RenameCollectionDialog(collection: collection) { newName in
                if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                    collections[index].name = newName
                    collections[index].folderPath = settings.collectionFolderURL(named: newName).path
                    collections[index].modifiedAt = Date()
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
            Text("\"\(collection.name)\" contains \(collection.photos.count) photo(s). The metadata file will be removed, but photo files on disk will not be deleted.")
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
            ForEach(collections) { collection in
                // Collection header row
                HStack {
                    Image(systemName: expandedCollectionID == collection.id ? "folder" : "folder")
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(collection.name)
                            .font(.body)
                        Text("\(collection.photos.count) photo\(collection.photos.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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
                    Button("Rename…") {
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

    // MARK: - Thumbnail Grid

    @ViewBuilder
    private func thumbnailGrid(for collection: PhotoCollection) -> some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(collection.photos) { photo in
                PhotoThumbnailView(sourcePath: photo.path, thumbnailPath: photo.thumbnailPath)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .cornerRadius(3)
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
        let root = settings.collectionsRoot
        let fm = FileManager.default

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
                try? saveCollection(collection)
            }

            return collection
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func saveCollection(_ collection: PhotoCollection) throws {
        guard let folderPath = collection.folderPath,
              let folderURL = URL(string: "file://" + folderPath) else { return }
        let jsonURL = settings.collectionFileURL(for: folderURL)
        let data = try JSONEncoder().encode(collection)
        try data.write(to: jsonURL)
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
                if let thumbPath = ThumbnailGenerator.generateThumbnail(for: photo.path, in: folderURL),
                   let photoIndex = updated.photos.firstIndex(where: { $0.id == photo.id }) {
                    updated.photos[photoIndex].thumbnailPath = thumbPath
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
        Logger.debug("Deleting collection '\(collection.name)' (\(collection.photos.count) photo(s))")
        let fm = FileManager.default

        guard let folderPath = collection.folderPath else {
            collections.removeAll { $0.id == collection.id }
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let jsonURL = settings.collectionFileURL(for: folderURL)

        // Remove the metadata file
        try? fm.removeItem(at: jsonURL)

        // Check if directory is now empty
        if let remaining = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
           remaining.isEmpty {
            // Directory is empty — remove it
            try? fm.removeItem(at: folderURL)
        } else {
            // Directory still has files — warn
            dirWarningMessage = "The collection directory could not be deleted because it still contains files."
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
            let path = url.path

            // Check for duplicates
            if targetCollection.photos.contains(where: { $0.path == path }) {
                skippedCount += 1
                continue
            }

            // Copy if enabled
            var finalPath = path
            if settings.copyOnImport,
               let folderPath = targetCollection.folderPath {
                let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
                let destURL = folderURL.appendingPathComponent(url.lastPathComponent)
                if (try? FileManager.default.copyItem(at: url, to: destURL)) != nil {
                    finalPath = destURL.path
                }
            }

            var photo = CollectionPhoto(path: finalPath)

            // Generate thumbnail
            if let folderPath = targetCollection.folderPath {
                let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
                photo.thumbnailPath = ThumbnailGenerator.generateThumbnail(for: finalPath, in: folderURL)
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

// MARK: - Notification

extension Notification.Name {
    static let triggerImport = Notification.Name("PearblossomTriggerImport")
}
