import AppKit
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
        // What an interrupted Archive or Unarchive left behind.
        for folder in settings.romFolders { ROMArchiver.cleanUp(folder) }
        self.settings = settings
        journal = try? LudeumStore(directory: AppSettings.appFolder, backups: settings.backups())
        services = Services(settings: settings, journal: journal)
        importModel = ImportModel(services: services)
        syncModel = SyncModel(services: services, importModel: importModel)
    }

    var body: some Scene {
        // One window: no New Window, and closing it hides it until the Dock icon is clicked.
        Window("Ludeum", id: "main") {
            MainWindow(services: services, importModel: importModel, syncModel: syncModel)
                .modifier(OpenSettingsWithoutCredentials(settings: settings))
                .modifier(DailyBackupOnLaunch(journal: journal, backups: settings.backups()))
        }
        .defaultSize(width: 1700, height: 900)
        // Every launch opens at this size with the columns at their ideal widths, not as last left.
        .restorationBehavior(.disabled)
        .commands { TrimmedMenus() }

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

/// The menu bar holds only what Ludeum uses. Edit keeps Undo, Cut, Copy, Paste and Select All so text
/// fields keep their shortcuts; the word-processor groups go. Format, View, Window, Help and Services are
/// taken out by `MenuPruner`, as SwiftUI leaves their empty menus behind.
struct TrimmedMenus: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .textEditing) {}
        WindowAndHelpMenus()
    }
}

private struct WindowAndHelpMenus: Commands {
    var body: some Commands {
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .windowSize) {}
        CommandGroup(replacing: .windowList) {}
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .help) {}
        CommandGroup(replacing: .systemServices) {}
    }
}

/// Removes the Format, View, Window and Help menus and the app menu's Services, each time SwiftUI rebuilds the menu bar.
@MainActor enum MenuPruner {
    private static let unwanted: Set<String> = ["Format", "View", "Window", "Help"]

    static func start() {
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        prune()
        NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { note in
            let menu = (note.object as? NSMenu).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                let watched = [NSApp.mainMenu, NSApp.mainMenu?.items.first?.submenu].compactMap { $0.map(ObjectIdentifier.init) }
                guard let menu, watched.contains(menu) else { return }
                DispatchQueue.main.async { prune() }
            }
        }
    }

    static func prune() {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items where unwanted.contains(item.title) { main.removeItem(item) }
        if let appMenu = main.items.first?.submenu,
            let services = appMenu.items.firstIndex(where: { $0.submenu != nil && $0.submenu == NSApp.servicesMenu })
        {
            appMenu.removeItem(at: services)
            // The separator that set Services apart, so two don't end up together.
            if services < appMenu.items.count, appMenu.items[services].isSeparatorItem,
                services > 0, appMenu.items[services - 1].isSeparatorItem
            {
                appMenu.removeItem(at: services)
            }
        }
    }
}
