import JournalCore
import SwiftUI

@main
struct GamesJournalApp: App {
    private let settings = AppSettings()

    var body: some Scene {
        WindowGroup("Games Journal", id: "main") {
            MainWindow()
                .modifier(OpenSettingsWithoutCredentials(settings: settings))
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView(settings: settings)
        }
    }
}

/// With no IGDB credentials at launch, Settings opens so they can be entered. Once per launch,
/// not for every new main window.
struct OpenSettingsWithoutCredentials: ViewModifier {
    let settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @MainActor private static var checked = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.checked else { return }
            Self.checked = true
            if settings.needsCredentials { openSettings() }
        }
    }
}
