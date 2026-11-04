import Foundation

extension LudeumFolder {
    /// The folder of the Ymir Ludeum installs (ADR 0036): the app, and beside it what `-p` makes its profile (`Ymir.toml`,
    /// its GUI state and the like).
    public var ymirFolder: URL { emulators.appending(path: "Ymir", directoryHint: .isDirectory) }

    /// The Ymir Ludeum installs.
    public var ymirApp: URL { ymirFolder.appending(path: "Ymir.app", directoryHint: .isDirectory) }

    /// One of the folders Ymir keeps in the Data folder, under `Emulators/Ymir/`.
    public func ymir(_ folder: YmirFolder) -> URL {
        data.appending(path: "Emulators/Ymir/\(folder.name)", directoryHint: .isDirectory)
    }
}

/// A folder Ymir keeps that lives in the Data folder, under `Emulators/Ymir/`, where its Standing settings point it
/// (ADR 0036): what must survive losing this Mac. What's left (its GUI state, the console's language and clock, debugger
/// dumps) stays in its profile beside the app.
public enum YmirFolder: CaseIterable, Sendable {
    case saveStates, backupMemory, bios, cartridgeROMs, exportedSaves, screenshots

    /// Its name in the Data folder.
    public var name: String {
        switch self {
        case .saveStates: "Save States"
        case .backupMemory: "Backup Memory"
        case .bios: "BIOS"
        case .cartridgeROMs: "Cartridge ROMs"
        case .exportedSaves: "Exported Saves"
        case .screenshots: "Screenshots"
        }
    }

    /// Its key in `[General.PathOverrides]` of `Ymir.toml`.
    var key: String {
        switch self {
        case .saveStates: "SaveStates"
        case .backupMemory: "BackupMemory"
        case .bios: "IPLROMImages"
        case .cartridgeROMs: "ROMCartImages"
        case .exportedSaves: "ExportedBackups"
        case .screenshots: "Screenshots"
        }
    }
}

/// The Ymir Ludeum installs and keeps (ADR 0036): `Emulators/Ymir/Ymir.app` in the Ludeum folder, whose folder every launch
/// makes its profile with `-p`, so no other Ymir shares it and nothing goes in its ad-hoc signed bundle.
///
/// Its **Standing settings** are written into `Ymir.toml` before every Play and after Install: every folder worth keeping
/// into the Data folder (`YmirFolder`), no checking for updates, and a backup RAM image for each Game, so a Game's saves
/// are its own to show. Ymir keeps its settings in memory and rewrites the whole file on quitting, so they're only written
/// while it isn't running. Everything else in the file is Ymir's own, set in it during a Play.
///
/// A Play also says what's in its first controller port, as Ymir has one setting for every Game: the Virtua Gun for a
/// Disc whose header lists one, played with the mouse, and back to the Control Pad for one that doesn't. Any other
/// peripheral chosen in Ymir stays.
public struct YmirSettings: Sendable {
    /// The Ymir.app Ludeum installs.
    public let app: URL
    /// Its profile: the folder holding the app.
    let profile: URL
    /// The Ludeum folder, whose Data folder holds what Ymir keeps.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.ymirApp
        self.profile = ludeum.ymirFolder
        self.ludeum = ludeum
    }

    /// Its `Ymir.toml`, at the root of its profile.
    var settingsFile: URL { profile.appending(path: "Ymir.toml") }

    /// The empty file that says the update-check question has been answered, without which a new profile opens by asking.
    var onboardedMarker: URL { profile.appending(path: "state/updates/.onboarded") }

    /// The version of `Ymir.toml` the pinned release writes. Without it Ymir reads the file as older than any, and skips
    /// its controller binds.
    static let configVersion = 6

    /// The size of a Saturn BIOS image: Ymir looks at no other file in its BIOS folder.
    static let biosSize = 512 << 10

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/ymir-sdl3").path(percentEncoded: false))
    }

    /// A Saturn BIOS to boot with: a file of a BIOS's size in the Data folder's BIOS folder. Ymir picks the one for the
    /// Disc's region, by its hash, so Ludeum only checks there's one to pick.
    public var hasBIOS: Bool {
        let folder = ludeum.ymir(.bios)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.contains { name in
            guard !name.hasPrefix(".") else { return false }
            let values = try? folder.appending(path: name).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.fileSize == Self.biosSize
        }
    }

    /// Writes the Standing settings, and what's in its first port for this Disc, then opens the ROM with its profile. A
    /// Save state can't be started from: nothing in Ymir takes one, on its command line or otherwise. Refused while the
    /// Data folder is missing.
    func arguments(rom: URL) throws -> [String] {
        try writeStanding(virtuaGun: SaturnDisc.header(of: rom)?.takesVirtuaGun)
        return ["-p", Self.path(profile), "-d", rom.path(percentEncoded: false)]
    }

    /// Writes the Standing settings into `Ymir.toml`, making the Data folder's Ymir folders for it to write into. `virtuaGun`
    /// says whether this Play's Disc takes the Virtua Gun; nil leaves its first port as it is. Refused while the Data folder
    /// is missing, so nothing is kept somewhere Dropbox doesn't see, and while the file is there but can't be read, so what's
    /// in it isn't written over. The file is left alone when it already says so.
    public func writeStanding(virtuaGun: Bool? = nil) throws {
        try ludeum.checkData()
        let files = FileManager.default
        for folder in YmirFolder.allCases {
            try files.createDirectory(at: ludeum.ymir(folder), withIntermediateDirectories: true)
        }
        try files.createDirectory(at: onboardedMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !files.fileExists(atPath: onboardedMarker.path(percentEncoded: false)) { try Data().write(to: onboardedMarker) }
        let original =
            files.fileExists(atPath: settingsFile.path(percentEncoded: false)) ? try String(contentsOf: settingsFile, encoding: .utf8) : nil
        let updated = Self.standing(in: original ?? "", ludeum: ludeum, virtuaGun: virtuaGun)
        guard updated != original else { return }
        try updated.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// `toml` with the Standing settings: each folder's override an absolute path into the Data folder, as Ymir takes an
    /// override exactly as written, the update check off, backup RAM per Game, and its first port for `virtuaGun`.
    static func standing(in toml: String, ludeum: LudeumFolder, virtuaGun: Bool?) -> String {
        var toml = toml
        for folder in YmirFolder.allCases {
            toml = TOML.setting(folder.key, to: TOML.string(path(ludeum.ymir(folder))), in: "General.PathOverrides", of: toml)
        }
        toml = TOML.setting("CheckForUpdates", to: "false", in: "General", of: toml)
        toml = TOML.setting("InternalBackupRAMPerGame", to: "true", in: "System", of: toml)
        let port = (key: "PeripheralType", section: "Input.Port1")
        let gun = TOML.string("VirtuaGun")
        if virtuaGun == true {
            toml = TOML.setting(port.key, to: gun, in: port.section, of: toml)
        } else if virtuaGun == false, Ini.value(port.key, in: port.section, of: toml) == gun {
            toml = TOML.setting(port.key, to: TOML.string("ControlPad"), in: port.section, of: toml)
        }
        return TOML.withVersion(configVersion, of: toml)
    }

    /// A folder's path without a trailing `/`.
    private static func path(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// Editing Ymir's TOML settings file as text, keeping everything else in it. Tables look as `Ini`'s sections do, so it does
/// the rest; but a key before the first table is the file's own, so a new table can't go at the top as a new section does.
enum TOML {
    /// `toml` with `key = value` in `[table]`: replaced where it is, else added at the top of the table, else in a new table
    /// at the end. `value` is as TOML writes it.
    static func setting(_ key: String, to value: String, in table: String, of toml: String) -> String {
        if Ini.hasSection(table, in: toml) { return Ini.setting(key, to: value, in: table, of: toml) }
        let start = toml.isEmpty ? "" : (toml.hasSuffix("\n") ? toml : toml + "\n") + "\n"
        return "\(start)[\(table)]\n\(key) = \(value)\n"
    }

    /// `toml` with `ConfigVersion` at the top, unless it says one already.
    static func withVersion(_ version: Int, of toml: String) -> String {
        let says = toml.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("ConfigVersion") }
        return says ? toml : "ConfigVersion = \(version)\n\n\(toml)"
    }

    /// A string as Ymir writes one, in single quotes, which take no escapes; one holding a single quote can't be written that way.
    static func string(_ text: String) -> String {
        guard text.contains("'") else { return "'\(text)'" }
        return "\"\(text.replacing("\\", with: "\\\\").replacing("\"", with: "\\\""))\""
    }
}
