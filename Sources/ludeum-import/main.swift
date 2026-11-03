import AppKit
import Foundation
import LudeumCore

// ludeum-import: command-line tools on top of LudeumCore.
//
//   ludeum-import check                    Live check of IGDB and Hasheous through the real cache.
//   ludeum-import mesence [--run]          Moves MesenCE's own saves into the Data folder (ADR 0027): once, then goes.
//   ludeum-import gamecube-discs [--run]   Makes each multi-disc GameCube Version one ROM (ADR 0031): once, then goes.
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

/// Makes each multi-disc GameCube Version one ROM, a folder of its Discs with a playlist (ADR 0031): a plan unless
/// `--run`. Once, with Ludeum closed; Dropbox brings down any Disc it keeps online only. Then this command goes.
func gameCubeDiscs(run: Bool) async throws {
    // Each line as it happens, even into a file and even if the run stops short.
    setvbuf(stdout, nil, _IOLBF, 0)
    requireDataFolder()
    // Its launch clears the ROM folders' work folders, where an Archive is being written, and its Import would find the
    // Discs half moved.
    if run, !NSRunningApplication.runningApplications(withBundleIdentifier: "org.danielholmes.Ludeum").isEmpty {
        fail("Quit Ludeum first, and keep it closed until this is done.")
    }
    let ludeum = LudeumFolder.standard
    guard let url = ludeum.romFolder(platform: 21), let folder = ROMFolder.platform(21, url) else { fail("No GameCube ROM folder.") }
    let archiver: ROMArchiver
    do { archiver = try ROMArchiver.installed() } catch { fail(error.localizedDescription) }
    let backups = Backups(folder: ludeum.backups)
    let journal = try LudeumStore(directory: ludeum.url, backups: backups)
    let migration = GameCubeDiscsMigration(journal: journal, folder: folder, archiver: archiver, backups: backups)
    let plan = try migration.plan()
    for merge in plan.merges {
        let discs = merge.discs.map(\.name).joined(separator: " + ")
        let already = merge.gathered ? " (its Discs already in its folder)" : ""
        print("merge \(merge.game): \(discs)  →  \(merge.name)\(merge.archived ? ".7z" : "/"), keeping ROM \(merge.discs[0].id)\(already)")
    }
    for left in plan.left { print("leave \(left.rom): \(left.why)") }
    print("\(plan.merges.count) to merge, \(plan.left.count) left")
    guard run else {
        print("A plan: nothing was changed. Run again with --run, with Ludeum closed.")
        return
    }
    try await migration.run(plan) { print($0) }
    print("Done.")
}

switch CommandLine.arguments.dropFirst().first {
case "check": try await check()
case "mesence": try await mesence(run: CommandLine.arguments.contains("--run"))
case "gamecube-discs": try await gameCubeDiscs(run: CommandLine.arguments.contains("--run"))
default:
    fail("usage: ludeum-import check | mesence [--run] | gamecube-discs [--run]")
}
