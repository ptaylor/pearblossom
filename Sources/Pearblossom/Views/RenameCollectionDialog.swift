import SwiftUI

/// Sheet for editing a collection's name and description.
struct RenameCollectionDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    let collection: PhotoCollection

    @State private var name: String
    @State private var description: String
    @State private var nameError: String? = nil

    var onSaved: ((String, String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(collection: PhotoCollection, onSaved: ((String, String) -> Void)? = nil) {
        self.collection = collection
        self.onSaved = onSaved
        _name = State(initialValue: collection.name)
        _description = State(initialValue: collection.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Collection")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField(collection.name, text: $name)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Import Mode")
                    .font(.callout)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: collection.importMode == .copy ? "doc.on.doc" : "link")
                        .foregroundColor(.secondary)
                    Text(collection.importMode == .copy ? "Copy files into collection" : "Reference files in place")
                        .foregroundColor(.secondary)
                }

                Text("Import mode cannot be changed after creation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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

                Button("Save") {
                    editCollection()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || (name.trimmingCharacters(in: .whitespaces) == collection.name
                              && description == collection.description)
                          || nameIsTaken)
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - Validation

    /// Whether the current name maps to an existing directory (excluding the current collection).
    private var nameIsTaken: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != collection.name else { return false }
        return FileManager.default.fileExists(atPath: settings.collectionFolderURL(named: trimmed).path)
    }

    // MARK: - Rename

    private func editCollection() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            nameError = "Name cannot be empty."
            return
        }

        let nameChanged = trimmed != collection.name
        let descChanged = trimmedDesc != (collection.description.trimmingCharacters(in: .whitespaces))

        guard nameChanged || descChanged else {
            dismiss()
            return
        }

        // If only description changed, update in place without renaming
        if !nameChanged {
            onSaved?(trimmed, trimmedDesc)
            Logger.debug("Edited collection '\(collection.name)' — description updated")
            dismiss()
            return
        }

        // Name changed — rename folder on disk
        let newFolderURL = settings.collectionFolderURL(named: trimmed)
        let fm = FileManager.default

        // Check if target directory already exists
        if fm.fileExists(atPath: newFolderURL.path) {
            nameError = "A collection named \"\(trimmed)\" already exists. Choose another name."
            return
        }

        guard let oldPath = collection.folderPath else {
            nameError = "Cannot determine current folder location."
            return
        }

        let oldFolderURL = URL(fileURLWithPath: oldPath, isDirectory: true)

        do {
            // Rename folder on disk
            try fm.moveItem(at: oldFolderURL, to: newFolderURL)

            // Update .collection.json inside the renamed folder
            var updated = collection
            updated.name = trimmed
            updated.description = trimmedDesc
            updated.folderPath = newFolderURL.path
            updated.modifiedAt = Date()

            let jsonURL = settings.collectionFileURL(for: newFolderURL)
            let data = try JSONEncoder().encode(updated)
            try data.write(to: jsonURL)

            onSaved?(trimmed, trimmedDesc)

            Logger.debug("Edited collection '\(collection.name)' → name: '\(trimmed)', description: '\(trimmedDesc)'")
            dismiss()
        } catch {
            nameError = "Could not rename: \(error.localizedDescription)"
        }
    }
}
