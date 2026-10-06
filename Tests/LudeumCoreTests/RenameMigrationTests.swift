import Foundation
import Testing

@testable import LudeumCore

@Suite struct RenameMigrationTests {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "rename tests \(UUID().uuidString)", directoryHint: .isDirectory)
    let oldSecrets = InMemorySecretStore()
    let newSecrets = InMemorySecretStore()
    let oldDefaults: UserDefaults
    let newDefaults: UserDefaults

    init() {
        oldDefaults = UserDefaults(suiteName: "ludeum-tests-\(UUID().uuidString)")!
        newDefaults = UserDefaults(suiteName: "ludeum-tests-\(UUID().uuidString)")!
    }

    var oldApp: URL { root.appending(path: "GamesJournal", directoryHint: .isDirectory) }
    var newApp: URL { root.appending(path: "Ludeum", directoryHint: .isDirectory) }
    func migrate() {
        RenameMigration(
            oldAppFolder: oldApp, newAppFolder: newApp, oldDefaults: oldDefaults,
            oldSecrets: oldSecrets, settings: AppSettings(secrets: newSecrets, defaults: newDefaults)
        ).run()
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func theAppFolderMovesToItsNewName() throws {
        try write("mine", to: oldApp.appending(path: "journal.sqlite"))

        migrate()

        #expect(try String(contentsOf: newApp.appending(path: "journal.sqlite"), encoding: .utf8) == "mine")
        #expect(!FileManager.default.fileExists(atPath: oldApp.path(percentEncoded: false)))
    }

    @Test func anExistingNewAppFolderIsNeverOverwritten() throws {
        try write("old", to: oldApp.appending(path: "journal.sqlite"))
        try write("new", to: newApp.appending(path: "journal.sqlite"))

        migrate()

        #expect(try String(contentsOf: newApp.appending(path: "journal.sqlite"), encoding: .utf8) == "new")
    }

    @Test func settingsAndSecretsCarryOverWithoutReplacingNewOnes() throws {
        oldDefaults.set("/old/openemu", forKey: "openEmuLibrary")
        try oldSecrets.setSecret("id", for: "igdb-client-id")
        try oldSecrets.setSecret("secret", for: "igdb-client-secret")
        try oldSecrets.setSecret("old key", for: "hasheous-api-key")
        try newSecrets.setSecret("new key", for: "hasheous-api-key")

        migrate()

        #expect(newDefaults.string(forKey: "openEmuLibrary") == "/old/openemu")
        #expect(try newSecrets.secret(for: "igdb-client-id") == "id")
        #expect(try newSecrets.secret(for: "igdb-client-secret") == "secret")
        #expect(try newSecrets.secret(for: "hasheous-api-key") == "new key")
    }

}
