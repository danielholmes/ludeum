import Foundation

/// The Wine build Ludeum installs (ADR 0040): Sikarugir's engine, which both of the first games Play on, and the
/// libraries it doesn't carry, from Sikarugir's Template. Each is an asset of a GitHub release, pinned with its SHA-256
/// as GitHub's release API gives it. One pin serves every Windows ROM, so a bump means trying each of them again.
public struct WineRelease: Sendable, Equatable {
    /// The engine's name, its tar's without the extension.
    public let engine: String
    /// The engine's tar's SHA-256, lowercase hex.
    public let engineSHA256: String
    /// The Template's name, its tar's without the extension.
    public let template: String
    /// The Template's tar's SHA-256, lowercase hex.
    public let templateSHA256: String

    public static let pinned = WineRelease(
        engine: "WS12WineSikarugir10.0_6", engineSHA256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2",
        template: "Template-1.0.11", templateSHA256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a")

    /// Wine's version and Sikarugir's revision of it, as dotted numbers: `10.0.6` for the engine `…10.0_6`.
    public var version: String {
        guard let match = engine.firstMatch(of: /(\d+(?:\.\d+)*)_(\d+)$/) else { return engine }
        return "\(match.output.1).\(match.output.2)"
    }

    /// Where the engine's tar is: one of the assets of the Engines repository's one release.
    public var engineURL: URL { URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/\(engine).tar.xz")! }

    /// Where the Template's tar is.
    public var templateURL: URL { URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/\(template).tar.xz")! }

    /// Both digests, which say which build an installed copy is: the engine's has no version of its own to tell a
    /// revision by without running it.
    var digests: String { "\(engineSHA256.lowercased()) \(templateSHA256.lowercased())" }

    /// What Install recorded in the copy it installed: the release's version and digests. A prefix remembers it too, to
    /// be made again by another.
    public struct Installed: Sendable, Equatable {
        public let version: String
        public let digests: String

        /// Where it's recorded: at the top of the engine's folder.
        static func file(in folder: URL) -> URL { folder.appending(path: "Installed by Ludeum.txt", directoryHint: .notDirectory) }

        init(_ release: WineRelease) {
            version = release.version
            digests = release.digests
        }

        /// What's recorded in `folder`, or nil when there's no record: a copy Ludeum didn't install.
        init?(folder: URL) {
            guard let text = try? String(contentsOf: Self.file(in: folder), encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.count >= 2 else { return nil }
            version = lines[0]
            digests = lines[1]
        }

        /// The record's text: the version, then the digests, a line each.
        var text: String { "\(version)\n\(digests)\n" }

        func write(in folder: URL) throws {
            try text.write(to: Self.file(in: folder), atomically: true, encoding: .utf8)
        }
    }
}

/// Why an Install stopped, with nothing replaced.
public enum WineInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't one of the two downloads.
    case notFound(String, status: Int)
    /// A download isn't the one the release's digest names.
    case badChecksum(String, expected: String, found: String)
    /// The engine's tar held no `bin/wine` and `bin/wineserver`.
    case noEngine
    /// The Template's tar held none of the libraries the engine needs.
    case noLibraries
    /// `tar` couldn't unpack a download, with what it said.
    case couldntUnpack(String)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let name, let status): "Couldn't download \(name): GitHub answered \(status)."
        case .badChecksum(let name, let expected, let found):
            "The download of \(name) isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noEngine: "The engine's download has no wine and wineserver in it."
        case .noLibraries: "The Template's download has none of the libraries Wine needs in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        }
    }
}

/// Installs the Wine Ludeum keeps (ADR 0040): fetches the pinned engine and Template, checks each against its digest,
/// unpacks them, puts the Template's libraries into the engine's `lib`, records which release it is, and swaps it into
/// `Emulators/Wine/` in the Ludeum folder. Nothing is replaced until the new copy checks out.
///
/// Everything keeps the time its tar gave it. Wine updates every prefix that remembers another time for the engine's
/// `share/wine/wine.inf` than the one it finds, so a reinstall of the same release leaves the ROMs' prefixes as they are.
public struct WineInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: WineRelease
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(ludeum: LudeumFolder = .standard, release: WineRelease = .pinned, transport: any HTTPTransport = URLSessionTransport()) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the downloads are unpacked and checked before the engine is swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing Wine", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        // The engine is about twice the Template's size.
        let engineTar = try await download(release.engineURL, named: release.engine, sha256: release.engineSHA256) { progress($0 * 0.55) }
        let templateTar = try await download(release.templateURL, named: release.template, sha256: release.templateSHA256) {
            progress(0.55 + $0 * 0.25)
        }

        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        try files.createDirectory(at: unpacked, withIntermediateDirectories: true)
        do {
            try EmulatorInstall.untar(engineTar, into: unpacked)
            progress(0.9)
            try EmulatorInstall.untar(templateTar, into: unpacked)
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw WineInstallError.couldntUnpack(failed.message)
        }
        progress(0.95)
        try Task.checkCancellation()

        // The engine's tar holds `wswine.bundle`: `bin`, `lib` and `share`.
        let folders = ((try? files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [])
        func executable(_ path: String, in folder: URL) -> Bool {
            files.isExecutableFile(atPath: folder.appending(path: path).path(percentEncoded: false))
        }
        guard let engine = folders.first(where: { executable("bin/wine", in: $0) && executable("bin/wineserver", in: $0) }) else {
            throw WineInstallError.noEngine
        }
        // The Template is an app whose `Contents/Frameworks` has the libraries at its top, among frameworks the engine
        // doesn't ask for.
        let lib = engine.appending(path: "lib", directoryHint: .isDirectory)
        try files.createDirectory(at: lib, withIntermediateDirectories: true)
        var libraries = 0
        for template in folders where template != engine {
            let frameworks = template.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
            for name in (try? files.contentsOfDirectory(atPath: frameworks.path(percentEncoded: false))) ?? []
            where name.hasSuffix(".dylib") {
                let library = lib.appending(path: name, directoryHint: .notDirectory)
                guard !files.fileExists(atPath: library.path(percentEncoded: false)) else { continue }
                try files.moveItem(at: frameworks.appending(path: name, directoryHint: .notDirectory), to: library)
                libraries += 1
            }
        }
        guard libraries > 0 else { throw WineInstallError.noLibraries }
        EmulatorInstall.removeQuarantine(engine)
        try WineRelease.Installed(release).write(in: engine)
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back. The ROMs'
        // prefixes are beside it and their Game saves in the Data folder, so they stay where they are.
        let installed = ludeum.wineFolder
        let replaced = ludeum.emulators.appending(path: "Wine (replaced)", directoryHint: .isDirectory)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: engine, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        if hadOne { try? files.removeItem(at: replaced) }
        progress(1)
    }

    /// Fetches one of the two tars into the work folder and checks it's the one its digest names.
    private func download(_ url: URL, named name: String, sha256: String, progress: @escaping @Sendable (Double) -> Void) async throws
        -> URL
    {
        let tar = work.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
        let response = try await transport.download(URLRequest(url: url), to: tar, progress: progress)
        guard response.statusCode == 200 else { throw WineInstallError.notFound(name, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: tar)
        guard digest == sha256.lowercased() else { throw WineInstallError.badChecksum(name, expected: sha256, found: digest) }
        return tar
    }
}
