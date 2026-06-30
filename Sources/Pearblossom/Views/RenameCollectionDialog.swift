import SwiftUI

/// Sheet for renaming an existing photo collection.
struct RenameCollectionDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    let collection: PhotoCollection

    @State private var name: String
    @State private var nameError: String? = nil

    var onRenamed: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(collection: PhotoCollection, onRenamed: ((String) -> Void)? = nil) {
        self.collection = collection
        self.onRenamed = onRenamed
        _name = State(initialValue: collection.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Collection")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("New Name")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField(collection.name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in
                        nameError = nil
                    }
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

                Button("Rename") {
                    renameCollection()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || name.trimmingCharacters(in: .whitespaces) == collection.name
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

    private func renameCollection() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            nameError = "Name cannot be empty."
            return
        }

        guard trimmed != collection.name else {
            dismiss()
            return
        }

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
            updated.folderPath = newFolderURL.path
            updated.modifiedAt = Date()

            let jsonURL = settings.collectionFileURL(for: newFolderURL)
            let data = try JSONEncoder().encode(updated)
            try data.write(to: jsonURL)

            onRenamed?(trimmed)

            Logger.debug("Renamed collection '\(collection.name)' → '\(trimmed)'")
            dismiss()
        } catch {
            nameError = "Could not rename: \(error.localizedDescription)"
        }
    }
}
