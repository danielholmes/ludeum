import Foundation

/// The app's settings: secrets in a `SecretStore` (the Keychain), folder locations in user defaults.
/// Sendable because `UserDefaults` and every `SecretStore` are thread-safe.
public final class AppSettings: @unchecked Sendable {
    public let secrets: any SecretStore
    let defaults: UserDefaults

    public init(secrets: any SecretStore = KeychainSecretStore(), defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
    }

    // MARK: - Secrets

    /// Read failures count as no credentials: Settings then asks for them again.
    public var igdbCredentials: IGDBCredentials? {
        guard let id = try? secrets.secret(for: Keys.igdbClientID), let secret = try? secrets.secret(for: Keys.igdbClientSecret)
        else { return nil }
        return IGDBCredentials(clientID: id, clientSecret: secret)
    }

    /// Stores both halves, or clears both if either is blank.
    public func setIGDBCredentials(_ credentials: IGDBCredentials) throws {
        let id = credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = credentials.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let complete = !id.isEmpty && !secret.isEmpty
        try secrets.setSecret(complete ? id : nil, for: Keys.igdbClientID)
        try secrets.setSecret(complete ? secret : nil, for: Keys.igdbClientSecret)
    }

    /// With none, Settings opens at launch.
    public var needsCredentials: Bool { igdbCredentials == nil }

    public var hasheousKey: String? { try? secrets.secret(for: Keys.hasheousKey) }

    public func setHasheousKey(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.setSecret(key.isEmpty ? nil : key, for: Keys.hasheousKey)
    }

    // MARK: - Folders

    /// Defaults to wherever OpenEmu itself keeps its library.
    public var openEmuLibrary: URL {
        get { folder(Keys.openEmuLibrary) ?? Self.openEmuDefaultLibrary }
        set { defaults.set(newValue.path(percentEncoded: false), forKey: Keys.openEmuLibrary) }
    }

    /// Normally in Dropbox. When it isn't there, backups go to `Backups/` in the app's folder instead.
    public var backupFolder: URL {
        get {
            folder(Keys.backupFolder) ?? .homeDirectory.appending(path: "Dropbox/Ludeum Backups", directoryHint: .isDirectory)
        }
        set { defaults.set(newValue.path(percentEncoded: false), forKey: Keys.backupFolder) }
    }

    /// The PS2 ROM folder, normally in Dropbox.
    public var ps2Folder: URL {
        get { folder(Keys.ps2Folder) ?? .homeDirectory.appending(path: "Dropbox/games/PS2", directoryHint: .isDirectory) }
        set { defaults.set(newValue.path(percentEncoded: false), forKey: Keys.ps2Folder) }
    }

    /// Where the ROM folders live, one per Platform, each named for its Platform. Normally in Dropbox.
    public var romFoldersRoot: URL {
        get { folder(Keys.romFoldersRoot) ?? .homeDirectory.appending(path: "Dropbox/games", directoryHint: .isDirectory) }
        set { defaults.set(newValue.path(percentEncoded: false), forKey: Keys.romFoldersRoot) }
    }

    /// A Platform's ROM folder: PS2's is its own setting, every other under the root. Nil for a Platform without one.
    public func romFolder(platform: Int64) -> URL? {
        if platform == ROMPlatform.ps2 { return ps2Folder }
        return ROMPlatform.all[platform].map { romFoldersRoot.appending(path: $0.folderName, directoryHint: .isDirectory) }
    }

    /// Every ROM folder an Import reads.
    public var romFolders: [ROMFolder] { [.ps2(ps2Folder)] }

    /// `~/Library/Application Support/Ludeum/`: the journal database, the cache and the fallback `Backups/`.
    public static let appFolder = URL.applicationSupportDirectory.appending(path: "Ludeum", directoryHint: .isDirectory)

    /// Backups into the current backup folder, falling back to `Backups/` in the app's folder.
    public func backups() -> Backups {
        Backups(folder: { [self] in backupFolder }, fallback: Self.appFolder.appending(path: "Backups", directoryHint: .isDirectory))
    }

    private func folder(_ key: String) -> URL? {
        defaults.string(forKey: key).map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    static var openEmuDefaultLibrary: URL {
        let path =
            (UserDefaults(suiteName: "org.openemu.OpenEmu")?.string(forKey: "databasePath")
            ?? "~/Library/Application Support/OpenEmu/Game Library") as NSString
        return URL(filePath: path.expandingTildeInPath, directoryHint: .isDirectory)
    }

    enum Keys {
        static let igdbClientID = "igdb-client-id"
        static let igdbClientSecret = "igdb-client-secret"
        static let hasheousKey = "hasheous-api-key"
        static let openEmuLibrary = "openEmuLibrary"
        static let backupFolder = "backupFolder"
        static let ps2Folder = "ps2Folder"
        static let romFoldersRoot = "romFoldersRoot"
    }
}
