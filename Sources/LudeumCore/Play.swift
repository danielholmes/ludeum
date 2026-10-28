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
        /// A PlayStation Game with settings of its own whose ROM's Serial (Disc 1's) isn't known, so its per-game file
        /// can't be named (ADR 0021).
        case noSerial(SerialMissing)
        /// DuckStation is open: Ludeum writes its settings before each Play, which an open DuckStation would write over
        /// (ADR 0024).
        case running(Emulator)
        /// DuckStation is being installed, so there's nothing to open yet.
        case installing(Emulator)

        public enum SerialMissing: Sendable, Equatable {
            /// Not read off its Discs yet: it will be at the next Import.
            case notReadYet
            /// Its Disc 1 has none DuckStation goes by.
            case noneOnDisc
            /// Kept in a form whose Serials aren't read yet: `chd`, `pbp`.
            case unreadForm(String)
        }

        public var message: String {
            switch self {
            case .noEmulator(let platform): "No \(platform) emulator yet"
            case .noROM: "No ROM in its ROM folder"
            case .archived: "Archived: unarchive to play"
            case .archivedNeedsCompacting: "Archived: compact to play"
            case .needsPlaylist: "Its Discs have no playlist: put an .m3u naming them in its folder, and it's seen at the next Import"
            case .busy: "Waiting for Archive, Unarchive or Compact to finish"
            case .tooOld(let message): message
            case .notInstalled(.duckStation): "DuckStation isn't installed. Install it from Ludeum ▸ Emulators…"
            case .notInstalled(let emulator): "\(emulator.name) isn't installed."
            case .fileNotFound(let file): "Couldn't find \(file). Run an Import, then try again."
            case .couldntLook(let file, let why): "Couldn't look for \(file): \(why)"
            case .couldntWriteSettings(let emulator, let why): "Couldn't write \(emulator.name)'s settings: \(why)"
            case .needsXISO: "It's a full Redump image, and xemu boots only an XISO: make one with `xdvdfs pack`, then put it in its place."
            case .noSerial(.notReadYet):
                "Its Serial hasn't been read yet, and its own DuckStation settings need it: it's read at the next Import. "
                    + "Set them back to Default to Play meanwhile."
            case .noSerial(.noneOnDisc):
                "Its Disc has no Serial DuckStation can use, so it can't have DuckStation settings of its own: set them back to Default to Play."
            case .noSerial(.unreadForm(let ext)):
                "Its Serial can't be read from a .\(ext) yet, so it can't have DuckStation settings of its own: set them back to Default to Play."
            case .running(let emulator):
                "\(emulator.name) is open. Quit it, then Play: Ludeum writes its settings before each Play, which an open \(emulator.name) would write over."
            case .installing(let emulator): "\(emulator.name) is being installed."
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
    var rom: LudeumROM? {
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
        if emulator == .duckStation, settings.hasDuckStationSettings, let rom, rom.serials.first == nil {
            return .refused(.noSerial(Self.serialMissing(rom)))
        }
        return .ready(emulator)
    }

    private static func serialMissing(_ rom: LudeumROM) -> Refusal.SerialMissing {
        let ext = (rom.fileName as NSString).pathExtension.lowercased()
        if Serials.unreadForms.contains(ext) { return .unreadForm(ext) }
        return rom.serials == .notRead ? .notReadYet : .noneOnDisc
    }
    /// The Emulator's installed version, as the version checks found it.
    public enum VersionStatus: Sendable, Equatable {
        case ok
        /// Play goes ahead, with this shown first.
        case warn(String)
        case tooOld(String)
    }

    public enum Outcome: Sendable, Equatable {
        /// Open `app` with `arguments`, showing `warning` first when there is one.
        case open(app: URL, arguments: [String], warning: String?)
        case refused(Refusal)

        public var refusal: Refusal? {
            if case .refused(let refusal) = self { refusal } else { nil }
        }

        public var arguments: [String]? {
            if case .open(_, let arguments, _) = self { arguments } else { nil }
        }

        public var warning: String? {
            if case .open(_, _, let warning) = self { warning } else { nil }
        }
    }

    /// What a press of Play does. It writes the settings files of an Emulator that takes them only
    /// that way. `app` finds an installed app by its bundle identifier; DuckStation is the one Ludeum installs
    /// (`duckStation.app`), refused while it's `running`. `saveState` starts DuckStation from that state.
    public func prepare(
        locator: ROMLocator, version: VersionStatus, app installed: (String) -> URL?, saveState: URL? = nil,
        duckStation: DuckStationSettings = .init(), running: (Emulator) -> Bool = { _ in false }
    ) -> Outcome {
        let emulator: Emulator
        switch availability {
        case .refused(.noSerial(.notReadYet)):
            // Its playlist's Discs may be in a form whose Serials aren't read yet, which only its files say.
            if let rom, let file = try? locator.file(of: rom, ready: true),
                let ext = ROMFiles.files(of: file).map({ $0.pathExtension.lowercased() }).first(where: Serials.unreadForms.contains)
            {
                return .refused(.noSerial(.unreadForm(ext)))
            }
            return .refused(.noSerial(.notReadYet))
        case .refused(let refusal): return .refused(refusal)
        case .ready(let ready): emulator = ready
        }
        if case .tooOld(let message) = version { return .refused(.tooOld(message)) }
        let app: URL
        if emulator == .duckStation {
            guard duckStation.isInstalled else { return .refused(.notInstalled(emulator)) }
            if running(emulator) { return .refused(.running(emulator)) }
            app = duckStation.app
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
        do {
            let arguments = try emulator.arguments(
                rom: file, platformId: platformId, settings: settings, serials: rom.serials, saveState: saveState, duckStation: duckStation)
            if case .warn(let warning) = version { return .open(app: app, arguments: arguments, warning: warning) }
            return .open(app: app, arguments: arguments, warning: nil)
        } catch {
            return .refused(.couldntWriteSettings(emulator, error.localizedDescription))
        }
    }
}
