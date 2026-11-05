import Foundation

/// Play: opening a Game's present ROM in its Platform's Emulator, with every Emulator setting on
/// the command line (ADR 0008). It decides what to open, or why it can't; the app does the opening.
public struct Play: Sendable {
    public enum Availability: Sendable, Equatable {
        case ready(Emulator)
        case refused(Refusal)

        public var refusal: Refusal? {
            if case .refused(let refusal) = self { refusal } else { nil }
        }
    }

    /// Why a Game can't be Played.
    public enum Refusal: Sendable, Equatable {
        case noEmulator(String)
        /// No present ROM: none, or every one missing.
        case noROM
        case archived
        /// Archived in a `.7z` its Emulator can't open, on a Platform whose ROMs Compact into one it can (ares's `.zip`).
        case archivedNeedsCompacting
        case needsPlaylist
        case busy
        case tooOld(String)
        case notInstalled(Emulator)
        case fileNotFound(String)
        case couldntLook(String, String)
        case couldntWriteSettings(Emulator, String)
        /// An Xbox ROM that's a full Redump image, which xemu can't boot.
        case needsXISO
        /// DuckStation, MesenCE, ares, PCSX2 or Ymir is open: Ludeum writes its settings before each Play, which an open
        /// DuckStation, ares, PCSX2 or Ymir would write over (ADRs 0024, 0028, 0032, 0036) and an open MesenCE wouldn't read
        /// (ADR 0027).
        case running(Emulator)
        /// DuckStation, MesenCE, ares, PCSX2 or Ymir is being installed, so there's nothing to open yet.
        case installing(Emulator)
        /// The installed Emulator's build needs a library from Homebrew that isn't installed (MesenCE 2.2.1's SDL2).
        case needs(Emulator, HomebrewLibrary)
        /// PCSX2 or Ymir has no BIOS of this Platform's to boot with: none in the Data folder's BIOS folder, at this path
        /// (ADRs 0032, 0036).
        case noBIOS(platform: String, folder: String)
        /// ares has no Sega CD BIOS to boot with: none named for a region in this folder (ADR 0037).
        case noSegaCDBIOS(String)
        /// An Amiga ROM that isn't Compacted: Amiberry would write a game's saves into its loose disk (ADR 0035).
        case needsCompacting
        /// An Amiga ROM's disks couldn't be listed from its archive or their save images made, with why.
        case couldntGetDisksReady(String)
        /// A Windows ROM's game is still running in Wine, or closed less than a few seconds ago: its clone can't be
        /// replaced under it (ADR 0040).
        case stillRunning
        /// A Windows ROM's launch file can't be Played as it is, with what's wrong with it.
        case badLaunchFile(String)

        public var message: String {
            switch self {
            case .noEmulator(let platform): "No \(platform) emulator yet"
            case .noROM: "No ROM in its ROM folder"
            case .archived: "Archived: unarchive to play"
            case .archivedNeedsCompacting: "Archived: compact to play"
            case .needsPlaylist: "Its Discs have no playlist: put an .m3u naming them in its folder, and it's seen at the next Import"
            case .busy: "Waiting for Archive, Unarchive or Compact to finish"
            case .tooOld(let message): message
            case .notInstalled(let emulator) where emulator.isLudeums:
                "\(emulator.name) isn't installed. Install it from Ludeum ▸ Emulators…"
            case .notInstalled(let emulator): "\(emulator.name) isn't installed."
            case .fileNotFound(let file): "Couldn't find \(file). Run an Import, then try again."
            case .couldntLook(let file, let why): "Couldn't look for \(file): \(why)"
            case .couldntWriteSettings(let emulator, let why): "Couldn't write \(emulator.name)'s settings: \(why)"
            case .needsXISO: "It's a full Redump image, and xemu boots only an XISO: make one with `xdvdfs pack`, then put it in its place."
            case .running(.mesenCE):
                "MesenCE is open. Quit it, then Play: Ludeum says where to keep this Platform's saves before each Play, "
                    + "which an open MesenCE wouldn't read."
            case .running(.amiberry):
                "Amiberry is open. Quit it, then Play: it keeps its settings in memory and writes them over when it quits."
            case .running(let emulator):
                "\(emulator.name) is open. Quit it, then Play: Ludeum writes its settings before each Play, which an open \(emulator.name) would write over."
            case .installing(let emulator): "\(emulator.name) is being installed."
            case .needs(let emulator, let library):
                "\(emulator.name) needs \(library.name), which isn't installed: install it with `\(library.install)`, then Play."
            case .noBIOS(let platform, let folder): "No \(platform) BIOS. Put one in \(folder), then Play."
            case .noSegaCDBIOS(let folder):
                "No Sega CD BIOS. Put one in \(folder), named Mega CD US.bin, Mega CD Japan.bin or Mega CD Europe.bin, then Play."
            case .needsCompacting: "Compact it to Play: a game saves to its disk, and a loose disk would be written over."
            case .couldntGetDisksReady(let why): "Couldn't get its disks ready: \(why)"
            case .stillRunning: "It's still running in Wine. Quit it, give Wine a few seconds to finish, then Play."
            case .badLaunchFile(let why): why
            }
        }
    }

    let platformId: Int64
    let platformName: String
    let roms: [LudeumROM]
    let settings: EmulatorSettings
    let busyROMs: Set<Int64>

    /// `busyROMs`: the ROMs a Background task is working on.
    public init(platformId: Int64, platformName: String, roms: [LudeumROM], settings: EmulatorSettings, busyROMs: Set<Int64> = []) {
        self.platformId = platformId
        self.platformName = platformName
        self.roms = roms
        self.settings = settings
        self.busyROMs = busyROMs
    }

    /// The ROM a Play opens: the playlist of a multi-disc Version, else the first present ROM that isn't archived.
    public var rom: LudeumROM? {
        let present = roms.filter { !$0.missing && !$0.archived }
        return present.first { $0.fileName.lowercased().hasSuffix(".m3u") } ?? present.first
    }

    /// Whether Play can be pressed, before it is.
    public var availability: Availability {
        guard let emulator = Emulator.of(platformId: platformId) else { return .refused(.noEmulator(platformName)) }
        let present = roms.filter { !$0.missing }
        if present.isEmpty { return .refused(.noROM) }
        if present.allSatisfy(\.archived) {
            return .refused(ROMPlatform.all[platformId]?.compactExtension == nil ? .archived : .archivedNeedsCompacting)
        }
        if roms.contains(where: { busyROMs.contains($0.id) }) { return .refused(.busy) }
        if rom?.needsPlaylist == true { return .refused(.needsPlaylist) }
        if emulator == .amiberry, rom?.fileName.lowercased().hasSuffix(".7z") == false { return .refused(.needsCompacting) }
        return .ready(emulator)
    }

    /// The Emulator's installed version, as the version checks found it.
    public enum VersionStatus: Sendable, Equatable {
        case ok
        /// Play goes ahead, with this shown first.
        case warn(String)
        case tooOld(String)
    }

    public enum Outcome: Sendable, Equatable {
        /// Open `app` with `arguments`, showing `warning` first when there is one. `startsOn` is the Disc a multi-disc ROM
        /// starts on, for the journal to remember. `environment` is what it needs set for this launch (Amiberry's home).
        case open(app: URL, arguments: [String], warning: String?, startsOn: DiscStart? = nil, environment: [String: String] = [:])
        /// Run this Play in Wine, showing `warning` first when there is one: there's no app to open, and it isn't over
        /// until the game has ended and its Game save is kept (ADR 0040).
        case wine(WinePlay, warning: String?)
        case refused(Refusal)

        public var refusal: Refusal? {
            if case .refused(let refusal) = self { refusal } else { nil }
        }

        public var arguments: [String]? {
            if case .open(_, let arguments, _, _, _) = self { arguments } else { nil }
        }

        public var warning: String? {
            switch self {
            case .open(_, _, let warning, _, _), .wine(_, let warning): warning
            case .refused: nil
            }
        }

        public var startsOn: DiscStart? {
            if case .open(_, _, _, let startsOn, _) = self { startsOn } else { nil }
        }
    }

    /// The Disc a multi-disc ROM's Play starts on, which it starts on next time too (ADR 0026).
    public struct DiscStart: Sendable, Equatable {
        public let rom: Int64
        public let disc: Int

        public init(rom: Int64, disc: Int) {
            self.rom = rom
            self.disc = disc
        }
    }

    /// The Discs its Play can start on: a multi-disc PlayStation ROM's, in its playlist's order, else none. Disc 1 is
    /// opened through the playlist, so a Disc set DuckStation's database doesn't know still swaps; any other as its own
    /// cue sheet, as DuckStation can't be told which of a playlist's Discs to boot, and swaps from its game list.
    public func discs(locator: ROMLocator) -> [PlayDisc] {
        guard Emulator.of(platformId: platformId) == .duckStation, let rom, let file = try? locator.file(of: rom, ready: true) else {
            return []
        }
        let serials: [String?] = if case .read(let serials) = rom.serials { serials } else { [] }
        return Self.discs(ofPlaylist: file).map { disc in
            var disc = disc
            disc.serial = serials.indices.contains(disc.number - 1) ? serials[disc.number - 1] : nil
            return disc
        }
    }

    static func discs(ofPlaylist file: URL) -> [PlayDisc] {
        guard file.pathExtension.lowercased() == "m3u" else { return [] }
        let entries = ROMFiles.playlistEntries(file)
        guard entries.count > 1 else { return [] }
        return entries.enumerated().map { i, entry in
            PlayDisc(
                number: i + 1, label: ROMName((entry as NSString).deletingPathExtension).discLabel,
                file: file.deletingLastPathComponent().appending(path: entry))
        }
    }

    /// The Disc a Play starts on, of `discs`: `chosen` (Disc 1 when it hasn't that one), else the one it last started on
    /// while that Disc's file is there, else Disc 1. Nil for a ROM of one Disc.
    public func startingDisc(among discs: [PlayDisc], chosen: Int? = nil) -> PlayDisc? {
        if let chosen { return discs.first { $0.number == chosen } ?? discs.first }
        return discs.first { $0.number == rom?.lastDisc && FileManager.default.fileExists(atPath: $0.file.path(percentEncoded: false)) }
            ?? discs.first
    }

    /// The Resume state its Play starts from, when its Emulator keeps one for its ROM (ADR 0034): the one DuckStation or
    /// PCSX2 saved on closing, by each Disc's Serial (the latest saved, where more than one Disc has one), or MesenCE's
    /// automatic state of the ROM's name. Nil where there's none, for a ROM whose Serials aren't read, for an archive
    /// MesenCE's name can't be read from, and for ares and the rest, which keep none Ludeum knows.
    public func resumeState(locator: ROMLocator, ludeum: LudeumFolder) async -> SaveState? {
        guard let rom else { return nil }
        let emulator = Emulator.of(platformId: platformId)
        let states: [SaveState]
        if emulator == .duckStation {
            states = DuckStationSaveStates(ludeum: ludeum).states(of: rom.serials.known)
        } else if emulator == .pcsx2 {
            states = PCSX2SaveStates(ludeum: ludeum).states(of: rom.serials.known)
        } else if emulator == .mesenCE {
            guard let folders = MesenSaveStates(ludeum: ludeum, platformId: platformId), let file = try? locator.file(of: rom, ready: true),
                let name = await MesenROMName.of(file, platformId: platformId)?.name
            else { return nil }
            states = folders.states(of: name)
        } else {
            return nil
        }
        return states.filter { $0.slot == .resume && !$0.previous }.max { $0.saved < $1.saved }
    }

    /// What a press of Play starts from, and a double-click on the Game's Cover (ADR 0034): `resume` when there is one,
    /// ahead of the Disc a multi-disc ROM last started on; else that Disc; else just its ROM.
    public func start(discs: [PlayDisc], resume: SaveState?) -> PlayStart {
        if let resume { return .resume(resume) }
        return startingDisc(among: discs).map(PlayStart.disc) ?? .rom
    }

    /// Every way its Play can start, for Play's menu: Resume when there's a Resume state, then each Disc of a multi-disc
    /// ROM, or just its ROM. One way alone is a plain button.
    public func starts(discs: [PlayDisc], resume: SaveState?) -> [PlayStart] {
        (resume.map { [PlayStart.resume($0)] } ?? []) + (discs.isEmpty ? [.rom] : discs.map(PlayStart.disc))
    }

    /// The Disc a Save state was saved on, by its Serial.
    private func disc(savedIn saveState: URL) -> Int? {
        guard let rom, case .read(let serials) = rom.serials,
            let serial = SaveState.parse(saveState.lastPathComponent, serials: rom.serials.known)?.serial,
            let index = serials.firstIndex(of: serial)
        else { return nil }
        return index + 1
    }

    /// What a press of Play does. It writes the settings files of an Emulator that takes them only
    /// that way. `app` finds an installed app by its bundle identifier; DuckStation, MesenCE, ares, PCSX2, Amiberry and Ymir
    /// are the ones Ludeum installs (`duckStation.app`, `mesen.app`, `ares.app`, `pcsx2.app`, `amiberry.app`, `ymir.app`),
    /// refused while any copy is `running`, and PCSX2 and Ymir until they have a BIOS. `saveState` starts the Play from that
    /// state, DuckStation's on its own Disc; else a multi-disc ROM starts on `disc`, or the one it last started on. A
    /// Windows ROM's is a Play in the `wine` Ludeum installs, refused until it's there, while the ROM's game is still
    /// running, and when its launch file can't be Played as it is (ADR 0040).
    public func prepare(
        locator: ROMLocator, version: VersionStatus, app installed: (String) -> URL?, saveState: URL? = nil, disc: Int? = nil,
        duckStation: DuckStationSettings = .init(), mesen: MesenSettings = .init(), ares: AresSettings = .init(),
        pcsx2: PCSX2Settings = .init(), amiberry: AmiberrySettings = .init(), ymir: YmirSettings = .init(),
        wine: WineSettings = .init(), running: (Emulator) -> Bool = { _ in false }
    ) -> Outcome {
        let emulator: Emulator
        switch availability {
        case .refused(let refusal): return .refused(refusal)
        case .ready(let ready): emulator = ready
        }
        if case .tooOld(let message) = version { return .refused(.tooOld(message)) }
        let app: URL
        if emulator == .duckStation {
            guard duckStation.isInstalled else { return .refused(.notInstalled(emulator)) }
            if running(emulator) { return .refused(.running(emulator)) }
            app = duckStation.app
        } else if emulator == .mesenCE {
            guard mesen.isInstalled else { return .refused(.notInstalled(emulator)) }
            if let library = MesenRelease.pinned.needs, !library.isInstalled { return .refused(.needs(emulator, library)) }
            if running(emulator) { return .refused(.running(emulator)) }
            app = mesen.app
        } else if emulator == .ares {
            guard ares.isInstalled else { return .refused(.notInstalled(emulator)) }
            if running(emulator) { return .refused(.running(emulator)) }
            if platformId == ROMPlatform.segaCD, !ares.hasSegaCDBIOS {
                return .refused(.noSegaCDBIOS(ares.ludeum.aresBIOS.path(percentEncoded: false)))
            }
            app = ares.app
        } else if emulator == .pcsx2 {
            guard pcsx2.isInstalled else { return .refused(.notInstalled(emulator)) }
            if running(emulator) { return .refused(.running(emulator)) }
            guard pcsx2.hasBIOS else {
                return .refused(.noBIOS(platform: "PlayStation 2", folder: pcsx2.ludeum.pcsx2BIOS.path(percentEncoded: false)))
            }
            app = pcsx2.app
        } else if emulator == .ymir {
            guard ymir.isInstalled else { return .refused(.notInstalled(emulator)) }
            if running(emulator) { return .refused(.running(emulator)) }
            guard ymir.hasBIOS else {
                return .refused(.noBIOS(platform: "Saturn", folder: ymir.ludeum.ymir(.bios).path(percentEncoded: false)))
            }
            app = ymir.app
        } else if emulator == .amiberry {
            guard amiberry.isInstalled else { return .refused(.notInstalled(emulator)) }
            if running(emulator) { return .refused(.running(emulator)) }
            app = amiberry.app
        } else if emulator == .wine {
            // Other ROMs' games can be running: each has a prefix of its own.
            guard wine.isInstalled else { return .refused(.notInstalled(emulator)) }
            app = wine.folder
        } else {
            guard let found = installed(emulator.bundleIdentifier) else { return .refused(.notInstalled(emulator)) }
            app = found
        }
        guard let rom else {
            return .refused(.archived)
        }
        let file: URL
        do {
            guard let found = try locator.file(of: rom, ready: true) else { return .refused(.fileNotFound(rom.fileName)) }
            file = found
        } catch {
            return .refused(.couldntLook(rom.fileName, error.localizedDescription))
        }
        // xemu would only reach its dashboard. An image that's neither kind goes ahead, as xemu may know better.
        if emulator == .xemu, XboxDisc.kind(of: file) == .redump { return .refused(.needsXISO) }
        if emulator == .wine {
            let play: WinePlay
            do {
                play = try WinePlay(launchFile: file, romName: rom.folderName, wine: wine)
            } catch {
                return .refused(.badLaunchFile(error.localizedDescription))
            }
            if play.isRunning { return .refused(.stillRunning) }
            return .wine(play, warning: { if case .warn(let warning) = version { warning } else { nil } }())
        }
        var opened = file
        var startsOn: DiscStart?
        let discs = emulator == .duckStation ? Self.discs(ofPlaylist: file) : []
        // A state DuckStation boots on the disc it was saved with, falling back to the file it's given: its own Disc's. One
        // whose Disc can't be told opens the playlist, and nothing's remembered.
        let start =
            if let saveState { self.disc(savedIn: saveState).flatMap { n in discs.first { $0.number == n } } } else {
                startingDisc(among: discs, chosen: disc)
            }
        if let start {
            startsOn = DiscStart(rom: rom.id, disc: start.number)
            if start.number > 1 {
                guard FileManager.default.fileExists(atPath: start.file.path(percentEncoded: false)) else {
                    return .refused(.fileNotFound(start.file.lastPathComponent))
                }
                opened = start.file
            }
        }
        let warning: String? = if case .warn(let warning) = version { warning } else { nil }
        do {
            let arguments = try emulator.arguments(
                rom: opened, platformId: platformId, settings: settings, saveState: saveState,
                duckStation: duckStation, mesen: mesen, ares: ares, pcsx2: pcsx2, amiberry: amiberry, ymir: ymir)
            return .open(
                app: app, arguments: arguments, warning: warning, startsOn: startsOn,
                environment: emulator == .amiberry ? amiberry.environment : [:])
        } catch {
            return .refused(
                emulator == .amiberry
                    ? .couldntGetDisksReady(error.localizedDescription) : .couldntWriteSettings(emulator, error.localizedDescription))
        }
    }
}

/// One of the Discs a multi-disc ROM's Play can start on (ADR 0026): its number in the playlist, its Disc label and its
/// file.
public struct PlayDisc: Sendable, Equatable, Identifiable {
    public let number: Int
    public let label: String?
    public let file: URL
    /// Its Serial, once read, which its Save states are named by.
    public var serial: String?

    public var id: Int { number }

    /// "Disc 2 · Gran Turismo Mode", or "Disc 2" without a Disc label.
    public var numberAndLabel: String { label.map { "Disc \(number) · \($0)" } ?? "Disc \(number)" }

    /// "Gran Turismo Mode", or "Disc 2" without a Disc label: what Play says it starts on.
    public var labelOrNumber: String { label ?? "Disc \(number)" }
}

/// What a Play starts from (ADR 0034): its Resume state, when its Emulator keeps one; else the Disc a multi-disc ROM
/// starts on; else just its ROM. Play's button says it and does it, and so does a double-click on the Game's Cover.
public enum PlayStart: Sendable, Equatable, Identifiable {
    case resume(SaveState)
    case disc(PlayDisc)
    case rom

    public var id: String {
        switch self {
        case .resume: "resume"
        case .disc(let disc): "disc \(disc.number)"
        case .rom: "rom"
        }
    }

    /// What the Play button says: "Resume", "Play · Gran Turismo Mode", "Play".
    public var title: String {
        switch self {
        case .resume: "Resume"
        case .disc(let disc): "Play · \(disc.labelOrNumber)"
        case .rom: "Play"
        }
    }

    /// What its entry in the Play button's menu says: "Resume", "Play Disc 2 · Gran Turismo Mode", "Play".
    public var menuTitle: String {
        switch self {
        case .resume: "Resume"
        case .disc(let disc): "Play \(disc.numberAndLabel)"
        case .rom: "Play"
        }
    }

    /// The state it Plays from, as `Play.prepare` takes it.
    public var saveState: URL? {
        if case .resume(let state) = self { state.file } else { nil }
    }

    /// The Disc it chooses, as `Play.prepare` takes it.
    public var disc: Int? {
        if case .disc(let disc) = self { disc.number } else { nil }
    }
}
