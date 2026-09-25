import Foundation
import JournalCore

// journal-import: command-line tools on top of JournalCore.
//
//   journal-import check    Live check of IGDB and Hasheous through the real cache.
//
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

let cacheDirectory = URL.applicationSupportDirectory.appending(path: "GamesJournal/cache", directoryHint: .isDirectory)

func check() async throws {
    let env = loadEnv()
    guard let clientID = env["IGDB_CLIENT_ID"], let secret = env["IGDB_CLIENT_SECRET"] else {
        fail("IGDB_CLIENT_ID / IGDB_CLIENT_SECRET not set; run scripts/setup-igdb.sh")
    }
    let cache = try CacheStore(directory: cacheDirectory)
    let igdb = IGDBClient(credentials: IGDBCredentials(clientID: clientID, clientSecret: secret), cache: cache)
    let hasheous = HasheousClient(cache: cache, apiKey: env["HASHEOUS_API_KEY"])
    print("cache: \(cacheDirectory.path(percentEncoded: false))")

    let search = IGDBSearch(name: "Super Mario World", platformID: 19)  // 19 = SNES
    let ids = try await igdb.search([search])[search] ?? []
    print("IGDB search '\(search.name)' on SNES → \(ids.prefix(5))")
    guard let first = ids.first, let game = try await igdb.games(ids: [first])[first] else { fail("no IGDB result") }
    print(
        "  \(game.name ?? "?"): \(game.record["screenshots"]?.array?.count ?? 0) screenshots, "
            + "\(game.record["artworks"]?.array?.count ?? 0) artworks, "
            + "time to beat (normally): \(game.timeToBeat?["normally"]?.int.map { "\($0 / 3600)h" } ?? "n/a")")
    if let coverID = game.record["cover"]?["image_id"]?.string {
        print("  cover → \(try await igdb.cover(imageID: coverID).path(percentEncoded: false))")
    }

    // A public reference hash from Hasheous's own docs (Jumpman Junior, C64).
    let result = try await hasheous.lookup(md5: "5d7550788a4d1b47ad81fbbbf5c615a9")
    print(
        "Hasheous 5d7550…c615a9 → IGDB game \(result.match?.igdbGameID.map(String.init) ?? "none"), "
            + "platform \(result.match?.igdbPlatformID.map(String.init) ?? "none")")
}

switch CommandLine.arguments.dropFirst().first {
case "check": try await check()
default: fail("usage: journal-import check")
}
