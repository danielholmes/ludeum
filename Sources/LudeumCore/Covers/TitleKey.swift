import Foundation

/// A name's two title keys, each a column of `launchbox_name`, tried in turn: how a Game's names find its LaunchBox
/// game. Accents are dropped; only once no title matches that way are the ones with umlauts or macrons tried spelled
/// out (`spelledOut`), as some names write them (Einhänder is `Einhaender`, Ōkami is `Ookami`).
enum TitleKey: String, CaseIterable {
    case title = "title_key"
    case loose = "loose_title_key"

    func of(_ title: String) -> String {
        switch self {
        case .title: Self.titleKey(title)
        case .loose: Self.looseTitleKey(title)
        }
    }

    /// The text before the first tag, normalised: the article dropped from the start or end of the title and of its
    /// subtitle, wherever No-Intro (`Legend of Zelda, The - Spirit Tracks`), GoodTools (`Legend of Zelda - Spirit Tracks,
    /// The`) or IGDB (`The Legend of Zelda: Spirit Tracks`) puts it, `&` and `_` read as "and", only letters and digits
    /// kept.
    private static func titleKey(_ name: String) -> String {
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

    /// The text before the first tag with "a", "an", "the", "and" and "in" dropped wherever they are, for the last try: a
    /// Standard name or IGDB's can keep small words another leaves out (`Spider-Man and the X-Men in Arcade's Revenge`
    /// is `Spider-Man - X-Men - Arcade's Revenge`).
    private static func looseTitleKey(_ name: String) -> String {
        let title = String(beforeTags(name))
            .replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "_", with: " and ")
        return title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !($0.isLetter || $0.isNumber) }
            .filter { !smallWords.contains($0) }
            .joined()
    }

    private static let smallWords: Set<Substring> = ["a", "an", "the", "and", "in"]

    /// The text before the first tag (`(` or `[`).
    private static func beforeTags<S: StringProtocol>(_ name: S) -> S.SubSequence { name.prefix { $0 != "(" && $0 != "[" } }

    /// Umlauts as a trailing `e` (ä → ae) and macrons as a doubled vowel (ō → oo).
    static func spelledOut(_ title: String) -> String {
        title.reduce(into: "") { s, c in s += spelledOutLetters[c] ?? String(c) }
    }

    private static let spelledOutLetters: [Character: String] = [
        "ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue",
        "ā": "aa", "ē": "ee", "ī": "ii", "ō": "oo", "ū": "uu", "Ā": "Aa", "Ē": "Ee", "Ī": "Ii", "Ō": "Oo", "Ū": "Uu",
    ]
}
