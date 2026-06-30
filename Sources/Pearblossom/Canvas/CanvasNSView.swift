import AppKit
import CoreImage

/// The AppKit NSView that renders the collage canvas.
final class CanvasNSView: NSView {

    // MARK: - Properties

    /// The CIContext used for rendering — Metal-backed on macOS 14+.
    private let ciContext = CIContext()

    /// Background color for the canvas.
    var canvasBackgroundColor: CGColor = .white

    /// The current project, set from SwiftUI.
    var project: CollageProject? {
        didSet { needsDisplay = true }
    }

    // MARK: - Lifecycle

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill with canvas background
        context.setFillColor(canvasBackgroundColor)
        context.fill(bounds)

        // Draw placeholder text if no project is loaded
        if project?.layers.isEmpty ?? true {
            drawPlaceholder(in: context)
        }
    }

    private func drawPlaceholder(in context: CGContext) {
        let text = "Canvas"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .light),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }

    // MARK: - Layout

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        // Update layer frame
        layer?.frame = bounds
    }
}
