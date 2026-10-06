import Foundation

/// The app was called Games Journal. On the first launch as Ludeum, carries over what was kept under
/// the old name: the app folder, settings and Keychain secrets. Backups now live in the Data folder (ADR 0010), so
/// the old Dropbox backup folder is left alone. Never overwrites anything already kept under the new name, so running
/// it again does nothing.
public struct RenameMigration {
    public static let oldBundleID = "org.danielholmes.GamesJournal"

    let oldAppFolder: URL
    let newAppFolder: URL
    let oldDefaults: UserDefaults?
    let oldSecrets: any SecretStore
    let settings: AppSettings

    public init(settings: AppSettings) {
        self.init(
            oldAppFolder: URL.applicationSupportDirectory.appending(path: "GamesJournal", directoryHint: .isDirectory),
            newAppFolder: settings.folder.url, oldDefaults: UserDefaults(suiteName: Self.oldBundleID),
            oldSecrets: KeychainSecretStore(service: Self.oldBundleID), settings: settings)
    }

    init(oldAppFolder: URL, newAppFolder: URL, oldDefaults: UserDefaults?, oldSecrets: any SecretStore, settings: AppSettings) {
        self.oldAppFolder = oldAppFolder
        self.newAppFolder = newAppFolder
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

        let key = AppSettings.Keys.openEmuLibrary
        if settings.defaults.object(forKey: key) == nil, let value = oldDefaults?.object(forKey: key) {
            settings.defaults.set(value, forKey: key)
        }

        // The Twitch token isn't carried over: it's fetched again when needed.
        for key in [AppSettings.Keys.igdbClientID, AppSettings.Keys.igdbClientSecret, AppSettings.Keys.hasheousKey]
        where (try? settings.secrets.secret(for: key)) ?? nil == nil {
            if let value = try? oldSecrets.secret(for: key) { try? settings.secrets.setSecret(value, for: key) }
        }
    }
}
