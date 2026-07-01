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
        .frame(width: 450, height: 680)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {

    @ObservedObject var settings: AppSettings
    @State private var showFolderPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Root Folder")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Root Folder")
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

            Text("Collections and collages are stored as subdirectories inside the root folder.")
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

            Text("Default import mode for new collections. Can be overridden per collection at creation time.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Thumbnail size")
                        .font(.body)

                    Spacer()

                    Text("\(Int(settings.thumbnailSize)) pt")
                        .font(.body)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                Slider(value: $settings.thumbnailSize, in: 80...400, step: 20)

                Text("Existing thumbnails are not regenerated. Only newly imported photos use this setting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Canvas Defaults")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Default Background")
                    .font(.callout)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(CodableColor.grayscalePresets.indices, id: \.self) { index in
                        let preset = CodableColor.grayscalePresets[index]
                        let isSelected = settings.defaultBackgroundColor.red == preset.red
                            && settings.defaultBackgroundColor.green == preset.green
                            && settings.defaultBackgroundColor.blue == preset.blue

                        Button {
                            settings.defaultBackgroundColor = preset
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: NSColor(
                                    calibratedRed: preset.red,
                                    green: preset.green,
                                    blue: preset.blue,
                                    alpha: 1.0)))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Default border margin:")
                    .font(.body)

                Slider(value: $settings.defaultBorderMargin, in: 0...200, step: 5)

                Text("\(Int(settings.defaultBorderMargin)) px")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            Text("Applied to new collages. Existing collages are unaffected.")
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
