import Foundation
import GRDB

/// What kind of Copy one I record by hand is. A ROM is the fourth Kind, and is a ROM row, not one of these.
public enum CopyKind: String, Sendable, CaseIterable {
    case physical, digital
    /// A disc that came with a linked digital licence: one Copy, not two.
    case physicalAndDigital
}

/// What a Copy cost: an amount in a currency, since a Japanese cart isn't bought in dollars.
public struct Price: Sendable, Equatable {
    public var amount: Decimal
    /// A 3-letter code, e.g. "AUD".
    public var currency: String

    /// The currency a price is in unless I say otherwise.
    public static let homeCurrency = "AUD"

    public init(amount: Decimal, currency: String = Price.homeCurrency) {
        self.amount = amount
        self.currency = currency
    }
}

/// What every Copy can say about itself, ROMs included: its Regions, and where, when and for how much it was acquired.
public struct CopyDetails: Sendable, Equatable {
    /// Where it was released for, e.g. "USA", "Europe". Any text, though the usual ones are offered (`Regions.suggested`).
    public var regions: [String]
    public var acquiredOn: PartialDate?
    public var acquiredFrom: String?
    public var price: Price?

    public init(regions: [String] = [], acquiredOn: PartialDate? = nil, acquiredFrom: String? = nil, price: Price? = nil) {
        self.regions = regions
        self.acquiredOn = acquiredOn
        self.acquiredFrom = acquiredFrom
        self.price = price
    }
}

/// A Copy I no longer have: where it went and when, both optional.
public struct Gone: Sendable, Equatable {
    public var on: PartialDate?
    public var to: String?

    public init(on: PartialDate? = nil, to: String? = nil) {
        self.on = on
        self.to = to
    }
}

/// A hand-recorded Copy's fields, for adding or editing one.
public struct CopyDraft: Sendable, Equatable {
    public var kind: CopyKind
    public var details: CopyDetails
    /// Set once I no longer have it. Nil is Owned.
    public var gone: Gone?

    public init(kind: CopyKind, details: CopyDetails = CopyDetails(), gone: Gone? = nil) {
        self.kind = kind
        self.details = details
        self.gone = gone
    }

    /// A Copy can't go before it was acquired, though a less precise date that contains the other is fine
    /// (acquired `2024-03`, gone `2024`).
    func validate() throws {
        if let on = gone?.on, let acquired = details.acquiredOn, on < acquired, !on.contains(acquired) {
            throw LudeumError.goneBeforeAcquired
        }
    }
}

/// A hand-recorded Copy, as Game detail shows it.
public struct Copy: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let draft: CopyDraft

    public init(id: Int64, _ draft: CopyDraft) {
        self.id = id
        self.draft = draft
    }
}

public enum Regions {
    /// The Regions offered first: the ones my Copies are for, in the order they're shown.
    public static let suggested = ["Europe", "USA", "World", "Australia", "Japan", "Asia"]

    /// Regions in the order they're shown, without repeats: the usual ones in their order, then the rest alphabetically.
    public static func ordered(_ regions: [String]) -> [String] {
        var seen: [String] = []
        for r in regions where !seen.contains(r) { seen.append(r) }
        return seen.sorted { a, b in
            switch (suggested.firstIndex(of: a), suggested.firstIndex(of: b)) {
            case (let i?, let j?): i < j
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        }
    }

    /// How a Copy's Regions are stored: a JSON array of their names in their shown order, or nothing for none.
    static func encode(_ regions: [String]) -> String? {
        let regions = ordered(regions)
        guard !regions.isEmpty else { return nil }
        return String(decoding: try! JSONEncoder().encode(regions), as: UTF8.self)
    }

    static func decode(_ text: String?) -> [String] {
        guard let text, let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

extension LudeumStore {
    // MARK: Hand-recorded Copies

    @discardableResult
    public func addCopy(_ game: GameID, _ draft: CopyDraft) throws -> Int64 {
        try draft.validate()
        return try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO copy (gameId, kind, regions, acquiredOn, acquiredFrom, price, currency, gone, goneOn, goneTo)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [game, draft.kind.rawValue] + Self.arguments(draft.details) + Self.arguments(draft.gone))
            return db.lastInsertedRowID
        }
    }

    public func updateCopy(_ id: Int64, _ draft: CopyDraft) throws {
        try draft.validate()
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE copy SET kind = ?, regions = ?, acquiredOn = ?, acquiredFrom = ?, price = ?, currency = ?,
                        gone = ?, goneOn = ?, goneTo = ?
                    WHERE id = ?
                    """,
                arguments: [draft.kind.rawValue] + Self.arguments(draft.details) + Self.arguments(draft.gone) + [id])
        }
    }

    /// Deletes a hand-recorded Copy for good, unlike marking it Gone. A ROM is deleted with `deleteROM(_:romFolders:)`.
    public func deleteCopy(_ id: Int64) throws {
        try backups?.backUp(self, operation: .beforeDelete)
        try db.write { db in try db.execute(sql: "DELETE FROM copy WHERE id = ?", arguments: [id]) }
    }

    /// A Game's hand-recorded Copies: Owned before Gone, each by when acquired (undated last), then as added.
    public func copies(of game: GameID) throws -> [Copy] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM copy WHERE gameId = ? ORDER BY gone, acquiredOn IS NULL, acquiredOn, id", arguments: [game]
            ).map { row in
                Copy(
                    id: row["id"],
                    CopyDraft(
                        kind: CopyKind(rawValue: row["kind"])!, details: Self.details(row),
                        gone: row["gone"] ? Gone(on: (row["goneOn"] as String?).flatMap(PartialDate.init), to: row["goneTo"]) : nil))
            }
        }
    }

    // MARK: ROM Copies

    /// Sets a ROM's Copy details: the fields it shares with every other Copy.
    public func setROMDetails(_ rom: Int64, _ details: CopyDetails) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE rom SET regions = ?, acquiredOn = ?, acquiredFrom = ?, price = ?, currency = ? WHERE id = ?",
                arguments: Self.arguments(details) + [rom])
        }
    }

    // MARK: Suggestions

    /// Regions to offer: the usual ones, then every other I've used, alphabetically.
    public func regionSuggestions() throws -> [String] {
        let used = try db.read { db in
            try String.fetchAll(db, sql: "SELECT regions FROM copy UNION SELECT regions FROM rom")
        }
        let others = Set(used.flatMap(Regions.decode)).subtracting(Regions.suggested)
        return Regions.suggested + others.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Where I've acquired Copies from, most used first.
    public func acquiredFromSuggestions() throws -> [String] {
        try db.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT acquiredFrom FROM (
                        SELECT acquiredFrom FROM copy WHERE acquiredFrom IS NOT NULL
                        UNION ALL SELECT acquiredFrom FROM rom WHERE acquiredFrom IS NOT NULL)
                    GROUP BY acquiredFrom ORDER BY COUNT(*) DESC, acquiredFrom COLLATE NOCASE
                    """)
        }
    }

    static func details(_ row: Row) -> CopyDetails {
        CopyDetails(
            regions: Regions.decode(row["regions"]),
            acquiredOn: (row["acquiredOn"] as String?).flatMap(PartialDate.init),
            acquiredFrom: row["acquiredFrom"],
            price: (row["price"] as String?).flatMap { Decimal(string: $0) }.map { Price(amount: $0, currency: row["currency"]) })
    }

    /// `regions, acquiredOn, acquiredFrom, price, currency`.
    private static func arguments(_ d: CopyDetails) -> StatementArguments {
        [Regions.encode(d.regions), d.acquiredOn?.text, d.acquiredFrom, d.price.map { "\($0.amount)" }, d.price?.currency]
    }

    /// `gone, goneOn, goneTo`.
    private static func arguments(_ gone: Gone?) -> StatementArguments {
        [gone != nil, gone?.on?.text, gone?.to]
    }
}
