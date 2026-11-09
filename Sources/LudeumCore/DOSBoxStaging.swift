import Foundation
import GRDB

extension LudeumFolder {
    /// The DOSBox Staging Ludeum installs (ADR 0042).
    public var dosBoxStagingApp: URL { emulators.appending(path: "DOSBox Staging.app", directoryHint: .isDirectory) }

    /// The General MIDI SoundFont Ludeum installs with it, which every Play uses unless a Game's own settings choose another.
    /// Downloaded again by an Install, so not in the Data folder.
    public var dosBoxStagingSoundFont: URL {
        emulators.appending(path: "DOSBox Staging SoundFonts/\(DOSBoxStagingRelease.soundFontName)", directoryHint: .notDirectory)
    }

    /// The home folder DOSBox Staging is given for each Play, so its own folder, `~/Library/Preferences/DOSBox`, is made in
    /// here rather than shared with any other copy. Nothing in it needs keeping.
    var dosBoxStagingHome: URL { emulators.appending(path: "DOSBox Staging Home", directoryHint: .isDirectory) }

    /// The Standing settings, written before each Play.
    var dosBoxStagingStanding: URL { dosBoxStagingHome.appending(path: "ludeum.conf", directoryHint: .notDirectory) }

    /// What DOSBox Staging keeps that has to survive: `Emulators/DOSBox Staging/` in the Data folder.
    var dosBoxStagingData: URL { data.appending(path: "Emulators/DOSBox Staging", directoryHint: .isDirectory) }

    /// Every DOS ROM's Game save.
    public var dosGameSaves: URL { dosBoxStagingData.appending(path: "Game Saves", directoryHint: .isDirectory) }

    /// The ROM `name`'s Game save: everything its game has written, laid over its drive C, and a CD game's install.
    public func dosGameSave(ofROM name: String) -> URL { dosGameSaves.appending(path: name, directoryHint: .isDirectory) }

    /// Every DOS ROM's own settings.
    var dosGameSettings: URL { dosBoxStagingData.appending(path: "Game Settings", directoryHint: .isDirectory) }

    /// The ROM `name`'s own DOSBox Staging settings: only what differs for its game, laid over the Standing settings.
    public func dosGameSettings(ofROM name: String) -> URL {
        dosGameSettings.appending(path: "\(name).conf", directoryHint: .notDirectory)
    }

    /// SoundFonts of my own, which a Game's settings can name.
    public var dosSoundFonts: URL { dosBoxStagingData.appending(path: "SoundFonts", directoryHint: .isDirectory) }

    /// The Roland MT-32's ROMs, which can't be shipped, for a Game whose settings choose one.
    public var dosMT32ROMs: URL { dosBoxStagingData.appending(path: "MT-32 ROMs", directoryHint: .isDirectory) }
}

/// The programs on a DOS ROM's drive C, in DOS's own form, `KEEN1\KEEN1.EXE` (ADR 0042).
public enum DOSPrograms {
    /// What a program's file is.
    static let extensions: Set<String> = ["exe", "com", "bat"]

    /// What DOSBox Staging names a file its overlay has deleted: a marker beside where it was.
    static let deletedPrefix = "DBOVERLAY_DEL_"

    /// The characters a DOS name may hold besides letters and digits.
    private static let allowed = Set("!#$%&'()-@^_`{}~")

    /// Whether a file or folder's name is one DOS knows as it is: up to eight characters, then up to three after a dot. A
    /// longer one DOSBox shortens in a way that can't be known ahead, so its programs aren't offered.
    static func isShortName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let base = parts.first, (1...8).contains(base.count) else { return false }
        if parts.count == 2, !(1...3).contains(parts[1].count) { return false }
        return name.allSatisfy { $0 == "." || ($0.isASCII && ($0.isLetter || $0.isNumber)) || allowed.contains($0) }
    }

    /// The programs on drive C: the ROM's `C/`, with its Game save laid over it (or alone, for a ROM with no `C/`), as
    /// DOS paths in upper case, in name order. What the overlay has deleted isn't there.
    public static func on(c: URL?, gameSave: URL) -> [String] {
        var found: [String: String] = [:]
        var deleted: Set<String> = []
        for folder in [c, gameSave].compactMap(\.self) {
            for path in (try? FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [] {
                let components = (path as NSString).pathComponents
                guard let name = components.last, !components.contains(where: { $0.hasPrefix(".") }) else { continue }
                let parent = components.dropLast().map { $0.uppercased() }
                if name.uppercased().hasPrefix(deletedPrefix) {
                    deleted.insert((parent + [String(name.uppercased().dropFirst(deletedPrefix.count))]).joined(separator: "\\"))
                    continue
                }
                guard extensions.contains((name as NSString).pathExtension.lowercased()), components.allSatisfy(isShortName),
                    (try? folder.appending(path: path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                let dos = (parent + [name.uppercased()]).joined(separator: "\\")
                found[dos] = dos
            }
        }
        return found.keys.filter { !deleted.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The DOS commands that start `program` from drive C: into its folder, then it, a batch file with `CALL` so DOSBox
    /// comes back to quit once it's done.
    static func commands(starting program: String) -> [String] {
        let parts = program.split(separator: "\\").map(String.init)
        guard let file = parts.last else { return [] }
        let call = (file as NSString).pathExtension.lowercased() == "bat" ? "CALL \(file)" : file
        return ["C:", "CD \\\(parts.dropLast().joined(separator: "\\"))", call]
    }
}

/// Which DOS ROMs the open DOSBox Stagings are playing, told by the Game save each was told to lay over drive C. Nothing a
/// Play writes is shared between ROMs, so DOS Games Play side by side; a Game save can be written by only one at a time.
public struct DOSBoxStagingsOpen: Sendable, Equatable {
    let roms: Set<String>
    /// An open DOSBox Staging's command line couldn't be read, so it could be playing any ROM.
    let anyUnreadable: Bool

    /// No DOSBox Staging open.
    public static let none = DOSBoxStagingsOpen(roms: [], anyUnreadable: false)

    private init(roms: Set<String>, anyUnreadable: Bool) {
        self.roms = roms
        self.anyUnreadable = anyUnreadable
    }

    /// From each open DOSBox Staging's command line, or nil for one that couldn't be read. One with no Game save of
    /// Ludeum's on its drive C plays no ROM.
    public init(commandLines: [[String]?], ludeum: LudeumFolder) {
        let saves = ludeum.dosGameSaves.standardizedFileURL.path(percentEncoded: false)
        var roms: Set<String> = []
        var anyUnreadable = false
        for commandLine in commandLines {
            guard let commandLine else {
                anyUnreadable = true
                continue
            }
            for argument in commandLine where argument.lowercased().hasPrefix("mount c \"") {
                let quoted = argument.dropFirst("mount c \"".count).prefix { $0 != "\"" }
                let folder = URL(filePath: String(quoted), directoryHint: .isDirectory).standardizedFileURL
                if folder.deletingLastPathComponent().path(percentEncoded: false) == saves { roms.insert(folder.lastPathComponent) }
            }
        }
        self.init(roms: roms, anyUnreadable: anyUnreadable)
    }

    /// An open DOSBox Staging is, or may be, playing the ROM `name`.
    public func isPlaying(_ name: String) -> Bool { anyUnreadable || roms.contains(name) }
}

/// The DOSBox Staging Ludeum installs and keeps (ADR 0042): `Emulators/DOSBox Staging.app` in the Ludeum folder, with the
/// SoundFont it plays General MIDI with.
///
/// A ROM is a subfolder of drives and is never written to: its `C/` is mounted as drive C with its Game save laid over it,
/// so what a game writes goes there, and its `CD/`'s Discs are in drive D. Every Standing setting is for the one launch: a
/// home of its own, so it shares no folder with another copy, its own and the working folder's settings files ignored, and
/// Ludeum's Standing settings then the ROM's own, if it has any, as settings files layered in that order.
public struct DOSBoxStagingSettings: Sendable {
    /// The DOSBox Staging.app Ludeum installs.
    public let app: URL
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.dosBoxStagingApp
        self.ludeum = ludeum
    }

    /// The app's executable and the SoundFont are there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/dosbox").path(percentEncoded: false))
            && FileManager.default.fileExists(atPath: ludeum.dosBoxStagingSoundFont.path(percentEncoded: false))
    }

    /// What a Play is opened with: its home.
    public var environment: [String: String] { ["HOME": ludeum.dosBoxStagingHome.path(percentEncoded: false)] }

    /// The Standing settings: General MIDI through FluidSynth with the SoundFont Ludeum installs, which DOSBox Staging would
    /// send to a CoreMIDI port that isn't there, and my own SoundFonts' and MT-32 ROMs' folders in the Data folder.
    static func standing(ludeum: LudeumFolder) -> String {
        [
            "# Ludeum writes this before every Play of a DOS Game (ADR 0042), so a change here lasts only until the next.",
            "# A Game's own settings go in its file in the Data folder's Emulators/DOSBox Staging/Game Settings.",
            "",
            "[midi]",
            "mididevice = fluidsynth",
            "",
            "[fluidsynth]",
            "soundfont = \(ludeum.dosBoxStagingSoundFont.path(percentEncoded: false))",
            "soundfont_dir = \(ludeum.dosSoundFonts.path(percentEncoded: false))",
            "",
            "[mt32]",
            "romdir = \(ludeum.dosMT32ROMs.path(percentEncoded: false))",
            "",
        ].joined(separator: "\n")
    }

    /// What a new file of a ROM's own settings says, before anything's set in it.
    static func gameSettingsTemplate(romName: String) -> String {
        [
            "# DOSBox Staging settings for \(romName), laid over Ludeum's own at every Play (ADR 0042).",
            "# Put only what this game needs differently, under its section. For example:",
            "#",
            "# [cpu]",
            "# cpu_cycles = 8000",
            "#",
            "# Every setting is in DOSBox Staging's manual: https://www.dosbox-staging.org/manual/",
            "",
        ].joined(separator: "\n")
    }

    /// The ROM `name`'s own settings file, made with a note of what goes in it when there's none yet, to be opened.
    public func gameSettings(ofROM name: String) throws -> URL {
        try ludeum.checkData()
        let file = ludeum.dosGameSettings(ofROM: name)
        guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return file }
        try FileManager.default.createDirectory(at: ludeum.dosGameSettings, withIntermediateDirectories: true)
        try Data(Self.gameSettingsTemplate(romName: name).utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    /// The programs a Play of the ROM `romName`, its subfolder `subfolder`, could start with: its drive C's and its Game
    /// save's, as `DOSPrograms.on(c:gameSave:)` lists them.
    public func programs(ofROMIn subfolder: URL, romName: String) -> [String] {
        DOSPrograms.on(c: ROMFolder.drive(ROMPlatform.driveC, in: subfolder), gameSave: ludeum.dosGameSave(ofROM: romName))
    }

    /// A path in double quotes, as a DOS command takes one with spaces. One with a double quote of its own can't be.
    private static func quoted(_ url: URL) throws -> String {
        let path = url.path(percentEncoded: false)
        guard !path.contains("\"") else { throw DOSBoxStagingPlayError.quoteInPath(url.lastPathComponent) }
        return "\"\(path.hasSuffix("/") ? String(path.dropLast()) : path)\""
    }

    /// Writes the Standing settings, makes the folders they and the Game save name, and gives the command line for a Play of
    /// the ROM `romName`, its subfolder `subfolder`: its drives mounted, then into its program and quitting once that's
    /// done, or, with `prompt` or no program chosen, at a DOS prompt on drive C.
    func arguments(subfolder: URL, romName: String, settings: EmulatorSettings, prompt: Bool) throws -> [String] {
        try ludeum.checkData()
        let files = FileManager.default
        let save = ludeum.dosGameSave(ofROM: romName)
        for folder in [save, ludeum.dosSoundFonts, ludeum.dosMT32ROMs, ludeum.dosBoxStagingHome.appending(path: "Library/Preferences")] {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data(Self.standing(ludeum: ludeum).utf8).write(to: ludeum.dosBoxStagingStanding, options: .atomic)

        var arguments = ["--noprimaryconf", "--nolocalconf", "--conf", ludeum.dosBoxStagingStanding.path(percentEncoded: false)]
        let own = ludeum.dosGameSettings(ofROM: romName)
        if files.fileExists(atPath: own.path(percentEncoded: false)) { arguments += ["--conf", own.path(percentEncoded: false)] }
        var commands: [String] = []
        if let c = ROMFolder.drive(ROMPlatform.driveC, in: subfolder) {
            commands += ["mount c \(try Self.quoted(c))", "mount c \(try Self.quoted(save)) -t overlay"]
        } else {
            // Nothing to keep unwritten: the Game save is drive C, where a CD game installs.
            commands.append("mount c \(try Self.quoted(save))")
        }
        if let cd = ROMFolder.drive(ROMPlatform.driveCD, in: subfolder) {
            let discs = ROMFolder.cdDiscs(among: ROMFolder.topFiles(of: cd))
            if !discs.isEmpty { commands.append("mount d " + (try discs.map(Self.quoted)).joined(separator: " ")) }
        }
        let program = prompt ? nil : settings.dosProgram
        commands += program.map(DOSPrograms.commands(starting:)) ?? ["C:"]
        arguments += commands.flatMap { ["-c", $0] }
        if program != nil { arguments.append("--exit") }
        return arguments
    }
}

/// Why a Play in DOSBox Staging couldn't start.
public enum DOSBoxStagingPlayError: LocalizedError, Equatable {
    /// A path DOSBox Staging is given in double quotes has one of its own, which would end it early.
    case quoteInPath(String)

    public var errorDescription: String? {
        switch self {
        case .quoteInPath(let name): "\(name) has a double quote in its name, which DOSBox Staging can't be given. Rename it without one."
        }
    }
}

/// A DOS ROM's Game save, as Game detail shows it: how big, and when its game last wrote to it.
public struct DOSGameSave: Sendable, Equatable {
    public let folder: URL
    public let size: Int64
    public let written: Date

    /// The ROM `name`'s, or nil while its game has written nothing.
    public static func of(romName name: String, ludeum: LudeumFolder) -> DOSGameSave? {
        let folder = ludeum.dosGameSave(ofROM: name)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return nil }
        var size: Int64 = 0
        var written: Date?
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            size += Int64(values.fileSize ?? 0)
            if let modified = values.contentModificationDate, modified > written ?? .distantPast { written = modified }
        }
        return written.map { DOSGameSave(folder: folder, size: size, written: $0) }
    }
}

/// Why a DOS ROM's Rename was refused, with nothing renamed.
public enum DOSBoxStagingRenameError: LocalizedError, Equatable {
    /// There's a Game save, or a file of its own settings, under the new name.
    case inTheWay(String)

    public var errorDescription: String? {
        switch self {
        case .inTheWay(let name): "There's already a Game save or settings file for \(name), so nothing was renamed."
        }
    }
}

extension LudeumStore {
    /// Renames a DOS ROM as `renameROM(_:to:in:)` does, with its Game save and its own settings. Refused, with nothing
    /// renamed, when either is there under the new name, its own or not: a deleted ROM's left behind would otherwise become
    /// this one's. They move first and come back if the ROM can't be renamed, as a ROM whose Game save stayed behind would
    /// start again with none.
    public func renameDOSBoxStagingROM(
        _ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard
    )
        throws
    {
        let files = FileManager.default
        // Differing only in case, they're the same files.
        let same = oldName.caseInsensitiveCompare(name) == .orderedSame
        let both = [
            (ludeum.dosGameSave(ofROM: oldName), ludeum.dosGameSave(ofROM: name)),
            (ludeum.dosGameSettings(ofROM: oldName), ludeum.dosGameSettings(ofROM: name)),
        ]
        if !same, both.contains(where: { files.fileExists(atPath: $0.1.path(percentEncoded: false)) }) {
            throw DOSBoxStagingRenameError.inTheWay(name)
        }
        let moves = both.filter { files.fileExists(atPath: $0.0.path(percentEncoded: false)) }
        var moved: [(URL, URL)] = []
        do {
            for (from, to) in moves {
                try files.moveItem(at: from, to: to)
                moved.append((from, to))
            }
            try renameROM(rom, to: name, in: folder)
        } catch {
            for (from, to) in moved.reversed() { try? files.moveItem(at: to, to: from) }
            throw error
        }
    }
}
