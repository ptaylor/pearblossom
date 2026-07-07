import SwiftUI

/// Sheet for creating a new collage project.
struct NewCollageDialog: View {

    @ObservedObject private var settings = AppSettings.shared

    @State private var name: String
    @State private var description: String
    @State private var nameError: String? = nil
    @State private var isMultiExposure = false

    var onCreated: ((CollageProject) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(initialName: String = "", initialDescription: String = "", onCreated: ((CollageProject) -> Void)? = nil) {
        _name = State(initialValue: initialName)
        _description = State(initialValue: initialDescription)
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collage")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField("My Collage", text: $name)
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
                Toggle("Multi-Exposure", isOn: $isMultiExposure)
                    .font(.callout)

                if isMultiExposure {
                    Text("Photos blend equally regardless of layering order. Best with solid black, white, or transparent backgrounds.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                Button("Create") {
                    createCollage()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nameIsTaken)
            }
        }
        .padding()
        .frame(width: 350)
        .onSubmit {
            createCollage()
        }
    }

    // MARK: - Validation

    private var nameIsTaken: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let fileURL = settings.collageFileURL(named: trimmed)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Creation

    private func createCollage() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            nameError = "Name cannot be empty."
            return
        }

        let fileURL = settings.collageFileURL(named: trimmed)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            nameError = "A collage named \"\(trimmed)\" already exists. Choose another name."
            return
        }

        do {
            // Ensure collages directory exists
            let fm = FileManager.default
            if !fm.fileExists(atPath: settings.collagesDir.path) {
                try fm.createDirectory(at: settings.collagesDir, withIntermediateDirectories: true)
            }

            // Build the collage with global defaults
            let collage = CollageProject(
                name: trimmed,
                description: description,
                filePath: fileURL.path,
                backgroundColor: settings.defaultBackgroundColor,
                borderMargin: settings.defaultBorderMargin,
                isMultiExposure: isMultiExposure
            )

            // Write .collage.json
            let data = try JSONEncoder().encode(collage)
            try data.write(to: fileURL)

            Logger.debug("Created collage '\(trimmed)' at \(fileURL.path)")

            onCreated?(collage)
            dismiss()
        } catch {
            nameError = "Could not create collage: \(error.localizedDescription)"
        }
    }
}
