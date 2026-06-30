import Foundation

/// A photo collection — a named group of photos, backed by a folder on disk.
struct PhotoCollection: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var folderPath: String?
    var photos: [CollectionPhoto] = []
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
}

struct CollectionPhoto: Codable, Identifiable {
    var id: UUID = UUID()
    var path: String
    var addedAt: Date = Date()
}
