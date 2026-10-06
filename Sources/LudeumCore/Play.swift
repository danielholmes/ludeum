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
        case archived
        case busy
        case tooOld(String)
        case notInstalled(Emulator)
        case fileNotFound(String)
        case couldntLook(String, String)
        case couldntWriteSettings(Emulator, String)

        public var message: String {
            switch self {
            case .noEmulator(let platform): "No \(platform) emulator yet"
            case .archived: "Archived: unarchive to play"
            case .busy: "Waiting for Archive or Unarchive to finish"
            case .tooOld(let message): message
            case .notInstalled(let emulator): "\(emulator.name) isn't installed."
            case .fileNotFound(let file): "Couldn't find \(file). Run an Import, then try again."
            case .couldntLook(let file, let why): "Couldn't look for \(file): \(why)"
            case .couldntWriteSettings(let emulator, let why): "Couldn't write \(emulator.name)'s settings: \(why)"
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

    /// Whether Play can be pressed, before it is.
    public var availability: Availability {
        guard let emulator = Emulator.of(platformId: platformId) else { return .refused(.noEmulator(platformName)) }
        let present = roms.filter { !$0.missing }
        if !present.isEmpty, present.allSatisfy(\.archived) { return .refused(.archived) }
        if roms.contains(where: { busyROMs.contains($0.id) }) { return .refused(.busy) }
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
    /// that way. `app` finds an installed app by its bundle identifier.
    public func prepare(locator: ROMLocator, version: VersionStatus, app: (String) -> URL?) -> Outcome {
        let emulator: Emulator
        switch availability {
        case .refused(let refusal): return .refused(refusal)
        case .ready(let ready): emulator = ready
        }
        if case .tooOld(let message) = version { return .refused(.tooOld(message)) }
        guard let app = app(emulator.bundleIdentifier) else { return .refused(.notInstalled(emulator)) }
        let present = roms.filter { !$0.missing && !$0.archived }
        // The playlist of a multi-disc Version, else the first present ROM.
        guard let rom = present.first(where: { $0.fileName.lowercased().hasSuffix(".m3u") }) ?? present.first else {
            return .refused(.archived)
        }
        let file: URL
        do {
            guard let found = try locator.file(of: rom, ready: true) else { return .refused(.fileNotFound(rom.fileName)) }
            file = found
        } catch {
            return .refused(.couldntLook(rom.fileName, error.localizedDescription))
        }
        do {
            let arguments = try emulator.arguments(rom: file, platformId: platformId, settings: settings)
            if case .warn(let warning) = version { return .open(app: app, arguments: arguments, warning: warning) }
            return .open(app: app, arguments: arguments, warning: nil)
        } catch {
            return .refused(.couldntWriteSettings(emulator, error.localizedDescription))
        }
    }
}
