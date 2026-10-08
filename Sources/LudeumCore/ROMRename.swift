import Foundation

/// Renaming a ROM to the name No-Intro would give it (Redump, on disc Platforms): its Game's name written their way, its
/// Regions as its region tag, and the rest of its name's tags in their form and order (ADR 0012).
public enum ROMRename {
    /// The name to offer a ROM named `romName` (a file's without its extension, or a subfolder's), keeping every tag it
    /// can't place, or nil when it already has that name, or when its ROM folder couldn't read the Game's name.
    public static func newName(forROM romName: String, gameName: String, regions: [String], platformId: Int64) -> String? {
        guard let name = standardName(forROM: romName, gameName: gameName, regions: regions, platformId: platformId)?.name() else {
            return nil
        }
        return name == romName ? nil : name
    }

    /// A ROM's Standard name, before choosing which of the tags it can't place to drop: nil when its ROM folder couldn't
    /// read the Game's name.
    public static func standardName(forROM romName: String, gameName: String, regions: [String], platformId: Int64) -> StandardName? {
        let fileTitle = fitForAFileName(gameName)
        guard !fileTitle.isEmpty, !fileTitle.hasPrefix(".") else { return nil }
        // Its tags follow its title. Checked against the Game's whole name first, as it can have tags of its own: "Foo
        // (2008) (USA)" is Foo (2008)'s.
        let afterTitle =
            romName.hasPrefix(fileTitle + " ")
            ? String(romName.dropFirst(fileTitle.count)) : String(romName.dropFirst(ROMName(romName).title.count))
        let naming = ROMPlatform.all[platformId]?.naming ?? .noIntro
        var languages: [String] = []
        var disc: [String] = []
        var version: [String] = []
        var status: [String] = []
        var additional: [String] = []
        var unplaced: [String] = []
        var flags: [String] = []
        var translations: [String] = []
        var afterDisc = false
        let all = Tag.all(in: afterTitle)
        for tag in all {
            let t = tag.content
            let wasAfterDisc = afterDisc
            afterDisc = false
            if tag.isRegion(of: regions) || (!tag.square && matches(t, #"^(M\d+|Unk|Unknown)$"#)) { continue }
            if tag.square {
                if matches(t, #"^T[+-]"#) {
                    translations.append(tag.written)
                } else if matches(t, #"^(b\d*|h.*|t\d*)$"#) {
                    flags.append(tag.written)
                } else if !matches(t, Tag.dumpFlag) && !matches(t, Tag.serial) {
                    unplaced.append(tag.written)
                }
                continue
            }
            if matches(t, Tag.languages) {
                languages = [t.contains("+") ? t : Tag.inNoIntrosOrder(t)]
            } else if matches(t, #"^Dis[ck] [0-9A-Z]+$"#) {
                disc.append(tag.written)
                afterDisc = true
            } else if let prg = t.wholeMatch(of: /PRG(\d+)/) {
                // GoodTools' NES PRG1 is No-Intro's Rev 1; PRG0 has no tag.
                if let n = Int(prg.output.1), n > 0 { version.append("(Rev \(n))") }
            } else if let v = t.wholeMatch(of: /V(\d+)\.(\d+)/) {
                // GoodTools' V1.1 is No-Intro's Rev 1; V1.0 has no tag.
                if v.output.1 == "1", let minor = Int(v.output.2) {
                    if minor > 0 { version.append("(Rev \(minor))") }
                } else {
                    version.append("(v\(v.output.1).\(v.output.2))")
                }
            } else if matches(t, #"^(Rev [A-Z0-9.]+|v\d+(\.\d+)*[a-z]?)$"#) {
                version.append(tag.written)
            } else if matches(t, Tag.devStatus) {
                status.append(tag.written)
            } else if matches(t, Tag.additional) {
                additional.append(tag.written)
            } else if wasAfterDisc {
                disc.append(tag.written)
            } else {
                unplaced.append(tag.written)
            }
        }
        var tags: [StandardName.Tag] = []
        let region = regionTag(regions, naming: naming)
        if !region.isEmpty { tags.append(.init(text: "(\(region))", unplaced: false)) }
        tags += (languages.map { "(\($0))" } + disc + version + status + additional).map { .init(text: $0, unplaced: false) }
        tags += unplaced.map { .init(text: $0, unplaced: true) }
        tags += (flags + translations).map { .init(text: $0, unplaced: false) }
        // After the last tag, only a translation patch is part of the name; anything else is a file artefact.
        if let last = afterTitle.range(of: #"[\)\]][^\)\]]*$"#, options: .regularExpression), !all.isEmpty {
            let suffix = afterTitle[last].dropFirst().trimmingCharacters(in: .whitespaces)
            if matches(suffix, #"(?i)patch|english|translat"#) { tags.append(.init(text: suffix, unplaced: false)) }
        }
        return StandardName(title: fileTitle, tags: tags)
    }

    public struct StandardName: Sendable, Equatable {
        struct Tag: Sendable, Equatable {
            let text: String
            let unplaced: Bool
        }
        let title: String
        let tags: [Tag]

        /// The tags it couldn't place, as written: a scene group's, or an edition's, kept unless dropped.
        public var unplacedTags: [String] { tags.filter(\.unplaced).map(\.text) }

        /// The name, without the tags it couldn't place that are in `dropping`.
        public func name(dropping: Set<String> = []) -> String {
            ([title] + tags.filter { !($0.unplaced && dropping.contains($0.text)) }.map(\.text)).joined(separator: " ")
        }
    }

    /// The Regions as the group writes them: Japan, USA and Europe together as World, and the order its names have, which
    /// neither group documents: No-Intro's Japan, USA, Europe then the rest alphabetically, with Canada left out beside
    /// USA; Redump's USA, Japan, Europe, UK, then the rest.
    static func regionTag(_ regions: [String], naming: ROMPlatform.Naming) -> String {
        let uk = naming == .noIntro ? "United Kingdom" : "UK"
        var all: [String] = []
        for region in regions {
            let spelt = region == "UK" || region == "United Kingdom" ? uk : region
            if !all.contains(spelt) { all.append(spelt) }
        }
        if naming == .noIntro, all.contains("USA") { all.removeAll { $0 == "Canada" } }
        if ["Japan", "USA", "Europe"].allSatisfy(all.contains) {
            all.removeAll { ["Japan", "USA", "Europe", "World"].contains($0) }
            all.insert("World", at: 0)
        }
        let first = naming == .noIntro ? ["World", "Japan", "USA", "Europe"] : ["World", "USA", "Japan", "Europe", "UK"]
        return all.sorted { a, b in
            switch (first.firstIndex(of: a), first.firstIndex(of: b)) {
            case (let i?, let j?): i < j
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        }
        .joined(separator: ", ")
    }

    /// One of a name's tags, as written.
    struct Tag {
        let content: String
        let square: Bool
        var written: String { square ? "[\(content)]" : "(\(content))" }

        /// Whether it's a region tag: No-Intro's, Redump's or GoodTools', or one naming the ROM's own `regions`.
        func isRegion(of regions: [String]) -> Bool {
            if ROMName.goodToolsRegionNames(content) != nil { return true }
            return !square
                && content.components(separatedBy: ", ").allSatisfy { ROMName.noIntroRegions.contains($0) || regions.contains($0) }
        }

        static let dumpFlag = #"^(!|a\d*|o\d*|f\d*|p\d*|C|S|BF|x|c)$"#
        static let serial = #"^[A-Z]{4}[-_ ]?\d{3}\.?\d{2}$"#
        static let languages = #"^[A-Z][a-z](-[A-Z][a-z]+)?([,+][A-Z][a-z](-[A-Z][a-z]+)?)*$"#
        static let devStatus = #"^(Beta|Proto|Prototype|Demo|Sample|Kiosk|Promo|Possible Proto|Pre-Production|Debug)( \d+)?$"#
        static let additional =
            #"^(\d{4}-\d{2}-\d{2}|SGB Enhanced|GB Compatible|Rumble Version|Unl|NP|ST|MB|BS|Alt( \d+)?|Aftermarket|Pirate|Homebrew|.*Virtual Console.*|Switch Online|WiiWare|PSN|minis|N?DSi (Enhanced|Exclusive)|.*Mini.*|(?i:english|eng\b|t-?eng|translat).*)$"#

        /// No-Intro's order of languages, which it asks to be respected; any it doesn't list come after, alphabetically.
        static func inNoIntrosOrder(_ languages: String) -> String {
            let order = [
                "En", "Ja", "Fr", "De", "Es", "It", "Nl", "Pt", "Sv", "No", "Da", "Fi", "Zh", "Ko", "Pl", "Ru", "El", "Tr", "Cs", "Hu",
                "Th", "Hr", "Hi", "Ar", "He", "Sl", "Ro",
            ]
            func rank(_ code: String) -> Int { order.firstIndex(of: String(code.prefix(2))) ?? order.count }
            return languages.components(separatedBy: ",")
                .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0 < $1 }
                .joined(separator: ",")
        }

        static func all(in text: String) -> [Tag] {
            text.matches(of: /\(([^\)]*)\)|\[([^\]]*)\]/).map { m in
                if let round = m.output.1 {
                    Tag(content: round.trimmingCharacters(in: .whitespaces), square: false)
                } else {
                    Tag(content: (m.output.2 ?? "").trimmingCharacters(in: .whitespaces), square: true)
                }
            }
        }
    }

    /// The Game's name as No-Intro writes a title: a colon as " - ", in ASCII where it can be (accents and symbols go,
    /// a letter of another script stays), without the characters it forbids (though one joining two words is a "-",
    /// as in Q-bert), and with a leading article moved to the end of the main title.
    static func fitForAFileName(_ name: String) -> String {
        var s = name.applyingTransform(.stripDiacritics, reverse: false) ?? name
        for (from, to) in asciiSpellings { s = s.replacingOccurrences(of: from, with: to) }
        s = s.replacingOccurrences(of: #"(?<=\S)[/*\\|](?=\S)"#, with: "-", options: .regularExpression)
        s = String(
            String.UnicodeScalarView(
                s.unicodeScalars.filter { scalar in
                    scalar.isASCII
                        ? !#"\/*?"<>|`"#.unicodeScalars.contains(scalar)
                        : scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                }))
        s = s.replacingOccurrences(of: #"\s*:\s*"#, with: " - ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // The main title ends at its subtitle or its first tag.
        if let article = s.firstMatch(of: #/^(The|An|A) /#) {
            let rest = s.dropFirst(article.output.0.count)
            let end = rest.range(of: #" - | \("#, options: .regularExpression)?.lowerBound ?? rest.endIndex
            if end > rest.startIndex { s = "\(rest[..<end]), \(article.output.1)\(rest[end...])" }
        }
        return s
    }

    /// Letters and punctuation with an ASCII spelling that stripping accents doesn't give.
    private static let asciiSpellings: [(String, String)] = [
        ("ß", "ss"), ("æ", "ae"), ("Æ", "AE"), ("œ", "oe"), ("Œ", "OE"), ("ø", "o"), ("Ø", "O"), ("ł", "l"), ("Ł", "L"),
        ("đ", "d"), ("Đ", "D"), ("þ", "th"), ("Þ", "Th"), ("‘", "'"), ("’", "'"), ("‚", "'"), ("′", "'"), ("“", ""),
        ("”", ""), ("„", ""), ("–", "-"), ("—", "-"), ("‒", "-"), ("…", "..."), ("½", " 1-2"), ("⅓", " 1-3"), ("¼", " 1-4"),
        ("¾", " 3-4"), ("×", "x"),
    ]
}

public enum ROMRenameError: Error, Equatable, LocalizedError {
    /// A name its ROM folder wouldn't read back: empty, hidden (starting with a dot) or holding a slash.
    case unreadableName

    public var errorDescription: String? {
        "Its ROM folder can't read that name, so nothing was renamed."
    }
}

extension LudeumStore {
    /// Whether another ROM of the Platform has the name, in any case, present or missing: a missing one keeps its name
    /// so its file can come back to it.
    public func romNameIsTaken(_ name: String, besides rom: Int64, on platformId: Int64) throws -> Bool {
        try db.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE platformId = ? AND folderName = ? COLLATE NOCASE AND id <> ?)",
                arguments: [platformId, name, rom])!
        }
    }

    /// Renames the ROM in its ROM folder, every form it's kept in (`ROMMove.rename`), and in the journal, where it stays
    /// the same ROM with its Match. Refused, with nothing moved, when another ROM has the name in any case, in the
    /// folder or in the journal (a missing one keeps its name so its file can come back to it), or when its ROM folder
    /// wouldn't read the name. A name differing only in case is still a rename.
    public func renameROM(_ rom: Int64, to name: String, in folder: ROMFolder) throws {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { throw ROMRenameError.unreadableName }
        let oldName = try db.read { db in
            try String.fetchOne(db, sql: "SELECT folderName FROM rom WHERE id = ? AND platformId = ?", arguments: [rom, folder.platformId])
        }
        guard let oldName else { throw ReviewError.romFilesNotFound }
        if try romNameIsTaken(name, besides: rom, on: folder.platformId) { throw ReviewError.alreadyInROMFolder }
        let move = try ROMMove.rename(oldName, to: name, in: folder)
        try move.run()
        do {
            guard let file = try folder.rom(named: name) else { throw ROMRenameError.unreadableName }
            try db.write { db in
                try db.execute(sql: "UPDATE rom SET folderName = ?, name = ? WHERE id = ?", arguments: [name, name, rom])
                try Self.setFolderROM(db, rom, to: file)
            }
        } catch {
            move.undo()
            throw error
        }
    }
}
