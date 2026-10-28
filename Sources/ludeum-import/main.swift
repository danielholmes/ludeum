import Foundation
import LudeumCore

// ludeum-import: command-line tools on top of LudeumCore.
//
//   ludeum-import check                    Live check of IGDB and Hasheous through the real cache.
//   ludeum-import duckstation-cards [--run] One-off (ADR 0024): Serial-named memory cards take DuckStation's names, and
//                                          per-game files lose what every Play used to write. A plan unless --run.
//   ludeum-import checksums [--run]        One-off (#80): every present ROM's checksum becomes what an Import would
//                                          read today, replacing OpenEmu's MD5s. A plan unless --run.
//
// Every command first needs the Data folder, and refuses without it in the app's words.
// Credentials come from the environment or a .env file in the current directory
// (see scripts/setup-igdb.sh).

func loadEnv() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let file = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: ".env")
    if let text = try? String(contentsOf: file, encoding: .utf8) {
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, env[parts[0]] == nil { env[parts[0]] = parts[1] }
        }
    }
    return env
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Without the Data folder, refuses with the same words as the app's sheet.
func requireDataFolder() {
    do {
        try LudeumFolder.standard.checkData()
    } catch {
        fail(error.remedy)
    }
}

let cacheDirectory = CacheStore.defaultDirectory

func clients() throws -> (IGDBClient, HasheousClient) {
    let env = loadEnv()
    guard let clientID = env["IGDB_CLIENT_ID"], let secret = env["IGDB_CLIENT_SECRET"] else {
        fail("IGDB_CLIENT_ID / IGDB_CLIENT_SECRET not set; run scripts/setup-igdb.sh")
    }
    let cache = try CacheStore(directory: cacheDirectory)
    let igdb = IGDBClient(credentials: IGDBCredentials(clientID: clientID, clientSecret: secret), cache: cache)
    return (igdb, HasheousClient(cache: cache, apiKey: env["HASHEOUS_API_KEY"]))
}

func check() async throws {
    requireDataFolder()
    let (igdb, hasheous) = try clients()
    print("cache: \(cacheDirectory.path(percentEncoded: false))")
    // The same check as Settings' "Test connection".
    print(try await ConnectionCheck.run(igdb: igdb, hasheous: hasheous).summary)
}

/// Once the DuckStation Ludeum installs is there and scripts/migrate-duckstation.sh has moved its folders into the Data
/// folder. With Ludeum and DuckStation closed. To go once it has run.
func duckStationCards(run: Bool) throws {
    requireDataFolder()
    let ludeum = LudeumFolder.standard
    let duckStation = DuckStationSettings(ludeum: ludeum)
    guard duckStation.isInstalled, duckStation.isPortable else { fail("Install DuckStation from Ludeum ▸ Emulators… first.") }
    try duckStation.writeStanding()
    let journal = try LudeumStore(directory: ludeum.url, backups: Backups(folder: ludeum.backups))
    let migration = DuckStationCardMigration(
        journal: journal, duckStation: duckStation, resources: DuckStationMemoryCards.resources(of: duckStation.app))
    let actions = run ? try migration.run() : try migration.plan()
    for action in actions { print(action) }
    print(actions.isEmpty ? "Nothing to do." : run ? "Done: \(actions.count)." : "A plan: \(actions.count). Run again with --run to do it.")
}

/// With Ludeum closed, and the ROM folders' files on disk (Dropbox's online-only ones are left). Reads every present
/// ROM, so it takes a while either way. To go once it has run.
func checksums(run: Bool) async throws {
    requireDataFolder()
    guard let sevenZip = SevenZip.find() else {
        fail("\(SystemTool.sevenZip.name) isn't installed. Install it with `\(SystemTool.sevenZip.install)`.")
    }
    let ludeum = LudeumFolder.standard
    let backups = Backups(folder: ludeum.backups)
    let journal = try LudeumStore(directory: ludeum.url, backups: backups)
    let migration = ChecksumMigration(journal: journal, romFolders: ludeum.romFolders, sevenZip: sevenZip, backups: backups)
    let plan = run ? try await migration.run() : try await migration.plan()
    for line in plan.lines { print(line) }
    let count = plan.changes.count
    print(
        count == 0 ? "Nothing to change." : run ? "Done: \(count) changed." : "A plan: \(count) to change. Run again with --run to do it.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "check": try await check()
case "duckstation-cards": try duckStationCards(run: arguments.contains("--run"))
case "checksums": try await checksums(run: arguments.contains("--run"))
default:
    fail("usage: ludeum-import check | duckstation-cards [--run] | checksums [--run]")
}
