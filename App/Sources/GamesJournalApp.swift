import SwiftUI

@main
struct GamesJournalApp: App {
    var body: some Scene {
        WindowGroup("Games Journal", id: "main") {
            MainWindow()
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView()
        }
    }
}
