import SwiftUI

/// Sheet for creating a new photo collection.
struct NewCollectionDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var nameError: String? = nil

    var onCreated: ((PhotoCollection) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collection")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField("My Photos", text: $name)
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

                Button("Create") {
                    createCollection()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - Creation

    private func createCollection() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            nameError = "Name cannot be empty."
            return
        }

        let folderURL = settings.collectionFolderURL(named: trimmed)

        // Check if directory already exists
        if FileManager.default.fileExists(atPath: folderURL.path) {
            nameError = "A collection named \"\(trimmed)\" already exists. Choose another name."
            return
        }

        do {
            // Create the directory
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)

            // Build the collection
            let collection = PhotoCollection(
                name: trimmed,
                description: description,
                folderPath: folderURL.path
            )

            // Write .collection.json
            let fileURL = settings.collectionFileURL(for: folderURL)
            let data = try JSONEncoder().encode(collection)
            try data.write(to: fileURL)

            onCreated?(collection)
            dismiss()
        } catch {
            nameError = "Could not create collection: \(error.localizedDescription)"
        }
    }
}
