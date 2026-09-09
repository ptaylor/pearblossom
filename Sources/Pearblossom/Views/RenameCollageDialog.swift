import SwiftUI

/// Sheet for editing a collage's name and description.
struct RenameCollageDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    let collage: CollageProject

    @State private var name: String
    @State private var description: String
    @State private var nameError: String? = nil

    var onSaved: ((String, String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(collage: CollageProject, onSaved: ((String, String) -> Void)? = nil) {
        self.collage = collage
        self.onSaved = onSaved
        _name = State(initialValue: collage.name)
        _description = State(initialValue: collage.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Collage")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField(collage.name, text: $name)
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

                Button("Save") {
                    editCollage()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || (name.trimmingCharacters(in: .whitespaces) == collage.name
                              && description == collage.description)
                          || nameIsTaken)
            }
        }
        .padding()
        .frame(width: 350)
        .onSubmit {
            editCollage()
        }
    }

    // MARK: - Validation

    private var nameIsTaken: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != collage.name else { return false }
        let fileURL = settings.collageFileURL(named: trimmed)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Edit

    private func editCollage() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            nameError = "Name cannot be empty."
            return
        }

        let nameChanged = trimmed != collage.name
        let descChanged = trimmedDesc != (collage.description.trimmingCharacters(in: .whitespaces))

        guard nameChanged || descChanged else {
            dismiss()
            return
        }

        // If only description changed, update file in place
        if !nameChanged {
            // Update the .collage.json with new description
            let updated = collage
            updated.description = trimmedDesc
            updated.modifiedAt = Date()
            if let path = updated.filePath {
                let data = try? JSONEncoder().encode(updated)
                try? data?.write(to: URL(fileURLWithPath: path))
            }
            onSaved?(trimmed, trimmedDesc)
            Logger.debug("Edited collage '\(collage.name)' — description updated")
            dismiss()
            return
        }

        // Name changed — rename file on disk
        let newFileURL = settings.collageFileURL(named: trimmed)
        let fm = FileManager.default

        // Check if target file already exists
        if fm.fileExists(atPath: newFileURL.path) {
            nameError = "A collage named \"\(trimmed)\" already exists. Choose another name."
            return
        }

        guard let oldPath = collage.filePath else {
            nameError = "Cannot determine current file location."
            return
        }

        let oldFileURL = URL(fileURLWithPath: oldPath)

        do {
            // Build updated collage with new name and path
            let updated = collage
            updated.name = trimmed
            updated.description = trimmedDesc
            updated.filePath = newFileURL.path
            updated.modifiedAt = Date()

            // Write updated JSON to new location first, then remove old file
            let newData = try JSONEncoder().encode(updated)
            try newData.write(to: newFileURL)

            // Remove old file (it's safe — the new file has been written)
            try? fm.removeItem(at: oldFileURL)

            Logger.debug("Renamed collage '\(collage.name)' → '\(trimmed)'")

            onSaved?(trimmed, trimmedDesc)
            dismiss()
        } catch {
            nameError = "Could not rename: \(error.localizedDescription)"
        }
    }
}
