import Foundation

/// Finds a ROM's name in a libretro-thumbnails folder listing, in order: the file name minus its
/// extension (with libretro's substitutions), then with GoodTools tags rewritten to No-Intro ones,
/// then a fuzzy title match on the file name, then on each of `titles` (the ROM's name, then its Game's IGDB name).
/// A multi-disc ROM looks for its disc-less name first.
enum LibretroLookup {
    static func find(fileName: String, titles: [String], in names: Set<String>) -> String? {
        exact(fileName: fileName, in: names) ?? fuzzy(fileName: fileName, titles: titles, in: names)
    }

    /// The name (disc-less first), then the GoodTools rewrite.
    static func exact(fileName: String, in names: Set<String>) -> String? {
        let stem = substituted(Self.stem(fileName))
        return [withoutDisc(stem), stem, withoutDisc(goodToolsRewritten(stem))].first(where: names.contains)
    }

    /// A title match on the file name, then on each of `titles`, by region preference.
    static func fuzzy(fileName: String, titles: [String], in names: Set<String>) -> String? {
        fuzzy(fileName: fileName, titles: titles, in: titleIndex(names))
    }

    /// A folder's released names by title key, and by loose title key, a name led by its title's initials under its
    /// title's keys too: what a fuzzy match looks in.
    struct TitleIndex: Sendable {
        let byKey: [String: [String]]
        let byLooseKey: [String: [String]]
    }

    /// The index of `names`, leaving out prereleases. A name led by its title's initials (`WCR - World Championship
    /// Rugby`, `I.Q - Intelligent Qube`) is also found by the title after them.
    static func titleIndex(_ names: Set<String>) -> TitleIndex {
        let released = names.filter { !isPrerelease($0) }
        func index(by keyOf: (String) -> String) -> [String: [String]] {
            var index: [String: [String]] = [:]
            for name in released {
                for key in Set([name, withoutInitials(name)].compactMap { $0 }.map(keyOf)) { index[key, default: []].append(name) }
            }
            return index
        }
        return TitleIndex(byKey: index(by: titleKey), byLooseKey: index(by: looseTitleKey))
    }

    /// The name after a leading initialism of the title that follows it, with or without its subtitle, the initialism's
    /// dots dropped: `CTR - Crash Team Racing (USA)` is `Crash Team Racing (USA)`, `KKND - Krush, Kill 'N' Destroy` is
    /// `Krush, Kill 'N' Destroy`, `T2 - Terminator 2 - Judgment Day` is `Terminator 2 - Judgment Day`. Nil for a name not
    /// led that way (`Gex - Enter the Gecko`).
    static func withoutInitials(_ name: String) -> String? {
        guard let dash = name.range(of: " - ") else { return nil }
        let initials = name[..<dash.lowerBound].filter { $0 != "." }
        let rest = name[dash.upperBound...]
        let title = beforeTags(rest)
        let mainTitle = title.range(of: " - ").map { title[..<$0.lowerBound] } ?? title
        func wordInitials(_ words: Substring) -> String {
            String(words.split { $0 == " " || $0 == "-" }.compactMap { $0.first { $0.isLetter || $0.isNumber } }).uppercased()
        }
        guard initials.count > 1, initials.allSatisfy({ $0.isUppercase || $0.isNumber }),
            initials == wordInitials(title) || initials == wordInitials(mainTitle)
        else { return nil }
        return String(rest)
    }

    static func fuzzy(fileName: String, titles: [String], in index: TitleIndex) -> String? {
        let stem = substituted(Self.stem(fileName))
        return fuzzy(titles: [stem] + titles, regions: ROMName(stem).regions ?? [], in: index)
    }

    /// A title match on each of `titles` in turn, `regions`' release first, else USA, Europe, Japan: how a Game with no
    /// ROM, which has no file name, finds its Box art. Accents are dropped; only once no title matches that way are the
    /// ones with umlauts or macrons tried spelled out, as Redump sometimes writes them (Einhänder is `Einhaender`, Ōkami
    /// is `Ookami`). Only once none of those matches is each tried by its loose title key.
    static func fuzzy(titles: [String], regions: Set<NameRegion>, in index: TitleIndex) -> String? {
        let own = preferredOrder.filter(regions.contains)
        let spelled = titles.map(spelledOut).filter { !titles.contains($0) }
        let tiers: [((String) -> String, [String: [String]])] = [(titleKey, index.byKey), (looseTitleKey, index.byLooseKey)]
        for (key, names) in tiers {
            for title in titles + spelled {
                let key = key(title)
                guard !key.isEmpty, let candidates = names[key] else { continue }
                return candidates.min { rank($0, own) < rank($1, own) }
            }
        }
        return nil
    }

    /// Umlauts as a trailing `e` (ä → ae) and macrons as a doubled vowel (ō → oo).
    static func spelledOut(_ title: String) -> String {
        title.reduce(into: "") { s, c in s += spelledOutLetters[c] ?? String(c) }
    }

    private static let spelledOutLetters: [Character: String] = [
        "ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue",
        "ā": "aa", "ē": "ee", "ī": "ii", "ō": "oo", "ū": "uu", "Ā": "Aa", "Ē": "Ee", "Ī": "Ii", "Ō": "Oo", "Ū": "Uu",
    ]

    /// The file name minus its extension (`.nkit.iso` counts as one).
    static func stem(_ fileName: String) -> String {
        var s = fileName
        if s.lowercased().hasSuffix(".nkit.iso") || s.lowercased().hasSuffix(".nkit.gcz") { s = String(s.dropLast(9)) }
        let ext = (s as NSString).pathExtension
        if !ext.isEmpty, ext.count <= 4, !ext.contains(" ") { s = (s as NSString).deletingPathExtension }
        return s
    }

    /// libretro-thumbnails replaces ``&*/:`<>?\|"`` with `_` in its file names.
    static func substituted(_ name: String) -> String {
        String(name.map { #"&*/:`<>?\|""#.contains($0) ? "_" : $0 })
    }

    static func withoutDisc(_ name: String) -> String {
        name.replacingOccurrences(of: #" \(Dis[ck] \d+\)"#, with: "", options: .regularExpression)
    }

    private static let goodToolsRegions: [String: String] = [
        "U": "USA", "E": "Europe", "J": "Japan", "UE": "USA, Europe", "JU": "Japan, USA", "JUE": "Japan, USA, Europe",
        "JE": "Japan, Europe", "W": "World", "B": "Brazil", "F": "France", "G": "Germany", "K": "Korea",
    ]

    /// `(U)` → `(USA)`, `(V1.1)` → `(Rev 1)`; square-bracket flags and `(M5)`-style language counts dropped.
    static func goodToolsRewritten(_ name: String) -> String {
        var s = name.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\(M\d+\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([Vv]1\.(\d+)\)"#, with: "(Rev $1)", options: .regularExpression)
        for (code, region) in goodToolsRegions { s = s.replacingOccurrences(of: "(\(code))", with: "(\(region))") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The text before the first tag, normalised: the article dropped from the start or end of the title and of its
    /// subtitle, wherever No-Intro (`Legend of Zelda, The - Spirit Tracks`), GoodTools (`Legend of Zelda - Spirit Tracks,
    /// The`) or IGDB (`The Legend of Zelda: Spirit Tracks`) puts it, `&` and `_` read as "and", only letters and digits
    /// kept.
    static func titleKey(_ name: String) -> String {
        var title = beforeTags(name).replacingOccurrences(of: #"\s+-\s+|:\s+"#, with: "\n", options: .regularExpression)
            .split(separator: "\n")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"^(The|A|An) |, (The|A|An)$"#, with: "", options: .regularExpression)
            }
            .joined(separator: " ")
        title = title.replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "_", with: " and ")
        return String(title.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber })
    }

    /// The text before the first tag (`(` or `[`).
    static func beforeTags<S: StringProtocol>(_ name: S) -> S.SubSequence { name.prefix { $0 != "(" && $0 != "[" } }

    /// The text before the first tag with "a", "an", "the", "and" and "in" dropped wherever they are, for the last try: a
    /// Standard name or IGDB's can keep small words No-Intro leaves out (`Spider-Man and the X-Men in Arcade's Revenge`
    /// is `Spider-Man - X-Men - Arcade's Revenge`).
    static func looseTitleKey(_ name: String) -> String {
        let title = String(beforeTags(name))
            .replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "_", with: " and ")
        return title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !($0.isLetter || $0.isNumber) }
            .filter { !smallWords.contains($0) }
            .joined()
    }

    private static let smallWords: Set<Substring> = ["a", "an", "the", "and", "in"]

    private static func isPrerelease(_ name: String) -> Bool {
        name.range(of: #"\((Beta|Proto|Prototype|Demo|Sample|Kiosk)( \d+)?\)"#, options: .regularExpression) != nil
    }

    private static let preferredOrder: [NameRegion] = [.usa, .europe, .japan]

    /// Lower is better: the ROM's own region, else USA, Europe, Japan; then a disc-less name, then the shortest.
    private static func rank(_ name: String, _ own: [NameRegion]) -> (Int, Int, Int, String) {
        let regions = ROMName(name).regions ?? []
        let order = own + preferredOrder.filter { !own.contains($0) }
        let region = order.firstIndex(where: regions.contains) ?? order.count
        return (region, withoutDisc(name) == name ? 0 : 1, name.count, name)
    }
}

/// One libretro-thumbnails folder's image names (without `.png`), looked in for any number of ROMs: the title index a
/// fuzzy match needs is worked out once, the first time an exact name misses, not for every ROM.
struct LibretroFolder: Sendable {
    let names: Set<String>
    private var byTitle: LibretroLookup.TitleIndex?

    init(_ names: Set<String>) { self.names = names }

    mutating func find(fileName: String, titles: [String]) -> String? {
        if let exact = LibretroLookup.exact(fileName: fileName, in: names) { return exact }
        let index = byTitle ?? LibretroLookup.titleIndex(names)
        byTitle = index
        return LibretroLookup.fuzzy(fileName: fileName, titles: titles, in: index)
    }
}
