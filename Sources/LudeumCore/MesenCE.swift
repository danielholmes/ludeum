import Foundation

/// A folder MesenCE keeps for each of its Platforms in the Data folder, under `Emulators/MesenCE/<Platform>/`, where its
/// Standing settings point it before each Play (ADR 0027). One per Platform, as MesenCE names what it keeps by the ROM
/// file's name alone, which two Platforms' ROMs can share.
public enum MesenFolder: CaseIterable, Sendable {
    case saveStates, saves, screenshots

    /// Its name in the Platform's folder.
    public var name: String {
        switch self {
        case .saveStates: "Save States"
        case .saves: "Saves"
        case .screenshots: "Screenshots"
        }
    }

    /// The `Preferences` keys in `settings.json` that place it: the switch that says to use the path, and the path.
    var keys: (override: String, path: String) {
        switch self {
        case .saveStates: ("OverrideSaveStateFolder", "SaveStateFolder")
        case .saves: ("OverrideSaveDataFolder", "SaveDataFolder")
        case .screenshots: ("OverrideScreenshotFolder", "ScreenshotFolder")
        }
    }

    /// The name of a MesenCE Platform's folder: its ROM folder's, or PC Engine's, which has none. Nil for any other
    /// Platform.
    public static func platformName(_ platformId: Int64) -> String? {
        guard Emulator.of(platformId: platformId) == .mesenCE else { return nil }
        return ROMPlatform.all[platformId]?.folderName ?? (platformId == 86 ? "PC Engine" : nil)
    }
}

extension LudeumFolder {
    /// The MesenCE Ludeum installs (ADR 0027).
    public var mesenApp: URL { emulators.appending(path: "MesenCE.app", directoryHint: .isDirectory) }

    /// One of the folders MesenCE keeps for a Platform in the Data folder, under `Emulators/MesenCE/<Platform>/`. Nil
    /// for a Platform MesenCE doesn't play. Made before every Play.
    public func mesen(_ folder: MesenFolder, platform platformId: Int64) -> URL? {
        MesenFolder.platformName(platformId).map {
            data.appending(path: "Emulators/MesenCE/\($0)/\(folder.name)", directoryHint: .isDirectory)
        }
    }
}

/// The MesenCE Ludeum installs and keeps (ADR 0027): `Emulators/MesenCE.app` in the Ludeum folder, made portable by a
/// `settings.json` beside its executable, so its data root is its own `Contents/MacOS` and no other MesenCE shares it.
///
/// Its **Standing settings** are written before every Play: its Save state, Game save and screenshot folders into the
/// Data folder, the Play's Platform's (`MesenFolder`); no checking for updates; no game selection screen, so it writes
/// no resume files of its own; and an automatic Save state every minute, which a Game resumes from. MesenCE reads them
/// once, at startup, so they're only written while it isn't running. Everything else in the file is MesenCE's own, and
/// what's changed in it during a Play lasts.
public struct MesenSettings: Sendable {
    /// The MesenCE.app Ludeum installs.
    public let app: URL
    /// Its data root, holding its `settings.json`: `Contents/MacOS`, as it's portable.
    let dataFolder: URL
    /// The Ludeum folder, whose Data folder holds what MesenCE keeps.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.init(app: ludeum.mesenApp, ludeum: ludeum)
    }

    /// `dataFolder` stands in for the app's `Contents/MacOS`, in tests.
    init(app: URL, dataFolder: URL? = nil, ludeum: LudeumFolder) {
        self.app = app
        self.dataFolder = dataFolder ?? app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        self.ludeum = ludeum
    }

    /// Its `settings.json`.
    var settingsFile: URL { dataFolder.appending(path: "settings.json") }

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/Mesen").path(percentEncoded: false))
    }

    /// Its `settings.json` is beside its executable, so its data root is its own.
    public var isPortable: Bool { FileManager.default.fileExists(atPath: settingsFile.path(percentEncoded: false)) }

    /// The release Install put there, as it recorded it: nil for a copy Ludeum didn't install.
    public var installed: MesenRelease.Installed? { MesenRelease.Installed(app: app) }

    /// Writes the Standing settings, then gives the ROM to open, from `saveState` if given (ADR 0027): MesenCE loads the
    /// resume file Ludeum writes for it once the ROM is running. Run-ahead and Game Boy model go on the command line,
    /// for this Play.
    func arguments(rom: URL, platformId: Int64, settings: EmulatorSettings, saveState: URL? = nil) throws -> [String] {
        try writeStanding(platform: platformId)
        if let saveState { try writeResume(from: saveState, rom: rom) }
        return ["--emulation.runAheadFrames=\(settings.runAheadFrames ?? 0)"]
            + (GameBoyModel.applies(to: platformId) ? ["--gameboy.model=\(settings.gameBoyModel?.mesenName ?? "AutoFavorGbc")"] : [])
            + [rom.path(percentEncoded: false)] + (saveState == nil ? [] : ["--loadLastSession"])
    }

    /// Writes the Standing settings into `settings.json`, with the folders of `platform`'s, made for MesenCE to write
    /// into; without one (at Install), the folders are left as they are. Refused while the Data folder is missing, so
    /// nothing is kept somewhere Dropbox doesn't see. The file is left alone when it already says so.
    public func writeStanding(platform: Int64? = nil) throws {
        try ludeum.checkData()
        var folders: [MesenFolder: URL] = [:]
        if let platform {
            for folder in MesenFolder.allCases {
                guard let url = ludeum.mesen(folder, platform: platform) else { continue }
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                folders[folder] = url
            }
        }
        let original = try? Data(contentsOf: settingsFile)
        let json = original.flatMap(Self.object(_:)) ?? Self.seed
        let updated = Self.standing(in: json, folders: folders)
        guard original.flatMap(Self.object(_:)).map({ NSDictionary(dictionary: $0) != NSDictionary(dictionary: updated) }) ?? true
        else { return }
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: settingsFile, options: .atomic)
    }

    /// The settings a MesenCE starts from when there are none: its first run's, so it fills in its default controls.
    static var seed: [String: Any] { ["ConfigUpgrade": 1] }

    /// `json` with the Standing settings in its `Preferences`: each of `folders` as its switch on and its path, no
    /// update check, no game selection screen, and an automatic Save state every minute.
    static func standing(in json: [String: Any], folders: [MesenFolder: URL]) -> [String: Any] {
        var json = json
        var preferences = json["Preferences"] as? [String: Any] ?? [:]
        for (folder, url) in folders {
            let path = url.path(percentEncoded: false)
            preferences[folder.keys.override] = true
            preferences[folder.keys.path] = path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        preferences["AutomaticallyCheckForUpdates"] = false
        preferences["GameSelectionScreenMode"] = "Disabled"
        preferences["EnableAutoSaveState"] = true
        preferences["AutoSaveStateDelay"] = 1
        json["Preferences"] = preferences
        return json
    }

    /// The JSON object in a `settings.json`, which MesenCE writes with a byte order mark.
    static func object(_ data: Data) -> [String: Any]? {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let body = data.starts(with: bom) ? data.dropFirst(bom.count) : data
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// Where MesenCE keeps its resume files.
    var recentGames: URL { dataFolder.appending(path: "RecentGames", directoryHint: .isDirectory) }

    /// Writes the resume file `--loadLastSession` loads for `rom`, holding `saveState`: `RecentGames/<name>.rgd`, a zip
    /// of the state and the ROM's name and path as MesenCE writes them, `<archive>\u{1}<file inside>` for one in an
    /// archive. The ROM's file name, inside an archive or not, is the one the state was saved with.
    func writeResume(from saveState: URL, rom: URL) throws {
        let state = try Data(contentsOf: saveState)
        guard let romName = MesenSaveStates.romName(inState: state) else { throw MesenResumeError.notAState }
        let path = rom.path(percentEncoded: false)
        let romPath = ["7z", "zip"].contains(rom.pathExtension.lowercased()) ? "\(path)\u{1}\(romName)" : path
        let info = "\(romName)\n\(romPath)\n\n"
        try FileManager.default.createDirectory(at: recentGames, withIntermediateDirectories: true)
        let file = recentGames.appending(path: (romName as NSString).deletingPathExtension + ".rgd")
        try StoredZip.data(["Savestate.mss": state, "RomInfo.txt": Data(info.utf8)]).write(to: file, options: .atomic)
    }
}

/// A Save state that can't be Played from.
public enum MesenResumeError: LocalizedError {
    /// It isn't one MesenCE wrote.
    case notAState

    public var errorDescription: String? { "It isn't a MesenCE save state." }
}

/// A zip of files stored as they are, uncompressed: what MesenCE's resume files need, without a tool to make one.
enum StoredZip {
    /// The zip of `files`, by name, in name order.
    static func data(_ files: [String: Data]) -> Data {
        var zip = Data()
        var directory = Data()
        for (name, contents) in files.sorted(by: { $0.key < $1.key }) {
            let offset = UInt32(zip.count)
            let crc = crc32(contents)
            let nameBytes = Data(name.utf8)
            // Version 2.0, no flags, stored, no date, then the CRC and sizes.
            var header = Data()
            header.append(u16(20) + u16(0) + u16(0) + u16(0) + u16(0x21))
            header.append(u32(crc) + u32(UInt32(contents.count)) + u32(UInt32(contents.count)))
            header.append(u16(UInt16(nameBytes.count)) + u16(0))
            zip.append(u32(0x0403_4B50) + header + nameBytes + contents)
            directory.append(u32(0x0201_4B50) + u16(20) + header + u16(0) + u16(0) + u16(0) + u32(0) + u32(offset) + nameBytes)
        }
        let start = UInt32(zip.count)
        let count = u16(UInt16(files.count))
        zip.append(directory)
        zip.append(u32(0x0605_4B50) + u16(0) + u16(0) + count + count + u32(UInt32(directory.count)) + u32(start) + u16(0))
        return zip
    }

    private static func u16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    /// The CRC-32 a zip records (IEEE, reflected).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
