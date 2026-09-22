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
}
