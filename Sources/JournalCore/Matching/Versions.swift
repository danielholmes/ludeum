/// A ROM of one Game, as far as grouping it into Versions is concerned.
public struct GameROM: Sendable, Hashable {
    public let id: Int
    public let name: String
    /// An `.m3u` playlist that loads the Game's Discs.
    public let isPlaylist: Bool
    public let isPresent: Bool

    public init(id: Int, name: String, isPlaylist: Bool, isPresent: Bool) {
        self.id = id
        self.name = name
        self.isPlaylist = isPlaylist
        self.isPresent = isPresent
    }
}

/// The present ROMs of one Game, grouped into Versions, in the order given.
///
/// The ROMs that each carry a `(Disc N)`, with no number repeated, are the Discs of one
/// Version, whatever else their names say, and a playlist joins them. Any other ROM is a
/// Version of its own. Missing ROMs never count.
public func versions(of roms: [GameROM]) -> [[GameROM]] {
    let present = roms.filter(\.isPresent)
    let numbers = present.compactMap { ROMName($0.name).disc }
    guard !numbers.isEmpty, Set(numbers).count == numbers.count else { return present.map { [$0] } }
    let discs = present.filter { $0.isPlaylist || ROMName($0.name).disc != nil }
    let others = present.filter { !discs.contains($0) }
    return [discs] + others.map { [$0] }
}

/// Two or more present ROMs on one Game that aren't Discs of one Version.
public func hasDuplicateVersions(_ roms: [GameROM]) -> Bool { versions(of: roms).count > 1 }
