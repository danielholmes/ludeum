import Foundation
import GRDB

/// A Platform that has a ROM folder: what its folder is called, what its Emulator opens, and whether its ROMs can be
/// Compacted or Archived.
public struct ROMPlatform: Sendable, Equatable {
    /// IGDB's name, used until IGDB's own is known.
    public let name: String
    /// The ROM folder's name under the ROM folders' root.
    public let folderName: String
    /// What its Emulator opens, most preferred first.
    let readyExtensions: [String]
    /// The archive its Emulator opens directly, so its ROMs can be Compacted into it: `7z` for MesenCE and melonDS,
    /// `zip` for ares (which can't open a `.7z`). Nil where the Emulator opens neither.
    public let compactExtension: String?
    /// How its ROMs are Archived, when they can be: nil for the rest.
    public let archiving: Archiving?
    /// Whose names its ROMs are given by Rename: Redump's for the disc Platforms it catalogues, No-Intro's for the rest.
    let naming: Naming

    /// How an Archived ROM unpacks.
    public enum Archiving: Sendable, Equatable {
        /// Everything in the archive, into a folder named after the ROM (PS2 and the disc Platforms).
        case intoFolder
        /// Its one file, named after the ROM, loose in the ROM folder (PSP, Vita, GameCube, Wii and Xbox).
        case singleFile
    }

    /// The group whose names a Platform's ROMs follow (ADR 0012).
    public enum Naming: Sendable, Equatable {
        case noIntro, redump
    }

    init(
        name: String, folderName: String, readyExtensions: [String], compactExtension: String? = nil,
        archiving: Archiving? = nil, naming: Naming = .noIntro
    ) {
        self.name = name
        self.folderName = folderName
        self.readyExtensions = readyExtensions
        self.compactExtension = compactExtension
        self.archiving = archiving
        self.naming = naming
    }

    /// Whether a ROM whose file is `fileName` can still be Compacted: its Emulator opens an archive the file isn't yet.
    func canCompact(fileName: String) -> Bool {
        compactExtension.map { (fileName as NSString).pathExtension.lowercased() != $0 } ?? false
    }

    public static let ps2: Int64 = 8
    public static let psp: Int64 = 38
    public static let vita: Int64 = 46
    public static let xbox: Int64 = 11

    /// Every Platform with a ROM folder, by IGDB platform id. One folder per Platform: Game Boy and
    /// Game Boy Color, NES and Famicom, SNES and Super Famicom each have their own.
    public static let all: [Int64: ROMPlatform] = [
        33: .init(
            name: "Game Boy", folderName: "Game Boy", readyExtensions: ["gb", "gbc", "sgb"],
            compactExtension: "7z"),
        22: .init(
            name: "Game Boy Color", folderName: "Game Boy Color", readyExtensions: ["gbc", "gb"],
            compactExtension: "7z"),
        24: .init(
            name: "Game Boy Advance", folderName: "Game Boy Advance", readyExtensions: ["gba"],
            compactExtension: "7z"),
        18: .init(
            name: "Nintendo Entertainment System", folderName: "NES", readyExtensions: ["nes", "fds", "unf", "unif"],
            compactExtension: "7z"),
        99: .init(
            name: "Family Computer", folderName: "Famicom", readyExtensions: ["nes", "fds", "unf", "unif"],
            compactExtension: "7z"),
        19: .init(
            name: "Super Nintendo Entertainment System", folderName: "SNES", readyExtensions: ["sfc", "smc", "swc", "fig"],
            compactExtension: "7z"),
        58: .init(
            name: "Super Famicom", folderName: "Super Famicom", readyExtensions: ["sfc", "smc", "swc", "fig"],
            compactExtension: "7z"),
        4: .init(
            name: "Nintendo 64", folderName: "N64", readyExtensions: ["z64", "n64", "v64"],
            compactExtension: "zip"),
        20: .init(
            name: "Nintendo DS", folderName: "DS", readyExtensions: ["nds"], compactExtension: "7z"),
        21: .init(
            name: "Nintendo GameCube", folderName: "GameCube", readyExtensions: ["rvz", "iso", "gcm", "ciso", "gcz", "wbfs"],
            archiving: .singleFile, naming: .redump),
        // Not `.nfs`: a Wii U eShop Wii game is a folder with a key file.
        5: .init(
            name: "Wii", folderName: "Wii", readyExtensions: ["wad", "rvz", "wbfs", "iso", "wia", "gcz", "ciso"],
            archiving: .singleFile, naming: .redump),
        7: .init(
            name: "PlayStation", folderName: "PS1", readyExtensions: ["m3u", "chd", "cue", "pbp", "iso", "bin", "img"],
            archiving: .intoFolder, naming: .redump),
        38: .init(
            name: "PlayStation Portable", folderName: "PSP", readyExtensions: ["iso", "cso", "chd", "pbp"],
            archiving: .singleFile, naming: .redump),
        // A `.vpk`, though no Emulator plays it yet. Not a `.zip` of the game's folder, which Vita3K also installs:
        // a `.zip` is ares's.
        46: .init(
            name: "PlayStation Vita", folderName: "Vita", readyExtensions: ["vpk"],
            archiving: .singleFile),
        8: .init(
            name: "PlayStation 2", folderName: "PS2", readyExtensions: ["iso", "chd", "cso", "zso", "gz", "cue", "bin", "mdf"],
            archiving: .intoFolder, naming: .redump),
        29: .init(
            name: "Sega Mega Drive/Genesis", folderName: "Mega Drive", readyExtensions: ["md", "gen", "smd", "bin"],
            compactExtension: "zip"),
        64: .init(
            name: "Sega Master System/Mark III", folderName: "Master System", readyExtensions: ["sms"],
            compactExtension: "7z"),
        35: .init(
            name: "Sega Game Gear", folderName: "Game Gear", readyExtensions: ["gg"],
            compactExtension: "7z"),
        78: .init(
            name: "Sega CD", folderName: "Sega CD", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"],
            archiving: .intoFolder, naming: .redump),
        32: .init(
            name: "Sega Saturn", folderName: "Saturn", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"],
            archiving: .intoFolder, naming: .redump),
        150: .init(
            name: "Turbografx-16/PC Engine CD", folderName: "PC Engine CD", readyExtensions: ["m3u", "chd", "cue", "bin"],
            archiving: .intoFolder, naming: .redump),
        // An `.iso`, for xemu, which boots only an XISO (the game partition alone): a full Redump image is read as a ROM
        // all the same, and Play refuses it (`XboxDisc`).
        11: .init(
            name: "Xbox", folderName: "Xbox", readyExtensions: ["iso"],
            archiving: .singleFile, naming: .redump),
        // No Emulator yet, so nothing to Compact into.
        53: .init(
            name: "MSX2", folderName: "MSX2", readyExtensions: ["rom", "mx2", "mx1", "dsk", "cas"]),
    ]

    /// Records the Platform if the journal doesn't know it yet, so a ROM can point at it.
    static func ensureKnown(_ db: Database, _ id: Int64) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO platform (id, name) VALUES (?, ?)", arguments: [id, all[id]?.name ?? "Platform \(id)"])
    }
}
