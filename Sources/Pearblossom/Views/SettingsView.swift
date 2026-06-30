import SwiftUI
import UniformTypeIdentifiers

/// Settings window accessible via Pearblossom → Settings… (⌘,)
struct SettingsView: View {

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
                .padding()
        }
        .frame(width: 450, height: 460)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {

    @ObservedObject var settings: AppSettings
    @State private var showFolderPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Collections")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Collections Folder")
                        .font(.body)

                    Text(settings.collectionsRoot.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Change…") {
                    showFolderPicker = true
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Text("New collections will be created as subfolders here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Collection metadata filename")
                    .font(.callout)
                    .foregroundColor(.secondary)

                TextField(".collection.json", text: $settings.collectionFileName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            Toggle("Copy photos into collection folder on import", isOn: $settings.copyOnImport)
                .font(.body)

            Text("When off, photos are referenced in-place (no copies). When on, imported files are copied into the collection folder.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Developer")
                .font(.headline)

            Toggle("Debug logging", isOn: $settings.debugLoggingEnabled)
                .font(.body)

            Text("When on, diagnostic messages are printed to the console (visible in Terminal or Console.app).")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .onChange(of: showFolderPicker) { _, show in
            if show {
                chooseFolder()
                showFolderPicker = false
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Collections Folder"
        panel.message = "Select the folder where your collections will be stored."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.collectionsRoot

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.collectionsRoot = url
    }
}
