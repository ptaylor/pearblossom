import CoreGraphics
import Foundation

/// Picasa's non-destructive edits for one photo, as stored in the `Picasa.ini` beside it.
struct PicasaEdits: Equatable {
    /// `rotate=rotate(n)`: quarter turns clockwise, applied on top of any EXIF orientation.
    var quarterTurns = 0
    /// `crop=rect64(…)`: the kept region as fractions of the displayed image (top-left origin).
    /// Parsed for diagnostics only — the importer does not apply crops yet.
    var crop: CGRect?
}

/// Reads the `Picasa.ini` (or older `.picasa.ini`) that Picasa keeps in each photo folder.
///
/// Each photo with edits has a `[filename.jpg]` section. Picasa lays a collage out using the
/// *edited* photo, so a node's `w`/`h` describe the photo after these edits are applied.
enum PicasaINI {

    private static let fileNames = ["Picasa.ini", ".picasa.ini"]

    /// The edits Picasa recorded for the photo at `path`; empty when there are none.
    static func edits(forPhotoAt path: String) -> PicasaEdits {
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent()
        guard let text = fileNames.lazy
            .compactMap({ try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) })
            .first else { return PicasaEdits() }
        return parse(text)[url.lastPathComponent.lowercased()] ?? PicasaEdits()
    }

    /// Parses an ini file into edits keyed by lowercased file name.
    static func parse(_ text: String) -> [String: PicasaEdits] {
        var sections = [String: PicasaEdits]()
        var current: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            guard let section = current, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].lowercased()
            let value = String(line[line.index(after: equals)...])
            var edits = sections[section] ?? PicasaEdits()
            switch key {
            case "rotate":
                // "rotate(n)"
                if let n = Int(argument(of: value) ?? "") { edits.quarterTurns = ((n % 4) + 4) % 4 }
            case "crop":
                if let hex = argument(of: value) { edits.crop = rect64(hex) }
            default:
                break
            }
            sections[section] = edits
        }
        return sections
    }

    /// Decodes `rect64`: a 64-bit hex value (leading zeros dropped) packing four 16-bit
    /// fractions of 65535 — left, top, right, bottom.
    static func rect64(_ hex: String) -> CGRect? {
        guard let packed = UInt64(hex, radix: 16) else { return nil }
        let fraction = { (shift: UInt64) in CGFloat((packed >> shift) & 0xFFFF) / 65535 }
        let (left, top, right, bottom) = (fraction(48), fraction(32), fraction(16), fraction(0))
        guard right > left, bottom > top else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The text between the first `(` and the following `)`, e.g. `rotate(1)` → `1`.
    private static func argument(of value: String) -> String? {
        guard let open = value.firstIndex(of: "("),
              let close = value[open...].firstIndex(of: ")") else { return nil }
        return String(value[value.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
    }
}
