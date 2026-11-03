import Foundation

extension LudeumFolder {
    /// The folder of the PCSX2 Ludeum installs (ADR 0032): the app, and beside it the `portable.txt` that makes the
    /// folder PCSX2's data root (`inis/PCSX2.ini`, its caches and logs).
    public var pcsx2Folder: URL { emulators.appending(path: "PCSX2", directoryHint: .isDirectory) }

    /// The PCSX2 Ludeum installs.
    public var pcsx2App: URL { pcsx2Folder.appending(path: "PCSX2.app", directoryHint: .isDirectory) }

    /// One of the folders PCSX2 keeps in the Data folder, under `Emulators/PCSX2/`.
    public func pcsx2(_ folder: PCSX2Folder) -> URL {
        data.appending(path: "Emulators/PCSX2/\(folder.name)", directoryHint: .isDirectory)
    }

    /// Where PCSX2 keeps its Save states.
    public var pcsx2SaveStates: URL { pcsx2(.saveStates) }

    /// Where PCSX2 keeps its memory cards.
    public var pcsx2MemoryCards: URL { pcsx2(.memoryCards) }

    /// Where PCSX2 looks for a PlayStation 2 BIOS.
    public var pcsx2BIOS: URL { pcsx2(.bios) }
}

/// A folder PCSX2 keeps that lives in the Data folder, under `Emulators/PCSX2/`, where its Standing settings point it
/// (ADR 0032): what must survive losing this Mac. What's rebuildable (its game list cache, shader caches, covers, logs)
/// stays in its data root beside the app.
public enum PCSX2Folder: CaseIterable, Sendable {
    case saveStates, memoryCards, bios, gameSettings, inputProfiles, screenshots, cheats, patches, textures

    /// Its name in the Data folder.
    public var name: String {
        switch self {
        case .saveStates: "Save States"
        case .memoryCards: "Memory Cards"
        case .bios: "BIOS"
        case .gameSettings: "Game Settings"
        case .inputProfiles: "Input Profiles"
        case .screenshots: "Screenshots"
        case .cheats: "Cheats"
        case .patches: "Patches"
        case .textures: "Textures"
        }
    }

    /// Its key in `[Folders]` of `PCSX2.ini`.
    var key: String {
        switch self {
        case .saveStates: "Savestates"
        case .memoryCards: "MemoryCards"
        case .bios: "Bios"
        case .gameSettings: "GameSettings"
        case .inputProfiles: "InputProfiles"
        case .screenshots: "Snapshots"
        case .cheats: "Cheats"
        case .patches: "Patches"
        case .textures: "Textures"
        }
    }
}

/// The PCSX2 Ludeum installs and keeps (ADR 0032): `Emulators/PCSX2/PCSX2.app` in the Ludeum folder, made portable by
/// a `portable.txt` beside it, which makes that folder its data root, so no other PCSX2 shares it and nothing in its
/// notarised bundle changes.
///
/// Its **Standing settings** are written into `inis/PCSX2.ini` before every Play and after Install: every folder worth
/// keeping into the Data folder (`PCSX2Folder`), no checking for updates (PCSX2 would replace its own bundle), fast
/// boot, a Resume state saved when the game closes, and for every Game the lowest input latency PCSX2 has (no frames
/// queued for VSync, its Optimal Frame Pacing). PCSX2 keeps its settings in memory and rewrites the whole file a second
/// after any change, so they're only written while it isn't running. Everything else in the file is PCSX2's own, set in
/// it during a Play, and a Game's own settings are PCSX2's, in its Game Properties, kept in its per-game files in the
/// Data folder's `Game Settings`, which Ludeum doesn't write.
///
/// A file PCSX2 hasn't made yet is seeded with what PCSX2 writes only when it makes the file itself: its own first-run
/// keyboard controls for controller 1 and its hotkeys, as its source at the pinned build has them, and the settings
/// version it checks for, without which it would reset the file and run its setup wizard. A controller is mapped in
/// PCSX2's own settings during a Play.
public struct PCSX2Settings: Sendable {
    /// The PCSX2.app Ludeum installs.
    public let app: URL
    /// Its data root: the folder holding the app, as its `portable.txt` says.
    let root: URL
    /// The Ludeum folder, whose Data folder holds what PCSX2 keeps.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.pcsx2App
        self.root = ludeum.pcsx2Folder
        self.ludeum = ludeum
    }

    /// Its `PCSX2.ini`, in `inis/` under its data root.
    var settingsFile: URL { root.appending(path: "inis/PCSX2.ini") }

    /// The marker beside the app that makes its folder the data root.
    var portableMarker: URL { root.appending(path: "portable.txt") }

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/PCSX2").path(percentEncoded: false))
    }

    /// Its `portable.txt` is beside it, so its data root is its own.
    public var isPortable: Bool { FileManager.default.fileExists(atPath: portableMarker.path(percentEncoded: false)) }

    /// A PlayStation 2 BIOS to boot with: a file in the Data folder's BIOS folder. PCSX2 takes the first one there that
    /// is one when none is named in its settings, so Ludeum only checks there's a file to take.
    public var hasBIOS: Bool {
        let folder = ludeum.pcsx2BIOS
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.contains { name in
            !name.hasPrefix(".")
                && (try? folder.appending(path: name).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// Writes the Standing settings, then opens the ROM, quitting when the game closes (`-batch`), from `saveState` if
    /// given (`-statefile`, which loads it once the game has booted): `--` ends PCSX2's options. Refused while the Data
    /// folder is missing.
    func arguments(rom: URL, saveState: URL? = nil) throws -> [String] {
        try writeStanding()
        return ["-batch"] + (saveState.map { ["-statefile", $0.path(percentEncoded: false)] } ?? [])
            + ["--", rom.path(percentEncoded: false)]
    }

    /// Writes the Standing settings into `PCSX2.ini`, making the Data folder's PCSX2 folders for it to write into, and
    /// its two default memory cards as folder cards when nothing is at their names yet. Refused while the Data folder is
    /// missing, so nothing is kept somewhere Dropbox doesn't see. The file is left alone when it already says so.
    public func writeStanding() throws {
        try ludeum.checkData()
        let files = FileManager.default
        for folder in PCSX2Folder.allCases {
            try files.createDirectory(at: ludeum.pcsx2(folder), withIntermediateDirectories: true)
        }
        for card in Self.defaultCards {
            // Checked without a trailing slash: a file card at the name counts as there.
            let path = ludeum.pcsx2MemoryCards.appending(path: card, directoryHint: .notDirectory).path(percentEncoded: false)
            if !files.fileExists(atPath: path) {
                try files.createDirectory(atPath: path, withIntermediateDirectories: false)
            }
        }
        let original = try? String(contentsOf: settingsFile, encoding: .utf8)
        let updated = Self.standing(in: original ?? Self.firstRun, ludeum: ludeum)
        guard updated != original else { return }
        try files.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// The cards PCSX2 names by default, in its slots 1 and 2. A directory at a card's name is a folder card: one
    /// subfolder per save, which PCSX2 shows a running game only its own of, by its serial (ADR 0032).
    static let defaultCards = ["Mcd001.ps2", "Mcd002.ps2"]

    /// `ini` with the Standing settings: each folder's key an absolute path into the Data folder, `[AutoUpdater]
    /// CheckAtStartup` off, fast boot, a Resume state on closing, no frames queued for VSync, and the settings version
    /// PCSX2 checks for.
    static func standing(in ini: String, ludeum: LudeumFolder) -> String {
        var ini = ini
        for folder in PCSX2Folder.allCases {
            ini = Ini.setting(folder.key, to: path(ludeum.pcsx2(folder)), in: "Folders", of: ini)
        }
        for (section, key, value) in standingKeys { ini = Ini.setting(key, to: value, in: section, of: ini) }
        return ini
    }

    /// A folder's path as PCSX2's settings write one: without a trailing `/`.
    private static func path(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The keys the same for every Game.
    static let standingKeys: [(section: String, key: String, value: String)] = [
        ("UI", "SettingsVersion", "1"),
        ("EmuCore", "EnableFastBoot", "true"),
        ("EmuCore", "SaveStateOnShutdown", "true"),
        ("EmuCore/GS", "VsyncQueueSize", "0"),
        ("AutoUpdater", "CheckAtStartup", "false"),
    ]

    /// What PCSX2 writes only when it makes `PCSX2.ini` itself (`VMManager::SetDefaultSettings` at v2.9.103): the
    /// settings version, controller 1 as a DualShock 2 on the keyboard (`Pad::SetDefaultControllerConfig`, its generic
    /// keyboard mapping) and its hotkeys (`Pad::SetDefaultHotkeyConfig`). Everything else it defaults in code.
    static let firstRun = """
        [UI]
        SettingsVersion = 1

        [Pad1]
        Type = DualShock2
        Up = Keyboard/Up
        Right = Keyboard/Right
        Down = Keyboard/Down
        Left = Keyboard/Left
        Triangle = Keyboard/I
        Circle = Keyboard/L
        Cross = Keyboard/K
        Square = Keyboard/J
        Select = Keyboard/Backspace
        Start = Keyboard/Return
        L1 = Keyboard/Q
        L2 = Keyboard/1
        R1 = Keyboard/E
        R2 = Keyboard/3
        L3 = Keyboard/2
        R3 = Keyboard/4
        LUp = Keyboard/W
        LRight = Keyboard/D
        LDown = Keyboard/S
        LLeft = Keyboard/A
        RUp = Keyboard/T
        RRight = Keyboard/H
        RDown = Keyboard/G
        RLeft = Keyboard/F

        [Hotkeys]
        ToggleFullscreen = Keyboard/Alt & Keyboard/Return
        CycleAspectRatio = Keyboard/F6
        CycleInterlaceMode = Keyboard/F5
        ToggleMipmapMode = Keyboard/Insert
        GSDumpMultiFrame = Keyboard/Control & Keyboard/Shift & Keyboard/F8
        Screenshot = Keyboard/F8
        GSDumpSingleFrame = Keyboard/Shift & Keyboard/F8
        GSStartSavingMetricsVariableFrames = Keyboard/F10
        GSStartSavingMetricsFixedFrames = Keyboard/Control & Keyboard/F10
        ToggleSoftwareRendering = Keyboard/F9
        ZoomIn = Keyboard/Control & Keyboard/Plus
        ZoomOut = Keyboard/Control & Keyboard/Minus
        Mute = Keyboard/Control & Keyboard/M
        InputRecToggleMode = Keyboard/Shift & Keyboard/R
        LoadStateFromSlot = Keyboard/F3
        SaveStateToSlot = Keyboard/F1
        NextSaveStateSlot = Keyboard/F2
        PreviousSaveStateSlot = Keyboard/Shift & Keyboard/F2
        OpenPauseMenu = Keyboard/Escape
        ToggleFrameLimit = Keyboard/F4
        TogglePause = Keyboard/Space
        ToggleSlowMotion = Keyboard/Shift & Keyboard/Backtab
        ToggleTurbo = Keyboard/Tab
        HoldTurbo = Keyboard/Period

        """
}
