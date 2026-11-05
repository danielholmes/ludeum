import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import LudeumCore

/// A prepared Windows game in a folder, as Add ROM is given one and as a Windows ROM is kept (ADR 0040).
struct PreparedGame {
    let url: URL

    /// Makes `name` in `directory` with a launch file of `launch`, a `Game` folder holding its exe and some of the kinds
    /// of file a game has, a `Prefix` folder and the disc it came from.
    @discardableResult
    init(_ name: String, in directory: URL, launch: String = #"{ "exe": "GAME.EXE" }"#) throws {
        url = directory.appending(path: name, directoryHint: .isDirectory)
        try add("launch.json", launch)
        try add("Game/GAME.EXE", "the game")
        try add("Game/DATA/settings.ini", "volume=5")
        try add("Game/DATA/title.bmp", "a picture that's the game's")
        try add("Game/readme.txt", "a text that's the game's")
        try add("Prefix/game.reg", "REGEDIT4\n")
        try add("Prefix/codec.dll", "a codec")
        try add("Prefix/Fonts/game.ttf", "a font")
        try add("Disc/GAME.bin", "the disc")
        try add("Disc/GAME.cue", "FILE \"GAME.bin\" BINARY\n")
        try FileManager.default.createDirectory(at: url.appending(path: "Game/SAVEGAME"), withIntermediateDirectories: true)
    }

    @discardableResult
    func add(_ path: String, _ contents: String) throws -> URL {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    var launchFile: URL { url.appending(path: "launch.json") }
}

/// A launch file that asks for everything one can.
private let fullLaunch = #"""
    {
      "exe": "GAME.EXE",
      "startsIn": "DATA",
      "arguments": ["-nointro"],
      "installedAt": "Games/Test",
      "dllOverrides": { "ddraw": "n,b" },
      "locale": "en_GB.UTF-8",
      "registryFile": "game.reg",
      "drives": [{ "letter": "D", "kind": "cdrom", "label": "GAME" }],
      "windowsFiles": { "codec.dll": "syswow64/codec.dll", "Fonts": "Fonts" },
      "registryKeys": ["HKEY_CURRENT_USER\\Software\\Game", "HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Game"]
    }
    """#

/// A Windows ROM in its ROM folder (ADR 0040).
@Suite struct WindowsROMFolderTests {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "windows folder \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func aSubfolderWithALaunchFileAtItsTopIsAROMAndNoLooseFileIs() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let game = try PreparedGame("Age of Empires (USA)", in: windows.url)
        try windows.add("Not Prepared/Game/GAME.EXE")
        try windows.add("Not Prepared/Game/launch.json")
        try windows.add("loose.json")
        try windows.add("loose.exe")
        let archive = try windows.add("Z (Europe).7z")

        let roms = try windows.folder.scan()

        #expect(
            roms == [
                FolderROMFile(name: "Age of Empires (USA)", ready: game.launchFile, archive: nil),
                FolderROMFile(name: "Z (Europe)", ready: nil, archive: archive),
            ])
        #expect(roms.first?.fileName == "Age of Empires (USA)/launch.json")
        #expect(Emulator.of(platformId: ROMPlatform.windows) == .wine)
        #expect(Emulator.wine.isLudeums)
    }

    @Test func onlyFindersFilesAreClutterInAPreparedGame() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows).folder

        #expect(!windows.isClutter("Game/DATA/title.bmp"))
        #expect(!windows.isClutter("Game/readme.txt"))
        #expect(!windows.isClutter("Prefix/Fonts/game.otf"))
        #expect(windows.isClutter("Game/.DS_Store"))
        #expect(windows.isClutter("Game/DATA/._title.bmp"))
    }

    @Test func aPreparedFolderIsWindowsWhateverDiscItHoldsAndAnyOtherFolderIsnt() async throws {
        let prepared = ROMSource([try PreparedGame("Z (Europe)", in: directory).url])
        try FileManager.default.removeItem(at: try PreparedGame("Okami (USA)", in: directory).launchFile)
        let disc = ROMSource([directory.appending(path: "Okami (USA)", directoryHint: .isDirectory)])

        #expect(try await prepared.platforms(sevenZip: nil) == [ROMPlatform.windows])
        #expect(try await !disc.platforms(sevenZip: nil).contains(ROMPlatform.windows))
        #expect(AddROM.fileName(of: prepared, in: .platform(ROMPlatform.windows, directory)!) == "Z (Europe)/")
    }

    @Test func itHasNoChecksumToBeLookedUpBy() async throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        try PreparedGame("Z (Europe)", in: windows.url)
        let rom = try #require(try windows.folder.rom(named: "Z (Europe)"))

        #expect(await ROMChecksum.read(rom, platformId: ROMPlatform.windows, sevenZip: nil) == .noDump)
    }
}

/// A Windows ROM's launch file (ADR 0040).
@Suite struct WineLaunchFileTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "launch file \(UUID().uuidString)", directoryHint: .isDirectory)

    func reading(_ launch: String) throws -> WineLaunchFile {
        try WineLaunchFile.read(try PreparedGame("Game \(UUID().uuidString)", in: directory, launch: launch).launchFile)
    }

    @Test func itSaysHowTheGameIsStarted() throws {
        let launch = try reading(fullLaunch)

        #expect(launch.exe == "GAME.EXE")
        #expect(launch.startsIn == "DATA")
        #expect(launch.arguments == ["-nointro"])
        #expect(launch.dllOverrides == ["ddraw": "n,b"])
        #expect(launch.locale == "en_GB.UTF-8")
        #expect(launch.registryFile == "game.reg")
        #expect(launch.drives == [WineLaunchFile.Drive(letter: "D", kind: .cdrom, label: "GAME")])
        #expect(launch.windowsFiles == ["codec.dll": "syswow64/codec.dll", "Fonts": "Fonts"])
        #expect(launch.registryKeys == ["HKEY_CURRENT_USER\\Software\\Game", "HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Game"])
        #expect(launch.windowsPath(launch.exe) == "C:\\Games\\Test\\GAME.EXE")
    }

    @Test func onlyItsExeHasToBeNamed() throws {
        let launch = try reading(#"{ "exe": "GAME.EXE" }"#)

        #expect(launch.installed == "Game")
        #expect(launch.windowsPath(launch.exe) == "C:\\Game\\GAME.EXE")
    }

    @Test func oneThatCouldntBePlayedSaysWhy() throws {
        #expect(throws: WineLaunchFileError.unreadable("it isn't JSON")) { try reading("exe = GAME.EXE") }
        #expect(throws: WineLaunchFileError.unreadable("it has no \"exe\"")) { try reading("{}") }
        #expect(throws: WineLaunchFileError.unreadable("its \"drives.[0].kind\" isn't a value it can be")) {
            try reading(#"{ "exe": "GAME.EXE", "drives": [{ "letter": "d", "kind": "tape" }] }"#)
        }
        #expect(throws: WineLaunchFileError.notFound("Game/OTHER.EXE")) { try reading(#"{ "exe": "OTHER.EXE" }"#) }
        #expect(throws: WineLaunchFileError.notFound("Prefix/other.reg")) {
            try reading(#"{ "exe": "GAME.EXE", "registryFile": "other.reg" }"#)
        }
        #expect(throws: WineLaunchFileError.notFound("Prefix/other.dll")) {
            try reading(#"{ "exe": "GAME.EXE", "windowsFiles": { "other.dll": "system32/other.dll" } }"#)
        }
        #expect(throws: WineLaunchFileError.outside("../GAME.EXE")) { try reading(#"{ "exe": "../GAME.EXE" }"#) }
        #expect(throws: WineLaunchFileError.outside("DATA\\GAME.EXE")) { try reading(#"{ "exe": "DATA\\GAME.EXE" }"#) }
        #expect(throws: WineLaunchFileError.outside("/tmp")) {
            try reading(#"{ "exe": "GAME.EXE", "windowsFiles": { "codec.dll": "/tmp" } }"#)
        }
        #expect(throws: WineLaunchFileError.cantInstallAt("windows/system32")) {
            try reading(#"{ "exe": "GAME.EXE", "installedAt": "windows/system32" }"#)
        }
        #expect(throws: WineLaunchFileError.cantInstallAt("Program Files")) {
            try reading(#"{ "exe": "GAME.EXE", "installedAt": "Program Files" }"#)
        }
        #expect(throws: WineLaunchFileError.badDrive("c")) {
            try reading(#"{ "exe": "GAME.EXE", "drives": [{ "letter": "c", "kind": "hd" }] }"#)
        }
        #expect(throws: WineLaunchFileError.badRegistryKey("HKEY_USERS\\Game")) {
            try reading(#"{ "exe": "GAME.EXE", "registryKeys": ["HKEY_USERS\\Game"] }"#)
        }
        #expect(throws: WineLaunchFileError.badOverride("ddraw;mscoree")) {
            try reading(#"{ "exe": "GAME.EXE", "dllOverrides": { "ddraw;mscoree": "n" } }"#)
        }
    }

    @Test func aROMWithNoGameFolderIsRefused() throws {
        let game = try PreparedGame("No Game", in: directory)
        try FileManager.default.removeItem(at: game.url.appending(path: "Game"))

        #expect(throws: WineLaunchFileError.noGameFolder) { try WineLaunchFile.read(game.launchFile) }
    }
}

/// A Windows Game's Game save: what its game wrote (ADR 0040).
@Suite struct WineGameSaveTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wine save \(UUID().uuidString)", directoryHint: .isDirectory)
    var original: URL { directory.appending(path: "ROM/Game", directoryHint: .isDirectory) }
    var clone: URL { directory.appending(path: "Prefix/drive_c/Game", directoryHint: .isDirectory) }
    var save: WineGameSave { WineGameSave(folder: directory.appending(path: "Saves/Z (Europe)", directoryHint: .isDirectory)) }

    init() throws {
        for (path, contents) in [("GAME.EXE", "the game"), ("DATA/settings.ini", "volume=5"), ("DATA/level1.dat", "a level")] {
            let file = original.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original, to: clone)
    }

    func write(_ contents: String, to path: String) throws {
        let file = clone.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    func kept(_ path: String) -> String? { try? String(contentsOf: save.files.appending(path: path), encoding: .utf8) }

    @Test func itsEveryFileThatsNewOrDiffersFromTheROMsAndTheGamesRegistryKeys() throws {
        try write("volume=9", to: "DATA/settings.ini")
        try write("a saved game", to: "SAVEGAME/one.sav")
        // Written again as it was: the same bytes aren't a difference.
        try write("a level", to: "DATA/level1.dat")

        try save.gather(from: clone, against: original, registry: Data("keys".utf8))

        #expect(save.contents()?.files == ["DATA/settings.ini", "SAVEGAME/one.sav"])
        #expect(save.contents()?.hasRegistry == true)
        #expect(kept("DATA/settings.ini") == "volume=9")
        #expect(kept("SAVEGAME/one.sav") == "a saved game")
        #expect(try Data(contentsOf: save.registry) == Data("keys".utf8))
        // The ROM is as it was.
        #expect(try String(contentsOf: original.appending(path: "DATA/settings.ini"), encoding: .utf8) == "volume=5")
    }

    @Test func aGameThatWroteNothingHasNoGameSave() throws {
        try save.gather(from: clone, against: original, registry: nil)

        #expect(save.contents() == nil)
        #expect(!FileManager.default.fileExists(atPath: save.folder.path(percentEncoded: false)))
    }

    @Test func keptAgainItsTheWholeDifferenceWithWhatHasntChangedLeftAsItWas() throws {
        try write("volume=9", to: "DATA/settings.ini")
        try write("a saved game", to: "SAVEGAME/one.sav")
        try save.gather(from: clone, against: original, registry: Data("keys".utf8))
        let before = Date(timeIntervalSince1970: 1_000_000)
        let unchanged = save.files.appending(path: "SAVEGAME/one.sav").path(percentEncoded: false)
        try FileManager.default.setAttributes([.modificationDate: before], ofItemAtPath: unchanged)

        // The next Play: the settings go back to the ROM's, one save is added, and the keys are gone.
        try write("volume=5", to: "DATA/settings.ini")
        try write("another", to: "SAVEGAME/two.sav")
        try save.gather(from: clone, against: original, registry: nil)

        #expect(save.contents()?.files == ["SAVEGAME/one.sav", "SAVEGAME/two.sav"])
        #expect(save.contents()?.hasRegistry == false)
        #expect(!FileManager.default.fileExists(atPath: save.files.appending(path: "DATA").path(percentEncoded: false)))
        #expect(try FileManager.default.attributesOfItem(atPath: unchanged)[.modificationDate] as? Date == before)
    }

    @Test func itsLaidOverAFreshCloneOfTheROMsGame() throws {
        try write("volume=9", to: "DATA/settings.ini")
        try write("a saved game", to: "SAVEGAME/one.sav")
        try save.gather(from: clone, against: original, registry: nil)
        try FileManager.default.removeItem(at: clone)
        try FileManager.default.copyItem(at: original, to: clone)

        try save.lay(over: clone)

        #expect(try String(contentsOf: clone.appending(path: "DATA/settings.ini"), encoding: .utf8) == "volume=9")
        #expect(try String(contentsOf: clone.appending(path: "SAVEGAME/one.sav"), encoding: .utf8) == "a saved game")
        #expect(try String(contentsOf: clone.appending(path: "GAME.EXE"), encoding: .utf8) == "the game")
        // Kept again straight away, it's the same Game save.
        try save.gather(from: clone, against: original, registry: nil)
        #expect(save.contents()?.files == ["DATA/settings.ini", "SAVEGAME/one.sav"])
    }

    @Test func severalKeysExportsAreOneRegistryFile() {
        let header = "Windows Registry Editor Version 5.00\r\n\r\n"
        let first = header + "[HKEY_CURRENT_USER\\Software\\Game]\r\n\"Score\"=\"42\"\r\n\r\n"
        let second = header + "[HKEY_LOCAL_MACHINE\\Software\\Game]\r\n\"Disc\"=\"D\"\r\n\r\n"

        #expect(
            WinePlay.joined([first, header, second])
                == header + "[HKEY_CURRENT_USER\\Software\\Game]\r\n\"Score\"=\"42\"\r\n\r\n"
                + "[HKEY_LOCAL_MACHINE\\Software\\Game]\r\n\"Disc\"=\"D\"\r\n")
        #expect(WinePlay.joined([header]) == nil)
        #expect(WinePlay.joined([]) == nil)
    }
}

/// A Ludeum folder with a stand-in for the Wine Ludeum installs: scripts that do as much of `wineboot`, `reg` and a game
/// as a Play looks for, and write down what they were asked.
struct FakeWine {
    let ludeum: LudeumFolder
    var settings: WineSettings { WineSettings(ludeum: ludeum) }

    /// `wine`: `wineboot` makes a prefix's registry, `reg import` and `reg export` keep the keys in a file of the
    /// prefix's, and anything else is the game, which adds a line to `save.dat` where it starts and writes a key.
    static let wine = #"""
        #!/bin/sh
        echo "$*" >> "$WINEPREFIX/../asked.txt"
        case "$1" in
        wineboot)
            mkdir -p "$WINEPREFIX/drive_c/windows" "$WINEPREFIX/dosdevices"
            echo "registry" > "$WINEPREFIX/system.reg" ;;
        reg)
            case "$2" in
            import) cat "$WINEPREFIX/drive_c/ludeum.reg" >> "$WINEPREFIX/keys.txt" ;;
            export)
                grep -qF "$3" "$WINEPREFIX/keys.txt" 2>/dev/null || exit 1
                printf '\377\376' > "$WINEPREFIX/drive_c/ludeum.reg"
                printf 'Windows Registry Editor Version 5.00\r\n\r\n[%s]\r\n"Score"="42"\r\n\r\n' "$3" \
                    | iconv -f UTF-8 -t UTF-16LE >> "$WINEPREFIX/drive_c/ludeum.reg" ;;
            esac ;;
        *)
            echo "played $* with $WINEDLLOVERRIDES in $LC_ALL" >> save.dat
            pwd > "$WINEPREFIX/../started-in.txt"
            echo "[HKEY_CURRENT_USER\\Software\\Game]" >> "$WINEPREFIX/keys.txt" ;;
        esac
        """#

    init(in root: URL) throws {
        ludeum = LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory))
        let files = FileManager.default
        try files.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        let bin = ludeum.wineFolder.appending(path: "bin", directoryHint: .isDirectory)
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = Self.wine.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }.joined(separator: "\n")
        for (name, contents) in [("wine", script), ("wineserver", "#!/bin/sh\nexit 0\n")] {
            let file = bin.appending(path: name)
            try contents.write(to: file, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        }
        try WineRelease.Installed(.pinned).write(in: ludeum.wineFolder)
    }

    var windows: ROMFolder { .platform(ROMPlatform.windows, ludeum.romFolder(platform: ROMPlatform.windows)!)! }

    /// What the stand-in was asked, a line each, from the first.
    var asked: [String] {
        ((try? String(contentsOf: ludeum.winePrefixes.appending(path: "asked.txt"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }
}

/// A Play of a Windows ROM in Wine (ADR 0040), with a stand-in for Wine.
@Suite struct WinePlayTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "wine play \(UUID().uuidString)", directoryHint: .isDirectory)
    let wine: FakeWine
    let game: PreparedGame
    let name = "Z (Europe)"

    init() throws {
        wine = try FakeWine(in: root)
        game = try PreparedGame(name, in: wine.windows.url, launch: fullLaunch)
    }

    var prefix: URL { wine.ludeum.winePrefix(ofROM: name) }
    var clone: URL { prefix.appending(path: "drive_c/Games/Test", directoryHint: .isDirectory) }
    var save: WineGameSave { wine.ludeum.wineSave(ofROM: name) }

    func play() throws -> WinePlay { try WinePlay(launchFile: game.launchFile, romName: name, wine: wine.settings) }

    /// Plays it, returning the phases it went through.
    @discardableResult
    func run() async throws -> [WinePlay.Phase] {
        let phases = Mutex<[WinePlay.Phase]>([])
        try await play().run { phase in phases.withLock { $0.append(phase) } }
        return phases.withLock { $0 }
    }

    func text(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }
    func exists(_ file: URL) -> Bool { FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) }

    @Test func theFirstPlayMakesThePrefixRunsACloneAndKeepsWhatTheGameWrote() async throws {
        let phases = try await run()

        #expect(phases == [.makingPrefix, .gettingReady, .playing, .keepingSave])
        // The prefix: Wine's own, then what the launch file asks for.
        #expect(wine.asked.prefix(3) == ["wineboot --init", "reg import C:\\ludeum.reg", "reg import C:\\ludeum.reg"])
        #expect(text(prefix.appending(path: "drive_c/windows/syswow64/codec.dll")) == "a codec")
        #expect(text(prefix.appending(path: "drive_c/windows/Fonts/game.ttf")) == "a font")
        #expect(text(prefix.appending(path: "drives/d/.windows-label")) == "GAME")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: prefix.appending(path: "dosdevices/d:").path(percentEncoded: false))
                == "../drives/d")
        #expect(text(prefix.appending(path: "keys.txt"))?.contains("\"d:\"=\"cdrom\"") == true)
        #expect(text(prefix.appending(path: "keys.txt"))?.hasSuffix("REGEDIT4\n[HKEY_CURRENT_USER\\Software\\Game]\n") == true)
        // The game: its exe by its Windows path, started in its folder in the clone, with its overrides and locale.
        #expect(wine.asked.contains("C:\\Games\\Test\\GAME.EXE -nointro"))
        #expect(text(wine.ludeum.winePrefixes.appending(path: "started-in.txt"))?.hasSuffix("/drive_c/Games/Test/DATA\n") == true)
        #expect(
            text(clone.appending(path: "DATA/save.dat"))
                == "played C:\\Games\\Test\\GAME.EXE -nointro with ddraw=n,b;mscoree,mshtml= in en_GB.UTF-8\n")
        // What it wrote is the Game save, in the Data folder, and the ROM is as it was Added.
        #expect(save.contents()?.files == ["DATA/save.dat"])
        #expect(save.folder.path(percentEncoded: false).hasPrefix(wine.ludeum.data.path(percentEncoded: false)))
        let registry = try #require(String(data: try Data(contentsOf: save.registry), encoding: .utf16))
        #expect(registry == "Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\Game]\r\n\"Score\"=\"42\"\r\n")
        #expect(!exists(game.url.appending(path: "Game/DATA/save.dat")))
        #expect(!exists(WinePlay.saveToKeep(in: prefix)))
        #expect(!exists(prefix.appending(path: "drive_c/ludeum.reg")))
    }

    @Test func theNextPlayLaysTheGameSaveOverAFreshCloneInTheSamePrefix() async throws {
        try await run()
        // Something left in the clone that the game didn't write a second time, and a ROM that's still untouched.
        try "stale".write(to: clone.appending(path: "left-behind.tmp"), atomically: true, encoding: .utf8)

        let phases = try await run()

        #expect(phases == [.gettingReady, .playing, .keepingSave])
        #expect(wine.asked.filter { $0 == "wineboot --init" }.count == 1)
        #expect(text(clone.appending(path: "DATA/save.dat"))?.split(separator: "\n").count == 2)
        #expect(text(save.files.appending(path: "DATA/save.dat"))?.split(separator: "\n").count == 2)
        #expect(!exists(clone.appending(path: "left-behind.tmp")))
        #expect(save.contents()?.files == ["DATA/save.dat"])
    }

    @Test func aPrefixMadeFromAnotherLaunchFileOrAnotherWineIsMadeAgainWithTheGameSaveKept() async throws {
        try await run()
        try game.add("launch.json", fullLaunch.replacingOccurrences(of: "\"-nointro\"", with: "\"-window\""))

        #expect(try await run().first == .makingPrefix)

        try WineRelease.Installed(
            WineRelease(engine: "WS12WineSikarugir11.0_1", engineSHA256: "a", template: "Template-1.0.12", templateSHA256: "b")
        )
        .write(in: wine.ludeum.wineFolder)
        #expect(try await run().first == .makingPrefix)
        #expect(try await run().first == .gettingReady)
        #expect(text(save.files.appending(path: "DATA/save.dat"))?.split(separator: "\n").count == 4)
    }

    @Test func aPlayLudeumDidntSeeEndHasItsGameSaveKeptBeforeTheNextClone() async throws {
        try await run()
        // The game went on after Ludeum quit: it wrote into its clone, and nothing kept it.
        try "written unseen".write(to: clone.appending(path: "SAVEGAME/unseen.sav"), atomically: true, encoding: .utf8)
        try Data().write(to: WinePlay.saveToKeep(in: prefix))

        let phases = try await run()

        #expect(phases == [.keepingLastSave, .gettingReady, .playing, .keepingSave])
        #expect(text(clone.appending(path: "SAVEGAME/unseen.sav")) == "written unseen")
        #expect(save.contents()?.files == ["DATA/save.dat", "SAVEGAME/unseen.sav"])
    }

    @Test func aPrefixThatCouldntBeMadeStopsThePlayBeforeAnythingIsCloned() async throws {
        let bin = wine.ludeum.wineFolder.appending(path: "bin/wine")
        try "#!/bin/sh\nexit 3\n".write(to: bin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path(percentEncoded: false))

        await #expect(throws: WinePlayError.couldntMakePrefix("wineboot ended with status 3.")) { try await run() }
        #expect(!exists(clone))
        #expect(save.contents() == nil)
    }

    @Test func playIsRunInWineOnceItsInstalledAndItsLaunchFileReads() throws {
        let rom = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.windows, fileName: "\(name)/launch.json", name: name, version: "", disc: nil,
            missing: false, archived: false, serials: .notRead)
        let playing = Play(
            platformId: ROMPlatform.windows, platformName: "PC (Microsoft Windows)", roms: [rom], settings: EmulatorSettings())
        let locator = ROMLocator(romFolders: [wine.windows])
        func outcome(_ settings: WineSettings) -> Play.Outcome {
            playing.prepare(locator: locator, version: .warn("Check it"), app: { _ in nil }, wine: settings)
        }

        #expect(playing.availability == .ready(.wine))
        #expect(outcome(wine.settings) == .wine(try play(), warning: "Check it"))
        #expect(outcome(WineSettings(ludeum: LudeumFolder(url: root.appending(path: "Empty")))) == .refused(.notInstalled(.wine)))
        #expect(Play.Refusal.notInstalled(.wine).message == "Wine isn't installed. Install it from Ludeum ▸ Emulators…")

        try game.add("launch.json", #"{ "exe": "OTHER.EXE" }"#)
        #expect(outcome(wine.settings) == .refused(.badLaunchFile("Its launch.json names Game/OTHER.EXE, which isn't in it.")))
    }

    @Test func noGameIsRunningInAPrefixNoServerHasALockOn() throws {
        #expect(!wine.settings.isRunning(prefix: prefix))
        #expect(!wine.settings.isRunning)
        #expect(try !play().isRunning)
    }

    @Test func aROMThatsGoneLosesItsPrefixUnlessItHasAGameSaveToKeepAndKeepsItsGameSave() async throws {
        try await run()
        try Data().write(to: WinePlay.saveToKeep(in: prefix))
        wine.settings.removePrefix(ofROM: name)
        #expect(exists(prefix))

        try FileManager.default.removeItem(at: WinePlay.saveToKeep(in: prefix))
        wine.settings.removePrefix(ofROM: name)

        #expect(!exists(prefix))
        #expect(save.contents()?.files == ["DATA/save.dat"])
    }
}

/// Renaming a Windows ROM takes its Game save and its prefix with it (ADR 0040).
@Suite struct WineRenameTests {
    let j: LudeumHarness
    let root = FileManager.default.temporaryDirectory.appending(path: "wine rename \(UUID().uuidString)", directoryHint: .isDirectory)
    let wine: FakeWine

    init() throws {
        j = try LudeumHarness()
        wine = try FakeWine(in: root)
    }

    @Test func itsGameSaveAndItsPrefixAreRenamedWithIt() async throws {
        let game = try PreparedGame("Z", in: wine.windows.url)
        let file = try #require(try wine.windows.rom(named: "Z"))
        let (_, rom) = try j.journal.recordAddedROM(
            file, checksum: nil, on: ROMPlatform.windows, reusing: nil, regions: [], match: .byHand(name: "Z"))
        try await WinePlay(launchFile: game.launchFile, romName: "Z", wine: wine.settings).run()

        try j.journal.renameWineROM(rom, from: "Z", to: "Z (Europe)", in: wine.windows, ludeum: wine.ludeum)

        let files = FileManager.default
        #expect(try wine.windows.scan().map(\.name) == ["Z (Europe)"])
        #expect(wine.ludeum.wineSave(ofROM: "Z (Europe)").contents()?.files == ["save.dat"])
        #expect(wine.ludeum.wineSave(ofROM: "Z").contents() == nil)
        #expect(
            files.fileExists(atPath: wine.ludeum.winePrefix(ofROM: "Z (Europe)").appending(path: "system.reg").path(percentEncoded: false)))
        #expect(!files.fileExists(atPath: wine.ludeum.winePrefix(ofROM: "Z").path(percentEncoded: false)))
    }

    @Test func aGameSaveAlreadyUnderTheNewNameRefusesIt() throws {
        try PreparedGame("Z", in: wine.windows.url)
        let file = try #require(try wine.windows.rom(named: "Z"))
        let (_, rom) = try j.journal.recordAddedROM(
            file, checksum: nil, on: ROMPlatform.windows, reusing: nil, regions: [], match: .byHand(name: "Z"))
        try FileManager.default.createDirectory(at: wine.ludeum.wineSave(ofROM: "Z (Europe)").folder, withIntermediateDirectories: true)

        #expect(throws: WineRenameError.inTheWay("Z (Europe)")) {
            try j.journal.renameWineROM(rom, from: "Z", to: "Z (Europe)", in: wine.windows, ludeum: wine.ludeum)
        }
        #expect(try wine.windows.scan().map(\.name) == ["Z"])
    }
}

/// Installing the Wine Ludeum keeps (ADR 0040).
@Suite struct WineInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "wine install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: WineSettings { WineSettings(ludeum: ludeum) }
    /// When the engine's `wine.inf` was written, in its tar.
    let written = Date(timeIntervalSince1970: 1_775_000_000)

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// A folder as a `.tar.xz`, as GitHub serves one.
    func tar(_ folder: URL) throws -> Data {
        let file = folder.deletingLastPathComponent().appending(path: "\(UUID().uuidString).tar.xz")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.currentDirectoryURL = folder.deletingLastPathComponent()
        tar.arguments = ["-cJf", file.path(percentEncoded: false), folder.lastPathComponent]
        try tar.run()
        tar.waitUntilExit()
        return try Data(contentsOf: file)
    }

    func write(_ contents: String, to file: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false)) }
    }

    /// A fake engine and Template, each in a tar, and the release that names them.
    func release(engineHasWine: Bool = true, engineSHA256: String? = nil, templateSHA256: String? = nil) throws
        -> (release: WineRelease, tars: [URL: Data])
    {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let engine = staging.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        if engineHasWine { try write("#!/bin/sh\n", to: engine.appending(path: "bin/wine"), executable: true) }
        try write("#!/bin/sh\n", to: engine.appending(path: "bin/wineserver"), executable: true)
        try write("ntdll", to: engine.appending(path: "lib/wine/x86_64-unix/ntdll.so"))
        try write("[Version]", to: engine.appending(path: "share/wine/wine.inf"))
        try FileManager.default.setAttributes(
            [.modificationDate: written], ofItemAtPath: engine.appending(path: "share/wine/wine.inf").path(percentEncoded: false))
        let template = staging.appending(path: "Template-1.0.11.app", directoryHint: .isDirectory)
        try write("freetype", to: template.appending(path: "Contents/Frameworks/libfreetype.6.dylib"))
        try write("gnutls", to: template.appending(path: "Contents/Frameworks/libgnutls.30.dylib"))
        try write("a framework", to: template.appending(path: "Contents/Frameworks/GStreamer.framework/GStreamer"))
        try write("the wrapper", to: template.appending(path: "Contents/MacOS/Sikarugir"))
        let (engineTar, templateTar) = (try tar(engine), try tar(template))
        func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let release = WineRelease(
            engine: "WS12WineSikarugir10.0_6", engineSHA256: engineSHA256 ?? digest(engineTar), template: "Template-1.0.11",
            templateSHA256: templateSHA256 ?? digest(templateTar))
        return (release, [release.engineURL: engineTar, release.templateURL: templateTar])
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: ludeum.wineFolder.appending(path: path).path(percentEncoded: false))
    }

    @Test func installPutsTheEngineInTheLudeumFolderWithTheTemplatesLibrariesInItsLib() async throws {
        let (release, tars) = try self.release()
        let github = FakeReleases(tars)
        let installer = WineInstaller(ludeum: ludeum, release: release, transport: github)
        let seen = Mutex<[Double]>([])
        #expect(!settings.isInstalled)

        try await installer.install { value in seen.withLock { $0.append(value) } }

        #expect(github.requested.withLock { $0 } == [release.engineURL, release.templateURL])
        #expect(settings.isInstalled)
        #expect(settings.installed == WineRelease.Installed(release))
        #expect(exists("lib/wine/x86_64-unix/ntdll.so"))
        #expect(exists("lib/libfreetype.6.dylib"))
        #expect(exists("lib/libgnutls.30.dylib"))
        // Only the libraries: not the Template's frameworks, nor anything else of its app.
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: ludeum.wineFolder.appending(path: "lib").path(percentEncoded: false))
                .sorted()
                == ["libfreetype.6.dylib", "libgnutls.30.dylib", "wine"])
        // A prefix remembers this time, and is updated by a Wine that has another.
        let inf = ludeum.wineFolder.appending(path: "share/wine/wine.inf").path(percentEncoded: false)
        #expect(try FileManager.default.attributesOfItem(atPath: inf)[.modificationDate] as? Date == written)
        #expect(seen.withLock { $0 }.last == 1)
        #expect(!FileManager.default.fileExists(atPath: installer.work.path(percentEncoded: false)))
    }

    @Test func thePinnedReleaseIsSikarugirsEngineAndItsTemplate() {
        let pinned = WineRelease.pinned

        #expect(pinned.version == "10.0.6")
        #expect(
            pinned.engineURL.absoluteString
                == "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz")
        #expect(
            pinned.templateURL.absoluteString == "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.11.tar.xz")
        #expect(Emulator.wine.expectedVersion == "10.0.6")
    }

    @Test func aDownloadThatIsntTheReleaseIsRefusedWhicheverItIs() async throws {
        let zeros = String(repeating: "0", count: 64)
        let (right, _) = try self.release()
        let (engine, engineTars) = try self.release(engineSHA256: zeros)
        let (template, templateTars) = try self.release(templateSHA256: zeros)

        await #expect(throws: WineInstallError.self) {
            try await WineInstaller(ludeum: ludeum, release: engine, transport: FakeReleases(engineTars)).install()
        }
        await #expect(throws: WineInstallError.self) {
            try await WineInstaller(ludeum: ludeum, release: template, transport: FakeReleases(templateTars)).install()
        }
        #expect(!settings.isInstalled)
        #expect(right.engineSHA256 != zeros)
    }

    @Test func aDownloadGitHubHasntIsRefused() async throws {
        let (release, tars) = try self.release()

        await #expect(throws: WineInstallError.notFound("Template-1.0.11", status: 404)) {
            try await WineInstaller(ludeum: ludeum, release: release, transport: FakeReleases(tars.filter { $0.key == release.engineURL }))
                .install()
        }
        await #expect(throws: WineInstallError.notFound("WS12WineSikarugir10.0_6", status: 404)) {
            try await WineInstaller(ludeum: ludeum, release: release, transport: FakeReleases([:])).install()
        }
        #expect(!settings.isInstalled)
    }

    @Test func anEngineWithNoWineInItIsRefused() async throws {
        let (release, tars) = try self.release(engineHasWine: false)

        await #expect(throws: WineInstallError.noEngine) {
            try await WineInstaller(ludeum: ludeum, release: release, transport: FakeReleases(tars)).install()
        }
        #expect(!settings.isInstalled)
    }

    @Test func aReinstallReplacesTheEngineAndLeavesThePrefixesBesideIt() async throws {
        let (release, tars) = try self.release()
        try await WineInstaller(ludeum: ludeum, release: release, transport: FakeReleases(tars)).install()
        try write("mine", to: ludeum.wineFolder.appending(path: "mine.txt"))
        try write("registry", to: ludeum.winePrefix(ofROM: "Z (Europe)").appending(path: "system.reg"))

        try await WineInstaller(ludeum: ludeum, release: release, transport: FakeReleases(tars)).install()

        #expect(settings.isInstalled)
        #expect(!exists("mine.txt"))
        #expect(
            FileManager.default.fileExists(
                atPath: ludeum.winePrefix(ofROM: "Z (Europe)").appending(path: "system.reg").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: ludeum.emulators.appending(path: "Wine (replaced)").path(percentEncoded: false)))
    }

    @Test func itsBuildIsCheckedByWhatInstallRecorded() throws {
        try FileManager.default.createDirectory(at: ludeum.wineFolder, withIntermediateDirectories: true)
        #expect(EmulatorVersions.check(.wine, app: ludeum.wineFolder)?.check == .unreadable)

        try WineRelease.Installed(.pinned).write(in: ludeum.wineFolder)
        #expect(EmulatorVersions.check(.wine, app: ludeum.wineFolder)?.check == .ok)
        #expect(EmulatorVersions.check(.wine, app: ludeum.wineFolder)?.installed == "10.0.6")

        let other = WineRelease(engine: "WS12WineSikarugir10.0_8", engineSHA256: "a", template: "Template-1.0.11", templateSHA256: "b")
        try WineRelease.Installed(other).write(in: ludeum.wineFolder)
        #expect(EmulatorVersions.check(.wine, app: ludeum.wineFolder)?.check == .wrongBuild(found: "10.0.8"))
    }
}

/// Adding, Archiving and Unarchiving a Windows ROM (ADR 0040).
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct WindowsROMTests {
    let j: LudeumHarness
    let directory = FileManager.default.temporaryDirectory.appending(path: "windows rom \(UUID().uuidString)", directoryHint: .isDirectory)
    let windows: FakeROMFolder
    let picked: URL
    let trash: URL

    init() throws {
        j = try LudeumHarness()
        windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        picked = directory.appending(path: "Downloads", directoryHint: .isDirectory)
        trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        for folder in [picked, trash] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    var moveToTrash: @Sendable (URL) throws -> Void {
        let trash = trash
        return { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) }
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: windows.url.appending(path: path).path(percentEncoded: false))
    }

    @Test func addROMTakesAPreparedFolderAsItIsAndMatchesItByHand() async throws {
        let prepared = try PreparedGame("Z (Europe)", in: picked)
        try prepared.add("Game/.DS_Store", "Finder's")
        let adder = AddROM(journal: j.journal, sevenZip: SevenZip.find(), moveToTrash: moveToTrash)

        let game = try await adder.add(ROMSource([prepared.url]), to: windows.folder, match: .byHand(name: "Z"), keepingOriginals: true)

        let rom = try #require(try j.journal.roms(of: game).first)
        #expect(rom.folderName == "Z (Europe)")
        #expect(rom.fileName == "Z (Europe)/launch.json")
        #expect(!rom.archived)
        #expect(try j.journal.game(game).platformId == ROMPlatform.windows)
        // Its pictures, texts, disc and empty folders with it, and only Finder's file left out.
        for path in ["Game/GAME.EXE", "Game/DATA/title.bmp", "Game/readme.txt", "Game/SAVEGAME", "Prefix/Fonts/game.ttf", "Disc/GAME.bin"] {
            #expect(exists("Z (Europe)/\(path)"), "\(path)")
        }
        #expect(!exists("Z (Europe)/Game/.DS_Store"))
        #expect(FileManager.default.fileExists(atPath: prepared.url.path(percentEncoded: false)))
    }

    @Test func aPreparedFolderThatCouldntBePlayedIsntTaken() async throws {
        let prepared = try PreparedGame("Z (Europe)", in: picked, launch: #"{ "exe": "OTHER.EXE" }"#)
        let adder = AddROM(journal: j.journal, sevenZip: SevenZip.find(), moveToTrash: moveToTrash)

        await #expect(throws: WineLaunchFileError.notFound("Game/OTHER.EXE")) {
            try await adder.add(ROMSource([prepared.url]), to: windows.folder, match: .byHand(name: "Z"), keepingOriginals: true)
        }
        #expect(try windows.folder.scan().isEmpty)
    }

    @Test func itsArchivedWholeAndUnarchivedAsItWas() async throws {
        let game = try PreparedGame("Z (Europe)", in: windows.url)
        try game.add("Game/.DS_Store", "Finder's")
        let archiver = ROMArchiver(sevenZip: SevenZip.find()!, freeSpace: { _ in .max }, moveToTrash: moveToTrash)

        try await archiver.archive("Z (Europe)", in: windows.folder)

        #expect(
            try windows.folder.scan() == [
                FolderROMFile(name: "Z (Europe)", ready: nil, archive: windows.url.appending(path: "Z (Europe).7z"))
            ])
        let packed = try await SevenZip.find()!.contents(of: windows.url.appending(path: "Z (Europe).7z")).map(\.path).sorted()
        #expect(
            packed == [
                "Disc/GAME.bin", "Disc/GAME.cue", "Game/DATA/settings.ini", "Game/DATA/title.bmp", "Game/GAME.EXE", "Game/readme.txt",
                "Prefix/Fonts/game.ttf", "Prefix/codec.dll", "Prefix/game.reg", "launch.json",
            ])

        try await archiver.unarchive(windows.url.appending(path: "Z (Europe).7z"), romName: "Z (Europe)", in: windows.folder)

        #expect(try windows.folder.scan() == [FolderROMFile(name: "Z (Europe)", ready: game.launchFile, archive: nil)])
        for path in ["Game/GAME.EXE", "Game/DATA/title.bmp", "Game/readme.txt", "Game/SAVEGAME", "Disc/GAME.cue"] {
            #expect(exists("Z (Europe)/\(path)"), "\(path)")
        }
        #expect(!exists("Z (Europe)/Game/.DS_Store"))
    }

    @Test func itsArchivedOrUnarchivedAndNeverCompacted() {
        func rom(archived: Bool) -> LudeumROM {
            LudeumROM(
                id: 1, folderName: "Z (Europe)", platformId: ROMPlatform.windows,
                fileName: archived ? "Z (Europe).7z" : "Z (Europe)/launch.json", name: "Z (Europe)", version: "", disc: nil, missing: false,
                archived: archived, serials: .notRead)
        }

        #expect(ROMArchiving.action(for: rom(archived: false)) == .archive)
        #expect(ROMArchiving.action(for: rom(archived: true)) == .unarchive)
        #expect(ROMArchiving.unpacking(rom(archived: true)) == .folder)
    }

    @Test func anArchiveWithNoLaunchFileAtItsTopIsntUnarchived() throws {
        let windows = windows.folder
        #expect(throws: ArchiveError.noLaunchFile("launch.json")) {
            try ROMArchiver.unarchivePlan(
                listing: [
                    SevenZip.Entry(path: "Z (Europe)/launch.json", size: 10), SevenZip.Entry(path: "Z (Europe)/Game/GAME.EXE", size: 10),
                ],
                archive: windows.url.appending(path: "Z (Europe).7z"), romName: "Z (Europe)", folder: windows)
        }
    }
}
