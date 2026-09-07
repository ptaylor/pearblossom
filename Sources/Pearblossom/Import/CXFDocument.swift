import Foundation

/// A parsed Picasa collage file (`.cxf`), restricted to the two supported themes.
struct CXFCollage {
    var version: String?
    var format: String?      // e.g. "8:5" or "297:210"
    var orientation: String? // "landscape" | "portrait"
    var theme: String = ""
    var shadows: Bool = false
    var captions: Bool = false
    var albumUID: String?
    var background: CXFBackground?
    var nodes: [CXFNode] = []
}

/// The `<background>` element. Only solid backgrounds are understood.
struct CXFBackground {
    var type: String = "solid"
    var color: String?       // AARRGGBB hex
}

/// A single `<node>` element — one photo layer in the collage.
struct CXFNode {
    var x: Double = 0        // normalized center X [0,1]
    var y: Double = 0        // normalized center Y [0,1]
    var w: Double = 0        // normalized width  [0,1]
    var h: Double = 0        // normalized height [0,1]
    var theta: Double = 0    // rotation in radians
    var scale: Double = 1    // parsed but unused by Pearblossom
    var alpha: Double?       // per-node opacity [0,1], nil → renderer default
    var theme: String?       // e.g. "noborder", "whiteframe"
    var src: String?         // Wine/Windows source path
    var uid: String?
}

/// Streaming `XMLParser` delegate for `.cxf` files.
final class CXFParser: NSObject, XMLParserDelegate {

    private(set) var collage = CXFCollage()
    private var currentNode: CXFNode?
    private var currentText = ""

    // MARK: - Public API

    /// Parses a `.cxf` file and validates that its theme is importable.
    static func parse(_ data: Data) throws -> CXFCollage {
        let parser = XMLParser(data: data)
        let delegate = CXFParser()
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "unknown parse error"
            throw CXFError.invalidXML(message)
        }

        let theme = delegate.collage.theme
        guard theme == "multiexp" || theme == "picturepile" else {
            throw CXFError.unsupportedTheme(theme)
        }

        return delegate.collage
    }

    /// Lightweight read of just the root `theme` attribute (for UI previews).
    static func peekTheme(from data: Data) -> String? {
        let parser = XMLParser(data: data)
        let delegate = CXFParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.collage.theme.isEmpty ? nil : delegate.collage.theme
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "collage":
            collage.version = attributeDict["version"]
            collage.format = attributeDict["format"]
            collage.orientation = attributeDict["orientation"]
            collage.theme = attributeDict["theme"] ?? ""
            collage.shadows = attributeDict["shadows"] == "1"
            collage.captions = attributeDict["captions"] == "1"
            collage.albumUID = attributeDict["albumUID"]

        case "background":
            var background = CXFBackground()
            background.type = attributeDict["type"] ?? "solid"
            background.color = attributeDict["color"]
            collage.background = background

        case "node":
            var node = CXFNode()
            node.x = Double(attributeDict["x"] ?? "") ?? 0
            node.y = Double(attributeDict["y"] ?? "") ?? 0
            node.w = Double(attributeDict["w"] ?? "") ?? 0
            node.h = Double(attributeDict["h"] ?? "") ?? 0
            node.theta = Double(attributeDict["theta"] ?? "") ?? 0
            node.scale = Double(attributeDict["scale"] ?? "") ?? 1
            if let alphaString = attributeDict["alpha"], let alpha = Double(alphaString) {
                node.alpha = alpha
            }
            currentNode = node

        default:
            break
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "node":
            if let node = currentNode {
                collage.nodes.append(node)
            }
            currentNode = nil

        case "theme":
            currentNode?.theme = trimmed.isEmpty ? nil : trimmed

        case "src":
            currentNode?.src = trimmed.isEmpty ? nil : trimmed

        case "uid":
            currentNode?.uid = trimmed.isEmpty ? nil : trimmed

        default:
            break
        }
        currentText = ""
    }
}
