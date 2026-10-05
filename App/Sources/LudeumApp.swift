import LudeumCore
import SwiftUI

@main
struct LudeumApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let settings: AppSettings
    private let journal: LudeumStore?
    private let services: Services
    private let importModel: ImportModel
    private let syncModel: SyncModel

    init() {
        let settings = AppSettings()
        RenameMigration(settings: settings).run()
        self.settings = settings
        journal = try? LudeumStore(directory: AppSettings.appFolder, backups: settings.backups())
        services = Services(settings: settings, journal: journal)
        importModel = ImportModel(services: services)
        syncModel = SyncModel(services: services, importModel: importModel)
    }

    var body: some Scene {
        WindowGroup("Ludeum", id: "main") {
            MainWindow(services: services, importModel: importModel, syncModel: syncModel)
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
    let journal: LudeumStore?
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
