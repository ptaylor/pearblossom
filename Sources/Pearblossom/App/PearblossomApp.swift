import SwiftUI
import AppKit

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Set app icon from bundled Resources
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

        Logger.debug("App launched — debug logging: \(AppSettings.shared.debugLoggingEnabled), collections root: \(AppSettings.shared.collectionsRoot.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.debug("App shutting down")
    }
}

// MARK: - App

@main
struct PearblossomApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Standard File menu
            CommandGroup(replacing: .newItem) {
                Button("New Collage…") {
                    // TODO: Implement
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .importExport) {
                Button("Import Photos…") {
                    NotificationCenter.default.post(name: .triggerImport, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("Export Collage…") {
                    NotificationCenter.default.post(name: .triggerExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            // Settings — placed in the app menu (Pearblossom → Settings…)
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Settings…") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    // MARK: - Settings Window

    /// Opens a settings window manually (avoids SwiftUI Settings scene conflicts with WindowGroup).
    private func openSettingsWindow() {
        // If already open, bring to front
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.title = "Pearblossom Settings"
        window.setContentSize(NSSize(width: 480, height: 300))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
