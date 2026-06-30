import SwiftUI
import AppKit

/// SwiftUI wrapper for the AppKit canvas view.
struct CanvasView: NSViewRepresentable {

    @Binding var project: CollageProject?

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.project = project
    }
}
