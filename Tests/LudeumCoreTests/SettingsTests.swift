import Foundation
import Synchronization
import Testing

@testable import LudeumCore

@Suite struct SettingsTests {
    let secrets = InMemorySecretStore()
    let defaults: UserDefaults

    init() {
        let suite = "ludeum-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func settings() -> AppSettings { AppSettings(secrets: secrets, defaults: defaults) }

    @Test func withNoCredentialsSettingsAreNeeded() {
        #expect(settings().igdbCredentials == nil)
        #expect(settings().needsCredentials)
    }

    @Test func credentialsAreKeptInTheSecretStoreAndSurviveARelaunch() throws {
        try settings().setIGDBCredentials(IGDBCredentials(clientID: "id", clientSecret: "secret"))

        let relaunched = settings()

        #expect(relaunched.igdbCredentials?.clientID == "id")
        #expect(relaunched.igdbCredentials?.clientSecret == "secret")
        #expect(!relaunched.needsCredentials)
        #expect(defaults.dictionaryRepresentation().values.allSatisfy { ($0 as? String) != "secret" })
    }

    @Test func blankCredentialsAreCleared() throws {
        try settings().setIGDBCredentials(IGDBCredentials(clientID: "id", clientSecret: "secret"))

        try settings().setIGDBCredentials(IGDBCredentials(clientID: " ", clientSecret: ""))

        #expect(settings().igdbCredentials == nil)
    }

    @Test func theHasheousKeyIsOptional() throws {
        #expect(settings().hasheousKey == nil)
        try settings().setHasheousKey("key")
        #expect(settings().hasheousKey == "key")
        try settings().setHasheousKey("")
        #expect(settings().hasheousKey == nil)
    }

    @Test func openEmusLibraryHasADefaultAndCanBeChanged() {
        let s = settings()
        #expect(s.openEmuLibrary == AppSettings.openEmuDefaultLibrary)

        s.openEmuLibrary = URL(filePath: "/tmp/OpenEmu Library", directoryHint: .isDirectory)

        #expect(settings().openEmuLibrary.path(percentEncoded: false) == "/tmp/OpenEmu Library/")
    }

    @Test func theROMFoldersAndBackupsAreInTheDataFolderWhateverOldSettingsSay() {
        defaults.set("/old/games", forKey: "romFoldersRoot")
        defaults.set("/old/PS2", forKey: "ps2Folder")
        defaults.set("/old/backups", forKey: "backupFolder")
        let folder = LudeumFolder(url: URL(filePath: "/tmp/Ludeum", directoryHint: .isDirectory))

        let s = AppSettings(secrets: secrets, defaults: defaults, folder: folder)

        #expect(s.romFolders.first { $0.platformId == ROMPlatform.ps2 }?.url.path(percentEncoded: false) == "/tmp/Ludeum/Data/ROMs/PS2/")
        #expect(s.romFolders.first { $0.platformId == 19 }?.url.path(percentEncoded: false) == "/tmp/Ludeum/Data/ROMs/SNES/")
        #expect(s.backups().folder.path(percentEncoded: false) == "/tmp/Ludeum/Data/Backups/")
    }
}

@Suite struct KeychainTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "CI runners have no unlocked login keychain"))
    func aSecretRoundTripsThroughTheKeychain() throws {
        let store = KeychainSecretStore(service: "org.danielholmes.Ludeum.tests.\(UUID().uuidString)")
        defer { try? store.setSecret(nil, for: "k") }

        try store.setSecret("one", for: "k")
        try store.setSecret("two", for: "k")
        #expect(try store.secret(for: "k") == "two")

        try store.setSecret(nil, for: "k")
        #expect(try store.secret(for: "k") == nil)
    }
}

@Suite struct TwitchTokenInSecretStoreTests {
    @Test func theTokenIsKeptInTheSecretStoreAndReusedAfterARelaunch() async throws {
        let h = try Harness()
        let secrets = InMemorySecretStore()
        func client() -> IGDBClient {
            IGDBClient(
                credentials: IGDBCredentials(clientID: "client", clientSecret: "secret"), cache: h.cache,
                transport: h.internet, clock: h.clock, tokenStore: secrets)
        }
        for id in 1...2 { h.internet.addGame(id, "Game \(id)") }
        _ = try await client().games(ids: [1])

        _ = try await client().games(ids: [2])

        #expect(h.internet.tokensIssued == 1)
        #expect(try h.cache.entries(["twitch:token:client"]).isEmpty)
        #expect(try secrets.secret(for: "twitch-token:client") != nil)
    }
}

@Suite struct ConnectionCheckTests {
    @Test func reportsWhatIGDBAndHasheousAnswered() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World", normallySeconds: 36_000)
        h.internet.addSearch("Super Mario World", platform: 19, results: [1070])
        h.internet.addHash(md5: ConnectionCheck.hasheousReferenceMD5, game: 99, platform: 15)

        let report = try await ConnectionCheck.run(igdb: h.igdb, hasheous: h.hasheous)

        #expect(report.igdbGameName == "Super Mario World")
        #expect(report.hasheousGameID == 99)
        #expect(report.summary.contains("Super Mario World"))
    }

    @Test func failsWhenIGDBRejectsTheCredentials() async throws {
        let h = try Harness()
        h.internet.setDown(FakeInternet.Hosts.twitch, true)

        await #expect(throws: (any Error).self) { try await ConnectionCheck.run(igdb: h.igdb, hasheous: h.hasheous) }
    }
}

/// A secret store that counts its reads, and can be made to fail them.
private final class CountedSecretStore: SecretStore {
    struct Unreadable: Error {}
    private let secrets = InMemorySecretStore()
    private let state = Mutex((reads: 0, unreadable: false))

    var reads: Int { state.withLock { $0.reads } }
    func setUnreadable(_ unreadable: Bool) { state.withLock { $0.unreadable = unreadable } }

    func secret(for key: String) throws -> String? {
        let unreadable = state.withLock { s in
            s.reads += 1
            return s.unreadable
        }
        if unreadable { throw Unreadable() }
        return try secrets.secret(for: key)
    }

    func setSecret(_ value: String?, for key: String) throws { try secrets.setSecret(value, for: key) }
}

/// Screens ask for the credentials constantly, and each read of the Keychain is a trip out of the app.
@Suite struct SecretsReadOnceTests {
    private let secrets = CountedSecretStore()
    let defaults = UserDefaults(suiteName: "ludeum-tests-\(UUID().uuidString)")!

    func settings() -> AppSettings { AppSettings(secrets: secrets, defaults: defaults) }

    @Test func eachSecretIsReadFromTheStoreOnceHoweverOftenItsAskedFor() throws {
        try settings().setIGDBCredentials(IGDBCredentials(clientID: "id", clientSecret: "secret"))
        let relaunched = settings()

        for _ in 1...5 {
            #expect(relaunched.igdbCredentials == IGDBCredentials(clientID: "id", clientSecret: "secret"))
            #expect(relaunched.hasheousKey == nil)
        }

        #expect(secrets.reads == 3)
    }

    @Test func aSecretJustSetIsWhatsReadNext() throws {
        let s = settings()
        try s.setIGDBCredentials(IGDBCredentials(clientID: "id", clientSecret: "secret"))
        #expect(s.igdbCredentials?.clientID == "id")

        try s.setIGDBCredentials(IGDBCredentials(clientID: "new id", clientSecret: "new secret"))
        try s.setHasheousKey("key")

        #expect(s.igdbCredentials == IGDBCredentials(clientID: "new id", clientSecret: "new secret"))
        #expect(s.hasheousKey == "key")
        try s.setIGDBCredentials(IGDBCredentials(clientID: "", clientSecret: ""))
        #expect(s.igdbCredentials == nil)
    }

    @Test func aReadThatFailedIsTriedAgain() throws {
        try settings().setIGDBCredentials(IGDBCredentials(clientID: "id", clientSecret: "secret"))
        let relaunched = settings()
        secrets.setUnreadable(true)
        #expect(relaunched.igdbCredentials == nil)

        secrets.setUnreadable(false)

        #expect(relaunched.igdbCredentials?.clientID == "id")
    }
}
