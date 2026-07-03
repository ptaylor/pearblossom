import SwiftUI
import AppKit
import CoreImage

/// A sheet that lets the user configure export settings before saving.
struct ExportSettingsView: View {

    let project: CollageProject

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedFormat: ExportFormat = .png
    @State private var jpegQuality: Double = 0.92
    @State private var scaleMode: ScaleMode = .multiplier1x
    @State private var customScale: Double = 1.0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var sourceDPI: CGFloat? = nil
    @State private var exportFileName: String = ""

    private let ciContext = CIContext()

    enum ScaleMode: Hashable {
        case multiplier0_25x
        case multiplier0_5x
        case multiplier1x
        case multiplier2x
        case custom

        var label: String {
            switch self {
            case .multiplier0_25x: return "0.25×"
            case .multiplier0_5x:  return "0.5×"
            case .multiplier1x:    return "1× (Source Resolution)"
            case .multiplier2x:    return "2×"
            case .custom:          return "Custom"
            }
        }

        var scaleValue: Double {
            switch self {
            case .multiplier0_25x: return 0.25
            case .multiplier0_5x:  return 0.5
            case .multiplier1x:    return 1.0
            case .multiplier2x:    return 2.0
            case .custom:          return -1  // sentinel
            }
        }
    }

    /// Effective scale multiplier for the current selection.
    private var effectiveScale: Double {
        if scaleMode == .custom { return customScale }
        return scaleMode.scaleValue
    }

    /// Computed output pixel dimensions.
    private var outputPixelSize: CGSize {
        let scale = effectiveScale > 0 ? effectiveScale : 1.0
        return ExportRenderer.outputPixelSize(project: project, scaleMultiplier: scale)
    }

    private var hasLayers: Bool {
        !project.layers.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Collage")
                .font(.title2)
                .fontWeight(.semibold)

            // Format picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Format")
                    .font(.headline)

                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // JPEG quality (only when JPEG selected)
            if selectedFormat == .jpeg {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality: \(Int(jpegQuality * 100))%")
                        .font(.headline)

                    Slider(value: $jpegQuality, in: 0.0...1.0, step: 0.05)
                }
            }

            // Scale / size
            VStack(alignment: .leading, spacing: 6) {
                Text("Image Size")
                    .font(.headline)

                Picker("Scale", selection: $scaleMode) {
                    Text(ScaleMode.multiplier0_25x.label).tag(ScaleMode.multiplier0_25x)
                    Text(ScaleMode.multiplier0_5x.label).tag(ScaleMode.multiplier0_5x)
                    Text(ScaleMode.multiplier1x.label).tag(ScaleMode.multiplier1x)
                    Text(ScaleMode.multiplier2x.label).tag(ScaleMode.multiplier2x)
                    Text(ScaleMode.custom.label).tag(ScaleMode.custom)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                if scaleMode == .custom {
                    HStack {
                        Text("×")
                        TextField("Scale", value: $customScale, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $customScale, in: 0.1...10.0, step: 0.1)
                    }
                }

                // Output dimensions preview
                HStack {
                    Text("Output:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(outputPixelSize.width)) × \(Int(outputPixelSize.height)) px")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    if outputPixelSize.width > 16384 || outputPixelSize.height > 16384 {
                        Text("(capped)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            if !hasLayers {
                Text("The collage has no images to export.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // File name
            VStack(alignment: .leading, spacing: 6) {
                Text("File Name")
                    .font(.headline)
                TextField("File name", text: $exportFileName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: exportFileName) { _, newValue in
                        // Sanitize: no path separators
                        exportFileName = newValue.replacingOccurrences(of: "/", with: "")
                            .replacingOccurrences(of: ":", with: "")
                    }
                Text(".\(selectedFormat.fileExtension)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Export…") {
                    performExport()
                }
                .keyboardShortcut(.return)
                .disabled(!hasLayers || isExporting)
            }
            .padding(.top, 8)

            if isExporting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            // Pre-populate from global defaults
            selectedFormat = settings.defaultExportFormat
            jpegQuality = settings.defaultJPEGQuality
            switch settings.defaultExportScale {
            case 0.25: scaleMode = .multiplier0_25x
            case 0.5:  scaleMode = .multiplier0_5x
            case 1.0:  scaleMode = .multiplier1x
            case 2.0:  scaleMode = .multiplier2x
            default:   scaleMode = .custom; customScale = settings.defaultExportScale
            }
            // Detect DPI from source photos (async, lightweight)
            DispatchQueue.global(qos: .userInitiated).async {
                let dpi = ExportRenderer.detectSourceDPI(project: project)
                DispatchQueue.main.async {
                    sourceDPI = dpi
                }
            }
            // Default filename from collage name
            exportFileName = project.name
        }
    }

    // MARK: - Export

    private func performExport() {
        guard hasLayers else { return }

        isExporting = true
        exportError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let scale = effectiveScale > 0 ? effectiveScale : 1.0
            let cgImage = ExportRenderer.render(
                project: project,
                scaleMultiplier: scale,
                context: ciContext
            )

            guard let image = cgImage else {
                DispatchQueue.main.async {
                    exportError = "Failed to render the collage for export."
                    isExporting = false
                }
                Logger.error("ExportSettingsView: render returned nil")
                return
            }

            DispatchQueue.main.async {
                isExporting = false
                presentSavePanel(with: image)
            }
        }
    }

    private func presentSavePanel(with image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [selectedFormat.utType]
        panel.nameFieldStringValue = "\(exportFileName).\(selectedFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.title = "Export Collage"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try ExportWriter.write(image, to: url, format: selectedFormat, jpegQuality: jpegQuality, dpi: sourceDPI)
                Logger.debug("Export succeeded: \(url.path)")
                dismiss()
            } catch {
                exportError = error.localizedDescription
                Logger.error("Export failed: \(error.localizedDescription)")
            }
        }
    }
}
