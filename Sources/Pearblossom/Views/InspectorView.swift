import SwiftUI

/// Inspector panel shown on the right side of the main window.
/// Displays canvas configuration when a project is selected.
struct InspectorView: View {

    @Binding var project: CollageProject?
    @Binding var magnification: CGFloat
    @State private var showExportSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Canvas Config")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let binding = Binding($project) {
                        backgroundSection(binding)
                        Divider()
                        boundingBoxSection(binding)
                        Divider()
                        shadowSection(binding)
                        Divider()
                        zoomSection()
                        Divider()
                        canvasInfoSection(binding.wrappedValue)
                        Divider()
                        exportSection
                    }
                }
                .padding()
            }

            if project == nil {
                Spacer()
                Text("Select a collage to configure")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
        }
        .frame(minWidth: 260)
        .sheet(isPresented: $showExportSheet) {
            if let proj = project {
                ExportSettingsView(project: proj)
            }
        }
    }

    // MARK: - Background Section

    /// The allowed background colors in multi-exposure mode: white, black, transparent.
    private static let multiExposureBackgrounds: [CodableColor] = [
        .white, .black, .transparent
    ]

    private func backgroundSection(_ binding: Binding<CollageProject>) -> some View {
        // In multi-exposure mode, restrict to white/black/transparent only.
        // Intermediate greys add a grey cast to the additive blend and don't make sense.
        if binding.wrappedValue.isMultiExposure {
            return AnyView(restrictedBackgroundSection(binding))
        }
        return AnyView(fullBackgroundSection(binding))
    }

    private func restrictedBackgroundSection(_ binding: Binding<CollageProject>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.headline)

            Text("Multi-exposure works best with solid white, black, or transparent.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Self.multiExposureBackgrounds.indices, id: \.self) { index in
                    let preset = Self.multiExposureBackgrounds[index]
                    let isSelected = backgroundIsSelected(binding.wrappedValue.backgroundColor, preset)

                    Button {
                        binding.wrappedValue.backgroundColor = preset
                        binding.wrappedValue.modifiedAt = Date()
                    } label: {
                        if preset.isTransparent {
                            checkerboardSwatch(isSelected: isSelected)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: NSColor(
                                    calibratedRed: preset.red,
                                    green: preset.green,
                                    blue: preset.blue,
                                    alpha: 1.0)))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help(presetLabel(preset))
                }
            }
        }
    }

    private func fullBackgroundSection(_ binding: Binding<CollageProject>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(CodableColor.grayscalePresets.indices, id: \.self) { index in
                    let preset = CodableColor.grayscalePresets[index]
                    let isSelected = binding.wrappedValue.backgroundColor.red == preset.red
                        && binding.wrappedValue.backgroundColor.green == preset.green
                        && binding.wrappedValue.backgroundColor.blue == preset.blue
                        && !binding.wrappedValue.backgroundColor.isTransparent

                    Button {
                        binding.wrappedValue.backgroundColor = preset
                        binding.wrappedValue.modifiedAt = Date()
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: NSColor(
                                calibratedRed: preset.red,
                                green: preset.green,
                                blue: preset.blue,
                                alpha: 1.0)))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(presetLabel(preset))
                }

                // Transparent / checkerboard option
                let isTransparent = binding.wrappedValue.backgroundColor.isTransparent
                Button {
                    binding.wrappedValue.backgroundColor = .transparent
                    binding.wrappedValue.modifiedAt = Date()
                } label: {
                    checkerboardSwatch(isSelected: isTransparent)
                }
                .buttonStyle(.plain)
                .help("Transparent")
            }
        }
    }

    /// A checkerboard swatch used for the transparent background option.
    private func checkerboardSwatch(isSelected: Bool) -> some View {
        Canvas { context, size in
            let tileCount = 6
            let tileW = size.width / CGFloat(tileCount)
            let tileH = size.height / CGFloat(tileCount)
            for row in 0..<tileCount {
                for col in 0..<tileCount {
                    let isWhite = (row + col) % 2 == 0
                    let color: Color = isWhite ? .white : Color(NSColor(white: 0.82, alpha: 1.0))
                    let rect = CGRect(
                        x: CGFloat(col) * tileW, y: CGFloat(row) * tileH,
                        width: tileW + 1, height: tileH + 1)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
        )
    }

    private func presetLabel(_ color: CodableColor) -> String {
        if color.red == 0 && color.green == 0 && color.blue == 0 { return "Black (0%)" }
        if color.red == 1 && color.green == 1 && color.blue == 1 { return "White (100%)" }
        if color.isTransparent { return "Transparent" }
        let pct = Int(color.red * 100)
        return "\(pct)% Grey"
    }

    /// Checks whether `current` matches `preset` for the background picker selection highlight.
    private func backgroundIsSelected(_ current: CodableColor, _ preset: CodableColor) -> Bool {
        if preset.isTransparent { return current.isTransparent }
        if current.isTransparent { return false }
        return current.red == preset.red
            && current.green == preset.green
            && current.blue == preset.blue
    }

    // MARK: - Bounding Box Section

    private func boundingBoxSection(_ binding: Binding<CollageProject>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bounding Box")
                .font(.headline)

            Picker("Mode", selection: binding.boundingBoxMode) {
                Text("Defined Border").tag(BoundingBoxMode.definedBorder)
                Text("Manual").tag(BoundingBoxMode.manual)
            }
            .pickerStyle(.segmented)
            .onChange(of: binding.wrappedValue.boundingBoxMode) { _, newMode in
                if newMode == .manual {
                    binding.wrappedValue.ensureManualBoundingBox()
                }
                binding.wrappedValue.modifiedAt = Date()
            }

            if binding.wrappedValue.boundingBoxMode == .definedBorder {
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: binding.borderMargin, in: 0...200, step: 5)
                        .onChange(of: binding.wrappedValue.borderMargin) { _, _ in
                            binding.wrappedValue.modifiedAt = Date()
                        }
                    HStack {
                        Text("Margin")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(binding.wrappedValue.borderMargin)) px")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if binding.wrappedValue.boundingBoxMode == .manual {
                Text("Drag the edges of the bounding box on the canvas to resize.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button {
                NotificationCenter.default.post(name: .fitToBoundingBox, object: nil)
            } label: {
                if binding.wrappedValue.showBoundingBox {
                    Label("Fit Content", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                } else {
                    Label("Show All", systemImage: "arrow.down.backward.and.arrow.up.forward")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(binding.wrappedValue.showBoundingBox
                  ? "Zoom to the content area for export preview"
                  : "Reset zoom and return to normal view")

            Toggle("Show Bounding Box", isOn: binding.showBoundingBox)
                .font(.body)
                .onChange(of: binding.wrappedValue.showBoundingBox) { _, _ in
                    binding.wrappedValue.modifiedAt = Date()
                }
        }
    }

    // MARK: - Shadow Section

    private func shadowSection(_ binding: Binding<CollageProject>) -> some View {
        // Shadows are meaningless in multi-exposure (additive blend) mode.
        if binding.wrappedValue.isMultiExposure {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Shadow")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: Binding<CGFloat>(
                        get: { commonShadowRadius(binding.wrappedValue) },
                        set: { newValue in
                            guard !binding.wrappedValue.layers.isEmpty else { return }
                            binding.wrappedValue.layers.indices.forEach { i in
                                binding.wrappedValue.layers[i].shadowRadius = newValue
                            }
                            binding.wrappedValue.modifiedAt = Date()
                        }
                    ), in: 0...30, step: 1)
                    HStack {
                        Text("Radius")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(commonShadowRadius(binding.wrappedValue))) px")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }

                if commonShadowRadius(binding.wrappedValue) > 0 {
                    Text("Drop shadows increase the rendered bounds of each image.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        )
    }

    /// Returns the shadow radius from the first layer (all layers share the same
    /// value since the slider sets them in unison), or 0 if there are no layers.
    private func commonShadowRadius(_ project: CollageProject) -> CGFloat {
        return project.layers.first?.shadowRadius ?? 0
    }

    // MARK: - Zoom Section

    private func zoomSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zoom")
                .font(.headline)

            Slider(value: $magnification, in: 0.1...5.0, step: 0.25)
                .help("Zoom Level")

            HStack {
                Spacer()
                Text("\(Int(magnification * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    let newMag = max(magnification - 0.25, 0.1)
                    magnification = newMag
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Zoom Out (⌘–)")

                Button("Reset") {
                    magnification = 1.0
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption)

                Spacer()

                Button {
                    let newMag = min(magnification + 0.25, 5.0)
                    magnification = newMag
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Zoom In (⌘+)")
            }
        }
    }

    // MARK: - Canvas Info

    private func canvasInfoSection(_ project: CollageProject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Canvas")
                .font(.headline)
            Text("\(Int(project.canvasWidth)) × \(Int(project.canvasHeight)) pt")
                .font(.caption)
                .foregroundColor(.secondary)

            let bb = project.effectiveBoundingBox()
            Text("Bounding box: \(Int(bb.width)) × \(Int(bb.height)) pt")
                .font(.caption)
                .foregroundColor(.secondary)

            if project.isMultiExposure {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                    Text("Multi-Exposure")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showExportSheet = true
            } label: {
                Label("Export Collage…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Export the collage as PNG or JPEG")
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerExport)) { _ in
            if project != nil {
                showExportSheet = true
            }
        }
    }
}

extension Notification.Name {
    /// Posted to open the Export sheet (from the menu bar).
    static let triggerExport = Notification.Name("PearblossomTriggerExport")
    /// Posted to open the Picasa collage (.cxf) importer.
    static let triggerImportCollage = Notification.Name("PearblossomTriggerImportCollage")
    /// Posted when the set of collages changes (e.g. after a Picasa import).
    static let collagesDidChange = Notification.Name("PearblossomCollagesDidChange")
    /// Posted when photos are dropped on a blank canvas. UserInfo: paths, point, name, description.
    static let blankCanvasDrop = Notification.Name("PearblossomBlankCanvasDrop")
    /// Posted to re-trigger a photo drop after a new collage has been created.
    static let deferredDrop = Notification.Name("PearblossomDeferredDrop")
}
