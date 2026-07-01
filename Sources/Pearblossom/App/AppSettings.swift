import SwiftUI

/// Central app settings backed by UserDefaults.
/// Access globally via `@ObservedObject var settings = AppSettings.shared` or read directly.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let collectionsRoot = "collectionsRoot"
        static let copyOnImport = "copyOnImport"
        static let collectionFileName = "collectionFileName"
        static let debugLoggingEnabled = "debugLoggingEnabled"
        static let collectionSortOrder = "collectionSortOrder"
        static let collectionSortAscending = "collectionSortAscending"
        static let thumbnailSize = "thumbnailSize"
    }

    // MARK: - Defaults

    /// Default collections root: ~/Pictures/Pearblossom Collections
    static let defaultCollectionsRoot: URL = {
        let pictures = FileManager.default.urls(
            for: .picturesDirectory, in: .userDomainMask
        ).first!
        return pictures.appendingPathComponent("Pearblossom Collections", isDirectory: true)
    }()

    // MARK: - Published Settings

    /// The root directory where collection folders are stored.
    @Published var collectionsRoot: URL {
        didSet {
            defaults.set(collectionsRoot.path, forKey: Keys.collectionsRoot)
            ensureDirectoryExists(at: collectionsRoot)
        }
    }

    /// Whether to copy imported photos into the collection folder (vs referencing in-place).
    @Published var copyOnImport: Bool {
        didSet {
            defaults.set(copyOnImport, forKey: Keys.copyOnImport)
        }
    }

    /// The filename used for collection metadata files (default: ".collection.json").
    @Published var collectionFileName: String {
        didSet {
            defaults.set(collectionFileName, forKey: Keys.collectionFileName)
        }
    }

    /// Whether debug logging is enabled (default: true).
    @Published var debugLoggingEnabled: Bool {
        didSet {
            defaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled)
        }
    }

    /// Sort order for the collections list (default: "dateModified").
    @Published var collectionSortOrder: String {
        didSet {
            defaults.set(collectionSortOrder, forKey: Keys.collectionSortOrder)
        }
    }

    /// Whether collection sort is ascending (default: false = descending).
    @Published var collectionSortAscending: Bool {
        didSet {
            defaults.set(collectionSortAscending, forKey: Keys.collectionSortAscending)
        }
    }

    /// Desired maximum dimension for collection photo thumbnails in points (default: 200).
    @Published var thumbnailSize: CGFloat {
        didSet {
            defaults.set(thumbnailSize, forKey: Keys.thumbnailSize)
        }
    }

    // MARK: - Init

    private init() {
        // Load saved path or use default
        if let savedPath = defaults.string(forKey: Keys.collectionsRoot),
           !savedPath.isEmpty {
            self.collectionsRoot = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.collectionsRoot = Self.defaultCollectionsRoot
            defaults.set(Self.defaultCollectionsRoot.path, forKey: Keys.collectionsRoot)
        }

        // Load copy-on-import preference (default false = reference-only)
        self.copyOnImport = defaults.bool(forKey: Keys.copyOnImport)

        // Load collection file name (default ".collection.json")
        if let name = defaults.string(forKey: Keys.collectionFileName), !name.isEmpty {
            self.collectionFileName = name
        } else {
            self.collectionFileName = ".collection.json"
        }

        // Load debug logging preference (default true)
        if defaults.object(forKey: Keys.debugLoggingEnabled) != nil {
            self.debugLoggingEnabled = defaults.bool(forKey: Keys.debugLoggingEnabled)
        } else {
            self.debugLoggingEnabled = true
        }

        // Load collection sort preferences (default: dateModified descending)
        self.collectionSortOrder = defaults.string(forKey: Keys.collectionSortOrder) ?? "dateModified"
        if defaults.object(forKey: Keys.collectionSortAscending) != nil {
            self.collectionSortAscending = defaults.bool(forKey: Keys.collectionSortAscending)
        } else {
            self.collectionSortAscending = false
        }

        // Load thumbnail size (default: 200)
        let savedThumbSize = defaults.double(forKey: Keys.thumbnailSize)
        self.thumbnailSize = savedThumbSize > 0 ? savedThumbSize : 200

        // Ensure the directory exists
        ensureDirectoryExists(at: collectionsRoot)
    }

    // MARK: - Helpers

    /// Create the directory if it doesn't exist.
    private func ensureDirectoryExists(at url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// URL for a specific collection folder inside the collections root.
    func collectionFolderURL(named name: String) -> URL {
        collectionsRoot.appendingPathComponent(name, isDirectory: true)
    }

    /// URL for the collection metadata file inside a collection folder.
    func collectionFileURL(for folderURL: URL) -> URL {
        folderURL.appendingPathComponent(collectionFileName)
    }
}
