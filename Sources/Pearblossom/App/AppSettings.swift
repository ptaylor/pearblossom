import SwiftUI

/// Central app settings backed by UserDefaults.
/// Access globally via `@ObservedObject var settings = AppSettings.shared` or read directly.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let collectionsRoot = "collectionsRoot"  // Now the root directory
        static let copyOnImport = "copyOnImport"
        static let collectionFileName = "collectionFileName"
        static let debugLoggingEnabled = "debugLoggingEnabled"
        static let collectionSortOrder = "collectionSortOrder"
        static let collectionSortAscending = "collectionSortAscending"
        static let thumbnailSize = "thumbnailSize"
        static let collageSortOrder = "collageSortOrder"
        static let collageSortAscending = "collageSortAscending"
        static let defaultBackgroundRed = "defaultBackgroundRed"
        static let defaultBackgroundGreen = "defaultBackgroundGreen"
        static let defaultBackgroundBlue = "defaultBackgroundBlue"
        static let defaultBorderMargin = "defaultBorderMargin"
        static let defaultPhotoScalePercent = "defaultPhotoScalePercent"
    }

    // MARK: - Defaults

    /// Default root directory: ~/Pictures/Pearblossom/
    static let defaultRoot: URL = {
        let pictures = FileManager.default.urls(
            for: .picturesDirectory, in: .userDomainMask
        ).first!
        return pictures.appendingPathComponent("Pearblossom", isDirectory: true)
    }()

    /// The old default collections root (for migration).
    private static let legacyCollectionsRoot: URL = {
        let pictures = FileManager.default.urls(
            for: .picturesDirectory, in: .userDomainMask
        ).first!
        return pictures.appendingPathComponent("Pearblossom Collections", isDirectory: true)
    }()

    // MARK: - Published Settings

    /// The root directory for all Pearblossom data. Collections live in `Collections/`, collages in `Collages/`.
    @Published var collectionsRoot: URL {
        didSet {
            defaults.set(collectionsRoot.path, forKey: Keys.collectionsRoot)
            ensureDirectoryExists(at: collectionsRoot)
        }
    }

    /// The subdirectory where collection folders are stored.
    var collectionsDir: URL {
        collectionsRoot.appendingPathComponent("Collections", isDirectory: true)
    }

    /// The subdirectory where collage .json files are stored.
    var collagesDir: URL {
        collectionsRoot.appendingPathComponent("Collages", isDirectory: true)
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

    /// Sort order for the collages list (default: "dateModified").
    @Published var collageSortOrder: String {
        didSet {
            defaults.set(collageSortOrder, forKey: Keys.collageSortOrder)
        }
    }

    /// Whether collage sort is ascending (default: false = descending).
    @Published var collageSortAscending: Bool {
        didSet {
            defaults.set(collageSortAscending, forKey: Keys.collageSortAscending)
        }
    }

    /// Default background color for new collages (default: white).
    @Published var defaultBackgroundColor: CodableColor {
        didSet {
            defaults.set(defaultBackgroundColor.red, forKey: Keys.defaultBackgroundRed)
            defaults.set(defaultBackgroundColor.green, forKey: Keys.defaultBackgroundGreen)
            defaults.set(defaultBackgroundColor.blue, forKey: Keys.defaultBackgroundBlue)
        }
    }

    /// Default border margin in points for new collages (default: 40).
    @Published var defaultBorderMargin: CGFloat {
        didSet {
            defaults.set(defaultBorderMargin, forKey: Keys.defaultBorderMargin)
        }
    }

    /// Default photo scale as percentage of canvas size for new layers (default: 30).
    @Published var defaultPhotoScalePercent: CGFloat {
        didSet {
            defaults.set(defaultPhotoScalePercent, forKey: Keys.defaultPhotoScalePercent)
        }
    }

    // MARK: - Init

    private init() {
        let fm = FileManager.default
        let newCollectionsDir = Self.defaultRoot.appendingPathComponent("Collections", isDirectory: true)

        // Determine the root directory, migrating from legacy layout if needed
        if let savedPath = defaults.string(forKey: Keys.collectionsRoot), !savedPath.isEmpty {
            let savedURL = URL(fileURLWithPath: savedPath, isDirectory: true)

            // Migrate from old default "Pearblossom Collections" → "Pearblossom/Collections/"
            if savedURL.path == Self.legacyCollectionsRoot.path,
               fm.fileExists(atPath: savedPath) {
                // Ensure parent exists
                try? fm.createDirectory(at: Self.defaultRoot, withIntermediateDirectories: true)
                // Remove empty destination if it exists from a previous partial run
                if fm.fileExists(atPath: newCollectionsDir.path) {
                    let contents = (try? fm.contentsOfDirectory(at: newCollectionsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                    if contents.isEmpty {
                        try? fm.removeItem(at: newCollectionsDir)
                    }
                }
                // Try moving the whole directory, or move individual contents
                if !fm.fileExists(atPath: newCollectionsDir.path) {
                    do {
                        try fm.moveItem(at: savedURL, to: newCollectionsDir)
                        print("[Pearblossom] Migrated collections from legacy path to \(newCollectionsDir.path)")
                    } catch {
                        print("[Pearblossom] ERROR: Migration move failed: \(error.localizedDescription)")
                    }
                } else {
                    // Destination exists with content — move individual items
                    print("[Pearblossom] Migrating individual collection folders from legacy path")
                    if let items = try? fm.contentsOfDirectory(at: savedURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                        for item in items {
                            let dest = newCollectionsDir.appendingPathComponent(item.lastPathComponent)
                            if !fm.fileExists(atPath: dest.path) {
                                try? fm.moveItem(at: item, to: dest)
                            }
                        }
                    }
                }
                self.collectionsRoot = Self.defaultRoot
                defaults.set(Self.defaultRoot.path, forKey: Keys.collectionsRoot)
            } else {
                self.collectionsRoot = savedURL
            }
        } else {
            self.collectionsRoot = Self.defaultRoot
            defaults.set(Self.defaultRoot.path, forKey: Keys.collectionsRoot)
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

        // Load collage sort preferences (default: dateModified descending)
        self.collageSortOrder = defaults.string(forKey: Keys.collageSortOrder) ?? "dateModified"
        if defaults.object(forKey: Keys.collageSortAscending) != nil {
            self.collageSortAscending = defaults.bool(forKey: Keys.collageSortAscending)
        } else {
            self.collageSortAscending = false
        }

        // Load default background color (default: white)
        let bgRed = defaults.double(forKey: Keys.defaultBackgroundRed)
        let bgGreen = defaults.double(forKey: Keys.defaultBackgroundGreen)
        let bgBlue = defaults.double(forKey: Keys.defaultBackgroundBlue)
        if bgRed > 0 || bgGreen > 0 || bgBlue > 0 {
            self.defaultBackgroundColor = CodableColor(red: bgRed, green: bgGreen, blue: bgBlue, alpha: 1)
        } else {
            self.defaultBackgroundColor = .white
        }

        // Load default border margin (default: 40)
        let savedMargin = defaults.double(forKey: Keys.defaultBorderMargin)
        self.defaultBorderMargin = savedMargin > 0 ? savedMargin : 40

        // Load default photo scale percent (default: 30)
        let savedScale = defaults.double(forKey: Keys.defaultPhotoScalePercent)
        self.defaultPhotoScalePercent = savedScale > 0 ? savedScale : 30

        // Ensure subdirectories exist (safe to call after all properties initialized)
        prepareDirectories()

        // Migrate any collection folders that may be sitting directly in the root
        // (from earlier versions that didn't use a Collections/ subdirectory)
        migrateRootCollections()
    }

    /// Move any collection folders (.collection.json present) from root into Collections/.
    private func migrateRootCollections() {
        let fm = FileManager.default
        guard let rootContents = try? fm.contentsOfDirectory(
            at: collectionsRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        for item in rootContents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Skip the Collections and Collages subdirectories themselves
            let name = item.lastPathComponent
            if name == "Collections" || name == "Collages" { continue }
            // Check if this folder contains a .collection.json
            let jsonURL = item.appendingPathComponent(collectionFileName)
            if fm.fileExists(atPath: jsonURL.path) {
                let dest = collectionsDir.appendingPathComponent(name)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: item, to: dest)
                    print("[Pearblossom] Migrated collection '\(name)' from root to Collections/")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Create the directory if it doesn't exist.
    private func ensureDirectoryExists(at url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Ensure all required subdirectories exist. Safe to call after migration.
    func prepareDirectories() {
        ensureDirectoryExists(at: collectionsDir)
        ensureDirectoryExists(at: collagesDir)
    }

    /// URL for a specific collection folder inside the collections directory.
    func collectionFolderURL(named name: String) -> URL {
        ensureDirectoryExists(at: collectionsDir)
        return collectionsDir.appendingPathComponent(name, isDirectory: true)
    }

    /// URL for the collection metadata file inside a collection folder.
    func collectionFileURL(for folderURL: URL) -> URL {
        folderURL.appendingPathComponent(collectionFileName)
    }

    /// URL for a collage .json file in the collages directory.
    func collageFileURL(named name: String) -> URL {
        ensureDirectoryExists(at: collagesDir)
        return collagesDir.appendingPathComponent("\(name).collage.json")
    }
}
