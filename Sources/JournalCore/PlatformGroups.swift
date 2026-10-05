import GRDB

/// IGDB platforms shown as one: in the sidebar, the Platform filter, the Library and Year in review.
/// Each Game keeps its own IGDB platform; only how it's shown changes.
public enum PlatformGroups {
    /// The first id is the one the group shows under.
    static let groups: [(name: String, ids: [Int64])] = [
        ("PC", [6, 13]),  // PC (Microsoft Windows), DOS
        ("Super Nintendo Entertainment System", [19, 58]),  // SNES, Super Famicom
        ("Nintendo Entertainment System", [18, 99]),  // NES, Family Computer
    ]

    /// The id a platform shows under: its group's first, else its own.
    public static func shownID(_ id: Int64) -> Int64 { groups.first { $0.ids.contains(id) }?.ids[0] ?? id }

    /// The platforms a shown id stands for.
    static func ids(shownAs id: Int64) -> [Int64] { groups.first { $0.ids[0] == id }?.ids ?? [id] }

    /// The group's name, if the platform is in one.
    static func groupName(_ id: Int64) -> String? { groups.first { $0.ids.contains(id) }?.name }

    /// SQL for the name a Game's platform shows as, given its `platformId` and platform `name` columns.
    static func shownNameSQL(platformId: String, name: String) -> String {
        let whens = groups.flatMap { g in g.ids.map { "WHEN \($0) THEN '\(g.name)'" } }
        return whens.isEmpty ? name : "CASE \(platformId) \(whens.joined(separator: " ")) ELSE \(name) END"
    }
}

extension JournalStore {
    /// The Platforms the Library offers to filter on: those with Games, grouped, by name.
    public func shownPlatforms() throws -> [IGDBPlatform] {
        try platformCounts().map { IGDBPlatform(id: $0.id, name: $0.name, abbreviation: nil) }
    }
}
