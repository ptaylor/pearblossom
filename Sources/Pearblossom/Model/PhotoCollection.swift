import Foundation

/// Import mode for a collection — determines whether photos are copied into the
/// collection folder or referenced in-place. Immutable after collection creation.
enum ImportMode: String, Codable, CaseIterable {
    case copy = "copy"
    case reference = "reference"
}

/// A photo collection — a named group of photos, backed by a folder on disk.
struct PhotoCollection: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var description: String = ""
    var folderPath: String?
    var photos: [CollectionPhoto] = []
    var importMode: ImportMode = .reference
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, name, description, folderPath, photos, importMode, createdAt, modifiedAt
    }

    init(id: UUID = UUID(),
         name: String,
         description: String = "",
         folderPath: String? = nil,
         photos: [CollectionPhoto] = [],
         importMode: ImportMode = .reference,
         createdAt: Date = Date(),
         modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.folderPath = folderPath
        self.photos = photos
        self.importMode = importMode
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
        photos = try container.decodeIfPresent([CollectionPhoto].self, forKey: .photos) ?? []
        // Handle missing importMode from older .collection.json files
        importMode = try container.decodeIfPresent(ImportMode.self, forKey: .importMode) ?? .reference
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }

    // MARK: - Lookup

    /// Finds a collection by its UUID by scanning the Collections directory on disk.
    /// This is a disk-based lookup — no in-memory cache for v1.
    static func find(by id: UUID) -> PhotoCollection? {
        let settings = AppSettings.shared
        let dir = settings.collectionsDir
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return nil
        }
        for folderURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let jsonURL = folderURL.appendingPathComponent(settings.collectionFileName)
            guard let data = try? Data(contentsOf: jsonURL),
                  let collection = try? JSONDecoder().decode(PhotoCollection.self, from: data),
                  collection.id == id else { continue }
            return collection
        }
        return nil
    }
}

struct CollectionPhoto: Codable, Identifiable {
    var id: UUID = UUID()
    /// Path to the photo. Absolute for referenced photos, relative to the collection folder for copied photos.
    var path: String
    /// Path to the cached thumbnail. Relative to the collection folder (inside .thumbnails/).
    var thumbnailPath: String? = nil
    var addedAt: Date = Date()

    /// Resolves the photo path to an absolute path. For relative paths (copied photos),
    /// prepends the collection folder path. For absolute paths (referenced photos), returns as-is.
    func resolvedPath(relativeTo folderPath: String?) -> String {
        guard let folder = folderPath else { return path }
        if path.hasPrefix("/") { return path }
        return (folder as NSString).appendingPathComponent(path)
    }

    /// Resolves the thumbnail path to an absolute path.
    func resolvedThumbnailPath(relativeTo folderPath: String?) -> String? {
        guard let thumb = thumbnailPath else { return nil }
        guard let folder = folderPath else { return thumb }
        if thumb.hasPrefix("/") { return thumb }
        return (folder as NSString).appendingPathComponent(thumb)
    }
}
