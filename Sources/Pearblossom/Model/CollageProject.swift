import Foundation

/// A collage project — persisted as a .collage.json file.
struct CollageProject: Codable, Identifiable {
    var id: UUID = UUID()
    var version: Int = 1
    var filePath: String?
    var canvasWidth: CGFloat = 2000
    var canvasHeight: CGFloat = 1500
    var backgroundColor: CodableColor = .white
    var layers: [PhotoLayer] = []
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
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
