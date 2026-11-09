import Foundation

/// The DOSBox Staging release Ludeum installs (ADR 0042): a versioned tag, pinned with its macOS disk image's SHA-256 as
/// GitHub's release API gives it, and the General MIDI SoundFont it plays with, pinned to a commit of its repository. A bump
/// is the version and digests here.
public struct DOSBoxStagingRelease: Sendable, Equatable {
    /// Its number, the tag without its "v": what its app says it is, before its build.
    public let version: String
    /// The disk image's SHA-256, lowercase hex.
    public let sha256: String
    /// The commit of GeneralUser GS's repository the SoundFont is taken from.
    public let soundFontCommit: String
    /// The SoundFont's SHA-256, lowercase hex.
    public let soundFontSHA256: String

    /// GeneralUser GS v2.0.3, which its licence lets any software use.
    public static let pinned = DOSBoxStagingRelease(
        version: "0.83.0", sha256: "d8a771adfb8010fa6b5f7fb5351abfba659273ad01c89f03675a92bdbdae8167",
        soundFontCommit: "97049183643d5fc5a9322a69c5b09efb667c6c3a",
        soundFontSHA256: "9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe")

    /// The SoundFont's file name.
    public static let soundFontName = "GeneralUser-GS.sf2"

    /// Where the disk image is.
    public var url: URL {
        URL(string: "https://github.com/dosbox-staging/dosbox-staging/releases/download/v\(version)/dosbox-staging-macOS-v\(version).dmg")!
    }

    /// Where the SoundFont is.
    public var soundFontURL: URL {
        URL(string: "https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/\(soundFontCommit)/\(Self.soundFontName)")!
    }
}

/// Why an Install stopped, with nothing replaced.
public enum DOSBoxStagingInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't the download.
    case notFound(String, status: Int)
    /// A download isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The disk image had no DOSBox Staging.app in it.
    case noApp
    /// `hdiutil` or `ditto` couldn't open the disk image or copy out of it, with what it said.
    case couldntUnpack(String)
    /// The app in the disk image says it's another version, or couldn't say.
    case wrongBuild(found: String?)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let what, let status): "Couldn't download \(what): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no DOSBox Staging.app in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(let found):
            "The download says it's \(found.map { "v\($0)" } ?? "no version"), not v\(DOSBoxStagingRelease.pinned.version)."
        }
    }
}

/// Installs the DOSBox Staging Ludeum keeps (ADR 0042): fetches the pinned release's disk image and SoundFont, checks each
/// against its digest, mounts the image where nothing shows it, copies the app out with no quarantine, checks its build, and
/// swaps both into `Emulators/` in the Ludeum folder. Its version is its app's, which needs no launch. Nothing is replaced
/// until both check out.
public struct DOSBoxStagingInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: DOSBoxStagingRelease
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(
        ludeum: LudeumFolder = .standard, release: DOSBoxStagingRelease = .pinned, transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the downloads are unpacked and checked before they're swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing DOSBox Staging", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let image = work.appending(path: release.url.lastPathComponent)
        try await download(release.url, to: image, sha256: release.sha256, what: "DOSBox Staging v\(release.version)") {
            progress($0 * 0.6)
        }
        let soundFont = work.appending(path: DOSBoxStagingRelease.soundFontName)
        try await download(release.soundFontURL, to: soundFont, sha256: release.soundFontSHA256, what: "its SoundFont") {
            progress(0.6 + $0 * 0.3)
        }

        let app = work.appending(path: "DOSBox Staging.app", directoryHint: .isDirectory)
        try copyApp(outOf: image, to: app)
        progress(0.95)
        guard files.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/dosbox").path(percentEncoded: false)) else {
            throw DOSBoxStagingInstallError.noApp
        }
        EmulatorInstall.removeQuarantine(app)
        let found = EmulatorVersions.read(.dosBoxStaging, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == EmulatorVersions.parse(release.version, .dotted) else {
            throw DOSBoxStagingInstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }
        try Task.checkCancellation()

        // The swap: the old copies aside, the new ones in; should either not go in, the old ones go back. What DOSBox
        // Staging keeps is in the Data folder, so it stays where it is.
        let swaps = [
            (app, ludeum.dosBoxStagingApp),
            (soundFont, ludeum.dosBoxStagingSoundFont),
        ]
        var done: [(installed: URL, replaced: URL?)] = []
        do {
            for (new, installed) in swaps {
                let replaced = work.appending(path: "replaced \(installed.lastPathComponent)")
                let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
                try files.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
                if hadOne { try files.moveItem(at: installed, to: replaced) }
                done.append((installed, hadOne ? replaced : nil))
                try files.moveItem(at: new, to: installed)
            }
        } catch {
            for (installed, replaced) in done.reversed() {
                guard let replaced else { continue }
                try? files.removeItem(at: installed)
                try? files.moveItem(at: replaced, to: installed)
            }
            throw error
        }
        progress(1)
    }

    /// Downloads `url` and checks it against `sha256`.
    private func download(
        _ url: URL, to file: URL, sha256: String, what: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let response = try await transport.download(URLRequest(url: url), to: file, progress: progress)
        guard response.statusCode == 200 else { throw DOSBoxStagingInstallError.notFound(what, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: file)
        guard digest == sha256.lowercased() else { throw DOSBoxStagingInstallError.badChecksum(expected: sha256, found: digest) }
    }

    /// Mounts the disk image read-only, unseen in the Finder, and copies its DOSBox Staging.app out, detaching it either way.
    private func copyApp(outOf image: URL, to app: URL) throws {
        let mountPoint = work.appending(path: "mounted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try run(
            "/usr/bin/hdiutil",
            [
                "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path(percentEncoded: false),
                image.path(percentEncoded: false),
            ])
        defer {
            do {
                try run("/usr/bin/hdiutil", ["detach", mountPoint.path(percentEncoded: false)])
            } catch {
                try? run("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path(percentEncoded: false)])
            }
        }
        let inside = mountPoint.appending(path: "DOSBox Staging.app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: inside.path(percentEncoded: false)) else { throw DOSBoxStagingInstallError.noApp }
        try run("/usr/bin/ditto", [inside.path(percentEncoded: false), app.path(percentEncoded: false)])
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DOSBoxStagingInstallError.couldntUnpack(
                String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
