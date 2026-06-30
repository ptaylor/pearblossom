import SwiftUI

/// Central app settings backed by UserDefaults.
/// Access globally via `@ObservedObject var settings = AppSettings.shared` or read directly.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let collectionsRoot = "collectionsRoot"
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

    /// URL for the .collection.json file inside a collection folder.
    func collectionFileURL(for folderURL: URL) -> URL {
        folderURL.appendingPathComponent(".collection.json")
    }
}
