import Foundation

/// The one-off move from Ludeum naming each PlayStation ROM's card by its Serial (ADR 0023) to DuckStation naming its
/// own (ADR 0024), run by hand through `ludeum-import duckstation-cards` once the Standing settings keep the cards and
/// per-game files in the Data folder. Each per-game file loses what every Play used to write into it (card 1, fast
/// boot, the lowest latency), and each `<Serial>.mcd` takes the name DuckStation gives that disc's card. Where DuckStation
/// has a card of that name already, the newer of the two keeps it and the older is set aside as `… (older).mcd`,
/// never deleted. To go once it has run.
public struct DuckStationCardMigration: Sendable {
    /// One thing the move does, or would do, as the command prints it.
    public enum Action: Equatable, Sendable, CustomStringConvertible {
        /// A per-game file lost the keys every Play used to write.
        case stripped(URL)
        /// A Serial-named card takes DuckStation's name for it.
        case renamed(from: URL, to: URL)
        /// The older of two cards for one disc, set aside so the newer keeps the name.
        case setAside(URL, as: URL)
        /// A ROM whose card DuckStation wouldn't keep (card 1 is off for it), so its Serial-named card stays as it is.
        case unnamed(serial: String, rom: String)

        public var description: String {
            switch self {
            case .stripped(let file): "strip   \(file.lastPathComponent)"
            case .renamed(let from, let to): "rename  \(from.lastPathComponent) → \(to.lastPathComponent)"
            case .setAside(let file, let aside): "aside   \(file.lastPathComponent) → \(aside.lastPathComponent)"
            case .unnamed(let serial, let rom): "skip    \(serial).mcd: DuckStation keeps no card for \(rom)"
            }
        }
    }

    let journal: LudeumStore
    let duckStation: DuckStationSettings
    /// DuckStation's `Contents/Resources`, whose game database names its cards; nil names them by the file.
    let resources: URL?

    /// `duckStation` is the copy Ludeum installs, whose settings say where the cards and per-game files are.
    public init(journal: LudeumStore, duckStation: DuckStationSettings = .init(), resources: URL?) {
        self.journal = journal
        self.duckStation = duckStation
        self.resources = resources
    }

    /// What `run` would do.
    public func plan() throws -> [Action] { try perform(dryRun: true) }

    /// Does it, returning what was done.
    public func run() throws -> [Action] { try perform(dryRun: false) }

    private func perform(dryRun: Bool) throws -> [Action] {
        let files = FileManager.default
        var actions: [Action] = []
        let folder = duckStation.gameSettingsFolder
        var stripped: [String: String] = [:]
        for name in ((try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
        where name.hasSuffix(".ini") {
            let file = folder.appending(path: name)
            guard let original = try? String(contentsOf: file, encoding: .utf8) else { continue }
            // The file's own Serial names the card it pointed at, except a disc set's other Discs, which pointed at Disc
            // 1's: those are met at the Game's next Play.
            let updated = DuckStationSettings.removingWhatIsStanding(from: original, serial: String(name.dropLast(4)))
            stripped[name] = updated
            guard updated != original else { continue }
            actions.append(.stripped(file))
            if !dryRun { try updated.write(to: file, atomically: true, encoding: .utf8) }
        }
        let cards = duckStation.ludeum.duckStationMemoryCards
        let locator = ROMLocator(romFolders: duckStation.ludeum.romFolders)
        for rom in try journal.roms(onPlatform: ROMPlatform.ps1) {
            guard let serial = rom.serials.first else { continue }
            let source = cards.appending(path: DuckStationSettings.fileName(serial) + ".mcd")
            guard files.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let file = (try? locator.file(of: rom)) ?? nil
            let perGame = stripped[DuckStationSettings.fileName(serial) + ".ini"] ?? ""
            guard
                let target = DuckStationMemoryCards(duckStation: duckStation).duckStationsCard(
                    serial: serial, rom: file ?? URL(filePath: rom.fileName), resources: resources, perGame: perGame)
            else {
                actions.append(.unnamed(serial: serial, rom: rom.name))
                continue
            }
            guard target != source else { continue }
            if files.fileExists(atPath: target.path(percentEncoded: false)) {
                let older = Self.modified(source) > Self.modified(target) ? target : source
                let aside = cards.appending(path: older.deletingPathExtension().lastPathComponent + " (older).mcd")
                actions.append(.setAside(older, as: aside))
                if !dryRun { try files.moveItem(at: older, to: aside) }
                guard older == target else { continue }
            }
            actions.append(.renamed(from: source, to: target))
            if !dryRun { try files.moveItem(at: source, to: target) }
        }
        return actions
    }

    private static func modified(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date ?? .distantPast
    }
}
