import Foundation
import LudeumCore

// ludeum-import: command-line tools on top of LudeumCore.
//
//   ludeum-import check                    Live check of IGDB and Hasheous through the real cache.
//   ludeum-import migrate-openemu [--dry-run] [--journal <folder>] [--library <folder>] [--data <folder>]
//                                           Moves OpenEmu's ROMs into ROM folders, once (OpenEmu closed).
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

/// Where the Data folder resolves to; without it, refuses with the same words as the app's sheet.
@discardableResult
func requireDataFolder(_ folder: LudeumFolder = .standard) -> URL {
    do {
        return try folder.checkData()
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

switch CommandLine.arguments.dropFirst().first {
case "check": try await check()
case "migrate-openemu":
    try await migrateOpenEmuRun(Array(CommandLine.arguments.dropFirst(2)))
default:
    fail("usage: ludeum-import check | \(migrateOpenEmuUsage)")
}
