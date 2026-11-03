import Foundation

/// The PCSX2 release Ludeum installs (ADR 0032): a versioned tag of `PCSX2/pcsx2` (every nightly is one, with a SHA-256
/// digest per asset in GitHub's release API, and nothing ages off) and its macOS tar's digest. A bump is both, in code.
public struct PCSX2Release: Sendable, Equatable {
    /// `2.9.152`, tagged `v2.9.152`.
    public let version: String
    /// The tar's SHA-256, lowercase hex, as GitHub's release API gives it.
    public let sha256: String

    public static let pinned = PCSX2Release(
        version: "2.9.152", sha256: "efd8e76bed5febf22c0f0bdf7938bcf358cd13651195390364949b3da117353f")

    /// Where the macOS tar is: `pcsx2-v<version>-macos-Qt.tar.xz`, holding `PCSX2-v<version>.app`.
    public var url: URL {
        URL(string: "https://github.com/PCSX2/pcsx2/releases/download/v\(version)/pcsx2-v\(version)-macos-Qt.tar.xz")!
    }
}

public enum PCSX2InstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// The tar wasn't at its URL.
    case notFound(version: String, status: Int)
    /// The download isn't the pinned tar.
    case badChecksum(expected: String, found: String)
    /// The tar held no PCSX2.app.
    case noApp
    case couldntUnpack(String)
    /// The app in the tar isn't the pinned version, or its version couldn't be read (nil).
    case wrongBuild(found: String?)

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let version, let status):
            "PCSX2 v\(version) isn't on GitHub (HTTP \(status))."
        case .badChecksum(let expected, let found):
            "The download isn't PCSX2's release: its SHA-256 is \(found), not \(expected)."
        case .noApp: "The download holds no PCSX2.app."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(.some(let found)):
            "The download is PCSX2 v\(found), not v\(PCSX2Release.pinned.version)."
        case .wrongBuild(nil):
            "Couldn't read the download's version: its PCSX2 -version printed nothing Ludeum understood within a minute."
        }
    }
}

/// Installs the pinned PCSX2 into the Ludeum folder (ADR 0032): fetches the release tar, checks its digest, unpacks it,
/// confirms its version with `-version`, swaps it into `Emulators/PCSX2/PCSX2.app`, makes it portable with a
/// `portable.txt` beside it, and writes the Standing settings. What PCSX2 keeps for itself is beside the app, not in it,
/// so a reinstall carries nothing across.
public struct PCSX2Installer: Sendable {
    let ludeum: LudeumFolder
    let release: PCSX2Release
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(ludeum: LudeumFolder = .standard, release: PCSX2Release = .pinned, transport: any HTTPTransport = URLSessionTransport()) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing PCSX2", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let tar = work.appending(path: release.url.lastPathComponent)
        let response = try await transport.download(URLRequest(url: release.url), to: tar) { progress($0 * 0.8) }
        guard response.statusCode == 200 else { throw PCSX2InstallError.notFound(version: release.version, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: tar)
        guard digest == release.sha256.lowercased() else {
            throw PCSX2InstallError.badChecksum(expected: release.sha256, found: digest)
        }

        // The tar holds `PCSX2-v<version>.app`.
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        try files.createDirectory(at: unpacked, withIntermediateDirectories: true)
        do {
            try EmulatorInstall.untar(tar, into: unpacked)
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw PCSX2InstallError.couldntUnpack(failed.message)
        }
        progress(0.9)
        let apps = ((try? files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
        guard
            let app = apps.first(where: {
                files.isExecutableFile(atPath: $0.appending(path: "Contents/MacOS/PCSX2").path(percentEncoded: false))
            })
        else { throw PCSX2InstallError.noApp }
        EmulatorInstall.removeQuarantine(app)
        let found = EmulatorVersions.read(.pcsx2, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == EmulatorVersions.parse(release.version, .dotted) else {
            throw PCSX2InstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back. What PCSX2
        // keeps is beside the app, not in it, so it stays where it is.
        let installed = ludeum.pcsx2App
        let replaced = ludeum.pcsx2Folder.appending(path: "PCSX2 (replaced).app", directoryHint: .isDirectory)
        try files.createDirectory(at: ludeum.pcsx2Folder, withIntermediateDirectories: true)
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
        let settings = PCSX2Settings(ludeum: ludeum)
        if !settings.isPortable { try Data().write(to: settings.portableMarker) }
        try settings.writeStanding()
        progress(1)
    }
}

extension EmulatorInstall {
    /// Unpacks a tar (`.tar.xz` included: `tar` tells the compression by itself) into `folder`, without quarantine.
    static func untar(_ tar: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = ["-xf", tar.path(percentEncoded: false), "-C", folder.path(percentEncoded: false)]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CouldntUnpack(message: String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
