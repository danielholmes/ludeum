// ─────────────────────────────────────────────────────────────────────────────
// PROTOTYPE: throwaway. Answers "Matching rules in detail" (issue #14):
//   - what exactly counts as "names agree" for an Automatic Match,
//   - how Disc and Version are parsed out of ROM names,
//   - which IGDB game_type values count as bundles (or never as a Game).
// It re-runs the first-Import dry run's matching from the cache, against the same
// library snapshot, then measures a ladder of name rules and a name parser.
// It is not the real matcher and must not grow into it.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import GRDB
import JournalCore

private struct MRom {
    let pk: Int
    let name: String  // ZGAME.ZNAME
    let title: String?  // ZGAME.ZGAMETITLE (OpenVGDB)
    let system: String
    let md5: String
    let file: URL?
    var sys: String { system.replacingOccurrences(of: "openemu.system.", with: "") }
    var present: Bool { file.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false }
}

private enum Found {
    case hash(Int)
    case suggestion([Int])
    case nothing
}

/// My verdict on each of the dry run's 46 checksum matches whose names disagreed:
/// is the checksum's IGDB game the right Game for this ROM?
private let checksumVerdicts: [String: Bool] = [
    "Army Men - Air Combat (USA, Europe) (En,Fr,De)": false,
    "Choplifter II - Rescue & Survive (E) [!]": true,
    "Feed_IT_Souls_v1.4": true,
    "Gradius - The Interstellar Assault (USA)": false,
    "Harvest Moon GB (USA) (SGB Enhanced)": false,
    "Hermano_1.1_jam": true,
    "Looney Tunes - Twouble! (USA) (En,Fr,Es)": false,
    "Mickey Mouse - Magic Wand (USA, Europe)": false,
    "New Batman Adventures, The - Chaos in Gotham (U) [C][!]": true,
    "Oddworld Adventures II (Europe) (En,Fr,De,Es,It)": true,
    "Resident Evil GB": true,
    "Resident Evil GBC Cart 1 (Bugfix v1.0)": true,
    "Rolan's Curse II (USA)": true,
    "Super Jacked Up Tomato Face Johnson v2.3": true,
    "Wizards & Warriors Chapter X - The Fortress of Fear (USA, Europe)": true,
    "elden ring gb v1.0": true,
    "fpg": true,
    "grimacebday v.1.7": true,
    "Colin McRae Rally 2 # GBA": true,
    "Lilo & Stitch (USA)": false,
    "Scooby-Doo! - Mystery Mayhem (U)": false,
    "Super Mario Advance 2 - Super Mario World (U) [!]": true,
    "Super Mario Advance 3 - Yoshi's Island (U) [!]": true,
    "Tomb Raider - The Prophecy (U) (M5)": false,
    "007 - The World Is Not Enough (USA)": true,
    "Baseball Stars II (USA)": true,
    "Battletoads-Double Dragon (USA)": false,
    "Holy Diver (Japan)": false,
    "Teenage Mutant Ninja Turtles - Tournament Fighters (USA)": false,
    "Tiny Toon Adventures Cartoon Workshop (USA)": false,
    "Medal of Honor - Heroes": false,
    "Resident Evil 2 - Dual Shock Ver. (USA) (Disc 1) (Leon)": false,
    "Resident Evil 2 - Dual Shock Ver. (USA) (Disc 2) (Claire)": false,
    "Asterix and the Power of the Gods (Europe) (En,Fr,De,Es)": true,
    "James Pond II - Codename - Robocod (USA, Europe)": true,
    "QuackShot Starring Donald Duck ~ QuackShot - I Love Donald Duck - Guruzia Ou no Hihou (World) (v1.1)": true,
    "RE MD DEMO": true,
    "RE MD DEMO 2": true,
    "Toy Story (Europe)": true,
    "Undead_Line_J_TEng1.0-20070903_MIJET": true,
    "Ren & Stimpy - Quest for the Shaven Yak, The (B) [!]": true,
    "King of Dragons (USA)": true,
    "Spider-Man & Venom - Maximum Carnage (U)": false,
    "Spider-Man and the X-Men in Arcade's Revenge (U) 2": false,
    "Super Star Wars - Return of the Jedi (USA)": false,
    "Super Star Wars - The Empire Strikes Back (USA)": false,
]

// MARK: - Name rules

private struct Rules {
    var label: String
    var diacritics = false
    var roman = false
    var romanXV = false
    var ampersand = false
    var articles = false
    var prefixes = false
    var swap = false
    var tilde = false
    var artefacts = false
    var noAcronyms = false
    var regionalAlts = false
    var noOpenVGDB = false
}

private let ladder: [Rules] = {
    var r = Rules(label: "R0 baseline (the dry run's rule)")
    var out = [r]
    func add(_ label: String, _ f: (inout Rules) -> Void) {
        f(&r)
        r.label = label
        out.append(r)
    }
    add("R1 + fold diacritics") { $0.diacritics = true }
    add("R2 + roman numerals II–XX as digits (not I, V, X)") { $0.roman = true }
    add("R3 + ignore `&` / `and`") { $0.ampersand = true }
    add("R4 + ignore `the` anywhere, leading `a`/`an`") { $0.articles = true }
    add("R5 + drop `Disney's`, `James Bond` … prefixes") { $0.prefixes = true }
    add("R6 + title and subtitle may be swapped") { $0.swap = true }
    add("R7 + ` ~ ` separates alternative titles") { $0.tilde = true }
    add("R8 + clean file artefacts (underscores, bare versions, `# GBA`, copy suffixes, patches)") { $0.artefacts = true }
    add("R9 + regional alt names and localizations only for that region's ROMs") { $0.regionalAlts = true }
    return out
}()

private let variants: [Rules] = {
    var acr = ladder.last!
    acr.noAcronyms = true
    acr.label = "R9 but ignoring Acronym / Abbreviation alt names"
    var xv = ladder.last!
    xv.romanXV = true
    xv.label = "R9 but V and X count as roman numerals too"
    var ovg = ladder.last!
    ovg.noOpenVGDB = true
    ovg.label = "R9 but without OpenVGDB's title (ROM name only)"
    return [acr, xv, ovg]
}()

private let romans: [String: Int] = [
    "ii": 2, "iii": 3, "iv": 4, "vi": 6, "vii": 7, "viii": 8, "ix": 9, "xi": 11, "xii": 12, "xiii": 13,
    "xiv": 14, "xv": 15, "xvi": 16, "xvii": 17, "xviii": 18, "xix": 19, "xx": 20,
]

private let droppedPrefixes: [[String]] = [
    ["disney", "pixar", "s"], ["disney", "s"], ["james", "bond"], ["tom", "clancy", "s"], ["sid", "meier", "s"],
]

private func has(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
private func sub(_ s: String, _ pattern: String, _ with: String) -> String {
    s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
}

/// Title strings a ROM name offers, before normalising.
private func romTitles(_ raw: String, _ r: Rules) -> [String] {
    var s = raw
    if r.artefacts {
        s = sub(s, #"(?i)\.(nkit|sav|iso|gcm)(\s+\d+)?$"#, "")  // ".nkit", ".nkit 2"
        s = sub(s, #"(?i)-redump$"#, "")
        s = sub(s, #"^\d{4} - "#, "")  // scene release numbers: "0173 - Harry Potter …"
        s = sub(s, #"\s+#\s*\w+$"#, "")  // "Colin McRae Rally 2 # GBA"
        s = sub(s, #"\)\s+[a-z]{2,4}$"#, ")")  // "(USA) gb"
        s = sub(s, #"[\)\]]\s+(\d+|-\s.*)$"#, ")")  // "(U) 2", "(USA) - bofner patch"
        if !s.contains("(") && !s.contains("[") {
            if !s.contains(" ") { s = s.replacingOccurrences(of: "_", with: " ") }
            s = sub(s, #"\s+v?\.?\d+(\.\d+)+.*$"#, "")  // "Feed IT Souls v1.4", "grimacebday v.1.7", "Hermano 1.1 jam"
        }
    }
    let parts = r.tilde ? s.components(separatedBy: " ~ ") : [s]
    var out: [String] = []
    for p in parts {
        let c = cleanName(p)
        out.append(c)
        if r.swap, let i = c.range(of: ": ") {
            out.append("\(c[i.upperBound...]): \(c[..<i.lowerBound])")
        }
    }
    return out
}

private func normKey(_ raw: String, _ r: Rules) -> String {
    var s = raw.lowercased()
    if r.diacritics { s = s.folding(options: .diacriticInsensitive, locale: nil) }
    s = s.replacingOccurrences(of: "&", with: " and ")
    var t = s.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    if r.roman {
        t = t.map { tok in
            if let n = romans[tok] { return String(n) }
            if r.romanXV, tok == "v" { return "5" }
            if r.romanXV, tok == "x" { return "10" }
            return tok
        }
    }
    if r.prefixes, let p = droppedPrefixes.first(where: { t.starts(with: $0) && t.count > $0.count }) { t.removeFirst(p.count) }
    if r.ampersand { t.removeAll { $0 == "and" } }
    if r.articles {
        t.removeAll { $0 == "the" }
        if let f = t.first, ["a", "an"].contains(f), t.count > 1 { t.removeFirst() }
    }
    return t.joined()
}

private enum Region: String { case japan = "Japan", europe = "Europe", usa = "USA", korea = "Korea" }

/// IGDB names for a game, with where each came from. With `regionalAlts`, a regional
/// alt name or localization is only offered to a ROM from that region (or of unknown region).
private func igdbNames(_ g: IGDBGame, regions: Set<Region>?, _ r: Rules) -> [(name: String, source: String)] {
    var out: [(String, String)] = g.name.map { [($0, "name")] } ?? []
    func allowed(_ region: Region?) -> Bool {
        guard r.regionalAlts, let region, let regions else { return true }
        return regions.contains(region)
    }
    for alt in g.record["alternative_names"]?.array ?? [] {
        guard let n = alt["name"]?.string else { continue }
        let comment = (alt["comment"]?.string ?? "").lowercased()
        if r.noAcronyms, comment.contains("acronym") || comment.contains("abbreviation") { continue }
        let region: Region? =
            comment.hasPrefix("japanese") ? .japan
            : comment.hasPrefix("european") ? .europe
            : comment.hasPrefix("korean") ? .korea
            : (comment.hasPrefix("north american") || comment.hasPrefix("american")) ? .usa : nil
        if allowed(region) { out.append((n, "alt: \(alt["comment"]?.string ?? "no comment")")) }
    }
    for loc in g.record["game_localizations"]?.array ?? [] {
        guard let n = loc["name"]?.string else { continue }
        let region: Region? = [4: .europe, 2: .korea, 3: .japan][loc["region"]?.int ?? 0]
        if allowed(region) { out.append((n, "localization: \(region?.rawValue ?? "?")")) }
    }
    return out
}

/// The IGDB name source that agrees with the ROM, or nil if none does.
private func agreement(_ rom: MRom, _ g: IGDBGame, _ r: Rules) -> String? {
    let parsed = parseName(rom.name)
    var romNames = romTitles(rom.name, r)
    if !r.noOpenVGDB, let t = rom.title { romNames += romTitles(t, r) }
    let keys = Set(romNames.map { normKey($0, r) }).subtracting([""])
    let regions = parsed.regionSet
    for (n, source) in igdbNames(g, regions: regions, r) {
        if keys.contains(normKey(cleanName(n), r)) {
            let viaROM = Set(romTitles(rom.name, r).map { normKey($0, r) }).contains(normKey(cleanName(n), r))
            return viaROM ? source : "\(source) (via OpenVGDB title)"
        }
    }
    return nil
}

// MARK: - Name parser (Version and Disc)

private struct Parsed {
    var title = ""
    var regions: [String] = []
    var languages: String?
    var revision: String?
    var dev: [String] = []
    var disc: Int?
    var discLabel: String?
    var extras: [String] = []
    var dump: [String] = []
    var translation: String?
    var serial: String?
    var unknown: [String] = []

    /// Everything that tells this Version apart, except the Disc.
    var version: String {
        (regions + [languages, revision].compactMap { $0 } + dev + extras + [translation].compactMap { $0 } + unknown)
            .joined(separator: " · ")
    }
    var regionSet: Set<Region>? {
        var out = Set<Region>()
        for r in regions {
            switch r {
            case "Japan": out.insert(.japan)
            case "USA", "Canada": out.insert(.usa)
            case "Korea": out.insert(.korea)
            case "World": out.formUnion([.japan, .usa, .europe])
            case "Europe", "UK", "Australia", "France", "Germany", "Spain", "Italy", "Netherlands", "Sweden",
                "Scandinavia":
                out.insert(.europe)
            default: break
            }
        }
        return out.isEmpty ? nil : out
    }
}

private let noIntroRegions: Set<String> = [
    "USA", "Europe", "Japan", "World", "Asia", "Australia", "Brazil", "Canada", "China", "France", "Germany",
    "Hong Kong", "Italy", "Korea", "Netherlands", "Spain", "Sweden", "Taiwan", "UK", "Russia", "Scandinavia",
    "Latin America", "Unknown",
]
private let goodRegions: [String: [String]] = [
    "U": ["USA"], "E": ["Europe"], "J": ["Japan"], "UE": ["USA", "Europe"], "JU": ["Japan", "USA"],
    "JUE": ["Japan", "USA", "Europe"], "JE": ["Japan", "Europe"], "B": ["Brazil"], "4": ["USA", "Brazil"],
    "W": ["World"], "US": ["USA"], "EU": ["Europe"], "F": ["France"], "G": ["Germany"], "K": ["Korea"],
]
private let knownExtras: Set<String> = [
    "SGB Enhanced", "GB Compatible", "NP", "Unl", "Pirate", "Virtual Console", "Switch Online", "Rumble Version",
    "Alt", "EDC", "Evercade", "Retro-Bit", "ST", "MB",
]

private func parseName(_ raw: String) -> Parsed {
    var p = Parsed()
    let re = try! NSRegularExpression(pattern: #"\(([^\)]*)\)|\[([^\]]*)\]"#)
    let ns = raw as NSString
    let ms = re.matches(in: raw, range: NSRange(location: 0, length: ns.length))
    p.title = (ms.first.map { ns.substring(to: $0.range.location) } ?? raw).trimmingCharacters(in: .whitespaces)
    var afterDisc = false
    for m in ms {
        let square = m.range(at: 2).location != NSNotFound
        let t = ns.substring(with: m.range(at: square ? 2 : 1)).trimmingCharacters(in: .whitespaces)
        let wasAfterDisc = afterDisc
        afterDisc = false
        if square {
            if has(t, #"^(!|a\d*|b\d*|f\d*|h.*|o\d*|p\d*|t\d*|T[+-].*|C|S|BF|x)$"#) {
                p.dump.append("[\(t)]")
            } else if has(t, #"^[A-Z]{4}[-_ ]?\d{3}\.?\d{2}$"#) {
                p.serial = t
            } else {
                p.unknown.append("[\(t)]")
            }
            continue
        }
        let parts = t.components(separatedBy: ", ")
        if parts.allSatisfy(noIntroRegions.contains) {
            p.regions += parts
        } else if let g = goodRegions[t] {
            p.regions += g
        } else if has(t, #"^[A-Z][a-z](-[A-Z]{2})?(,[A-Z][a-z](-[A-Z]{2})?)*$"#) || has(t, #"^M\d+$"#) {
            p.languages = t
        } else if has(t, #"^(Rev [A-Z0-9]+|[vV]\d+(\.\d+)*[a-z]?)$"#) {
            p.revision = t
        } else if has(t, #"^(Beta|Proto|Prototype|Demo|Sample|Kiosk|Possible Proto|Promo)( \d+)?$"#)
            || has(t, #"^\d{4}-\d{2}-\d{2}$"#)
        {
            p.dev.append(t)
        } else if let n = t.wholeMatch(of: /Disc (\d+)/) {
            p.disc = Int(n.1)
            afterDisc = true
        } else if has(t, #"(?i)^(english|eng\b|t-?eng|translat)"#) {
            p.translation = t
        } else if knownExtras.contains(t) || has(t, #"^Alt \d+$"#) {
            p.extras.append(t)
        } else if wasAfterDisc {
            p.discLabel = t
        } else {
            p.unknown.append("(\(t))")
        }
    }
    if let last = ms.last {
        let suffix = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
        if has(suffix, #"(?i)patch|english|translat"#) {
            p.translation = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        } else if has(suffix, #"^\d+$"#) || has(suffix, #"(?i)^\.(nkit|sav)$"#) {
            // file-system copy suffix or tool artefact: not part of the Version
        } else if !suffix.isEmpty {
            p.unknown.append("suffix \"\(suffix)\"")
        }
    }
    return p
}

// MARK: - Run

func prototypeMatchingRules(igdb: IGDBClient, hasheous: HasheousClient, outputDirectory: URL) async throws {
    var config = Configuration()
    config.readonly = true
    let snapshot = try DatabaseQueue(
        path: outputDirectory.appending(path: "PROTOTYPE-wipe-me-openemu-snapshot.sqlite").path(percentEncoded: false),
        configuration: config)
    let libraryPath =
        (UserDefaults(suiteName: "org.openemu.OpenEmu")?.string(forKey: "databasePath")
        ?? "~/Library/Application Support/OpenEmu/Game Library") as NSString
    let library = URL(filePath: libraryPath.expandingTildeInPath, directoryHint: .isDirectory)
    let roms: [MRom] = try await snapshot.read { db in
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
            return MRom(
                pk: row["pk"], name: row["name"] ?? "?", title: row["title"], system: row["system"],
                md5: (row["md5"] as String?)?.lowercased() ?? "", file: file)
        }
    }
    log("\(roms.count) ROMs in the snapshot")

    // Same matching as the dry run, all from the cache.
    var found: [Int: Found] = [:]
    for rom in roms {
        if let g = try await hasheous.lookup(md5: rom.md5).match?.igdbGameID {
            found[rom.pk] = .hash(g)
            continue
        }
        if ["openemu.system.nes", "openemu.system.snes"].contains(rom.system), let file = rom.file, isLocal(file),
            let stripped = headerlessMD5(file, system: rom.system),
            let g = try await hasheous.lookup(md5: stripped).match?.igdbGameID
        {
            found[rom.pk] = .hash(g)
            continue
        }
        found[rom.pk] = .nothing
        let names = Set([cleanName(rom.name), rom.title].compactMap { $0 }.filter { !$0.isEmpty })
        search: for platform in igdbPlatforms[rom.system] ?? [] {
            for name in names {
                let s = IGDBSearch(name: name, platformID: platform)
                if let ids = try? await igdb.search([s])[s], !ids.isEmpty {
                    found[rom.pk] = .suggestion(ids)
                    break search
                }
            }
        }
    }

    // Records for checksum games, every suggestion candidate, and the checksum games' relatives.
    var ids = Set<Int>()
    for f in found.values {
        switch f {
        case .hash(let g): ids.insert(g)
        case .suggestion(let c): ids.formUnion(c)
        case .nothing: break
        }
    }
    var games = try await igdb.games(ids: Array(ids))
    let relationFields = ["parent_game", "version_parent"]
    let relationLists = ["expanded_games", "remasters", "remakes", "ports", "standalone_expansions", "forks"]
    func related(_ g: IGDBGame) -> [(Int, String)] {
        var out: [(Int, String)] = []
        for f in relationFields { if let id = g.record[f]?["id"]?.int { out.append((id, f)) } }
        for f in relationLists { for x in g.record[f]?.array ?? [] { if let id = x["id"]?.int { out.append((id, f)) } } }
        return out
    }
    var relIDs = Set<Int>()
    for case .hash(let g) in found.values { for (id, _) in games[g].map(related) ?? [] { relIDs.insert(id) } }
    log("fetching \(relIDs.subtracting(games.keys).count) related IGDB records…")
    games.merge(try await igdb.games(ids: Array(relIDs.subtracting(games.keys)))) { a, _ in a }

    let hashRoms: [(MRom, IGDBGame)] = roms.compactMap { r in
        if case .hash(let g) = found[r.pk], let game = games[g] { (r, game) } else { nil }
    }
    let suggRoms: [(MRom, [IGDBGame])] = roms.compactMap { r in
        if case .suggestion(let c) = found[r.pk] { (r, c.compactMap { games[$0] }) } else { nil }
    }
    let nothingRoms = roms.filter { if case .nothing = found[$0.pk] { true } else { false } }
    func typeOf(_ g: IGDBGame) -> Int { g.record["game_type"]?.int ?? -1 }
    let typeNames = [
        0: "Main Game", 1: "DLC", 2: "Expansion", 3: "Bundle", 4: "Standalone Expansion", 5: "Mod", 6: "Episode",
        7: "Season", 8: "Remake", 9: "Remaster", 10: "Expanded Game", 11: "Port", 12: "Fork", 13: "Pack / Addon",
        14: "Update",
    ]
    let neverAGame: Set<Int> = [1, 2, 5, 7, 13, 14]
    // Verdicts apply to the dry run's 46 only (a name can recur on another system, e.g. TMNT Tournament Fighters).
    let flagged = Set(hashRoms.filter { agreement($0.0, $0.1, ladder[0]) == nil }.map(\.0.pk))
    func label(_ rom: MRom) -> Bool? { flagged.contains(rom.pk) ? checksumVerdicts[rom.name] : nil }
    func verdict(_ rom: MRom) -> String {
        label(rom).map { $0 ? "✅ right game" : "❌ wrong game" } ?? ""
    }
    func esc(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }

    var md = "# PROTOTYPE: matching rules\n\n"
    md += "Generated \(Date().formatted()). Throwaway output of `journal-import prototype-matching-rules`, "
    md += "run against the first-Import dry run's snapshot and cache.\n\n"
    md += "\(roms.count) ROMs: \(hashRoms.count) checksum matches, \(suggRoms.count) name-search suggestions, "
    md += "\(nothingRoms.count) with nothing.\n\n"

    // 1. The ladder.
    md += "## 1. Name rules, applied cumulatively\n\n"
    md += "Checksum columns: of the \(hashRoms.count) checksum matches, how many have agreeing names (→ Automatic); "
    md += "of the \(checksumVerdicts.count) the dry run flagged, how many right and wrong games get through. "
    md += "Suggestion columns: of the \(suggRoms.count) name-search suggestions, how many have a top candidate whose "
    md += "name agrees (→ bulk confirm), and how many have *any* agreeing candidate that isn't a Mod, DLC, etc.\n\n"
    md += "| Rule | Checksum agree | ✅ right let in (of \(checksumVerdicts.values.filter { $0 }.count)) "
    md += "| ❌ wrong let in (of \(checksumVerdicts.values.filter { !$0 }.count)) | Suggestion: top agrees "
    md += "| Suggestion: any agrees |\n|---|---|---|---|---|---|\n"
    var previous: Set<Int> = []
    var previousSugg: Set<Int> = []
    var flips = ""
    for (i, rule) in (ladder + variants).enumerated() {
        let agree = Set(hashRoms.filter { agreement($0.0, $0.1, rule) != nil }.map(\.0.pk))
        let right = hashRoms.filter { agree.contains($0.0.pk) && label($0.0) == true }.count
        let wrong = hashRoms.filter { agree.contains($0.0.pk) && label($0.0) == false }
        let top = Set(suggRoms.filter { r in r.1.first.map { agreement(r.0, $0, rule) != nil } ?? false }.map(\.0.pk))
        let any = suggRoms.filter { r in
            r.1.contains { !neverAGame.contains(typeOf($0)) && agreement(r.0, $0, rule) != nil }
        }.count
        md += "| \(rule.label) | \(agree.count) | \(right) | \(wrong.count) | \(top.count) | \(any) |\n"
        let base = i < ladder.count ? previous : Set(hashRoms.filter { agreement($0.0, $0.1, ladder.last!) != nil }.map(\.0.pk))
        let baseSugg = i < ladder.count ? previousSugg : Set(suggRoms.filter { r in r.1.first.map { agreement(r.0, $0, ladder.last!) != nil } ?? false }.map(\.0.pk))
        if i > 0 {
            var lines = ""
            for (rom, g) in hashRoms where agree.contains(rom.pk) != base.contains(rom.pk) {
                lines += "- checksum \(agree.contains(rom.pk) ? "**now agrees**" : "**no longer agrees**"): `\(rom.name)` → *\(g.name ?? "?")* "
                lines += "\(verdict(rom)) (\(agreement(rom, g, rule) ?? "—"))\n"
            }
            for (rom, c) in suggRoms where top.contains(rom.pk) != baseSugg.contains(rom.pk) {
                lines += "- suggestion \(top.contains(rom.pk) ? "**now agrees**" : "**no longer agrees**"): `\(rom.name)` → *\(c.first?.name ?? "?")*\n"
            }
            if !lines.isEmpty { flips += "\n### \(rule.label)\n\n" + lines }
        }
        if i < ladder.count {
            previous = agree
            previousSugg = top
        }
    }
    md += "\n### What changed at each step\n" + flips

    // 2. Where names agree, under the final rule.
    let final = ladder.last!
    var sources: [String: Int] = [:]
    for (rom, g) in hashRoms {
        if let s = agreement(rom, g, final) {
            let k = s.hasPrefix("alt:") ? "alt name" + (s.contains("OpenVGDB") ? " (via OpenVGDB title)" : "")
                : s.hasPrefix("localization") ? "localization" + (s.contains("OpenVGDB") ? " (via OpenVGDB title)" : "")
                : s
            sources[k, default: 0] += 1
        }
    }
    md += "\n## 2. Which IGDB name agreed (checksum matches, final rule)\n\n| Agreed with | ROMs |\n|---|---|\n"
    for (k, v) in sources.sorted(by: { $0.value > $1.value }) { md += "| \(k) | \(v) |\n" }
    md += "\nAlt-name and localization agreements in full:\n\n"
    for (rom, g) in hashRoms {
        if let s = agreement(rom, g, final), s.hasPrefix("alt") || s.hasPrefix("loc") {
            md += "- `\(rom.name)` → *\(g.name ?? "?")* (\(s))\n"
        }
    }

    // 3. Still disagreeing: rescue through a related record?
    md += "\n## 3. Checksum matches still disagreeing under the final rule\n\n"
    md += "| ROM | Checksum's IGDB game (type) | My verdict | A related record whose name agrees |\n|---|---|---|---|\n"
    for (rom, g) in hashRoms where agreement(rom, g, final) == nil {
        let rescue = related(g).compactMap { id, rel -> String? in
            guard let rg = games[id], agreement(rom, rg, final) != nil else { return nil }
            return "*\(rg.name ?? "?")* (\(rel), \(typeNames[typeOf(rg)] ?? "?"))"
        }
        md += "| \(esc(rom.name)) | \(esc(g.name ?? "?")) (\(typeNames[typeOf(g)] ?? "?")) | \(verdict(rom)) "
        md += "| \(rescue.joined(separator: ", ")) |\n"
    }
    md += "\nSuggestions whose top candidate still disagrees:\n\n| ROM | Top candidate (type) | An agreeing candidate further down |\n|---|---|---|\n"
    for (rom, c) in suggRoms where !(c.first.map { agreement(rom, $0, final) != nil } ?? false) {
        let other = c.dropFirst().first { !neverAGame.contains(typeOf($0)) && agreement(rom, $0, final) != nil }
        md += "| \(esc(rom.name)) | \(esc(c.first?.name ?? "?")) (\(c.first.map { typeNames[typeOf($0)] ?? "?" } ?? "")) "
        md += "| \(other.map { "\(esc($0.name ?? "?")) (\(typeNames[typeOf($0)] ?? "?"))" } ?? "") |\n"
    }

    // 4. game_type.
    md += "\n## 4. IGDB game_type\n\n| game_type | Checksum matches | …of which names agree | Top suggestions | All suggestion candidates |\n|---|---|---|---|---|\n"
    let allCandidates = suggRoms.flatMap(\.1)
    for t in Set(hashRoms.map { typeOf($0.1) } + allCandidates.map(typeOf)).sorted() {
        let h = hashRoms.filter { typeOf($0.1) == t }
        md += "| \(t) \(typeNames[t] ?? "none") | \(h.count) | \(h.filter { agreement($0.0, $0.1, final) != nil }.count) "
        md += "| \(suggRoms.filter { $0.1.first.map(typeOf) == t }.count) | \(allCandidates.filter { typeOf($0) == t }.count) |\n"
    }
    md += "\nEvery checksum match or top suggestion that isn't a Main Game:\n\n| ROM | IGDB game | game_type | Names agree | parent_game / version_parent |\n|---|---|---|---|---|\n"
    let nonMain = hashRoms.map { ($0.0, $0.1, "checksum") } + suggRoms.compactMap { r in r.1.first.map { (r.0, $0, "suggestion") } }
    for (rom, g, how) in nonMain where typeOf(g) != 0 {
        let parent = [g.record["parent_game"]?["name"]?.string, g.record["version_parent"]?["name"]?.string].compactMap { $0 }
        md += "| \(esc(rom.name)) (\(how)) | \(esc(g.name ?? "?")) | \(typeNames[typeOf(g)] ?? "?") "
        md += "| \(agreement(rom, g, final) != nil ? "yes" : "no") | \(esc(parent.joined(separator: " / "))) |\n"
    }
    md += "\nSuggestion candidates that are never a Game (Mod, DLC, Expansion, Season, Pack, Update), by ROM:\n\n"
    for (rom, c) in suggRoms {
        let bad = c.enumerated().filter { neverAGame.contains(typeOf($0.element)) }
        if !bad.isEmpty {
            md += "- `\(rom.name)`: " + bad.map { "#\($0.offset + 1) *\($0.element.name ?? "?")* (\(typeNames[typeOf($0.element)] ?? "?"))" }.joined(separator: ", ") + "\n"
        }
    }

    // 5. Parser.
    let parsed = roms.map { ($0, parseName($0.name)) }
    md += "\n## 5. Parsing Version and Disc out of ROM names\n\n"
    md += "| | ROMs |\n|---|---|\n"
    md += "| With a region | \(parsed.filter { !$0.1.regions.isEmpty }.count) |\n"
    md += "| No brackets at all (bare title) | \(parsed.filter { !$0.0.name.contains("(") && !$0.0.name.contains("[") }.count) |\n"
    md += "| With a revision | \(parsed.filter { $0.1.revision != nil }.count) |\n"
    md += "| With a Disc number | \(parsed.filter { $0.1.disc != nil }.count) |\n"
    md += "| With a disc label | \(parsed.filter { $0.1.discLabel != nil }.count) |\n"
    md += "| With a translation or patch | \(parsed.filter { $0.1.translation != nil }.count) |\n"
    md += "| With GoodTools dump flags | \(parsed.filter { !$0.1.dump.isEmpty }.count) |\n"
    md += "| With something unrecognised | \(parsed.filter { !$0.1.unknown.isEmpty }.count) |\n"
    var unknown: [String: [String]] = [:]
    for (rom, p) in parsed { for u in p.unknown { unknown[u, default: []].append(rom.name) } }
    md += "\nUnrecognised parts (they stay in the Version text as they are):\n\n| Part | ROMs | Example |\n|---|---|---|\n"
    for (u, names) in unknown.sorted(by: { ($0.value.count, $1.key) > ($1.value.count, $0.key) }) {
        md += "| \(esc(u)) | \(names.count) | \(esc(names[0])) |\n"
    }
    md += "\nSample of parsed Versions:\n\n| ROM | Title | Version | Disc |\n|---|---|---|---|\n"
    for (rom, p) in parsed where rom.pk % 23 == 0 || p.disc != nil || p.translation != nil {
        md += "| \(esc(rom.name)) | \(esc(p.title)) | \(esc(p.version)) | \(p.disc.map { "\($0)\(p.discLabel.map { " (\($0))" } ?? "")" } ?? "") |\n"
    }

    // 6. Discs and Duplicate Versions under the final rule.
    //    A ROM's Game: its checksum game if names agree, else its top suggestion if that agrees (bulk confirm).
    var gameOf: [Int: Int] = [:]
    for (rom, g) in hashRoms where agreement(rom, g, final) != nil { gameOf[rom.pk] = g.id }
    for (rom, c) in suggRoms { if let t = c.first, agreement(rom, t, final) != nil { gameOf[rom.pk] = t.id } }
    let byGame = Dictionary(grouping: parsed.filter { gameOf[$0.0.pk] != nil }, by: { "\(gameOf[$0.0.pk]!):\($0.0.system)" })
    md += "\n## 6. Discs and Duplicate Versions (final rule; Games from agreeing checksums and bulk-confirmable suggestions)\n\n"
    md += "Chosen Disc rule: the ROMs of one Game that each carry a Disc number, with no number repeated, are Discs of one Version, and an `.m3u` playlist of that Game joins them. Any other ROM is its own Version.\n\n"
    var dupes = ""
    var multiDisc = ""
    for (key, rs) in byGame.sorted(by: { $0.key < $1.key }) {
        let present = rs.filter { $0.0.present }
        let discs = present.filter { $0.1.disc != nil || $0.0.file?.pathExtension.lowercased() == "m3u" }
        let numbers = discs.compactMap(\.1.disc)
        let oneSet = !numbers.isEmpty && Set(numbers).count == numbers.count
        let versions = Dictionary(grouping: present, by: { r in
            oneSet && discs.contains { $0.0.pk == r.0.pk } ? "Discs" : "\(r.0.pk): \(r.1.version)"
        })
        let gname = games[Int(key.split(separator: ":")[0])!]?.name ?? key
        if rs.contains(where: { $0.1.disc != nil }) {
            multiDisc += "- **\(gname)**: " + rs.map { "`\($0.0.name)`\($0.0.present ? "" : " (missing)")" }.joined(separator: ", ") + "\n"
        }
        if versions.count > 1 {
            dupes += "- **\(gname)** (\(rs[0].0.sys)): " + versions.map { v, r in "[\(v.isEmpty ? "no tags" : v)] " + r.map { "`\($0.0.name)`" }.joined(separator: " + ") }.joined(separator: " ≠ ") + "\n"
        }
    }
    md += "### Games with Discs\n\n" + multiDisc
    md += "\n### Duplicate Versions (\(dupes.split(separator: "\n").count))\n\n" + dupes

    // Disc-less entries next to Disc entries of the same title.
    md += "\n### Entries with no Disc number next to Disc entries of the same title\n\n"
    let discTitles = Set(parsed.filter { $0.1.disc != nil }.map { "\($0.0.system):\(normKey(cleanName($0.1.title), final))" })
    for (rom, p) in parsed where p.disc == nil && discTitles.contains("\(rom.system):\(normKey(cleanName(p.title), final))") {
        md += "- `\(rom.name)` (\(rom.sys)): file `\(rom.file?.lastPathComponent ?? "?")`\(rom.present ? "" : ", missing")\n"
    }

    let report = outputDirectory.appending(path: "matching-rules-report.md")
    try md.write(to: report, atomically: true, encoding: .utf8)
    print(md.components(separatedBy: "\n### What changed")[0])
    print("Full report: \(report.path(percentEncoded: false))")
}
