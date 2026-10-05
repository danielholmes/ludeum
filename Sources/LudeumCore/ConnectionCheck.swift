/// A live check that IGDB and Hasheous answer: Settings' "Test connection" and `ludeum-import check`.
public enum ConnectionCheck {
    /// A public reference hash from Hasheous's own docs (Jumpman Junior, C64).
    static let hasheousReferenceMD5 = "5d7550788a4d1b47ad81fbbbf5c615a9"

    public struct Report: Sendable {
        public let igdbGameName: String
        public let hasheousGameID: Int?

        public var summary: String {
            "IGDB found \(igdbGameName). Hasheous "
                + (hasheousGameID.map { "answered (IGDB game \($0))." } ?? "answered, without an IGDB game.")
        }
    }

    /// Searches IGDB for Super Mario World on SNES, fetches its record, and looks up a known hash.
    /// Throws if either service fails, e.g. on wrong IGDB credentials.
    public static func run(igdb: IGDBClient, hasheous: HasheousClient) async throws -> Report {
        let search = IGDBSearch(name: "Super Mario World", platformID: 19)  // 19 = SNES
        guard let first = try await igdb.search([search])[search]?.first, let game = try await igdb.games(ids: [first])[first]
        else { throw ConnectionCheckError.noIGDBResult }
        let hash = try await hasheous.lookup(md5: hasheousReferenceMD5)
        return Report(igdbGameName: game.name ?? "game \(first)", hasheousGameID: hash.match?.igdbGameID)
    }
}

public enum ConnectionCheckError: Error, CustomStringConvertible {
    case noIGDBResult
    public var description: String { "IGDB answered, but found nothing for Super Mario World on SNES." }
}
