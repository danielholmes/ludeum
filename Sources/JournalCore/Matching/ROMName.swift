import Foundation

/// The regions an IGDB regional name can belong to.
public enum NameRegion: Sendable, Hashable {
    case japan, usa, europe, korea
}

/// What a ROM's name says beyond its title: its Version text, Disc and regions.
///
/// Real names mix No-Intro, Redump, GoodTools, scene and ad-hoc forms, so the Version
/// isn't parsed into fields: it's the name's tags as written, in order, without the Disc
/// and its label, GoodTools dump flags and file artefacts.
public struct ROMName: Sendable, Hashable {
    public let raw: String
    /// The name before its first tag.
    public private(set) var title = ""
    public private(set) var version = ""
    public private(set) var disc: Int?
    /// The free-form tag straight after `(Disc N)`, e.g. "Claire".
    public private(set) var discLabel: String?
    /// The regions the name's tags say, or nil if it says none.
    public private(set) var regions: Set<NameRegion>?

    public init(_ raw: String) {
        self.raw = raw
        let ns = raw as NSString
        let tags = Self.tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        title = (tags.first.map { ns.substring(to: $0.range.location) } ?? raw).trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        var regionNames: [String] = []
        var afterDisc = false
        for m in tags {
            let square = m.range(at: 2).location != NSNotFound
            let t = ns.substring(with: m.range(at: square ? 2 : 1)).trimmingCharacters(in: .whitespaces)
            let wasAfterDisc = afterDisc
            afterDisc = false
            if square {
                if matches(t, #"^T[+-]"#) {
                    parts.append(t)
                } else if !matches(t, Self.dumpFlag) && !matches(t, Self.serial) {
                    parts.append(t)
                }
                continue
            }
            if let n = t.wholeMatch(of: /Disc (\d+)/) {
                disc = Int(n.1)
                afterDisc = true
                continue
            }
            let listed = t.components(separatedBy: ", ")
            if listed.allSatisfy(Self.noIntroRegions.contains) {
                regionNames += listed
            } else if let codes = Self.goodToolsRegions[t] {
                regionNames += codes
            } else if wasAfterDisc && !Self.isRecognised(t) {
                discLabel = t
                continue
            }
            parts.append(t)
        }
        if let last = tags.last {
            let suffix = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            if matches(suffix, #"(?i)patch|english|translat"#) {
                parts.append(suffix.trimmingCharacters(in: CharacterSet(charactersIn: "- ")))
            }
            // Anything else after the last tag is a file artefact: a copy number, ".nkit", …
        }
        version = parts.joined(separator: " · ")
        let found = Set(regionNames.flatMap { Self.regionsByName[$0] ?? [] })
        regions = found.isEmpty ? nil : found
    }

    private static let tag = try! NSRegularExpression(pattern: #"\(([^\)]*)\)|\[([^\]]*)\]"#)
    private static let dumpFlag = #"^(!|a\d*|b\d*|f\d*|h.*|o\d*|p\d*|t\d*|C|S|BF|x)$"#
    private static let serial = #"^[A-Z]{4}[-_ ]?\d{3}\.?\d{2}$"#

    /// A tag that means something on its own, so it can't be a disc label.
    private static func isRecognised(_ t: String) -> Bool {
        matches(t, #"^[A-Z][a-z](-[A-Z]{2})?(,[A-Z][a-z](-[A-Z]{2})?)*$"#) || matches(t, #"^M\d+$"#)
            || matches(t, #"^(Rev [A-Z0-9]+|[vV]\d+(\.\d+)*[a-z]?)$"#)
            || matches(t, #"^(Beta|Proto|Prototype|Demo|Sample|Kiosk|Possible Proto|Promo)( \d+)?$"#)
            || matches(t, #"^\d{4}-\d{2}-\d{2}$"#) || matches(t, #"(?i)^(english|eng\b|t-?eng|translat)"#)
    }

    private static let noIntroRegions: Set<String> = [
        "USA", "Europe", "Japan", "World", "Asia", "Australia", "Brazil", "Canada", "China", "France", "Germany",
        "Hong Kong", "Italy", "Korea", "Netherlands", "Spain", "Sweden", "Taiwan", "UK", "Russia", "Scandinavia",
        "Latin America", "Unknown",
    ]
    private static let goodToolsRegions: [String: [String]] = [
        "U": ["USA"], "E": ["Europe"], "J": ["Japan"], "UE": ["USA", "Europe"], "JU": ["Japan", "USA"],
        "JUE": ["Japan", "USA", "Europe"], "JE": ["Japan", "Europe"], "B": ["Brazil"], "4": ["USA", "Brazil"],
        "W": ["World"], "US": ["USA"], "EU": ["Europe"], "F": ["France"], "G": ["Germany"], "K": ["Korea"],
    ]
    private static let regionsByName: [String: Set<NameRegion>] = {
        var out: [String: Set<NameRegion>] = [
            "Japan": [.japan], "USA": [.usa], "Canada": [.usa], "Korea": [.korea], "World": [.japan, .usa, .europe],
        ]
        for e in ["Europe", "UK", "Australia", "France", "Germany", "Spain", "Italy", "Netherlands", "Sweden", "Scandinavia"] {
            out[e] = [.europe]
        }
        return out
    }()
}

func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
