import Foundation
import Synchronization

/// The app's settings: secrets in a `SecretStore` (the Keychain), OpenEmu's library in user defaults. Where Ludeum
/// keeps its own things is fixed, not a setting: the Ludeum folder (ADR 0010).
/// Sendable because `UserDefaults` and every `SecretStore` are thread-safe.
public final class AppSettings: @unchecked Sendable {
    public let secrets: any SecretStore
    let defaults: UserDefaults
    /// `.standard` but in tests.
    public let folder: LudeumFolder
    /// The secrets read so far (nil for one that isn't set), so asking again doesn't go back to the Keychain. They only
    /// change through here, which keeps it current.
    private let known = Mutex<[String: String?]>([:])

    public init(
        secrets: any SecretStore = KeychainSecretStore(), defaults: UserDefaults = .standard, folder: LudeumFolder = .standard
    ) {
        self.secrets = secrets
        self.defaults = defaults
        self.folder = folder
    }

    // MARK: - Secrets

    /// Read failures count as no credentials: Settings then asks for them again.
    public var igdbCredentials: IGDBCredentials? {
        guard let id = secret(Keys.igdbClientID), let secret = secret(Keys.igdbClientSecret) else { return nil }
        return IGDBCredentials(clientID: id, clientSecret: secret)
    }

    /// Stores both halves, or clears both if either is blank.
    public func setIGDBCredentials(_ credentials: IGDBCredentials) throws {
        let id = credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = credentials.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let complete = !id.isEmpty && !secret.isEmpty
        try setSecret(complete ? id : nil, for: Keys.igdbClientID)
        try setSecret(complete ? secret : nil, for: Keys.igdbClientSecret)
    }

    /// With none, Settings opens at launch.
    public var needsCredentials: Bool { igdbCredentials == nil }

    public var hasheousKey: String? { secret(Keys.hasheousKey) }

    public func setHasheousKey(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try setSecret(key.isEmpty ? nil : key, for: Keys.hasheousKey)
    }

    /// A secret, read from the store the first time. A read that fails is nil and is tried again next time.
    private func secret(_ key: String) -> String? {
        if let value = known.withLock({ $0[key] }) { return value }
        do {
            let value = try secrets.secret(for: key)
            known.withLock { $0[key] = .some(value) }
            return value
        } catch {
            return nil
        }
    }

    private func setSecret(_ value: String?, for key: String) throws {
        // If the store fails, what it now holds isn't known.
        known.withLock { $0[key] = nil }
        try secrets.setSecret(value, for: key)
        known.withLock { $0[key] = .some(value) }
    }

    // MARK: - Folders

    /// Defaults to wherever OpenEmu itself keeps its library.
    public var openEmuLibrary: URL {
        get {
            defaults.string(forKey: Keys.openEmuLibrary).map { URL(filePath: $0, directoryHint: .isDirectory) }
                ?? Self.openEmuDefaultLibrary
        }
        set { defaults.set(newValue.path(percentEncoded: false), forKey: Keys.openEmuLibrary) }
    }

    /// Every ROM folder an Import reads, in the Data folder.
    public var romFolders: [ROMFolder] { folder.romFolders }

    /// Backups into `Backups/` in the Data folder.
    public func backups() -> Backups { Backups(folder: folder.backups) }

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
    }
}
