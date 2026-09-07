import SwiftUI

/// Sheet that confirms and performs a Picasa `.cxf` collage import.
struct ImportCollageDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    let cxfURL: URL
    var onImported: ((CollageProject, PhotoCollection, [String]) -> Void)?

    @State private var name: String
    @State private var description: String = ""
    @State private var theme: String? = nil
    @State private var nameError: String? = nil
    @State private var isImporting = false

    @Environment(\.dismiss) private var dismiss

    init(cxfURL: URL, onImported: ((CollageProject, PhotoCollection, [String]) -> Void)? = nil) {
        self.cxfURL = cxfURL
        self.onImported = onImported
        _name = State(initialValue: cxfURL.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Picasa Collage")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(cxfURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let theme = theme {
                    Text(themeLabel(for: theme))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField("Collage Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in
                        nameError = nil
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField("Optional", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            Text("A collage and a matching photo collection will be created.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = nameError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .disabled(isImporting)

                Button(isImporting ? "Importing…" : "Import") {
                    performImport()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nameIsTaken || isImporting)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear(perform: loadTheme)
    }

    // MARK: - Theme Preview

    private func loadTheme() {
        DispatchQueue.global(qos: .utility).async {
            let data = try? Data(contentsOf: cxfURL)
            let found = data.flatMap { CXFParser.peekTheme(from: $0) }
            DispatchQueue.main.async {
                self.theme = found
            }
        }
    }

    private func themeLabel(for theme: String) -> String {
        switch theme {
        case "multiexp":
            return "Multi-Exposure collage"
        case "picturepile":
            return "Picture Pile collage"
        default:
            return theme
        }
    }

    // MARK: - Validation

    private var nameIsTaken: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: settings.collageFileURL(named: trimmed).path)
            || FileManager.default.fileExists(atPath: settings.collectionFolderURL(named: trimmed).path)
    }

    // MARK: - Import

    private func performImport() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            nameError = "Name cannot be empty."
            return
        }

        if FileManager.default.fileExists(atPath: settings.collageFileURL(named: trimmed).path) {
            nameError = "A collage named \"\(trimmed)\" already exists. Choose another name."
            return
        }
        if FileManager.default.fileExists(atPath: settings.collectionFolderURL(named: trimmed).path) {
            nameError = "A collection named \"\(trimmed)\" already exists. Choose another name."
            return
        }

        isImporting = true
        let descriptionText = description.trimmingCharacters(in: .whitespaces)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try CollageImporter.importCollage(
                    from: cxfURL,
                    name: trimmed,
                    description: descriptionText
                )
                let (project, collection) = try persist(result, name: trimmed)

                DispatchQueue.main.async {
                    onImported?(project, collection, result.skippedSources)
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    nameError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    /// Writes the collection and collage to disk, then returns the finalized objects.
    private func persist(
        _ result: CollageImporter.ImportResult,
        name: String
    ) throws -> (CollageProject, PhotoCollection) {
        let fm = FileManager.default

        // 1. Create the collection folder and its metadata.
        let folderURL = settings.collectionFolderURL(named: name)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: false)

        var collection = result.collection
        collection.folderPath = folderURL.path
        collection.modifiedAt = Date()

        // Generate thumbnails eagerly so the collection browser is ready immediately.
        for index in collection.photos.indices {
            let resolved = collection.photos[index].resolvedPath(relativeTo: folderURL.path)
            if let thumbnail = ThumbnailGenerator.generateThumbnail(for: resolved, in: folderURL) {
                collection.photos[index].thumbnailPath = Self.relativePath(thumbnail, from: folderURL.path)
            }
        }

        let collectionURL = settings.collectionFileURL(for: folderURL)
        try JSONEncoder().encode(collection).write(to: collectionURL)

        // 2. Write the collage project file.
        let project = result.project
        let collageURL = settings.collageFileURL(named: name)
        project.filePath = collageURL.path
        try JSONEncoder().encode(project).write(to: collageURL)

        Logger.debug("Picasa import: created collage '\(name)' and collection '\(name)'")
        return (project, collection)
    }

    private static func relativePath(_ absolute: String, from folder: String) -> String {
        if absolute.hasPrefix(folder + "/") {
            return String(absolute.dropFirst(folder.count + 1))
        }
        return absolute
    }
}
