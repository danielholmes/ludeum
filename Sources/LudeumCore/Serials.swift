import Foundation
import GRDB

/// What's known of a ROM's Serials (ADR 0021): read off its Discs, each Disc's in Disc order (nil for a Disc with none),
/// or not yet: its Platform has no reader, or its files couldn't be read at the last Import.
public enum Serials: Sendable, Equatable {
    case notRead
    case read([String?])

    /// Disc 1's, the one DuckStation names a multi-disc Version's per-game settings by.
    public var first: String? {
        if case .read(let serials) = self { serials.first ?? nil } else { nil }
    }

    /// The Serials there are, in Disc order.
    public var known: [String] {
        if case .read(let serials) = self { serials.compactMap { $0 } } else { [] }
    }

    /// The Regions its Discs were pressed for, each Disc's by its Serial's prefix, without repeats: none when no Serial's
    /// prefix says one.
    var regions: [String] {
        var regions: [String] = []
        for serial in known {
            guard let region = Self.prefixRegions[String(serial.prefix(4)).uppercased()], !regions.contains(region) else { continue }
            regions.append(region)
        }
        return regions
    }

    /// The Region each PlayStation Serial prefix is pressed for. Only the prefixes DuckStation's game database (its
    /// `discdb.yaml`, build 12442) never names a disc of another market for: `SCPS` is also Sony's Asian and Korean
    /// discs (`SCPS-45xxx`, `SCPS-46001`), `SLPM` Korean ones (`SLPM-885xx`) and `PAPX` Asian demos, while `SCAJ` and
    /// `SCKA` aren't in it at all. `SLPS` stays, its one exception a Breath of Fire IV (USA) beta that was never sold. A
    /// PAL disc can be for Australia alone, which a name's tag says and a Serial can't, so the name comes first.
    static let prefixRegions: [String: String] = [
        "SLUS": "USA", "SCUS": "USA",
        "SLES": "Europe", "SCES": "Europe", "SLED": "Europe", "SCED": "Europe",
        "SLPS": "Japan", "SCPM": "Japan", "SIPS": "Japan", "PCPX": "Japan",
        "SLKA": "Korea",
    ]

    /// From a row's `serials` and `serialsLookedUp`.
    init(_ row: Row) {
        guard row["serialsLookedUp"] as Bool? == true else {
            self = .notRead
            return
        }
        let text: String? = row["serials"]
        self = .read(text.flatMap { try? JSONDecoder().decode([String?].self, from: Data($0.utf8)) } ?? [])
    }

    /// How `rom.serials` stores them: a JSON array in Disc order with null for a Disc with none, or nothing when no Disc
    /// has one.
    static func encode(_ serials: [String?]) -> String? {
        guard serials.contains(where: { $0 != nil }) else { return nil }
        return String(decoding: try! JSONEncoder().encode(serials), as: UTF8.self)
    }

    /// The Platforms whose ROMs' Serials are read.
    static let platforms: Set<Int64> = [ROMPlatform.ps1]

    /// Forms a Disc is kept in whose Serials aren't read yet.
    static let unreadForms: Set<String> = ["chd", "pbp"]
}
