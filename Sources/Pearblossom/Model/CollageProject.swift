import Foundation
import CoreGraphics
import Combine

/// A collage project — persisted as a .collage.json file.
final class CollageProject: ObservableObject, Codable, Identifiable {
    let id: UUID
    let version: Int
    @Published var name: String
    @Published var description: String = ""
    @Published var filePath: String?
    @Published var canvasWidth: CGFloat = 2000
    @Published var canvasHeight: CGFloat = 1500
    @Published var backgroundColor: CodableColor = .white
    @Published var layers: [PhotoLayer] = []
    @Published var boundingBoxMode: BoundingBoxMode = .definedBorder
    @Published var borderMargin: CGFloat = 40
    @Published var manualBoundingBox: CGRect? = nil
    @Published var showBoundingBox: Bool = true
    let createdAt: Date
    @Published var modifiedAt: Date

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
                // Account for rotation: the axis-aligned bounding box of a rotated rect
                let cosA = abs(cos(layer.rotation))
                let sinA = abs(sin(layer.rotation))
                let boundingW = layer.size.width * cosA + layer.size.height * sinA
                let boundingH = layer.size.width * sinA + layer.size.height * cosA
                let layerRect = CGRect(
                    x: layer.position.x - boundingW / 2,
                    y: layer.position.y - boundingH / 2,
                    width: boundingW,
                    height: boundingH
                )
                result = result?.union(layerRect) ?? layerRect
            } ?? canvasRect
            return unionRect.insetBy(dx: -borderMargin, dy: -borderMargin)
        }
    }

    // MARK: - Layer Reordering

    /// Moves `layerID` relative to `targetID`. Toggle behavior: if the layer is
    /// currently below the target, it is placed just above it; if above, just below.
    /// All z-orders are then renumbered to contiguous integers starting at 0.
    func reorder(layerID: UUID, relativeTo targetID: UUID) {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let targetIndex = layers.firstIndex(where: { $0.id == targetID }),
              layerIndex != targetIndex else { return }

        let layer = layers.remove(at: layerIndex)
        let adjustedTarget = layerIndex < targetIndex ? targetIndex - 1 : targetIndex
        let target = layers[adjustedTarget]

        if layer.zOrder < target.zOrder {
            layers.insert(layer, at: adjustedTarget + 1)
        } else {
            layers.insert(layer, at: adjustedTarget)
        }

        renumberZOrders()
        modifiedAt = Date()
    }

    func bringToFront(layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
        let layer = layers.remove(at: index)
        layers.append(layer)
        renumberZOrders()
        modifiedAt = Date()
    }

    func sendToBack(layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
        let layer = layers.remove(at: index)
        layers.insert(layer, at: 0)
        renumberZOrders()
        modifiedAt = Date()
    }

    func moveUp(layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }),
              index + 1 < layers.count else { return }
        layers.swapAt(index, index + 1)
        renumberZOrders()
        modifiedAt = Date()
    }

    func moveDown(layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }),
              index > 0 else { return }
        layers.swapAt(index, index - 1)
        renumberZOrders()
        modifiedAt = Date()
    }

    private func renumberZOrders() {
        for i in layers.indices {
            layers[i].zOrder = i
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

    required init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(layers, forKey: .layers)
        try container.encode(boundingBoxMode, forKey: .boundingBoxMode)
        try container.encode(borderMargin, forKey: .borderMargin)
        try container.encode(manualBoundingBox, forKey: .manualBoundingBox)
        try container.encode(showBoundingBox, forKey: .showBoundingBox)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }
}

/// Wraps an optional CollageProject so SwiftUI can observe changes to it.
/// When the inner project is replaced or its @Published properties mutate,
/// this wrapper forwards the change notifications so views stay in sync.
final class ProjectState: ObservableObject {
    @Published var project: CollageProject? = nil {
        didSet { subscribe() }
    }

    private var cancellable: AnyCancellable?

    private func subscribe() {
        cancellable = project?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

/// A single photo placed on the canvas.
struct PhotoLayer: Codable, Identifiable {
    var id: UUID = UUID()
    var photoPath: String = ""      // Runtime-only, not persisted
    var collectionID: UUID?
    var photoID: UUID?
    var position: CGPoint = .zero
    var size: CGSize = CGSize(width: 400, height: 300)
    var rotation: CGFloat = 0
    var zOrder: Int = 0
    var opacity: Double = 1.0
    var sourceResolution: CGSize = .zero
    var cropRect: CGRect? = nil
    var featherRadius: CGFloat? = nil
    var blendMode: String? = nil
    var shadowRadius: CGFloat = 0

    enum CodingKeys: String, CodingKey {
        case id, collectionID, photoID, position, size, rotation, zOrder, opacity
        case sourceResolution, cropRect, featherRadius, blendMode
        case shadowRadius
    }

    /// Resolves the photo's absolute file path from its collection reference.
    /// Falls back to the runtime-only `photoPath` field (used for Finder drops,
    /// not persisted to JSON).
    func resolvedPhotoPath() -> String {
        if let collID = collectionID, let pID = photoID,
           let collection = PhotoCollection.find(by: collID),
           let photo = collection.photos.first(where: { $0.id == pID }) {
            return photo.resolvedPath(relativeTo: collection.folderPath)
        }
        // Runtime fallback (Finder drops, not in JSON)
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
