import Foundation
import Testing

@testable import JournalCore

@Suite struct SettingsTests {
    let secrets = InMemorySecretStore()
    let defaults: UserDefaults

    init() {
        let suite = "journal-tests-\(UUID().uuidString)"
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

    @Test func foldersHaveDefaultsAndCanBeChanged() {
        let s = settings()
        #expect(s.backupFolder.path(percentEncoded: false).hasSuffix("/Dropbox/Games Journal Backups/"))
        #expect(s.openEmuLibrary == AppSettings.openEmuDefaultLibrary)

        s.backupFolder = URL(filePath: "/tmp/journal backups", directoryHint: .isDirectory)
        s.openEmuLibrary = URL(filePath: "/tmp/OpenEmu Library", directoryHint: .isDirectory)

        #expect(settings().backupFolder.path(percentEncoded: false) == "/tmp/journal backups/")
        #expect(settings().openEmuLibrary.path(percentEncoded: false) == "/tmp/OpenEmu Library/")
    }
}

@Suite struct KeychainTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "CI runners have no unlocked login keychain"))
    func aSecretRoundTripsThroughTheKeychain() throws {
        let store = KeychainSecretStore(service: "org.danielholmes.GamesJournal.tests.\(UUID().uuidString)")
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
