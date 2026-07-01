import SwiftUI

/// Sheet for creating a new photo collection.
struct NewCollectionDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var nameError: String? = nil
    @State private var importAfterCreation: Bool = false
    @State private var importMode: ImportMode

    var onCreated: ((PhotoCollection) -> Void)?
    var onCreatedAndImport: ((PhotoCollection) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(onCreated: ((PhotoCollection) -> Void)? = nil,
         onCreatedAndImport: ((PhotoCollection) -> Void)? = nil) {
        self.onCreated = onCreated
        self.onCreatedAndImport = onCreatedAndImport
        _importMode = State(initialValue: AppSettings.shared.copyOnImport ? .copy : .reference)
    }

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Import Mode")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Picker("Import Mode", selection: $importMode) {
                    Text("Copy files into collection").tag(ImportMode.copy)
                    Text("Reference files in place").tag(ImportMode.reference)
                }
                .pickerStyle(.radioGroup)

                Text(importMode == .copy
                     ? "Photos will be copied into the collection folder."
                     : "Photos will be referenced at their current location.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Import photos after creation", isOn: $importAfterCreation)
                .font(.body)

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
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nameIsTaken)
            }
        }
        .padding()
        .frame(width: 350)
        .onSubmit {
            createCollection()
        }
    }

    // MARK: - Validation

    /// Whether the current name maps to an existing directory.
    private var nameIsTaken: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: settings.collectionFolderURL(named: trimmed).path)
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
                folderPath: folderURL.path,
                importMode: importMode
            )

            // Write .collection.json
            let fileURL = settings.collectionFileURL(for: folderURL)
            let data = try JSONEncoder().encode(collection)
            try data.write(to: fileURL)

            Logger.debug("Created collection '\(trimmed)' — importAfterCreation: \(importAfterCreation)")

            dismiss()

            if importAfterCreation {
                onCreatedAndImport?(collection)
            } else {
                onCreated?(collection)
            }
        } catch {
            nameError = "Could not create collection: \(error.localizedDescription)"
        }
    }
}
