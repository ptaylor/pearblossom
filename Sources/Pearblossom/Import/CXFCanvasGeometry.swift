import CoreGraphics
import Foundation

/// Derives a collage canvas size (in points) from the root `<collage>` element of a `.cxf` file.
///
/// Picasa writes `format` with the **long edge first**, for both orientations — a portrait
/// A4 collage is written `format="297:210" orientation="portrait"`. `orientation` is therefore
/// the authority for which axis carries the long edge; the numeric ordering of `format` must
/// not be used to infer the canvas shape.
///
/// Verified against `house.cxf` (`format="297:210" orientation="portrait"`): the portrait canvas
/// makes the stored node boxes exact 3:2 ratios, matching the referenced photos' real pixel
/// dimensions (4272×2848). A landscape canvas stretches every layer horizontally by
/// (297/210)² ≈ 2×, because `CanvasNSView` scales each photo non-uniformly to fill its box.
enum CXFCanvasGeometry {

    /// Point length assigned to the canvas's long edge.
    static let longEdge: CGFloat = 2000

    /// Ratio used when `format` is missing or malformed. Matches the app's default 4:3 canvas.
    private static let fallbackRatio: (width: Double, height: Double) = (4, 3)

    /// Returns the canvas dimensions in points for a CXF `format` (e.g. `"297:210"`) and
    /// `orientation` (`"portrait"` / `"landscape"`).
    ///
    /// `format` may be written either long-edge-first or short-edge-first; only the ratio
    /// between the two numbers is used. When `orientation` is absent or unrecognised, the
    /// ratio's own ordering decides the shape.
    static func dimensions(format: String?, orientation: String?) -> CGSize {
        let parts = (format ?? "").split(separator: ":").compactMap { Double($0) }
        let ratio: (width: Double, height: Double)
        if parts.count == 2, parts[0] > 0, parts[1] > 0 {
            ratio = (parts[0], parts[1])
        } else {
            ratio = fallbackRatio
        }

        let longRatio = max(ratio.width, ratio.height)
        let shortRatio = min(ratio.width, ratio.height)
        let shortEdge = (longEdge * CGFloat(shortRatio / longRatio)).rounded()

        let isPortrait: Bool
        switch orientation?.lowercased() {
        case "portrait": isPortrait = true
        case "landscape": isPortrait = false
        default: isPortrait = ratio.width < ratio.height
        }

        return isPortrait
            ? CGSize(width: shortEdge, height: longEdge)
            : CGSize(width: longEdge, height: shortEdge)
    }

    /// The node's unrotated box size in canvas points (`w`, `h` are fractions of the canvas).
    static func boxSize(for node: CXFNode, canvasSize: CGSize) -> CGSize {
        CGSize(width: node.w * Double(canvasSize.width), height: node.h * Double(canvasSize.height))
    }

    /// The canvas-space centre (top-left origin, y down) of a node's layer.
    ///
    /// **picturepile**: Picasa models each photo as a square whose side is the photo's long
    /// edge `L = max(w, h)` (the node's `scale` attribute is that same long edge, in units where
    /// the canvas's long edge is 1024). `(x, y)` is the square's top-left corner before
    /// rotation, and the photo is centred in the square, which is rotated clockwise by `theta`
    /// about that corner:
    ///
    ///     centre = (x·W, y·H) + R(θ)·(L/2, L/2)
    ///     R(θ)·(a, b) = (a·cosθ − b·sinθ,  a·sinθ + b·cosθ)     (y down, so clockwise)
    ///
    /// For a landscape photo `L = w`, which is the "half-width on both axes" rule this replaced;
    /// it only diverged for portrait photos, where it used the short edge. Verified with
    /// `Scripts/cxf_compare.sh` against Picasa's own exports (22 collages; θ = 0, ±small, 30°,
    /// 60°, 90°, 270°): mean content error 17.3 vs 44.5 for the half-width rule, never worse on
    /// any file, and per-photo residuals within the 2.5 pt fit resolution on the train scans.
    ///
    /// **multiexp**: plain rotation of the box about its top-left anchor, `(w/2, h/2)`. Its
    /// nodes are all θ = 0 full-canvas exposures, so this was never the source of a mismatch,
    /// and it has not been measured against Picasa.
    static func layerCenter(for node: CXFNode, canvasSize: CGSize, theme: String) -> CGPoint {
        let size = boxSize(for: node, canvasSize: canvasSize)
        let offset: (a: Double, b: Double)
        if theme == "picturepile" {
            let halfLongEdge = Double(max(size.width, size.height)) / 2
            offset = (halfLongEdge, halfLongEdge)
        } else {
            offset = (Double(size.width) / 2, Double(size.height) / 2)
        }
        let cosTheta = cos(node.theta)
        let sinTheta = sin(node.theta)
        return CGPoint(
            x: node.x * Double(canvasSize.width) + offset.a * cosTheta - offset.b * sinTheta,
            y: node.y * Double(canvasSize.height) + offset.a * sinTheta + offset.b * cosTheta
        )
    }
}
