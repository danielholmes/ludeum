import Foundation
import GRDB

/// `into-bundles`: the one-off move into Bundles (ADR 0016) of the Games that were really Bundles, each containing the
/// Games IGDB lists for it, and of the Copies I'd recorded once per Game of one box, as a Bundle made by hand with one
/// Copy. A Game becoming a Bundle keeps its Copies, ROMs, Attachments and Highlight note, and loses its Rating; one with
/// Playthroughs, Intent, Childhood or Battles is a problem, and nothing changes until it's dealt with.
public struct IntoBundles: Sendable {
    /// What to move.
    public struct Spec: Sendable {
        /// The IGDB games whose Games become Bundles.
        public var fromGames: [Int64]
        public var byHand: [HandMade]

        public init(fromGames: [Int64], byHand: [HandMade] = []) {
            self.fromGames = fromGames
            self.byHand = byHand
        }
    }

    /// A box I'd recorded as one Copy per Game: a Bundle with no IGDB link, on its Games' Platform.
    public struct HandMade: Sendable {
        public var name: String
        /// Its Games, by their IGDB games.
        public var games: [Int64]
        /// The Bundle's one Copy.
        public var copy: CopyDraft
        /// What the Copies it replaces were acquired from, at its start.
        public var replacing: String

        public init(name: String, games: [Int64], copy: CopyDraft, replacing: String) {
            self.name = name
            self.games = games
            self.copy = copy
            self.replacing = replacing
        }
    }

    /// Mine, as settled for issue #78.
    public static let mine = Spec(
        fromGames: [
            5199,  // Super Mario All-Stars
            81197,  // Super Mario Advance
            16617,  // Super Mario World: Super Mario Advance 2
            16747,  // Yoshi's Island: Super Mario Advance 3
            49835,  // Konami GB Collection Vol. 1
            50043,  // Konami GB Collection Vol. 4
            42896,  // Call of Duty: Infinite Warfare - Legacy Edition
            18165,  // Command & Conquer: The First Decade
            7348,  // Halo: The Master Chief Collection
            42729,  // Ninja Gaiden Trilogy
            408,  // Final Fantasy I & II: Dawn of Souls
            49895,  // Déjà Vu I & II: The Casebooks of Ace Harding
            5004,  // Metal Slug Anthology
            28230,  // Outlast: Trinity
            49829,  // R-Type DX
        ],
        byHand: [
            HandMade(
                name: "Command & Conquer and Red Alert compilation", games: [647, 663, 295, 676, 652],
                copy: CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: "Game Wizards"), gone: Gone()),
                replacing: "Game Wizards, compilation"),
            HandMade(
                name: "Duke Nukem 3D, Shadow Warrior and Final Doom", games: [342, 2947, 8191],
                copy: CopyDraft(kind: .physical, gone: Gone()),
                replacing: "bought in a bundle with Duke Nukem 3D, Shadow Warrior and Final Doom"),
        ])

    /// One Bundle to make.
    public struct PlannedBundle: Sendable, Equatable {
        public let name: String
        public let platformId: Int64
        /// The Game that becomes it; nil for one made by hand.
        public let game: GameID?
        public let contents: [PlannedGame]
        /// The Rating it loses, as a Bundle has none.
        public let droppedRating: Rating?
        /// A Bundle made by hand: its one Copy, and the Copies of its Games it replaces.
        public let copy: CopyDraft?
        public let replacedCopies: [Int64]
    }

    /// A Game a Bundle will contain: one already in the journal, or one to add.
    public struct PlannedGame: Sendable, Equatable {
        public let name: String
        public let igdbGameId: Int64?
        public let game: GameID?
    }

    public struct Plan: Sendable, Equatable {
        public var bundles: [PlannedBundle] = []
        /// Bundles already made, by a run before: nothing to do.
        public var done: [String] = []
        public var problems: [String] = []
        public var isRunnable: Bool { problems.isEmpty }
    }

    /// The plan has problems, so nothing was changed.
    public struct NotRunnable: Error {}

    let journal: LudeumStore
    let igdb: IGDBClient
    let backups: Backups
    let spec: Spec

    public init(journal: LudeumStore, igdb: IGDBClient, backups: Backups, spec: Spec = IntoBundles.mine) {
        self.journal = journal
        self.igdb = igdb
        self.backups = backups
        self.spec = spec
    }

    /// What a run would do, reading IGDB for each Bundle's contents. Changes nothing.
    public func plan() async throws -> Plan {
        var plan = Plan()
        for igdbGameId in spec.fromGames {
            let games = try journal.games(igdbGameId: igdbGameId)
            guard games.count == 1, let game = games.first else {
                plan.problems.append("IGDB game \(igdbGameId) is \(games.count) Games, not one")
                continue
            }
            if game.isBundle {
                plan.done.append(game.name)
                continue
            }
            let blockers = try await journal.db.read { db in
                func has(_ sql: String) throws -> Bool { try Bool.fetchOne(db, sql: sql, arguments: [game.id, game.id])! }
                return [
                    try has("SELECT EXISTS (SELECT 1 FROM playthrough WHERE gameId = ? OR gameId = ?)") ? "Playthroughs" : nil,
                    game.intent != nil ? "an Intent" : nil,
                    game.childhood ? "Childhood" : nil,
                    try has("SELECT EXISTS (SELECT 1 FROM battle WHERE gameAId = ? OR gameBId = ?)") ? "Battles" : nil,
                ].compactMap { $0 }
            }
            plan.problems += blockers.map { "\(game.name) has \($0)" }
            let ids = try await igdb.bundleContents(of: Int(igdbGameId))
            let records = try await igdb.games(ids: ids)
            let contents = try ids.compactMap { records[$0] }.map { record in
                PlannedGame(
                    name: record.name ?? "Game \(record.id)", igdbGameId: Int64(record.id),
                    game: try journal.gameID(igdbGameId: Int64(record.id), platformId: game.platformId))
            }
            plan.bundles.append(
                PlannedBundle(
                    name: game.name, platformId: game.platformId, game: game.id, contents: contents, droppedRating: game.rating,
                    copy: nil, replacedCopies: []))
        }
        for box in spec.byHand {
            let games = try box.games.flatMap { try journal.games(igdbGameId: $0) }
            guard games.count == box.games.count, let platformId = games.first?.platformId,
                games.allSatisfy({ $0.platformId == platformId })
            else {
                plan.problems.append("\(box.name): its Games aren't one each on one Platform")
                continue
            }
            if try journal.gameID(named: box.name, platformId: platformId).map(journal.game)?.isBundle == true {
                plan.done.append(box.name)
                continue
            }
            let replaced = try games.flatMap { try journal.copies(of: $0.id) }
                .filter { $0.draft.details.acquiredFrom?.hasPrefix(box.replacing) == true }.map(\.id)
            if try await journal.db.read({ db in
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS (SELECT 1 FROM playthrough WHERE copyId IN (\(databaseQuestionMarks(count: replaced.count))))",
                    arguments: StatementArguments(replaced))!
            }) {
                plan.problems.append("\(box.name): a Playthrough was played on a Copy it replaces")
            }
            plan.bundles.append(
                PlannedBundle(
                    name: box.name, platformId: platformId, game: nil,
                    contents: games.map { PlannedGame(name: $0.name, igdbGameId: $0.igdbGameId, game: $0.id) }, droppedRating: nil,
                    copy: box.copy, replacedCopies: replaced))
        }
        return plan
    }

    /// Takes a backup, then makes every Bundle in `plan` in one transaction. Refused, with nothing changed, while it has
    /// problems.
    @discardableResult
    public func run(_ plan: Plan) async throws -> Backup? {
        guard plan.isRunnable else { throw NotRunnable() }
        guard !plan.bundles.isEmpty else { return nil }
        let backup = try backups.backUp(journal, operation: .beforeIntoBundles)
        try await journal.db.write { db in
            for planned in plan.bundles {
                let bundle: GameID
                if let game = planned.game {
                    bundle = game
                    try db.execute(sql: "UPDATE game SET bundle = 1 WHERE id = ?", arguments: [game])
                    try db.execute(sql: "DELETE FROM ratingEntry WHERE gameId = ?", arguments: [game])
                    try db.execute(sql: "DELETE FROM keptRating WHERE gameId = ?", arguments: [game])
                    try db.execute(sql: "DELETE FROM battleSkip WHERE gameAId = ? OR gameBId = ?", arguments: [game, game])
                } else {
                    try db.execute(
                        sql: "INSERT INTO game (platformId, name, bundle) VALUES (?, ?, 1)", arguments: [planned.platformId, planned.name])
                    bundle = db.lastInsertedRowID
                }
                for content in planned.contents {
                    let game: GameID
                    // An earlier Bundle of this run may have added it already (Mario Bros. is in all three Super Mario Advances).
                    let added = try content.igdbGameId.flatMap { igdbGameId in
                        try GameID.fetchOne(
                            db, sql: "SELECT id FROM game WHERE igdbGameId = ? AND platformId = ?",
                            arguments: [igdbGameId, planned.platformId])
                    }
                    if let existing = content.game ?? added {
                        game = existing
                    } else {
                        try db.execute(
                            sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                            arguments: [
                                planned.platformId, content.name, content.igdbGameId, content.igdbGameId == nil ? nil : content.name,
                            ])
                        game = db.lastInsertedRowID
                    }
                    try db.execute(sql: "INSERT OR IGNORE INTO bundleGame (bundleId, gameId) VALUES (?, ?)", arguments: [bundle, game])
                }
                if let copy = planned.copy {
                    try db.execute(
                        sql: """
                            INSERT INTO copy (gameId, kind, acquiredFrom, notes, gone, goneOn, goneTo)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            bundle, copy.kind.rawValue, copy.details.acquiredFrom, copy.details.notes, copy.gone != nil,
                            copy.gone?.on?.text, copy.gone?.to,
                        ])
                }
                for id in planned.replacedCopies {
                    try db.execute(sql: "DELETE FROM copy WHERE id = ?", arguments: [id])
                }
            }
        }
        return backup
    }
}

extension LudeumStore {
    /// The Game or Bundle on `platformId` whose own name is `name`, if any.
    func gameID(named name: String, platformId: Int64) throws -> GameID? {
        try db.read { db in
            try GameID.fetchOne(
                db, sql: "SELECT id FROM game WHERE platformId = ? AND COALESCE(nameOverride, igdbName, name) = ? ORDER BY id",
                arguments: [platformId, name])
        }
    }
}
