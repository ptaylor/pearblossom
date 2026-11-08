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

    /// Where and how a node's photo is drawn: the layer centre and box in canvas points, and its
    /// total rotation in radians **clockwise on screen** (Picasa's convention; Pearblossom's
    /// renderer turns the other way, so the importer stores the negation).
    struct LayerPlacement: Equatable {
        var center: CGPoint
        var size: CGSize
        var clockwiseRotation: Double
    }

    /// Places a node, accounting for a `Picasa.ini` rotation of the source photo.
    ///
    /// Picasa lays out the *rotated* photo: the node's `w × h` box holds it after
    /// `quarterTurns` clockwise quarter turns. Pearblossom draws the photo as stored, so the
    /// layer instead gets the box with its sides swapped (for an odd number of turns) and the
    /// quarter turns added to `theta`. Rotating about the same centre, that covers exactly the
    /// footprint Picasa draws, with the content the right way up.
    static func layerPlacement(for node: CXFNode, canvasSize: CGSize, theme: String,
                               quarterTurns: Int = 0) -> LayerPlacement {
        let box = boxSize(for: node, canvasSize: canvasSize)
        let turns = ((quarterTurns % 4) + 4) % 4
        return LayerPlacement(
            center: layerCenter(for: node, canvasSize: canvasSize, theme: theme),
            size: turns % 2 == 1 ? CGSize(width: box.height, height: box.width) : box,
            clockwiseRotation: node.theta + Double(turns) * .pi / 2
        )
    }

    /// The Picasa.ini quarter turns that were in effect when Picasa laid this node out.
    ///
    /// `Picasa.ini` records a photo's *current* edits, which can postdate the collage: Picasa
    /// does not re-lay-out a saved collage when a photo is rotated later. The node's box
    /// records the photo's shape at layout time, so an odd number of turns is applied only
    /// when the box matches the rotated photo better than the photo as stored. (`sam-train-2`'s
    /// scans carry `rotate(3)` but have portrait boxes like the raw scans; `iona-office`'s carry
    /// `rotate(1)` and have portrait boxes for landscape photos.) A crop may postdate the
    /// collage too, so every combination — no edits, rotation only, crop only, both — is
    /// compared with the box and the closest wins; ties go to applying the edits. Picasa's boxes
    /// match the laid-out photo's aspect to about 0.01%, so even `scan1`'s near-coincidence
    /// (raw scan 0.7270, rotated crop 0.7068, box 0.7271) separates cleanly. Even turns leave
    /// the shape unchanged and cannot be tested, so they are trusted.
    ///
    /// - Parameter photoSize: the photo's EXIF-oriented pixel size, before Picasa.ini edits.
    static func quarterTurnsInEffect(for node: CXFNode, canvasSize: CGSize, photoSize: CGSize,
                                     edits: PicasaEdits) -> Int {
        let turns = edits.quarterTurns
        let box = boxSize(for: node, canvasSize: canvasSize)
        guard turns % 2 == 1, photoSize.width > 0, photoSize.height > 0,
              box.width > 0, box.height > 0 else { return turns }

        let stored = Double(photoSize.width / photoSize.height)
        let cropFactor = edits.crop.map { $0.height > 0 ? Double($0.width / $0.height) : 1 }
        let boxAspect = Double(box.width / box.height)
        func mismatch(_ aspect: Double) -> Double { abs(log(boxAspect / aspect)) }

        // (aspect, rotation in effect), most-edited first so that ties apply the edits.
        var candidates: [(aspect: Double, rotated: Bool)] = []
        if let cropFactor { candidates.append((1 / (stored * cropFactor), true)) }
        candidates.append((1 / stored, true))
        if let cropFactor { candidates.append((stored * cropFactor, false)) }
        candidates.append((stored, false))

        let best = candidates.min { mismatch($0.aspect) < mismatch($1.aspect) }!
        return best.rotated ? turns : 0
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
