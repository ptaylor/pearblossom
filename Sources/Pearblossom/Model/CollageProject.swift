import Foundation
import CoreGraphics

/// A collage project — persisted as a .collage.json file.
struct CollageProject: Codable, Identifiable {
    var id: UUID = UUID()
    var version: Int = 1
    var name: String
    var description: String = ""
    var filePath: String?
    var canvasWidth: CGFloat = 2000
    var canvasHeight: CGFloat = 1500
    var backgroundColor: CodableColor = .white
    var layers: [PhotoLayer] = []
    var boundingBoxMode: BoundingBoxMode = .definedBorder
    var borderMargin: CGFloat = 40
    var manualBoundingBox: CGRect? = nil
    var showBoundingBox: Bool = true
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, version, name, description, filePath, canvasWidth, canvasHeight
        case backgroundColor, layers, boundingBoxMode, borderMargin, manualBoundingBox
        case showBoundingBox, createdAt, modifiedAt
    }

    /// Computes the effective bounding box based on mode and layer positions.
    func effectiveBoundingBox() -> CGRect {
        let canvasRect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        switch boundingBoxMode {
        case .manual:
            return manualBoundingBox ?? canvasRect
        case .definedBorder:
            guard !layers.isEmpty else { return canvasRect }
            let unionRect = layers.reduce(into: CGRect?.none) { result, layer in
                let layerRect = CGRect(
                    x: layer.position.x - layer.size.width / 2,
                    y: layer.position.y - layer.size.height / 2,
                    width: layer.size.width,
                    height: layer.size.height
                )
                result = result?.union(layerRect) ?? layerRect
            } ?? canvasRect
            return unionRect.insetBy(dx: -borderMargin, dy: -borderMargin)
        }
    }

    init(id: UUID = UUID(),
         version: Int = 1,
         name: String,
         description: String = "",
         filePath: String? = nil,
         canvasWidth: CGFloat = 2000,
         canvasHeight: CGFloat = 1500,
         backgroundColor: CodableColor = .white,
         layers: [PhotoLayer] = [],
         boundingBoxMode: BoundingBoxMode = .definedBorder,
         borderMargin: CGFloat = 40,
         manualBoundingBox: CGRect? = nil,
         showBoundingBox: Bool = true,
         createdAt: Date = Date(),
         modifiedAt: Date = Date()) {
        self.id = id
        self.version = version
        self.name = name
        self.description = description
        self.filePath = filePath
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.backgroundColor = backgroundColor
        self.layers = layers
        self.boundingBoxMode = boundingBoxMode
        self.borderMargin = borderMargin
        self.manualBoundingBox = manualBoundingBox
        self.showBoundingBox = showBoundingBox
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        // Handle missing name from older .collage.json files — derive from filePath
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? URL(fileURLWithPath: (try? container.decodeIfPresent(String.self, forKey: .filePath)) ?? "Untitled").deletingPathExtension().lastPathComponent
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        canvasWidth = try container.decodeIfPresent(CGFloat.self, forKey: .canvasWidth) ?? 2000
        canvasHeight = try container.decodeIfPresent(CGFloat.self, forKey: .canvasHeight) ?? 1500
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) ?? .white
        layers = try container.decodeIfPresent([PhotoLayer].self, forKey: .layers) ?? []
        boundingBoxMode = try container.decodeIfPresent(BoundingBoxMode.self, forKey: .boundingBoxMode) ?? .definedBorder
        borderMargin = try container.decodeIfPresent(CGFloat.self, forKey: .borderMargin) ?? 40
        manualBoundingBox = try container.decodeIfPresent(CGRect.self, forKey: .manualBoundingBox)
        showBoundingBox = try container.decodeIfPresent(Bool.self, forKey: .showBoundingBox) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

/// A single photo placed on the canvas.
struct PhotoLayer: Codable, Identifiable {
    var id: UUID = UUID()
    var photoPath: String
    var position: CGPoint = .zero
    var size: CGSize = CGSize(width: 400, height: 300)
    var rotation: CGFloat = 0
    var zOrder: Int = 0
    var opacity: Double = 1.0
    var sourceResolution: CGSize = .zero
    var cropRect: CGRect? = nil
    var featherRadius: CGFloat? = nil
    var blendMode: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, photoPath, position, size, rotation, zOrder, opacity
        case sourceResolution, cropRect, featherRadius, blendMode
    }

    /// Resolves the photo path to an absolute path. Relative paths are resolved
    /// against the Pearblossom root directory.
    func resolvedPhotoPath() -> String {
        if photoPath.hasPrefix("/") { return photoPath }
        let root = AppSettings.shared.collectionsRoot.path
        return (root as NSString).appendingPathComponent(photoPath)
    }
}

/// A Codable wrapper for CGColor, used for the canvas background.
struct CodableColor: Codable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(cgColor: CGColor) {
        let comps = cgColor.components ?? [0, 0, 0, 1]
        self.red = comps.count >= 1 ? comps[0] : 0
        self.green = comps.count >= 2 ? comps[1] : 0
        self.blue = comps.count >= 3 ? comps[2] : 0
        self.alpha = comps.count >= 4 ? comps[3] : 1
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Greyscale presets for the background picker: 0%, 5%, 10%, 20%, 40%, 60%, 80%, 100%
    static let grayscalePresets: [CodableColor] = [
        .black,                                                     // 0%
        CodableColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1), // 5%
        CodableColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1), // 10%
        CodableColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1), // 20%
        CodableColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1), // 40%
        CodableColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1), // 60%
        CodableColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1), // 80%
        .white,                                                     // 100%
    ]
}

/// Bounding box mode for the collage canvas.
enum BoundingBoxMode: String, Codable, CaseIterable {
    case definedBorder = "definedBorder"
    case manual = "manual"
}
