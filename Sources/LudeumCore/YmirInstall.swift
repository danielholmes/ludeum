import Foundation

/// The Ymir release Ludeum installs (ADR 0036): a versioned tag of `ymir-emu/Ymir`, pinned with its Apple Silicon zip's
/// SHA-256 as GitHub's release API gives it. A bump is the version and digest here, and keeps every Save state, as Ymir
/// loads a state of any older version. Nightlies can't be pinned: each replaces the last on one moving tag.
public struct YmirRelease: Sendable, Equatable {
    /// Its number, the tag without its "v": what its app says it is.
    public let version: String
    /// The zip's SHA-256, lowercase hex.
    public let sha256: String

    public static let pinned = YmirRelease(version: "0.4.1", sha256: "070a234b7460608ae22f08ab5914c8edac3a5efaf364590d2dde18ff460627a7")

    /// Where the zip is.
    public var url: URL {
        URL(string: "https://github.com/ymir-emu/Ymir/releases/download/v\(version)/ymir-macos-arm64-v\(version).zip")!
    }
}

/// Why an Install stopped, with nothing replaced.
public enum YmirInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't the zip.
    case notFound(version: String, status: Int)
    /// The zip isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The zip had no Ymir app in it.
    case noApp
    /// `ditto` couldn't unpack the zip, with what it said.
    case couldntUnpack(String)
    /// The app in the zip says it's another version, or couldn't say.
    case wrongBuild(found: String?)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let version, let status): "Couldn't download Ymir v\(version): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no Ymir app in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(let found):
            "The download says it's \(found.map { "v\($0)" } ?? "no version"), not v\(YmirRelease.pinned.version)."
        }
    }
}

/// Installs the Ymir Ludeum keeps (ADR 0036): fetches the pinned release's zip, checks it against the digest, unpacks it
/// with no quarantine, as the release is ad-hoc signed and not notarised, checks its build by its app's version, swaps the
/// app into `Emulators/Ymir/Ymir.app` and puts the zip's controller database beside it, the root of its profile, where Ymir
/// reads it. Then the Standing settings are written. What Ymir keeps for itself is beside the app, not in it, so a
/// reinstall carries nothing across. Nothing is replaced until the new copy checks out.
public struct YmirInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: YmirRelease
    let transport: any HTTPTransport

    /// The file of SDL's controller mappings beside the app in the zip.
    static let controllerDatabase = "gamecontrollerdb.txt"

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(ludeum: LudeumFolder = .standard, release: YmirRelease = .pinned, transport: any HTTPTransport = URLSessionTransport()) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing Ymir", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: release.url.lastPathComponent)
        let response = try await transport.download(URLRequest(url: release.url), to: zip) { progress($0 * 0.8) }
        guard response.statusCode == 200 else { throw YmirInstallError.notFound(version: release.version, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: zip)
        guard digest == release.sha256.lowercased() else {
            throw YmirInstallError.badChecksum(expected: release.sha256, found: digest)
        }

        // The zip holds `ymir-sdl3.app` with its controller database, its documents and its licences beside it.
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        do {
            try EmulatorInstall.unpack(zip, into: unpacked)
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw YmirInstallError.couldntUnpack(failed.message)
        }
        progress(0.9)
        let app = unpacked.appending(path: "ymir-sdl3.app", directoryHint: .isDirectory)
        guard files.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/ymir-sdl3").path(percentEncoded: false)) else {
            throw YmirInstallError.noApp
        }
        EmulatorInstall.removeQuarantine(app)
        let found = EmulatorVersions.read(.ymir, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == EmulatorVersions.parse(release.version, .dotted) else {
            throw YmirInstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back. What Ymir keeps
        // is beside the app, not in it, so it stays where it is.
        let installed = ludeum.ymirApp
        let replaced = ludeum.ymirFolder.appending(path: "Ymir (replaced).app", directoryHint: .isDirectory)
        try files.createDirectory(at: ludeum.ymirFolder, withIntermediateDirectories: true)
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
        let database = unpacked.appending(path: Self.controllerDatabase)
        if files.fileExists(atPath: database.path(percentEncoded: false)) {
            let beside = ludeum.ymirFolder.appending(path: Self.controllerDatabase)
            try? files.removeItem(at: beside)
            try files.moveItem(at: database, to: beside)
        }
        try YmirSettings(ludeum: ludeum).writeStanding()
        progress(1)
    }
}
