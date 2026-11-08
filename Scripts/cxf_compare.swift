// Compares Pearblossom's Picasa `.cxf` placement against Picasa's own exported JPEG.
//
// Composites the real source photos using the CXF geometry, once per candidate placement rule,
// and reports the mean pixel error against the Picasa export (0–255, lower is better). It
// compiles in the app's own parser and geometry (`Sources/Pearblossom/Import/…`), so the
// `production` rule is exactly what the importer does — not a copy that could drift.
//
// Build and run via `Scripts/cxf_compare.sh` (see that file for usage).

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Placement rules

/// A candidate mapping from a CXF node to the layer Pearblossom draws.
///
/// `production` is the importer's own `CXFCanvasGeometry.layerPlacement`: it is handed the
/// photo as stored plus its Picasa.ini quarter turns, exactly like the importer. The other
/// rules are placement hypotheses about Picasa, so they are handed the photo already turned
/// the way Picasa shows it and only decide where its centre goes.
struct PlacementRule {
    typealias Placement = CXFCanvasGeometry.LayerPlacement
    let name: String
    let summary: String
    let handlesPicasaRotation: Bool
    let place: (_ node: CXFNode, _ canvas: CGSize, _ theme: String, _ quarterTurns: Int) -> Placement
}

/// Anchor `(x·W, y·H)` plus the offset `(a, b)` rotated clockwise (screen space) by theta.
private func anchoredCenter(_ node: CXFNode, _ canvas: CGSize, a: Double, b: Double) -> CGPoint {
    let c = cos(node.theta), s = sin(node.theta)
    return CGPoint(x: node.x * Double(canvas.width) + a * c - b * s,
                   y: node.y * Double(canvas.height) + a * s + b * c)
}

/// A hypothesis rule: the node's own box and theta, with `offset` choosing (a, b).
private func hypothesis(_ name: String, _ summary: String, offset: @escaping (CGSize) -> (Double, Double)) -> PlacementRule {
    PlacementRule(name: name, summary: summary, handlesPicasaRotation: false) { node, canvas, _, _ in
        let box = CXFCanvasGeometry.boxSize(for: node, canvasSize: canvas)
        let (a, b) = offset(box)
        return .init(center: anchoredCenter(node, canvas, a: a, b: b), size: box, clockwiseRotation: node.theta)
    }
}

let allRules: [PlacementRule] = [
    PlacementRule(name: "production", summary: "CXFCanvasGeometry.layerPlacement (what the importer does)",
                  handlesPicasaRotation: true) {
        CXFCanvasGeometry.layerPlacement(for: $0, canvasSize: $1, theme: $2, quarterTurns: $3)
    },
    hypothesis("halfW", "anchor + R(θ)·(w/2, w/2)") { (Double($0.width) / 2, Double($0.width) / 2) },
    hypothesis("longEdge", "anchor + R(θ)·(L/2, L/2), L = max(w, h)") {
        (Double(max($0.width, $0.height)) / 2, Double(max($0.width, $0.height)) / 2)
    },
    hypothesis("boxCentre", "anchor + R(θ)·(w/2, h/2), plain rotation about the top-left") {
        (Double($0.width) / 2, Double($0.height) / 2)
    },
]

// MARK: - Images

/// An 8-bit RGBA raster with a top-left origin.
struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func raster(of context: CGContext) -> Raster {
    let count = context.bytesPerRow * context.height
    let data = context.data!.bindMemory(to: UInt8.self, capacity: count)
    return Raster(width: context.width, height: context.height, pixels: Array(UnsafeBufferPointer(start: data, count: count)))
}

/// Loads an image downsampled to `maxPixel`, with its EXIF orientation applied (as Picasa shows it).
func loadImage(_ path: String, maxPixel: Int) -> (image: CGImage, orientation: Int)? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = (properties?[kCGImagePropertyOrientation] as? Int) ?? 1
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return (image, orientation)
}

// MARK: - Picasa.ini edits

/// Set by `--picasa-crop`: draw sources with their Picasa.ini crop, which the importer does
/// not apply yet. Rotation is always applied, because the importer applies it.
var applyPicasaCrop = false

/// Picasa's crop, in displayed (EXIF-oriented) terms with a top-left origin.
func cropped(_ image: CGImage, to crop: CGRect?) -> CGImage {
    guard let crop else { return image }
    let rect = CGRect(x: crop.minX * CGFloat(image.width), y: crop.minY * CGFloat(image.height),
                      width: crop.width * CGFloat(image.width), height: crop.height * CGFloat(image.height)).integral
    return image.cropping(to: rect) ?? image  // CGImage cropping uses a top-left origin
}

/// The image turned `quarterTurns` clockwise, as Picasa shows a `rotate(n)` photo.
func quarterTurned(_ image: CGImage, _ quarterTurns: Int) -> CGImage {
    guard quarterTurns % 4 != 0 else { return image }
    let swap = quarterTurns % 2 == 1
    let w = swap ? image.height : image.width, h = swap ? image.width : image.height
    let context = makeContext(width: w, height: h)
    // y-up CG space: a negative angle turns clockwise on screen.
    context.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
    context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
    context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
    return context.makeImage() ?? image
}

/// Draws `image` into a context of the given size, stretched to fill it.
func resampled(_ image: CGImage, width: Int, height: Int) -> Raster {
    let context = makeContext(width: width, height: height)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return raster(of: context)
}

func writePNG(_ raster: Raster, to url: URL) {
    var pixels = raster.pixels
    let image = pixels.withUnsafeMutableBytes { buffer -> CGImage in
        let context = CGContext(data: buffer.baseAddress, width: raster.width, height: raster.height,
                                bitsPerComponent: 8, bytesPerRow: raster.width * 4, space: sRGB,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// Places two rasters side by side (reference left, ours right) with a grey divider.
func sideBySide(_ left: Raster, _ right: Raster) -> Raster {
    let gap = 8
    let width = left.width + gap + right.width
    let height = max(left.height, right.height)
    var pixels = [UInt8](repeating: 128, count: width * height * 4)
    for (raster, x0) in [(left, 0), (right, left.width + gap)] {
        for y in 0..<raster.height {
            let src = y * raster.width * 4
            let dst = (y * width + x0) * 4
            pixels.replaceSubrange(dst..<(dst + raster.width * 4), with: raster.pixels[src..<(src + raster.width * 4)])
        }
    }
    return Raster(width: width, height: height, pixels: pixels)
}

// MARK: - Compositing

struct Layer {
    let image: CGImage
    let box: CGSize      // canvas points
    let theta: Double
    var center: CGPoint  // canvas points
}

/// Composites the layers bottom-to-top over the background at `scale` pixels per canvas point.
/// Mirrors the app's renderer: each photo is stretched to its box, rotated clockwise by theta
/// about the box centre.
func composite(_ layers: [Layer], width: Int, height: Int, scale: Double, background: CGColor) -> Raster {
    let context = makeContext(width: width, height: height)
    context.interpolationQuality = .high
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // y-down canvas space: here a positive rotate(by:) turns clockwise on screen, as Picasa does.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    for layer in layers {
        context.saveGState()
        context.translateBy(x: layer.center.x * scale, y: layer.center.y * scale)
        context.rotate(by: layer.theta)
        context.scaleBy(x: 1, y: -1)  // draw the image upright in the y-down frame
        let w = layer.box.width * scale, h = layer.box.height * scale
        context.draw(layer.image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        context.restoreGState()
    }
    return raster(of: context)
}

/// Mean absolute channel error (0–255): over the whole image, and over "content" — pixels
/// where either image differs visibly from the background — so empty canvas doesn't dilute it.
func error(_ a: Raster, _ b: Raster, background: (Int, Int, Int)) -> (all: Double, content: Double) {
    var total = 0, contentTotal = 0, contentCount = 0
    let count = a.width * a.height
    a.pixels.withUnsafeBufferPointer { pa in
        b.pixels.withUnsafeBufferPointer { pb in
            for i in 0..<count {
                let o = i * 4
                let dr = abs(Int(pa[o]) - Int(pb[o]))
                let dg = abs(Int(pa[o + 1]) - Int(pb[o + 1]))
                let db = abs(Int(pa[o + 2]) - Int(pb[o + 2]))
                let d = dr + dg + db
                total += d
                let fa = abs(Int(pa[o]) - background.0) + abs(Int(pa[o + 1]) - background.1) + abs(Int(pa[o + 2]) - background.2)
                let fb = abs(Int(pb[o]) - background.0) + abs(Int(pb[o + 1]) - background.1) + abs(Int(pb[o + 2]) - background.2)
                if fa > 40 || fb > 40 {
                    contentTotal += d
                    contentCount += 1
                }
            }
        }
    }
    return (Double(total) / Double(count * 3), contentCount > 0 ? Double(contentTotal) / Double(contentCount * 3) : 0)
}

// MARK: - Per-node fit

/// For each node (top layer first), searches the centre offset that best matches the reference
/// while the other nodes stay where `layers` puts them. Returns offsets in canvas points.
func fitResiduals(_ layers: [Layer], reference: Raster, width: Int, height: Int, scale: Double,
                  background: CGColor, bg: (Int, Int, Int)) -> [CGPoint] {
    var working = layers
    var residuals = [CGPoint](repeating: .zero, count: layers.count)
    func cost(_ candidate: [Layer]) -> Double {
        error(composite(candidate, width: width, height: height, scale: scale, background: background), reference, background: bg).all
    }
    for index in layers.indices.reversed() {
        let start = layers[index].center
        var best = (dx: 0.0, dy: 0.0, cost: cost(working))
        for (radius, step) in [(16.0, 4.0), (3.0, 1.0)] {
            let base = best
            var dy = -radius
            while dy <= radius {
                var dx = -radius
                while dx <= radius {
                    var candidate = working
                    let px = base.dx + dx, py = base.dy + dy
                    candidate[index].center = CGPoint(x: start.x + px / scale, y: start.y + py / scale)
                    let c = cost(candidate)
                    if c < best.cost { best = (px, py, c) }
                    dx += step
                }
                dy += step
            }
        }
        working[index].center = CGPoint(x: start.x + best.dx / scale, y: start.y + best.dy / scale)
        residuals[index] = CGPoint(x: best.dx / scale, y: best.dy / scale)
    }
    return residuals
}

// MARK: - Main

@main
struct CXFCompare {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var compareWidth = 800
        var outDir: URL?
        var fit = false
        var ruleNames = allRules.map(\.name)
        var pairs: [(cxf: String, reference: String)] = []

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--width": compareWidth = Int(arguments.removeFirst()) ?? compareWidth
            case "--out": outDir = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
            case "--fit": fit = true
            case "--picasa-crop": applyPicasaCrop = true
            case "--rules": ruleNames = arguments.removeFirst().split(separator: ",").map(String.init)
            default:
                guard !arguments.isEmpty else {
                    FileHandle.standardError.write("missing reference image for \(argument)\n".data(using: .utf8)!)
                    exit(2)
                }
                pairs.append((argument, arguments.removeFirst()))
            }
        }
        let rules = ruleNames.compactMap { name in allRules.first { $0.name == name } }
        guard !pairs.isEmpty, !rules.isEmpty else {
            print("usage: cxf_compare [--width N] [--out DIR] [--fit] [--picasa-crop] [--rules a,b] <file.cxf> <picasa-export.jpg> ...")
            print("rules: " + allRules.map { "\($0.name) — \($0.summary)" }.joined(separator: "\n       "))
            exit(2)
        }
        if let outDir { try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }

        print("content error (0–255, lower is better); [all-pixel error in brackets]")
        print(["file", "theme", "nodes", "rot°"].map { $0.padding(toLength: 10, withPad: " ", startingAt: 0) }.joined()
              + rules.map { $0.name.padding(toLength: 18, withPad: " ", startingAt: 0) }.joined())

        var totals = [String: Double]()
        var scored = 0
        for pair in pairs {
            if run(pair, rules: rules, compareWidth: compareWidth, outDir: outDir, fit: fit, totals: &totals) { scored += 1 }
        }
        if scored > 1 {
            print("mean of \(scored)".padding(toLength: 40, withPad: " ", startingAt: 0)
                  + rules.map { String(format: "%-18.2f", (totals[$0.name] ?? 0) / Double(scored)) }.joined())
        }
    }

    /// Scores one collage; returns false when it was skipped.
    @discardableResult
    static func run(_ pair: (cxf: String, reference: String), rules: [PlacementRule], compareWidth: Int,
                    outDir: URL?, fit: Bool, totals: inout [String: Double]) -> Bool {
        let name = URL(fileURLWithPath: pair.cxf).deletingPathExtension().lastPathComponent
        func note(_ message: String) -> Bool { print("  \(name): \(message)"); return false }

        guard let data = FileManager.default.contents(atPath: pair.cxf) else { return note("cannot read cxf") }
        let collage: CXFCollage
        do { collage = try CXFParser.parse(data) } catch { return note("\(error.localizedDescription)") }
        guard collage.theme == "picturepile" else { return note("skipped: theme \(collage.theme)") }
        guard let reference = loadImage(pair.reference, maxPixel: 4096)?.image else { return note("cannot read reference") }

        let canvas = CXFCanvasGeometry.dimensions(format: collage.format, orientation: collage.orientation)
        let refAspect = Double(reference.width) / Double(reference.height)
        let canvasAspect = Double(canvas.width / canvas.height)
        if abs(refAspect / canvasAspect - 1) > 0.01 {
            _ = note(String(format: "WARNING reference aspect %.3f ≠ canvas aspect %.3f", refAspect, canvasAspect))
        }

        let width = compareWidth
        let height = Int((Double(width) / canvasAspect).rounded())
        let scale = Double(width) / Double(canvas.width)
        let referenceRaster = resampled(reference, width: width, height: height)

        let argb = UInt32(collage.background?.color ?? "FFFFFFFF", radix: 16) ?? 0xFFFF_FFFF
        let bg = (Int((argb >> 16) & 0xFF), Int((argb >> 8) & 0xFF), Int(argb & 0xFF))
        let background = CGColor(srgbRed: CGFloat(bg.0) / 255, green: CGFloat(bg.1) / 255, blue: CGFloat(bg.2) / 255, alpha: 1)

        // Load each source once; record nodes that cannot be drawn.
        struct Source { let stored: CGImage; let edits: PicasaEdits; let photoSize: CGSize }
        struct Usable { let node: CXFNode; let stored: CGImage; let asPicasaShows: CGImage; let quarterTurns: Int }
        var sources = [String: Source]()
        var turnedCache = [String: CGImage]()
        var usable: [Usable] = []
        for node in collage.nodes {
            guard let raw = node.src, let path = WinePathTranslator.translate(raw) else { continue }
            if sources[path] == nil {
                guard let loaded = loadImage(path, maxPixel: 1024) else { _ = note("missing source \(path)"); continue }
                let edits = PicasaINI.edits(forPhotoAt: path)
                if edits.quarterTurns != 0 || edits.crop != nil {
                    _ = note("Picasa.ini rotate \(edits.quarterTurns)×90°"
                             + (edits.crop.map { String(format: ", crop %.3f,%.3f %.3f×%.3f (%@)", $0.minX, $0.minY,
                                                        $0.width, $0.height, applyPicasaCrop ? "applied" : "ignored") } ?? "")
                             + " — \(URL(fileURLWithPath: path).lastPathComponent)")
                }
                let stored = applyPicasaCrop ? cropped(loaded.image, to: edits.crop) : loaded.image
                sources[path] = Source(stored: stored, edits: edits,
                                       photoSize: ImageDimensions.orientedPixelSize(at: path) ?? .zero)
            }
            let source = sources[path]!
            // The importer's own decision about whether the edit predates the collage.
            let turns = CXFCanvasGeometry.quarterTurnsInEffect(for: node, canvasSize: canvas,
                                                               photoSize: source.photoSize, edits: source.edits)
            if turns != source.edits.quarterTurns {
                _ = note("Picasa.ini rotate \(source.edits.quarterTurns)×90° postdates the collage, not applied — "
                         + URL(fileURLWithPath: path).lastPathComponent)
            }
            let key = "\(path)#\(turns)"
            if turnedCache[key] == nil { turnedCache[key] = quarterTurned(source.stored, turns) }
            usable.append(Usable(node: node, stored: source.stored, asPicasaShows: turnedCache[key]!, quarterTurns: turns))
        }

        let rotations = Set(usable.map { Int(($0.node.theta * 180 / .pi).rounded()) % 360 }).sorted()
        var row = [name, collage.theme, "\(usable.count)/\(collage.nodes.count)",
                   rotations.map(String.init).joined(separator: ",")]
            .map { String($0.prefix(9)).padding(toLength: 10, withPad: " ", startingAt: 0) }.joined()

        var best: (rule: String, error: Double, raster: Raster)?
        for rule in rules {
            let layers = usable.map { item -> Layer in
                let placement = rule.place(item.node, canvas, collage.theme, item.quarterTurns)
                return Layer(image: rule.handlesPicasaRotation ? item.stored : item.asPicasaShows,
                             box: placement.size, theta: placement.clockwiseRotation, center: placement.center)
            }
            let rendered = composite(layers, width: width, height: height, scale: scale, background: background)
            let e = error(rendered, referenceRaster, background: bg)
            totals[rule.name, default: 0] += e.content
            row += String(format: "%6.2f [%5.2f]     ", e.content, e.all)
            if rule.name == "production" || (best == nil || e.content < best!.error) && !rules.contains(where: { $0.name == "production" }) {
                best = (rule.name, e.content, rendered)
            }
            if fit && rule.name == "production" {
                let residuals = fitResiduals(layers, reference: referenceRaster, width: width, height: height,
                                             scale: scale, background: background, bg: bg)
                for (index, r) in residuals.enumerated() {
                    let n = usable[index].node
                    let box = layers[index].box
                    print(String(format: "    fit %@ node %2d θ=%6.1f° box %4.0f×%-4.0f residual dx=%6.1f dy=%6.1f  (%@)",
                                 name, index, n.theta * 180 / .pi, box.width, box.height, r.x, r.y,
                                 URL(fileURLWithPath: n.src ?? "").lastPathComponent))
                }
            }
        }
        print(row)

        if let outDir, let best {
            writePNG(sideBySide(referenceRaster, best.raster),
                     to: outDir.appendingPathComponent("\(name)-picasa-vs-\(best.rule).png"))
        }
        return true
    }
}
