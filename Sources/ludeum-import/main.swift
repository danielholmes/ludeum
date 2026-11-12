import AppKit
import Foundation
import LudeumCore

// ludeum-import: command-line tools on top of LudeumCore.
//
//   ludeum-import check                    Live check of IGDB and Hasheous through the real cache.
//   ludeum-import mobile-attachments [--run]
//                                          Makes Legacy Mobile Device Games' jar Attachments ROMs (ADR 0044): once, then goes.
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

func mobileAttachments(run: Bool) async throws {
    // Each line as it happens, even into a file and even if the run stops short.
    setvbuf(stdout, nil, _IOLBF, 0)
    requireDataFolder()
    // Its launch clears the ROM folders' work folders, where the ROMs are being made, and its Import would find them half
    // made.
    if run, !NSRunningApplication.runningApplications(withBundleIdentifier: "org.danielholmes.Ludeum").isEmpty {
        fail("Quit Ludeum first, and keep it closed until this is done.")
    }
    let ludeum = LudeumFolder.standard
    guard let url = ludeum.romFolder(platform: ROMPlatform.legacyMobile), let folder = ROMFolder.platform(ROMPlatform.legacyMobile, url)
    else { fail("No Legacy Mobile Device ROM folder.") }
    let backups = Backups(folder: ludeum.backups)
    let journal = try LudeumStore(directory: ludeum.url, backups: backups)
    let migration = MobileAttachmentsMigration(journal: journal, ludeum: ludeum, folder: folder)
    let plan = try migration.plan()
    for rom in plan.roms {
        let what = rom.jars.count > 1 ? "\(rom.name)/ of \(rom.jars.count) Discs" : "\(rom.name).jar"
        print("\(rom.gameName): \(rom.jars.map(\.lastPathComponent).joined(separator: " + "))  →  \(what)")
    }
    for left in plan.left { print("leave \(left.what): \(left.why)") }
    print("\(plan.roms.count) ROMs to make, \(plan.left.count) left")
    guard run else {
        print("A plan: nothing was changed. Run again with --run, with Ludeum closed.")
        return
    }
    try await migration.run(plan) { print($0) }
    print("Done.")
}

switch CommandLine.arguments.dropFirst().first {
case "check": try await check()
case "mobile-attachments": try await mobileAttachments(run: CommandLine.arguments.contains("--run"))
default:
    fail("usage: ludeum-import check | mobile-attachments [--run]")
}
