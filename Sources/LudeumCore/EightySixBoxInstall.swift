import Foundation

/// The 86Box release Ludeum installs (ADR 0041), with the ROM set of the same version, as it can't start without one. Each is
/// pinned with its download's SHA-256. A bump is the version, build and digests here.
public struct EightySixBoxRelease: Sendable, Equatable {
    /// Its number: what its app says it is.
    public let version: String
    /// Its build, which names the zip.
    public let build: Int
    /// The app zip's SHA-256, lowercase hex.
    public let sha256: String
    /// The ROM set's tarball's SHA-256, lowercase hex.
    public let romSetSHA256: String

    public static let pinned = EightySixBoxRelease(
        version: "6.0", build: 9001,
        sha256: "fc66fc97225012af20145ae04193911bbf689fc75f89590774a904483140a5a9",
        romSetSHA256: "38fccaf4a7b48e581ccdfee2dc3cc0545e7d3a778bc25611e902a117eec571e6")

    /// Where the app's zip is.
    public var url: URL {
        URL(string: "https://github.com/86Box/86Box/releases/download/v\(version)/86Box-macOS-x86_64%2Barm64-b\(build).zip")!
    }

    /// Where the ROM set's tarball is.
    public var romSetURL: URL { URL(string: "https://github.com/86Box/roms/archive/refs/tags/v\(version).tar.gz")! }
}

/// Why an Install stopped, with nothing replaced.
public enum EightySixBoxInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't a download.
    case notFound(what: String, status: Int)
    /// A download isn't the one the release's digest names.
    case badChecksum(what: String, expected: String, found: String)
    /// The zip had no 86Box.app in it.
    case noApp
    /// The ROM set hadn't the machine's BIOS in it.
    case noMachine
    /// `ditto` or `tar` couldn't unpack a download, with what it said.
    case couldntUnpack(String)
    /// The app in the zip says it's another version, or couldn't say.
    case wrongBuild(found: String?)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let what, let status): "Couldn't download \(what): GitHub answered \(status)."
        case .badChecksum(let what, let expected, let found):
            "\(what) isn't the download Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no 86Box.app in it."
        case .noMachine: "86Box's ROM set hasn't the BIOS of the machine Ludeum uses."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(let found):
            "The download says it's \(found.map { "v\($0)" } ?? "no version"), not v\(EightySixBoxRelease.pinned.version)."
        }
    }
}

/// Installs the 86Box Ludeum keeps (ADR 0041): fetches the pinned app and ROM set, checks them against their digests, unpacks
/// them with no quarantine, checks the app's version and that the machine's BIOS is there, and swaps them into `Emulators/` in
/// the Ludeum folder. Nothing is replaced until both check out, and the base and game disks are in the Data folder.
public struct EightySixBoxInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: EightySixBoxRelease
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(
        ludeum: LudeumFolder = .standard, release: EightySixBoxRelease = .pinned, transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the downloads are unpacked and checked before they're swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing 86Box", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: "86Box.zip")
        try await fetch(release.url, to: zip, what: "86Box v\(release.version)", digest: release.sha256) { progress($0 * 0.5) }
        let tarball = work.appending(path: "roms.tar.gz")
        try await fetch(release.romSetURL, to: tarball, what: "86Box's ROM set", digest: release.romSetSHA256) { progress(0.5 + $0 * 0.4) }

        let unpacked = work.appending(path: "app", directoryHint: .isDirectory)
        try files.createDirectory(at: unpacked, withIntermediateDirectories: true)
        do {
            try EmulatorInstall.unpack(zip, into: unpacked)
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw EightySixBoxInstallError.couldntUnpack(failed.message)
        }
        let app = unpacked.appending(path: "86Box.app", directoryHint: .isDirectory)
        guard files.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/86Box").path(percentEncoded: false)) else {
            throw EightySixBoxInstallError.noApp
        }
        EmulatorInstall.removeQuarantine(app)
        let found = EmulatorVersions.read(.eightySixBox, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == EmulatorVersions.parse(release.version, .dotted) else {
            throw EightySixBoxInstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }

        let romSet = work.appending(path: "roms", directoryHint: .isDirectory)
        try files.createDirectory(at: romSet, withIntermediateDirectories: true)
        try unpackTarball(tarball, into: romSet)
        guard files.fileExists(atPath: romSet.appending(path: "machines/\(WindowsBase.board)").path(percentEncoded: false)) else {
            throw EightySixBoxInstallError.noMachine
        }
        progress(0.95)
        try Task.checkCancellation()

        try swap(romSet, into: ludeum.eightySixBoxROMSet, replacedName: "86Box ROMs (replaced)")
        try swap(app, into: ludeum.eightySixBoxApp, replacedName: "86Box (replaced).app")
        progress(1)
    }

    private func fetch(
        _ url: URL, to file: URL, what: String, digest: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let response = try await transport.download(URLRequest(url: url), to: file, progress: progress)
        guard response.statusCode == 200 else { throw EightySixBoxInstallError.notFound(what: what, status: response.statusCode) }
        try Task.checkCancellation()
        let found = try EmulatorInstall.sha256(of: file)
        guard found == digest.lowercased() else { throw EightySixBoxInstallError.badChecksum(what: what, expected: digest, found: found) }
    }

    /// The old copy aside, the new one in; should the new one not go in, the old one goes back.
    private func swap(_ new: URL, into installed: URL, replacedName: String) throws {
        let files = FileManager.default
        let replaced = ludeum.emulators.appending(path: replacedName, directoryHint: .isDirectory)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: new, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        if hadOne { try? files.removeItem(at: replaced) }
    }

    /// Unpacks a GitHub tarball, dropping the one folder it's all in.
    private func unpackTarball(_ tarball: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarball.path(percentEncoded: false), "--strip-components=1", "-C", folder.path(percentEncoded: false)]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EightySixBoxInstallError.couldntUnpack(
                String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
