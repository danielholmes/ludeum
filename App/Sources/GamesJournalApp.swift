import JournalCore
import SwiftUI

@main
struct GamesJournalApp: App {
    private let settings: AppSettings
    private let journal: JournalStore?

    init() {
        let settings = AppSettings()
        self.settings = settings
        journal = try? JournalStore(directory: AppSettings.appFolder, backups: settings.backups())
    }

    var body: some Scene {
        WindowGroup("Games Journal", id: "main") {
            MainWindow()
                .modifier(OpenSettingsWithoutCredentials(settings: settings))
                .modifier(DailyBackupOnLaunch(journal: journal, backups: settings.backups()))
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView(settings: settings, journal: journal)
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

/// The daily backup, if one is due, once per launch and off the main thread.
struct DailyBackupOnLaunch: ViewModifier {
    let journal: JournalStore?
    let backups: Backups
    @MainActor private static var done = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.done, let journal else { return }
            Self.done = true
            let backups = backups
            await Task.detached(priority: .utility) { _ = try? backups.backUpIfDailyDue(journal) }.value
        }
    }
}
