import Foundation

/// Errors thrown while parsing a Picasa `.cxf` collage file.
enum CXFError: LocalizedError {
    case invalidXML(String)
    case unsupportedTheme(String)

    var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            return "Invalid collage XML: \(message)"
        case .unsupportedTheme(let theme):
            return "Unsupported collage theme \"\(theme)\" — only \"multiexp\" and \"picturepile\" can be imported."
        }
    }
}
