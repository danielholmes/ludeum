// ─────────────────────────────────────────────────────────────────────────────
// PROTOTYPE: throwaway. Answers one question: "how much manual work will the
// first Import take?" It is not the real Import and must not grow into it.
//
// It reads a snapshot of the OpenEmu library (never the live file), matches every
// ROM (Hasheous by MD5 → IGDB, header-stripped retry, then IGDB name search),
// and writes a report of auto-links, the would-be Review queue, and Duplicate
// Versions. Everything external goes through the JournalCore cache, so re-runs
// are fast and don't hit the services again.
// ─────────────────────────────────────────────────────────────────────────────

import CryptoKit
import Foundation
import GRDB
import JournalCore

private struct OERom {
    let romPK: Int
    let name: String  // ZGAME.ZNAME (usually the No-Intro style file name)
    let title: String?  // ZGAME.ZGAMETITLE (from OpenVGDB)
    let system: String  // e.g. openemu.system.snes
    let md5: String
    let file: URL?
}

private enum Outcome {
    case hashMatch(game: Int, platform: Int?, headerStripped: Bool)
    case suggestion(ids: [Int], platform: Int)  // Review queue: name-search suggestion
    case nothing  // Review queue: no suggestion at all
}

/// OpenEmu system → IGDB platform ids, most likely first (GB includes GBC games,
/// SNES/NES include Japanese Super Famicom/Famicom releases).
let igdbPlatforms: [String: [Int]] = [
    "openemu.system.gb": [33, 22], "openemu.system.snes": [19, 58], "openemu.system.nes": [18, 99],
    "openemu.system.psx": [7], "openemu.system.sg": [29], "openemu.system.gba": [24],
    "openemu.system.nds": [20], "openemu.system.psp": [38], "openemu.system.n64": [4],
    "openemu.system.gc": [21], "openemu.system.sms": [64], "openemu.system.scd": [78],
    "openemu.system.saturn": [32], "openemu.system.gg": [35], "openemu.system.pcecd": [150],
]

func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// "Lost Vikings, The (U) [!]" → "The Lost Vikings"; "Foo - Bar (USA)" → "Foo: Bar".
func cleanName(_ raw: String) -> String {
    var s = raw.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
    s = s.trimmingCharacters(in: .whitespaces)
    if let r = s.range(of: #", (The|A|An)\b"#, options: .regularExpression) {
        let article = s[r].dropFirst(2)
        s = "\(article) " + s.replacingCharacters(in: r, with: "")
    }
    return s.replacingOccurrences(of: " - ", with: ": ")
}

/// Online-only (Dropbox File Provider) files are "dataless": reading them would download them.
func isLocal(_ url: URL) -> Bool {
    var st = stat()
    guard lstat(url.path(percentEncoded: false), &st) == 0 else { return false }
    return st.st_flags & 0x4000_0000 == 0  // SF_DATALESS
}

/// The ROM bytes: read directly, or unpacked in memory from a small single-file
/// .7z/.zip with the system's libarchive `tar`. Only called for files already on disk.
func romData(_ url: URL) -> Data? {
    guard ["7z", "zip"].contains(url.pathExtension.lowercased()) else { return try? Data(contentsOf: url) }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
    guard size < 16 << 20 else { return nil }
    func tar(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/tar")
        p.arguments = args + [url.path(percentEncoded: false)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
    let entries = tar(["-tf"]).map { String(decoding: $0, as: UTF8.self).split(separator: "\n") } ?? []
    guard entries.count == 1 else { return nil }
    return tar(["-xOf"])
}

/// MD5 of a headered NES/SNES dump with its header removed, if it has one.
func headerlessMD5(_ url: URL, system: String) -> String? {
    guard let data = romData(url) else { return nil }
    let body: Data
    if system == "openemu.system.nes", data.starts(with: [0x4E, 0x45, 0x53, 0x1A]) {
        body = data.dropFirst(16)
    } else if system == "openemu.system.snes", data.count % 1024 == 512 {
        body = data.dropFirst(512)
    } else {
        return nil
    }
    return Insecure.MD5.hash(data: body).map { String(format: "%02x", $0) }.joined()
}

func prototypeFirstImport(igdb: IGDBClient, hasheous: HasheousClient, outputDirectory: URL) async throws {
    // 1. Snapshot the live library with SQLite's backup API (safe while OpenEmu runs).
    let libraryPath =
        (UserDefaults(suiteName: "org.openemu.OpenEmu")?.string(forKey: "databasePath")
        ?? "~/Library/Application Support/OpenEmu/Game Library") as NSString
    let library = URL(filePath: libraryPath.expandingTildeInPath, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    var config = Configuration()
    config.readonly = true
    let live = try DatabaseQueue(path: library.appending(path: "Library.storedata").path(percentEncoded: false), configuration: config)
    let snapshot = try DatabaseQueue(
        path: outputDirectory.appending(path: "PROTOTYPE-wipe-me-openemu-snapshot.sqlite").path(percentEncoded: false))
    try live.backup(to: snapshot)

    let roms: [OERom] = try await snapshot.read { db in
        try Row.fetchAll(
            db,
            sql: """
                SELECT r.Z_PK AS pk, g.ZNAME AS name, g.ZGAMETITLE AS title, s.ZSYSTEMIDENTIFIER AS system,
                       r.ZMD5 AS md5, r.ZLOCATION AS location
                FROM ZROM r JOIN ZGAME g ON r.ZGAME = g.Z_PK JOIN ZSYSTEM s ON g.ZSYSTEM = s.Z_PK
                ORDER BY s.ZSYSTEMIDENTIFIER, g.ZNAME
                """
        ).map { row in
            let location: String? = row["location"]
            let file: URL? = location.flatMap { loc in
                loc.hasPrefix("file://")
                    ? URL(string: loc)
                    : loc.removingPercentEncoding.map { library.appending(path: "roms").appending(path: $0) }
            }
            return OERom(
                romPK: row["pk"], name: row["name"] ?? "?", title: row["title"], system: row["system"],
                md5: (row["md5"] as String?)?.lowercased() ?? "", file: file)
        }
    }
    log("\(roms.count) ROMs in the OpenEmu library")

    // 2. Hasheous by OpenEmu's MD5, with a header-stripped retry for local, uncompressed NES/SNES files.
    var outcomes: [Int: Outcome] = [:]
    var errors: [Int: String] = [:]
    var hasheousWithoutIGDB = 0
    var archivesSkipped = 0
    for (i, rom) in roms.enumerated() {
        if i % 50 == 0 { log("hasheous \(i)/\(roms.count)…") }
        do {
            let result = try await hasheous.lookup(md5: rom.md5)
            if let game = result.match?.igdbGameID {
                outcomes[rom.romPK] = .hashMatch(game: game, platform: result.match?.igdbPlatformID, headerStripped: false)
                continue
            }
            if result.match != nil { hasheousWithoutIGDB += 1 }
            guard ["openemu.system.nes", "openemu.system.snes"].contains(rom.system), let file = rom.file else { continue }
            guard isLocal(file) else { continue }
            guard let stripped = headerlessMD5(file, system: rom.system) else {
                if ["7z", "zip"].contains(file.pathExtension.lowercased()) { archivesSkipped += 1 }
                continue
            }
            if let game = try await hasheous.lookup(md5: stripped).match?.igdbGameID {
                outcomes[rom.romPK] = .hashMatch(game: game, platform: nil, headerStripped: true)
            }
        } catch {
            errors[rom.romPK] = "\(error)"
        }
    }

    // 3. IGDB name search for everything still unmatched: these would land in the Review queue.
    let unmatched = roms.filter { outcomes[$0.romPK] == nil }
    log("searching IGDB by name for \(unmatched.count) unmatched ROMs…")
    for (i, rom) in unmatched.enumerated() {
        if i % 50 == 0 { log("search \(i)/\(unmatched.count)…") }
        let names = [cleanName(rom.name), rom.title].compactMap { $0 }.filter { !$0.isEmpty }
        outcomes[rom.romPK] = .nothing
        search: for platform in igdbPlatforms[rom.system] ?? [] {
            for name in Set(names) {
                let s = IGDBSearch(name: name, platformID: platform)
                if let ids = try? await igdb.search([s])[s], !ids.isEmpty {
                    outcomes[rom.romPK] = .suggestion(ids: ids, platform: platform)
                    break search
                }
            }
        }
    }

    // 4. Full IGDB records for every matched game and top suggestion (warms the cache too).
    var gameIDs = Set<Int>()
    for o in outcomes.values {
        switch o {
        case .hashMatch(let g, _, _): gameIDs.insert(g)
        case .suggestion(let ids, _): gameIDs.insert(ids[0])
        case .nothing: break
        }
    }
    log("fetching \(gameIDs.count) IGDB game records…")
    let games = try await igdb.games(ids: Array(gameIDs))
    func name(_ id: Int) -> String { games[id]?.name ?? "IGDB #\(id)" }

    // 5. Report.
    let bySystem = Dictionary(grouping: roms, by: \.system)
    var md = "# PROTOTYPE: first Import dry run\n\n"
    md += "Generated \(Date().formatted()). Throwaway output of `journal-import prototype-first-import`.\n\n"
    func count(_ rs: [OERom], _ f: (Outcome) -> Bool) -> Int { rs.filter { outcomes[$0.romPK].map(f) ?? false }.count }
    let isHash: (Outcome) -> Bool = { if case .hashMatch(_, _, false) = $0 { true } else { false } }
    let isStripped: (Outcome) -> Bool = { if case .hashMatch(_, _, true) = $0 { true } else { false } }
    let isSuggestion: (Outcome) -> Bool = { if case .suggestion = $0 { true } else { false } }
    let isNothing: (Outcome) -> Bool = { if case .nothing = $0 { true } else { false } }

    md += "## Summary\n\n| | ROMs |\n|---|---|\n"
    md += "| Total | \(roms.count) |\n"
    md += "| **Automatic** (checksum → IGDB) | \(count(roms, isHash)) |\n"
    md += "| **Automatic** after stripping a header | \(count(roms, isStripped)) |\n"
    md += "| Review queue: name suggestion to confirm | \(count(roms, isSuggestion)) |\n"
    md += "| Review queue: no suggestion (manual search) | \(count(roms, isNothing)) |\n"
    md += "| Hasheous lookups that errored | \(errors.count) |\n\n"
    md += "Also: \(hasheousWithoutIGDB) ROMs were known to Hasheous but had no IGDB link; "
    md += "\(archivesSkipped) unmatched NES/SNES archives had no header to strip or couldn't be unpacked (too big, several files); "
    let files = roms.compactMap(\.file)
    let onlineOnly = files.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) && !isLocal($0) }.count
    let missing = files.filter { !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }.count
    md += "\(onlineOnly) ROM files are online-only in Dropbox; \(missing) ROM files weren't found on disk.\n\n"

    md += "## By system\n\n| System | ROMs | Automatic | Header-stripped | Suggestion | Nothing |\n|---|---|---|---|---|---|\n"
    for (system, rs) in bySystem.sorted(by: { $0.value.count > $1.value.count }) {
        md += "| \(system.replacingOccurrences(of: "openemu.system.", with: "")) | \(rs.count) | \(count(rs, isHash)) "
        md += "| \(count(rs, isStripped)) | \(count(rs, isSuggestion)) | \(count(rs, isNothing)) |\n"
    }

    // Duplicate Versions: ≥2 ROMs matched by checksum to the same IGDB game on the same platform.
    var groups: [String: [OERom]] = [:]
    for rom in roms {
        guard case .hashMatch(let g, let p, _) = outcomes[rom.romPK] else { continue }
        let platform = p ?? igdbPlatforms[rom.system]?.first ?? 0
        groups["\(g):\(platform)", default: []].append(rom)
    }
    let duplicates = groups.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
    md += "\n## Duplicate Versions (\(duplicates.count) Games, must be resolved before the first Import)\n\n"
    for (key, rs) in duplicates {
        md += "- **\(name(Int(key.split(separator: ":")[0])!))** (platform \(key.split(separator: ":")[1])): "
        md += rs.map { "`\($0.name)`" }.joined(separator: ", ") + "\n"
    }

    md += "\n## Review queue: name suggestions\n\n| System | ROM | Top IGDB suggestion | Other candidates |\n|---|---|---|---|\n"
    for rom in roms {
        guard case .suggestion(let ids, _) = outcomes[rom.romPK] else { continue }
        md += "| \(rom.system.replacingOccurrences(of: "openemu.system.", with: "")) | \(rom.name) | \(name(ids[0])) | \(ids.count - 1) |\n"
    }
    md += "\n## Review queue: no suggestion\n\n"
    for rom in roms where { if case .nothing = outcomes[rom.romPK] { true } else { false } }() {
        md += "- \(rom.system.replacingOccurrences(of: "openemu.system.", with: "")): \(rom.name)\n"
    }
    // Suspicious automatic matches: the ROM's name doesn't resemble any IGDB name for the game.
    func norm(_ s: String) -> String {
        cleanName(s).lowercased().replacingOccurrences(of: "&", with: "and").filter { $0.isLetter || $0.isNumber }
    }
    var suspicious: [(OERom, Int, String)] = []
    for rom in roms {
        guard case .hashMatch(let g, _, _) = outcomes[rom.romPK], let game = games[g] else { continue }
        var names = [game.name].compactMap { $0 }
        names += (game.record["alternative_names"]?.array ?? []).compactMap { $0["name"]?.string }
        names += (game.record["game_localizations"]?.array ?? []).compactMap { $0["name"]?.string }
        let romNames = [rom.name, rom.title].compactMap { $0 }.map(norm)
        let matches = names.map(norm).contains { n in romNames.contains { $0 == n } }
        if !matches {
            let method =
                (try? await hasheous.lookup(md5: rom.md5).match?.record["metadata"]?.array?
                    .first { $0["source"]?.string == "IGDB" }?["matchMethod"]?.string) ?? nil
            suspicious.append((rom, g, method ?? "?"))
        }
    }
    md += "\n## Automatic matches whose names differ (\(suspicious.count)): some fine, some wrong\n\n"
    md += "| System | ROM | IGDB game | Hasheous matchMethod |\n|---|---|---|---|\n"
    for (rom, g, method) in suspicious {
        md += "| \(rom.system.replacingOccurrences(of: "openemu.system.", with: "")) | \(rom.name) | \(name(g)) | \(method) |\n"
    }
    // How much of the Review queue could be confirmed in bulk: top suggestion's name equals the ROM's name.
    var exact = 0
    for rom in roms {
        guard case .suggestion(let ids, _) = outcomes[rom.romPK], let game = games[ids[0]] else { continue }
        let names = ([game.name] + (game.record["alternative_names"]?.array ?? []).map { $0["name"]?.string }).compactMap { $0 }
        if names.map(norm).contains(where: { n in [rom.name, rom.title].compactMap { $0 }.map(norm).contains(n) }) { exact += 1 }
    }
    md += "\n## Review queue suggestions that are exact name matches: \(exact) of \(count(roms, isSuggestion))\n"

    // Orphaned OpenEmu entries (file gone) that carry data worth keeping.
    let missingPKs = Set(
        roms.filter { $0.file.map { !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? true }.map(\.romPK))
    let withData: Int = try await snapshot.read { db in
        try Int.fetchOne(
            db,
            sql: """
                SELECT count(DISTINCT r.Z_PK) FROM ZROM r JOIN ZGAME g ON r.ZGAME = g.Z_PK
                LEFT JOIN Z_2GAMES c ON c.Z_7GAMES = g.Z_PK
                WHERE r.Z_PK IN (\(missingPKs.map(String.init).joined(separator: ",")))
                  AND (g.ZRATING > 0 OR c.Z_2COLLECTIONS IS NOT NULL OR r.ZPLAYCOUNT > 0)
                """) ?? 0
    }
    md += "\n## Orphaned OpenEmu entries (file missing): \(missingPKs.count), of which \(withData) have a rating, collection or plays\n"
    let missingFiles = files.filter { !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    md += "\n## Sample of ROM files not found\n\n" + missingFiles.prefix(10).map { "- `\($0.path(percentEncoded: false))`\n" }.joined()

    if !errors.isEmpty {
        md += "\n## Errors\n\n"
        for rom in roms { if let e = errors[rom.romPK] { md += "- \(rom.name): \(e)\n" } }
    }

    let report = outputDirectory.appending(path: "first-import-report.md")
    try md.write(to: report, atomically: true, encoding: .utf8)
    print(md.components(separatedBy: "\n## Duplicate")[0])
    print("Full report: \(report.path(percentEncoded: false))")
}
