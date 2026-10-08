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

    /// A folder's released names by title key: what a fuzzy match looks in.
    static func titleIndex(_ names: Set<String>) -> [String: [String]] {
        Dictionary(grouping: names.filter { !isPrerelease($0) }, by: { titleKey($0) })
    }

    static func fuzzy(fileName: String, titles: [String], in byTitle: [String: [String]]) -> String? {
        let stem = substituted(Self.stem(fileName))
        return fuzzy(titles: [stem] + titles, regions: ROMName(stem).regions ?? [], in: byTitle)
    }

    /// A title match on each of `titles` in turn, `regions`' release first, else USA, Europe, Japan: how a Game with no
    /// ROM, which has no file name, finds its Box art.
    static func fuzzy(titles: [String], regions: Set<NameRegion>, in byTitle: [String: [String]]) -> String? {
        let own = preferredOrder.filter(regions.contains)
        for title in titles {
            let key = titleKey(title)
            guard !key.isEmpty, let candidates = byTitle[key] else { continue }
            return candidates.min { rank($0, own) < rank($1, own) }
        }
        return nil
    }

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

    /// The text before the first tag, normalised: articles moved to the front, `&` and `_` read as "and",
    /// only letters and digits kept.
    static func titleKey(_ name: String) -> String {
        var title = String(name.prefix { $0 != "(" && $0 != "[" }).trimmingCharacters(in: .whitespaces)
        if let r = title.range(of: #", (The|A|An)$"#, options: .regularExpression) {
            title = "\(title[r].dropFirst(2)) " + title[..<r.lowerBound]
        }
        title = title.replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "_", with: " and ")
        return String(title.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber })
    }

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
    private var byTitle: [String: [String]]?

    init(_ names: Set<String>) { self.names = names }

    mutating func find(fileName: String, titles: [String]) -> String? {
        if let exact = LibretroLookup.exact(fileName: fileName, in: names) { return exact }
        let index = byTitle ?? LibretroLookup.titleIndex(names)
        byTitle = index
        return LibretroLookup.fuzzy(fileName: fileName, titles: titles, in: index)
    }
}
