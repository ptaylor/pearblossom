import SwiftUI

@main
struct PearblossomApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
                    // TODO: Implement
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
