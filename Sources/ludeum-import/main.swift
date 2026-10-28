import Foundation
import LudeumCore

// ludeum-import: command-line tools on top of LudeumCore.
//
//   ludeum-import check                    Live check of IGDB and Hasheous through the real cache.
//   ludeum-import mesence [--run]          Moves MesenCE's own saves into the Data folder (ADR 0027): once, then goes.
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

/// Moves what MesenCE kept for itself over to the copy Ludeum installs (ADR 0027): a plan unless `--run`. Once, with
/// MesenCE closed and installed from the Emulators sheet; then this command goes.
func mesence(run: Bool) async throws {
    requireDataFolder()
    guard MesenSettings().isInstalled else { fail("Install MesenCE from Ludeum ▸ Emulators… first.") }
    guard let sevenZip = SevenZip.find() else { fail("7-Zip isn't installed: brew install sevenzip") }
    let migration = MesenMigration(sevenZip: sevenZip)
    let plan = try await migration.plan()
    for move in plan.moves {
        print("move  \(move.from.lastPathComponent)  →  \(move.to.deletingLastPathComponent().path(percentEncoded: false))")
    }
    for copy in plan.firmware { print("copy  Firmware/\(copy.from.lastPathComponent)") }
    for rename in plan.innerRenames {
        print("name  \(rename.archive.lastPathComponent): \(rename.path)  →  \(rename.to), its saves following")
    }
    for left in plan.left { print("leave \(left.file): \(left.why)") }
    for unread in plan.unread { print("unread \(unread): online only in Dropbox") }
    print(
        "\(plan.moves.count) to move, \(plan.firmware.count) Firmware to copy, \(plan.innerRenames.count) archives' files to name, "
            + "\(plan.left.count) left, \(plan.unread.count) unread")
    guard run else {
        print("A plan: nothing was changed. Run again with --run, with MesenCE closed.")
        return
    }
    for left in try await migration.run(plan) { print("leave \(left.file): \(left.why)") }
    print("Done.")
}

switch CommandLine.arguments.dropFirst().first {
case "check": try await check()
case "mesence": try await mesence(run: CommandLine.arguments.contains("--run"))
default:
    fail("usage: ludeum-import check | mesence [--run]")
}
