import Foundation

/// The ares release Ludeum installs (ADR 0028): a versioned tag, pinned with its universal zip's SHA-256 as GitHub's
/// release API gives it. A bump is the version and digest here, and costs every Save state, as a state loads only in
/// the build that saved it.
public struct AresRelease: Sendable, Equatable {
    /// Its number, the tag without its "v": what `--version` prints, after a "v".
    public let version: String
    /// The zip's SHA-256, lowercase hex.
    public let sha256: String

    public static let pinned = AresRelease(version: "148", sha256: "1ae232ab6de341210f171f51d84b311527eb1399060706589334a8a7de136bb0")

    /// Where the zip is.
    public var url: URL {
        URL(string: "https://github.com/ares-emulator/ares/releases/download/v\(version)/ares-macos-universal.zip")!
    }
}

/// Why an Install stopped, with nothing replaced.
public enum AresInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't the zip.
    case notFound(version: String, status: Int)
    /// The zip isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The zip had no ares.app in it.
    case noApp
    /// `ditto` couldn't unpack the zip, with what it said.
    case couldntUnpack(String)
    /// The app in the zip says it's another version, or couldn't say.
    case wrongBuild(found: String?)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let version, let status): "Couldn't download ares v\(version): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no ares.app in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(let found):
            "The download says it's \(found.map { "v\($0)" } ?? "no version"), not v\(AresRelease.pinned.version)."
        }
    }
}

/// Installs the ares Ludeum keeps (ADR 0028): fetches the pinned release's zip, checks it against the digest, unpacks
/// it with no quarantine, checks its build, and swaps the app into `Emulators/ares/ares.app` in the Ludeum folder. It's
/// made portable by the `settings.bml` beside it: the one the copy it replaces kept, else the one ares keeps for itself
/// (`existing`), with my controls. Then the Standing settings are written. Its version is its app's, which needs no
/// launch: ares writes its settings whenever it starts, even for `--version`. Nothing is replaced until the new copy
/// checks out.
public struct AresInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: AresRelease
    let transport: any HTTPTransport
    /// The `settings.bml` an ares that isn't portable keeps for itself.
    let existing: URL

    /// `release`, `transport` and `existing` stand in for the pinned release, the real GitHub and ares's own settings,
    /// in tests.
    public init(
        ludeum: LudeumFolder = .standard, release: AresRelease = .pinned, transport: any HTTPTransport = URLSessionTransport(),
        existing: URL = URL.applicationSupportDirectory.appending(path: "ares/settings.bml")
    ) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
        self.existing = existing
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing ares", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: release.url.lastPathComponent)
        let response = try await transport.download(URLRequest(url: release.url), to: zip) { progress($0 * 0.8) }
        guard response.statusCode == 200 else { throw AresInstallError.notFound(version: release.version, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: zip)
        guard digest == release.sha256.lowercased() else {
            throw AresInstallError.badChecksum(expected: release.sha256, found: digest)
        }

        // The release zip holds `ares-v<version>/ares.app`.
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        do {
            try EmulatorInstall.unpack(zip, into: unpacked)
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw AresInstallError.couldntUnpack(failed.message)
        }
        progress(0.9)
        let folders = [unpacked] + ((try? files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [])
        guard
            let app = folders.map({ $0.appending(path: "ares.app", directoryHint: .isDirectory) })
                .first(where: { files.isExecutableFile(atPath: $0.appending(path: "Contents/MacOS/ares").path(percentEncoded: false)) })
        else { throw AresInstallError.noApp }
        EmulatorInstall.removeQuarantine(app)
        let found = EmulatorVersions.read(.ares, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == Int(release.version).map({ [$0] }) else {
            throw AresInstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back. What ares
        // keeps is beside the app, not in it, so it stays where it is.
        let installed = ludeum.aresApp
        let replaced = ludeum.aresFolder.appending(path: "ares (replaced).app", directoryHint: .isDirectory)
        try files.createDirectory(at: ludeum.aresFolder, withIntermediateDirectories: true)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: app, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        // The old copy's gone for good once the new one's in: its settings are beside it, so there's nothing to carry.
        if hadOne { try? files.removeItem(at: replaced) }
        let settings = AresSettings(ludeum: ludeum)
        if !settings.isPortable, files.fileExists(atPath: existing.path(percentEncoded: false)) {
            try files.copyItem(at: existing, to: settings.settingsFile)
        }
        try settings.writeStanding()
        progress(1)
    }
}
