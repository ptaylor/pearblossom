import Foundation
import OSLog

/// Debug logger using Apple's unified logging system.
/// View logs in Console.app (filter: subsystem "com.pearblossom")
/// or via Terminal: `log stream --predicate 'subsystem == "com.pearblossom"' --level debug`
enum Logger {

    private static let log = os.Logger(subsystem: "com.pearblossom", category: "general")

    // MARK: - Public API

    /// Log a debug message. Only logs if debug logging is enabled in settings.
    static func debug(_ message: @autoclosure () -> String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        guard AppSettings.shared.debugLoggingEnabled else { return }
        let fileName = (file as NSString).lastPathComponent
        let msg = message()
        log.debug("[\("[\(fileName):\(line)]", privacy: .public)] \(msg, privacy: .public)")
    }

    /// Log a warning (always logged).
    static func warn(_ message: @autoclosure () -> String,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let msg = message()
        log.warning("[\("[\(fileName):\(line)]", privacy: .public)] \(msg, privacy: .public)")
    }

    /// Log an error (always logged).
    static func error(_ message: @autoclosure () -> String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let msg = message()
        log.error("[\("[\(fileName):\(line)]", privacy: .public)] \(msg, privacy: .public)")
    }
}
