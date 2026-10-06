import AppKit
import LudeumCore
import SwiftUI

@main
struct LudeumApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var launch = AppLaunch()

    var body: some Scene {
        // One window: no New Window, and closing it hides it until the Dock icon is clicked.
        Window("Ludeum", id: "main") {
            Group {
                if let running = launch.running {
                    MainWindow(services: running.services, importModel: running.importModel)
                        .modifier(OpenSettingsWithoutCredentials(settings: launch.settings))
                        .modifier(DailyBackupOnLaunch(journal: running.services.journal, backups: launch.settings.backups()))
                } else {
                    Color.clear.frame(minWidth: 900, minHeight: 600)
                }
            }
            .sheet(isPresented: Binding(get: { launch.dataFolderMissing != nil }, set: { _ in })) {
                DataFolderSheet(launch: launch)
            }
            // The Data folder can go (Dropbox quit, the link broken) while Ludeum is open.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                launch.checkDataFolder()
            }
        }
        .defaultSize(width: 1700, height: 900)
        // MainWindow saves its own frame, columns and selection, so system restoration can't fight it.
        .restorationBehavior(.disabled)
        .commands {
            TrimmedMenus()
            CommandGroup(after: .appSettings) {
                Button("Players…") { launch.running?.services.sheets.players = true }
                    .disabled(launch.running == nil)
                Button("Emulators…") { launch.running?.services.sheets.emulators = true }
                    .disabled(launch.running == nil)
            }
        }

        Settings {
            SettingsView(settings: launch.settings, journal: launch.running?.services.journal)
        }
    }
}

/// Nothing works until the Data folder is found (ADR 0010): the journal isn't opened, and no Import or backup runs,
/// until it is. Once it's running, losing the Data folder blocks the window again until it's back.
@Observable @MainActor final class AppLaunch {
    let settings = AppSettings()
    /// Nil until the Data folder has been found.
    private(set) var running: Running?
    /// Shown in a sheet that blocks the window while it's set.
    private(set) var dataFolderMissing: DataFolderMissing?

    struct Running {
        let services: Services
        let importModel: ImportModel
    }

    init() {
        RenameMigration(settings: settings).run()
        checkDataFolder()
    }

    func checkDataFolder() {
        do {
            try settings.folder.checkData()
            dataFolderMissing = nil
        } catch {
            dataFolderMissing = error
            return
        }
        guard running == nil else { return }
        // What an interrupted Archive or Unarchive left behind.
        for folder in settings.romFolders { ROMArchiver.cleanUp(folder) }
        let journal = try? LudeumStore(directory: settings.folder.url, backups: settings.backups())
        let services = Services(settings: settings, journal: journal)
        running = Running(services: services, importModel: ImportModel(services: services))
    }
}

/// The Data folder can't be found: says how to fix it, and checks again. It can't be dismissed any other way.
struct DataFolderSheet: View {
    let launch: AppLaunch
    @State private var checked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ludeum can't find its Data folder", systemImage: "externaldrive.badge.exclamationmark").font(.headline)
            Text(launch.dataFolderMissing?.remedy ?? "").textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                if checked { Text("Still not there.").foregroundStyle(.secondary) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                Button("Check again") {
                    launch.checkDataFolder()
                    checked = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
        .interactiveDismissDisabled()
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
        SearchCommands()
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

/// Asks before quitting while an Import or Background tasks are running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { MenuPruner.start() }
    }

    /// Clicking the Dock icon brings the one window back after it was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if MainActor.assumeIsolated({ BackgroundTasks.isBusy }) {
            let alert = NSAlert()
            alert.messageText = "Background tasks are running"
            alert.informativeText = "Quitting stops them. Nothing is lost: a ROM being Archived or Unarchived keeps its original file."
            alert.addButton(withTitle: "Keep running")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() != .alertSecondButtonReturn { return .terminateCancel }
        }
        guard MainActor.assumeIsolated({ ImportModel.isRunning }) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "An Import is running"
        alert.informativeText =
            "Quitting stops it. Nothing has been written to the journal, and lookups already made are kept for next time."
        alert.addButton(withTitle: "Keep importing")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
