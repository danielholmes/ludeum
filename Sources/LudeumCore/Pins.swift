import GRDB

/// A franchise, series, theme or company pinned to the sidebar, which opens the Library filtered to it.
public struct Pin: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case franchise, series, theme, company
    }

    public let kind: Kind
    /// IGDB's name for it.
    public let name: String

    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }

    /// The Library filter it opens.
    public var filter: LibraryFilter {
        switch kind {
        case .franchise: LibraryFilter(franchise: name)
        case .series: LibraryFilter(series: name)
        case .theme: LibraryFilter(theme: name)
        case .company: LibraryFilter(company: name)
        }
    }
}

extension LudeumStore {
    /// Pins by name.
    public func pins() throws -> [Pin] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT kind, name FROM pin ORDER BY name COLLATE NOCASE").compactMap { row in
                Pin.Kind(rawValue: row["kind"]).map { Pin(kind: $0, name: row["name"]) }
            }
        }
    }

    public func pin(_ pin: Pin) throws {
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO pin (kind, name) VALUES (?, ?)", arguments: [pin.kind.rawValue, pin.name])
        }
    }

    public func unpin(_ pin: Pin) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM pin WHERE kind = ? AND name = ?", arguments: [pin.kind.rawValue, pin.name])
        }
    }
}
