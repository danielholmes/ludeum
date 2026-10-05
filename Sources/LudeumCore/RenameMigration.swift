import Foundation

/// The app was called Games Journal. On the first launch as Ludeum, carries over what was kept under
/// the old name: the app folder, the default Dropbox backup folder, settings and Keychain secrets.
/// Never overwrites anything already kept under the new name, so running it again does nothing.
public struct RenameMigration {
    public static let oldBundleID = "org.danielholmes.GamesJournal"

    let oldAppFolder: URL
    let newAppFolder: URL
    let oldBackupFolder: URL
    let oldDefaults: UserDefaults?
    let oldSecrets: any SecretStore
    let settings: AppSettings

    public init(settings: AppSettings) {
        let support = URL.applicationSupportDirectory
        self.init(
            oldAppFolder: support.appending(path: "GamesJournal", directoryHint: .isDirectory),
            newAppFolder: AppSettings.appFolder,
            oldBackupFolder: .homeDirectory.appending(path: "Dropbox/Games Journal Backups", directoryHint: .isDirectory),
            oldDefaults: UserDefaults(suiteName: Self.oldBundleID),
            oldSecrets: KeychainSecretStore(service: Self.oldBundleID),
            settings: settings)
    }

    init(
        oldAppFolder: URL, newAppFolder: URL, oldBackupFolder: URL, oldDefaults: UserDefaults?, oldSecrets: any SecretStore,
        settings: AppSettings
    ) {
        self.oldAppFolder = oldAppFolder
        self.newAppFolder = newAppFolder
        self.oldBackupFolder = oldBackupFolder
        self.oldDefaults = oldDefaults
        self.oldSecrets = oldSecrets
        self.settings = settings
    }

    public func run() {
        let files = FileManager.default
        if files.fileExists(atPath: oldAppFolder.path(percentEncoded: false)),
            !files.fileExists(atPath: newAppFolder.path(percentEncoded: false))
        {
            try? files.moveItem(at: oldAppFolder, to: newAppFolder)
        }

        for key in [AppSettings.Keys.openEmuLibrary, AppSettings.Keys.backupFolder]
        where settings.defaults.object(forKey: key) == nil {
            if let value = oldDefaults?.object(forKey: key) { settings.defaults.set(value, forKey: key) }
        }

        // A backup folder left at the old default moves to the new default.
        let newBackupFolder = settings.backupFolder
        if settings.defaults.object(forKey: AppSettings.Keys.backupFolder) == nil,
            files.fileExists(atPath: oldBackupFolder.path(percentEncoded: false)),
            !files.fileExists(atPath: newBackupFolder.path(percentEncoded: false))
        {
            try? files.moveItem(at: oldBackupFolder, to: newBackupFolder)
        }

        // The Twitch token isn't carried over: it's fetched again when needed.
        for key in [AppSettings.Keys.igdbClientID, AppSettings.Keys.igdbClientSecret, AppSettings.Keys.hasheousKey]
        where (try? settings.secrets.secret(for: key)) ?? nil == nil {
            if let value = try? oldSecrets.secret(for: key) { try? settings.secrets.setSecret(value, for: key) }
        }
    }
}
