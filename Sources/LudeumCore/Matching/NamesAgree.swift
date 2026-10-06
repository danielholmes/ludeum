import Foundation

/// Whether a ROM's names agree with an IGDB game's: any ROM-side name equals any IGDB-side
/// name after normalising. Never a prefix or containment test, because nearly every wrong
/// checksum match is the IGDB name being a prefix of the ROM's title (ADR 0004).
///
/// ROM side: the ROM's name. IGDB side: the game's name, its alternative names and its localizations,
/// where a regional one only counts for a ROM from that region (or of unknown region).
public func namesAgree(romName: String, game: IGDBGame) -> Bool {
    let keys = Set(romTitles(romName).map(nameKey)).subtracting([""])
    let regions = ROMName(romName).regions
    return igdbNames(game, for: regions).contains { keys.contains(nameKey(cleanName($0))) }
}

/// The title strings a ROM name offers, cleaned but not yet normalised.
func romTitles(_ raw: String) -> [String] {
    var s = raw
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
    var out: [String] = []
    for part in s.components(separatedBy: " ~ ") {
        let c = cleanName(part)
        out.append(c)
        if let i = c.range(of: ": ") { out.append("\(c[i.upperBound...]): \(c[..<i.lowerBound])") }
    }
    return out
}

/// "Lost Vikings, The (U) [!]" → "The Lost Vikings"; "Foo - Bar (USA)" → "Foo: Bar".
public func cleanName(_ raw: String) -> String {
    var s = sub(raw, #"\s*[\(\[][^\)\]]*[\)\]]"#, "").trimmingCharacters(in: .whitespaces)
    if let r = s.range(of: #", (The|A|An)\b"#, options: .regularExpression) {
        let article = s[r].dropFirst(2)
        s = "\(article) " + s.replacingCharacters(in: r, with: "")
    }
    return s.replacingOccurrences(of: " - ", with: ": ")
}

/// The normalised form two names are compared in.
func nameKey(_ raw: String) -> String {
    let s = raw.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "&", with: " and ")
    var words = s.split { !($0.isLetter || $0.isNumber) }.map { romanNumerals[String($0)].map(String.init) ?? String($0) }
    if let p = droppedPrefixes.first(where: { words.starts(with: $0) && words.count > $0.count }) { words.removeFirst(p.count) }
    words.removeAll { $0 == "and" || $0 == "the" }
    if let f = words.first, f == "a" || f == "an", words.count > 1 { words.removeFirst() }
    return words.joined()
}

/// II–XX; not I, V or X, which are as often words or letters as numbers.
private let romanNumerals: [String: Int] = [
    "ii": 2, "iii": 3, "iv": 4, "vi": 6, "vii": 7, "viii": 8, "ix": 9, "xi": 11, "xii": 12, "xiii": 13,
    "xiv": 14, "xv": 15, "xvi": 16, "xvii": 17, "xviii": 18, "xix": 19, "xx": 20,
]

private let droppedPrefixes: [[String]] = [
    ["disney", "pixar", "s"], ["disney", "s"], ["james", "bond"], ["tom", "clancy", "s"], ["sid", "meier", "s"],
]

/// An IGDB game's names, leaving out regional ones from regions the ROM isn't from.
private func igdbNames(_ game: IGDBGame, for regions: Set<NameRegion>?) -> [String] {
    func counts(_ region: NameRegion?) -> Bool {
        guard let region, let regions else { return true }
        return regions.contains(region)
    }
    var out = [game.name].compactMap { $0 }
    for alt in game.record["alternative_names"]?.array ?? [] {
        guard let name = alt["name"]?.string else { continue }
        let comment = (alt["comment"]?.string ?? "").lowercased()
        let region: NameRegion? =
            comment.hasPrefix("japanese")
            ? .japan
            : comment.hasPrefix("european")
                ? .europe
                : comment.hasPrefix("korean")
                    ? .korea
                    : (comment.hasPrefix("north american") || comment.hasPrefix("american")) ? .usa : nil
        if counts(region) { out.append(name) }
    }
    for localization in game.record["game_localizations"]?.array ?? [] {
        guard let name = localization["name"]?.string else { continue }
        let region: NameRegion? = [2: .korea, 3: .japan, 4: .europe][localization["region"]?.int ?? 0]
        if counts(region) { out.append(name) }
    }
    return out
}

private func sub(_ s: String, _ pattern: String, _ with: String) -> String {
    s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
}
