import Foundation

/// Translates Picasa/Wine Windows paths into native macOS paths.
/// See `SPEC_wine.md` for the full mapping matrix.
enum WinePathTranslator {

    /// Translates a single path string, or returns nil if the scheme is unrecognized.
    static func translate(_ raw: String) -> String? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Environment pseudo-variables.
        let variables: [(name: String, replacement: String)] = [
            ("$My Pictures", home + "/Pictures"),
            ("$My Documents", home + "/Documents")
        ]
        for (name, replacement) in variables where path.lowercased().hasPrefix(name.lowercased()) {
            let rest = path.dropFirst(name.count)
            return normalizeSlashes(replacement + rest)
        }

        // Drive-letter prefixes: [Z]\ , Z:\ , C:\ , [C]\ , etc.
        if let (letter, rest) = parseDrivePrefix(path) {
            let target: String
            if letter.lowercased() == "z" {
                // Wine maps Z: to the Unix root.
                target = "/"
            } else {
                // All other drive letters map to the Wine drive_c/drive_d/… folders.
                target = home + "/.wine/drive_\(letter.lowercased())/"
            }
            return normalizeSlashes(target + rest)
        }

        // Already a native POSIX path — normalize any stray backslashes.
        if path.hasPrefix("/") {
            return normalizeSlashes(path)
        }

        return nil
    }

    // MARK: - Helpers

    /// Parses a Windows drive prefix into `(driveLetter, remainder)`.
    /// Accepts both `C:\foo` and `[C]\foo` forms. Returns nil when no prefix matches.
    private static func parseDrivePrefix(_ path: String) -> (letter: String, rest: String)? {
        if path.hasPrefix("[") {
            // "[Z]\foo" — need at least "[X]" plus one separator.
            guard path.count >= 4 else { return nil }
            let letterIndex = path.index(path.startIndex, offsetBy: 1)
            let letter = String(path[letterIndex])
            guard letter.rangeOfCharacter(from: .letters) != nil else { return nil }
            var rest = String(path.dropFirst(3)) // skip "[X]"
            rest = droppingLeadingSeparator(rest)
            return (letter, rest)
        }

        // "C:\foo"
        guard path.count >= 2 else { return nil }
        let colonIndex = path.index(path.startIndex, offsetBy: 1)
        guard path[colonIndex] == ":" else { return nil }
        let letter = String(path[path.startIndex])
        guard letter.rangeOfCharacter(from: .letters) != nil else { return nil }
        var rest = String(path.dropFirst(2)) // skip "C:"
        rest = droppingLeadingSeparator(rest)
        return (letter, rest)
    }

    private static func droppingLeadingSeparator(_ path: String) -> String {
        var rest = path
        if rest.hasPrefix("\\") || rest.hasPrefix("/") {
            rest = String(rest.dropFirst())
        }
        return rest
    }

    private static func normalizeSlashes(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }
}
