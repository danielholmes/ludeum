import Foundation

/// The Amiberry release Ludeum installs (ADR 0035): a versioned tag, pinned with its macOS disk image's SHA-256 as
/// GitHub's release API gives it. A bump is the version and digest here.
public struct AmiberryRelease: Sendable, Equatable {
    /// Its number, the tag without its "v": what its app says it is.
    public let version: String
    /// The disk image's SHA-256, lowercase hex.
    public let sha256: String

    public static let pinned = AmiberryRelease(
        version: "8.5.0", sha256: "002bb71af68a86a23c2779258248af71683c6a56caf74cf716e40081b5df9e7a")

    /// Where the disk image is.
    public var url: URL {
        URL(string: "https://github.com/BlitterStudio/amiberry/releases/download/v\(version)/Amiberry-\(version)-macOS-universal.dmg")!
    }
}

/// Why an Install stopped, with nothing replaced.
public enum AmiberryInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't the disk image.
    case notFound(version: String, status: Int)
    /// The disk image isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The disk image had no Amiberry.app in it.
    case noApp
    /// `hdiutil` or `ditto` couldn't open the disk image or copy out of it, with what it said.
    case couldntUnpack(String)
    /// The app in the disk image says it's another version, or couldn't say.
    case wrongBuild(found: String?)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let version, let status): "Couldn't download Amiberry v\(version): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no Amiberry.app in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(let found):
            "The download says it's \(found.map { "v\($0)" } ?? "no version"), not v\(AmiberryRelease.pinned.version)."
        }
    }
}

/// Installs the Amiberry Ludeum keeps (ADR 0035): fetches the pinned release's disk image, checks it against the digest,
/// mounts it where nothing shows it, copies the app out with no quarantine, checks its build, and swaps it into
/// `Emulators/Amiberry.app` in the Ludeum folder. Its version is its app's, which needs no launch. Nothing is replaced
/// until the new copy checks out.
public struct AmiberryInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: AmiberryRelease
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(ludeum: LudeumFolder = .standard, release: AmiberryRelease = .pinned, transport: any HTTPTransport = URLSessionTransport())
    {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing Amiberry", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let image = work.appending(path: release.url.lastPathComponent)
        let response = try await transport.download(URLRequest(url: release.url), to: image) { progress($0 * 0.8) }
        guard response.statusCode == 200 else { throw AmiberryInstallError.notFound(version: release.version, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: image)
        guard digest == release.sha256.lowercased() else {
            throw AmiberryInstallError.badChecksum(expected: release.sha256, found: digest)
        }

        let app = work.appending(path: "Amiberry.app", directoryHint: .isDirectory)
        try copyApp(outOf: image, to: app)
        progress(0.9)
        guard files.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/Amiberry").path(percentEncoded: false)) else {
            throw AmiberryInstallError.noApp
        }
        EmulatorInstall.removeQuarantine(app)
        let found = EmulatorVersions.read(.amiberry, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == EmulatorVersions.parse(release.version, .dotted) else {
            throw AmiberryInstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back. What Amiberry
        // keeps is in the Data folder, so it stays where it is.
        let installed = ludeum.amiberryApp
        let replaced = ludeum.emulators.appending(path: "Amiberry (replaced).app", directoryHint: .isDirectory)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: app, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        if hadOne { try? files.removeItem(at: replaced) }
        progress(1)
    }

    /// Mounts the disk image read-only, unseen in the Finder, and copies its Amiberry.app out, detaching it either way.
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
        let inside = mountPoint.appending(path: "Amiberry.app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: inside.path(percentEncoded: false)) else { throw AmiberryInstallError.noApp }
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
            throw AmiberryInstallError.couldntUnpack(
                String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
