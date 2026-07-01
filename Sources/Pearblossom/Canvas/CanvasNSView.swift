import AppKit
import CoreImage

/// The AppKit NSView that renders the collage canvas.
final class CanvasNSView: NSView {

    // MARK: - Properties

    /// The CIContext used for rendering — Metal-backed on macOS 14+.
    private let ciContext = CIContext()

    /// The current project, set from SwiftUI.
    var project: CollageProject? {
        didSet { needsDisplay = true }
    }

    /// The resolved background color from the project, or white.
    private var currentBackground: CGColor {
        project?.backgroundColor.cgColor ?? .white
    }

    // MARK: - Lifecycle

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill with project's background color
        context.setFillColor(currentBackground)
        context.fill(bounds)

        // Draw bounding box
        if let proj = project {
            drawBoundingBox(proj.effectiveBoundingBox(), on: currentBackground, in: context)
        }

        // Draw placeholder text if no layers
        if project?.layers.isEmpty ?? true {
            drawPlaceholder(in: context)
        }
    }

    private func drawBoundingBox(_ rect: CGRect, on background: CGColor, in context: CGContext) {
        // Choose a contrasting dash color
        let bgBrightness = (background.components?[0] ?? 1) + (background.components?[1] ?? 1) + (background.components?[2] ?? 1)
        let dashColor: CGColor = bgBrightness > 1.5 ? NSColor.black.withAlphaComponent(0.5).cgColor : NSColor.white.withAlphaComponent(0.5).cgColor

        context.setStrokeColor(dashColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [8, 4])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
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
