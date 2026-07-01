import Foundation

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
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, version, name, description, filePath, canvasWidth, canvasHeight
        case backgroundColor, layers, createdAt, modifiedAt
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
}

/// A Codable wrapper for CGColor, used for the canvas background.
struct CodableColor: Codable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
}
