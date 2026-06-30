import SwiftUI

/// Inspector panel shown on the right side of the main window.
/// Displays properties for the selected photo or canvas.
struct InspectorView: View {

    var body: some View {
        VStack(spacing: 0) {
            Text("Inspector")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)

            Divider()

            Spacer()

            Text("No selection")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))

            Spacer()
        }
        .frame(minWidth: 240)
    }
}
