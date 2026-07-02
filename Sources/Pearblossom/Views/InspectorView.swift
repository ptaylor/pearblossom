import SwiftUI

/// Inspector panel shown on the right side of the main window.
/// Displays canvas configuration when a project is selected.
struct InspectorView: View {

    @Binding var project: CollageProject?

    var body: some View {
        VStack(spacing: 0) {
            Text("Canvas Config")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)

            Divider()

            if let binding = Binding($project) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        backgroundSection(binding)
                        Divider()
                        boundingBoxSection(binding)
                        Divider()
                        canvasInfoSection(binding.wrappedValue)
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("Select a collage to configure")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
        }
        .frame(minWidth: 240)
    }

    // MARK: - Background Section

    private func backgroundSection(_ binding: Binding<CollageProject>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(CodableColor.grayscalePresets.indices, id: \.self) { index in
                    let preset = CodableColor.grayscalePresets[index]
                    let isSelected = binding.wrappedValue.backgroundColor.red == preset.red
                        && binding.wrappedValue.backgroundColor.green == preset.green
                        && binding.wrappedValue.backgroundColor.blue == preset.blue

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
            }
        }
    }

    private func presetLabel(_ color: CodableColor) -> String {
        if color.red == 0 && color.green == 0 && color.blue == 0 { return "Black (0%)" }
        if color.red == 1 && color.green == 1 && color.blue == 1 { return "White (100%)" }
        let pct = Int(color.red * 100)
        return "\(pct)% Grey"
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
            .onChange(of: binding.wrappedValue.boundingBoxMode) { _, _ in
                binding.wrappedValue.modifiedAt = Date()
            }

            if binding.wrappedValue.boundingBoxMode == .definedBorder {
                HStack {
                    Text("Margin:")
                        .font(.body)
                    Slider(value: binding.borderMargin, in: 0...200, step: 5)
                        .onChange(of: binding.wrappedValue.borderMargin) { _, _ in
                            binding.wrappedValue.modifiedAt = Date()
                        }
                    Text("\(Int(binding.wrappedValue.borderMargin)) px")
                        .font(.body)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            } else {
                Text("Drag the edges of the bounding box on the canvas to resize.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                NotificationCenter.default.post(name: .fitToBoundingBox, object: nil)
            } label: {
                Label("Fit to Bounding Box", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Toggle("Show Bounding Box", isOn: binding.showBoundingBox)
                .font(.body)
                .onChange(of: binding.wrappedValue.showBoundingBox) { _, _ in
                    binding.wrappedValue.modifiedAt = Date()
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
        }
    }
}
