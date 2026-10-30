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
        /// DuckStation, MesenCE or ares is open: Ludeum writes its settings before each Play, which an open DuckStation
        /// or ares would write over (ADRs 0024, 0028) and an open MesenCE wouldn't read (ADR 0027).
        case running(Emulator)
        /// DuckStation, MesenCE or ares is being installed, so there's nothing to open yet.
        case installing(Emulator)
        /// The installed Emulator's build needs a library from Homebrew that isn't installed (MesenCE 2.2.1's SDL2).
        case needs(Emulator, HomebrewLibrary)

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
            case .running(let emulator):
                "\(emulator.name) is open. Quit it, then Play: Ludeum writes its settings before each Play, which an open \(emulator.name) would write over."
            case .installing(let emulator): "\(emulator.name) is being installed."
            case .needs(let emulator, let library):
                "\(emulator.name) needs \(library.name), which isn't installed: install it with `\(library.install)`, then Play."
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
        /// starts on, for the journal to remember.
        case open(app: URL, arguments: [String], warning: String?, startsOn: DiscStart? = nil)
        case refused(Refusal)

        public var refusal: Refusal? {
            if case .refused(let refusal) = self { refusal } else { nil }
        }

        public var arguments: [String]? {
            if case .open(_, let arguments, _, _) = self { arguments } else { nil }
        }

        public var warning: String? {
            if case .open(_, _, let warning, _) = self { warning } else { nil }
        }

        public var startsOn: DiscStart? {
            if case .open(_, _, _, let startsOn) = self { startsOn } else { nil }
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

    /// The Disc a Save state was saved on, by its Serial.
    private func disc(savedIn saveState: URL) -> Int? {
        guard let rom, case .read(let serials) = rom.serials,
            let serial = SaveState.parse(saveState.lastPathComponent, serials: rom.serials.known)?.serial,
            let index = serials.firstIndex(of: serial)
        else { return nil }
        return index + 1
    }

    /// What a press of Play does. It writes the settings files of an Emulator that takes them only
    /// that way. `app` finds an installed app by its bundle identifier; DuckStation, MesenCE and ares are the ones Ludeum
    /// installs (`duckStation.app`, `mesen.app`, `ares.app`), refused while any copy is `running`. `saveState` starts the
    /// Play from that state, DuckStation's on its own Disc; else a multi-disc ROM starts on `disc`, or the one it last
    /// started on.
    public func prepare(
        locator: ROMLocator, version: VersionStatus, app installed: (String) -> URL?, saveState: URL? = nil, disc: Int? = nil,
        duckStation: DuckStationSettings = .init(), mesen: MesenSettings = .init(), ares: AresSettings = .init(),
        running: (Emulator) -> Bool = { _ in false }
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
            app = ares.app
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
                duckStation: duckStation, mesen: mesen, ares: ares)
            return .open(app: app, arguments: arguments, warning: warning, startsOn: startsOn)
        } catch {
            return .refused(.couldntWriteSettings(emulator, error.localizedDescription))
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
