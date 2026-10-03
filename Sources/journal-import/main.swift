import Foundation
import JournalCore

// journal-import: command-line tools on top of JournalCore.
//
//   journal-import check                    Live check of IGDB and Hasheous through the real cache.
//   journal-import match-report <snapshot>  Match a snapshot of OpenEmu's database and print the counts.
//   journal-import first-import <library> <journal folder> [--commit]
//                                           The first Import into a scratch journal (OpenEmu is only read).
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
    let (igdb, hasheous) = try clients()
    print("cache: \(cacheDirectory.path(percentEncoded: false))")
    // The same check as Settings' "Test connection".
    print(try await ConnectionCheck.run(igdb: igdb, hasheous: hasheous).summary)
}

switch CommandLine.arguments.dropFirst().first {
case "check": try await check()
case "match-report" where CommandLine.arguments.count == 3:
    let (igdb, hasheous) = try clients()
    try await matchReport(snapshot: URL(filePath: CommandLine.arguments[2]), igdb: igdb, hasheous: hasheous)
case "first-import" where CommandLine.arguments.count >= 4:
    let (igdb, hasheous) = try clients()
    try await firstImportRun(
        library: URL(filePath: CommandLine.arguments[2], directoryHint: .isDirectory),
        journalFolder: URL(filePath: CommandLine.arguments[3], directoryHint: .isDirectory),
        commit: CommandLine.arguments.contains("--commit"), igdb: igdb, hasheous: hasheous)
default: fail("usage: journal-import check | match-report <snapshot.sqlite> | first-import <library> <journal folder> [--commit]")
}
