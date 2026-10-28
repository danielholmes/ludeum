import Foundation

/// The MesenCE release Ludeum installs (ADR 0027): a versioned tag, pinned with its Apple Silicon zip's SHA-256 as
/// GitHub's release API gives it. A bump is the version and digest here. Every build says it's 2.2.1 and has no version
/// flag, so Install records the digest it installed, and that's what's checked.
public struct MesenRelease: Sendable, Equatable {
    /// The tag, which is its version.
    public let version: String
    /// The zip's SHA-256, lowercase hex.
    public let sha256: String
    /// A library the build loads from where Homebrew puts it, which Ludeum doesn't supply: SDL2, for 2.2.1. Nil when it
    /// needs none, as builds since do.
    public let needs: HomebrewLibrary?

    public static let pinned = MesenRelease(
        version: "2.2.1", sha256: "9c230cc25ad0bae79fed810c9eeb21c1c507b96b1ce795bbd22ca4331ffb6e48", needs: .sdl2)

    /// Where the zip is.
    public var url: URL {
        URL(string: "https://github.com/nesdev-org/MesenCE/releases/download/\(version)/Mesen_\(version)_macOS_ARM64_AppleSilicon.zip")!
    }

    /// What Install recorded in the app it installed: the release's version and digest.
    public struct Installed: Sendable, Equatable {
        public let version: String
        public let sha256: String

        /// Where it's recorded: in the app's `Contents`, outside MesenCE's data root.
        static func file(in app: URL) -> URL { app.appending(path: "Contents/Installed by Ludeum.txt") }

        init(version: String, sha256: String) {
            self.version = version
            self.sha256 = sha256
        }

        /// What's recorded in `app`, or nil when there's no record: a copy Ludeum didn't install.
        init?(app: URL) {
            guard let text = try? String(contentsOf: Self.file(in: app), encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.count >= 2 else { return nil }
            self.init(version: lines[0], sha256: lines[1])
        }

        func write(in app: URL) throws {
            try "\(version)\n\(sha256)\n".write(to: Self.file(in: app), atomically: true, encoding: .utf8)
        }
    }
}

/// A library an Emulator's build loads from where Homebrew installs it.
public struct HomebrewLibrary: Sendable, Equatable {
    public let name: String
    /// Where the build looks for it.
    public let path: String
    /// The command that installs it.
    public let install: String

    public static let sdl2 = HomebrewLibrary(
        name: "SDL2", path: "/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib", install: "brew install sdl2")

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: path) }
}

/// Why an Install stopped, with nothing replaced.
public enum MesenInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// A library the build needs isn't installed.
    case needs(HomebrewLibrary)
    /// GitHub hadn't the zip.
    case notFound(version: String, status: Int)
    /// The zip isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The zip had no Mesen.app in it.
    case noApp
    /// `ditto` couldn't unpack the zip, with what it said.
    case couldntUnpack(String)
    /// The new copy is in place, but what the old one kept couldn't all be carried across: the old copy is beside it
    /// as `MesenCE (replaced).app`, to take it from by hand.
    case couldntCarryOver(String)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .needs(let library): "MesenCE \(MesenRelease.pinned.version) needs \(library.name): install it with `\(library.install)`."
        case .notFound(let version, let status): "Couldn't download MesenCE \(version): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no Mesen.app in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .couldntCarryOver(let why):
            "MesenCE is installed, but what it kept couldn't all be carried over from the copy it replaced, "
                + "kept beside it as MesenCE (replaced).app: \(why)"
        }
    }
}

/// Installs the MesenCE Ludeum keeps (ADR 0027): fetches the pinned release's zip, checks it against the digest, unpacks
/// it and the zip inside it with no quarantine, and swaps the app into `Emulators/MesenCE.app` in the Ludeum folder,
/// recording the release it is. It's made portable by its `settings.json`: the one the copy it replaces kept, carried
/// across with the rest of that copy's data root (Firmware, cheats) but the native code MesenCE unpacks there on every
/// launch; else the one MesenCE keeps for itself (`existing`), with my controls; else MesenCE's first run's. Then the
/// Standing settings are written. Nothing is replaced until the new copy checks out, and the old copy is kept until
/// what it had is across. Refused while a library the release needs isn't installed.
public struct MesenInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: MesenRelease
    let transport: any HTTPTransport
    /// The `settings.json` a MesenCE that isn't portable keeps for itself.
    let existing: URL

    /// `release`, `transport` and `existing` stand in for the pinned release, the real GitHub and MesenCE's own settings,
    /// in tests.
    public init(
        ludeum: LudeumFolder = .standard, release: MesenRelease = .pinned, transport: any HTTPTransport = URLSessionTransport(),
        existing: URL = URL.applicationSupportDirectory.appending(path: "MesenCE/settings.json")
    ) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
        self.existing = existing
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing MesenCE", directoryHint: .isDirectory) }

    /// What MesenCE unpacks into its data root on every launch, from inside its executable: not carried across, as the
    /// new build brings its own.
    static let unpackedOnLaunch: Set<String> = ["MesenCore.dylib", "libSkiaSharp.dylib", "libHarfBuzzSharp.dylib", "MesenNesDB.txt"]

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        if let library = release.needs, !library.isInstalled { throw MesenInstallError.needs(library) }
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: release.url.lastPathComponent)
        let response = try await transport.download(URLRequest(url: release.url), to: zip) { progress($0 * 0.8) }
        guard response.statusCode == 200 else { throw MesenInstallError.notFound(version: release.version, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: zip)
        guard digest == release.sha256.lowercased() else {
            throw MesenInstallError.badChecksum(expected: release.sha256, found: digest)
        }

        // The release zip holds `Mesen.app.zip`, which holds the app.
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        let inner = work.appending(path: "inner", directoryHint: .isDirectory)
        do {
            try EmulatorInstall.unpack(zip, into: unpacked)
            let appZip = unpacked.appending(path: "Mesen.app.zip")
            if files.fileExists(atPath: appZip.path(percentEncoded: false)) {
                try EmulatorInstall.unpack(appZip, into: inner)
            }
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw MesenInstallError.couldntUnpack(failed.message)
        }
        progress(0.9)
        guard
            let app = [inner, unpacked].map({ $0.appending(path: "Mesen.app", directoryHint: .isDirectory) })
                .first(where: { files.isExecutableFile(atPath: $0.appending(path: "Contents/MacOS/Mesen").path(percentEncoded: false)) })
        else { throw MesenInstallError.noApp }
        EmulatorInstall.removeQuarantine(app)
        try MesenRelease.Installed(version: release.version, sha256: digest).write(in: app)
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back.
        let installed = ludeum.mesenApp
        let replaced = ludeum.emulators.appending(path: "MesenCE (replaced).app", directoryHint: .isDirectory)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: app, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        let root = installed.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        if hadOne {
            // What MesenCE kept in its data root goes on: anything the new bundle hasn't got, but the native code.
            do {
                let oldRoot = replaced.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
                for name in try files.contentsOfDirectory(atPath: oldRoot.path(percentEncoded: false))
                where !Self.unpackedOnLaunch.contains(name)
                    && !files.fileExists(atPath: root.appending(path: name).path(percentEncoded: false))
                {
                    try files.moveItem(at: oldRoot.appending(path: name), to: root.appending(path: name))
                }
            } catch {
                throw MesenInstallError.couldntCarryOver(error.localizedDescription)
            }
            try files.removeItem(at: replaced)
        }
        let settings = MesenSettings(ludeum: ludeum)
        if !settings.isPortable, files.fileExists(atPath: existing.path(percentEncoded: false)) {
            try files.copyItem(at: existing, to: settings.settingsFile)
        }
        try settings.writeStanding()
        progress(1)
    }
}
