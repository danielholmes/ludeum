import Foundation
import GRDB
import LudeumCore

/// Runs the matcher over a snapshot of OpenEmu's database and prints the counts the spec
/// expects for the first Import: Automatic, suggestions by kind, nothing, and Duplicate Versions.
func matchReport(snapshot: URL, igdb: IGDBClient, hasheous: HasheousClient) async throws {
    var config = Configuration()
    config.readonly = true
    let db = try DatabaseQueue(path: snapshot.path(percentEncoded: false), configuration: config)
    let libraryPath =
        (UserDefaults(suiteName: "org.openemu.OpenEmu")?.string(forKey: "databasePath")
        ?? "~/Library/Application Support/OpenEmu/Game Library") as NSString
    let romsFolder = URL(filePath: libraryPath.expandingTildeInPath, directoryHint: .isDirectory).appending(path: "roms")
    let roms: [OpenEmuROM] = try await db.read { db in
        try Row.fetchAll(
            db,
            sql: """
                SELECT r.Z_PK AS id, g.ZNAME AS name, g.ZGAMETITLE AS title, s.ZSYSTEMIDENTIFIER AS system,
                       r.ZMD5 AS md5, r.ZLOCATION AS location
                FROM ZROM r JOIN ZGAME g ON r.ZGAME = g.Z_PK JOIN ZSYSTEM s ON g.ZSYSTEM = s.Z_PK
                """
        ).map { row in
            let location: String? = row["location"]
            let file = location.flatMap { loc in
                loc.hasPrefix("file://") ? URL(string: loc) : loc.removingPercentEncoding.map { romsFolder.appending(path: $0) }
            }
            return OpenEmuROM(
                id: row["id"], name: row["name"] ?? "", openVGDBTitle: row["title"], system: row["system"],
                md5: (row["md5"] as String?)?.lowercased() ?? "", file: file)
        }
    }
    print("\(roms.count) ROMs")

    let results = try await Matcher(igdb: igdb, hasheous: hasheous).match(roms)
    var counts: [String: Int] = [:]
    for result in results.values {
        let key =
            switch result {
            case .automatic: "Automatic"
            case .suggestion(let s): "\(s.source) suggestion, names \(s.namesAgree ? "agree" : "disagree")"
            case .noSuggestion: "No suggestion"
            }
        counts[key, default: 0] += 1
    }
    for (key, n) in counts.sorted(by: { $0.key < $1.key }) { print("  \(key): \(n)") }

    // Duplicate Versions among the Games of Automatic Matches and bulk-confirmable suggestions.
    var byGame: [String: [GameROM]] = [:]
    for rom in roms {
        let gameID: Int? =
            switch results[rom.id] {
            case .automatic(let id): id
            case .suggestion(let s) where s.namesAgree: s.gameID
            default: nil
            }
        guard let gameID, let file = rom.file else { continue }
        let present = FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        byGame["\(gameID) \(rom.system)", default: []].append(
            GameROM(id: rom.id, name: rom.name, isPlaylist: file.pathExtension.lowercased() == "m3u", isPresent: present))
    }
    let duplicates = byGame.filter { hasDuplicateVersions($0.value) }.sorted { $0.key < $1.key }
    print("Duplicate Versions: \(duplicates.count)")
    for (_, roms) in duplicates {
        print("  " + roms.filter(\.isPresent).map { "\($0.name) [\(ROMName($0.name).version)]" }.joined(separator: " ≠ "))
    }
}
