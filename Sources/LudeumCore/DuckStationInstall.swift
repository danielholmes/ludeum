import CryptoKit
import Foundation

/// The DuckStation release Ludeum installs (ADR 0024): a versioned tag, pinned with its macOS zip's SHA-256 as GitHub's
/// release API gives it. Rolling tags (`latest`, `preview`) can't be pinned, as their zip is replaced on every build. A
/// bump is the tag, build and digest here. Once a tag has aged off the main repo's first thirty releases its zip is in
/// `duckstation/old-releases`.
public struct DuckStationRelease: Sendable, Equatable {
    /// The versioned tag, `v0.1-<build>`.
    public let tag: String
    /// The build its `-version` prints.
    public let build: Int
    /// The zip's SHA-256, lowercase hex.
    public let sha256: String

    /// For now the rolling `latest` as it stood on 2026-10-25, build 12442, since the last versioned release (12083)
    /// can't read the save states 12442 made: Install breaks once the tag rolls, and the versioned pin comes back
    /// with the next versioned release past 12442 (#90).
    public static let pinned = DuckStationRelease(
        tag: "latest", build: 12442, sha256: "b9f6f0e747ee2617988de33e1fafdd17d02e918d042fed691355aed9a86c11cd")

    static let asset = "duckstation-mac-release.zip"

    /// Where the zip is: the main repo, else old-releases.
    public var urls: [URL] {
        ["stenzek/duckstation", "duckstation/old-releases"].map {
            URL(string: "https://github.com/\($0)/releases/download/\(tag)/\(Self.asset)")!
        }
    }
}

/// Why an Install stopped, with nothing replaced.
public enum DuckStationInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// Neither repo had the zip.
    case notFound(tag: String, status: Int)
    /// The zip isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The zip had no DuckStation.app in it.
    case noApp
    /// The unpacked app isn't the build the release says.
    case wrongBuild(found: String?)
    /// `ditto` couldn't unpack the zip, with what it said.
    case couldntUnpack(String)
    /// The new copy is in place, but what the old one kept couldn't all be carried across: the old copy is beside it
    /// as `DuckStation (replaced).app`, to take it from by hand.
    case couldntCarryOver(String)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let tag, let status): "Couldn't download DuckStation \(tag): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no DuckStation.app in it."
        case .wrongBuild(let found):
            "The download is build \(found ?? "unknown"), not the \(DuckStationRelease.pinned.build) Ludeum expects."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .couldntCarryOver(let why):
            "DuckStation is installed, but its settings couldn't all be carried over from the copy it replaced, "
                + "kept beside it as DuckStation (replaced).app: \(why)"
        }
    }
}

/// Installs the DuckStation Ludeum keeps (ADR 0024): fetches the pinned release's zip, checks it against the digest,
/// unpacks it with no quarantine, checks its build, makes it portable, and swaps it into `Emulators/DuckStation.app` in
/// the Ludeum folder, then carries across whatever the copy it replaces kept in its data root (`settings.ini`, play
/// time, its caches) and writes the Standing settings. Nothing is replaced until the new copy checks out, and the old
/// copy is kept until what it had is across.
public struct DuckStationInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: DuckStationRelease
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(
        ludeum: LudeumFolder = .standard, release: DuckStationRelease = .pinned, transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: DuckStationRelease.asset)
        try await download(to: zip) { progress($0 * 0.8) }
        try Task.checkCancellation()
        let digest = try Self.sha256(of: zip)
        guard digest == release.sha256.lowercased() else {
            throw DuckStationInstallError.badChecksum(expected: release.sha256, found: digest)
        }

        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        try Self.unpack(zip, into: unpacked)
        progress(0.9)
        let app = unpacked.appending(path: "DuckStation.app", directoryHint: .isDirectory)
        guard files.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/DuckStation").path(percentEncoded: false)) else {
            throw DuckStationInstallError.noApp
        }
        Self.removeQuarantine(app)
        let found = EmulatorVersions.read(.duckStation, app: app)
        guard let build = found.flatMap({ EmulatorVersions.parse($0, .buildNumber) })?.first, build == release.build else {
            throw DuckStationInstallError.wrongBuild(found: EmulatorVersions.shown(found: found, for: .duckStation))
        }
        try Task.checkCancellation()
        try Data().write(to: app.appending(path: "Contents/MacOS/portable.txt"))

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back.
        let installed = ludeum.duckStationApp
        let replaced = ludeum.emulators.appending(path: "DuckStation (replaced).app", directoryHint: .isDirectory)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: app, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        if hadOne {
            // What DuckStation kept in its data root goes on: anything the new bundle hasn't got.
            do {
                let root = installed.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
                let oldRoot = replaced.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
                for name in try files.contentsOfDirectory(atPath: oldRoot.path(percentEncoded: false))
                where !files.fileExists(atPath: root.appending(path: name).path(percentEncoded: false)) {
                    try files.moveItem(at: oldRoot.appending(path: name), to: root.appending(path: name))
                }
            } catch {
                throw DuckStationInstallError.couldntCarryOver(error.localizedDescription)
            }
            try files.removeItem(at: replaced)
        }
        try DuckStationSettings(ludeum: ludeum).writeStanding()
        progress(1)
    }

    /// The zip from the first repo that has it.
    private func download(to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var status = 0
        for url in release.urls {
            let response = try await transport.download(URLRequest(url: url), to: file, progress: progress)
            if response.statusCode == 200 { return }
            status = response.statusCode
            try? FileManager.default.removeItem(at: file)
        }
        throw DuckStationInstallError.notFound(tag: release.tag, status: status)
    }

    /// Its SHA-256, lowercase hex, read a megabyte at a time.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks with `ditto`, which keeps a bundle whole and doesn't carry quarantine over.
    static func unpack(_ zip: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path(percentEncoded: false), folder.path(percentEncoded: false)]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DuckStationInstallError.couldntUnpack(
                String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Takes the quarantine flag off, should the download have been given one, so Gatekeeper doesn't block it or run
    /// it translocated. Best effort: without it the first launch asks, as DuckStation's own README says.
    static func removeQuarantine(_ app: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", app.path(percentEncoded: false)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
