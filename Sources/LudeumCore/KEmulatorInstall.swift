import Foundation

/// The KEmulator Ludeum installs (ADR 0044): KEmulator nnmod's multi-platform release, pinned with its zip's SHA-256 as
/// GitHub's release API gives it, and the Java runtime it runs on, Eclipse Temurin's for Apple Silicon, pinned the same way.
/// A bump is the versions and digests here.
public struct KEmulatorRelease: Sendable, Equatable {
    /// Its number, the tag without its "v": what the app Ludeum makes says it is.
    public let version: String
    /// The zip's SHA-256, lowercase hex.
    public let sha256: String
    /// Temurin's tag, `jdk-21.0.13+9`.
    public let jreTag: String
    /// The JRE's SHA-256, lowercase hex.
    public let jreSHA256: String

    public static let pinned = KEmulatorRelease(
        version: "2.22", sha256: "f9a5a442014d43f1d9d2c51243795680d99fd91e49c300712ac6bd0823ed8e5e",
        jreTag: "jdk-21.0.13+9", jreSHA256: "225bab0a09491ef06835488cd942f5d2befa9a0410a2484f0c8bbcf7506ec09a")

    /// Where the zip is.
    public var url: URL {
        URL(string: "https://github.com/shinovon/KEmulator/releases/download/v\(version)/kemnnx64.v\(version).zip")!
    }

    /// The JRE's version as its file names it, `21.0.13_9`.
    var jreVersion: String { jreTag.replacingOccurrences(of: "jdk-", with: "").replacingOccurrences(of: "+", with: "_") }

    /// Where the JRE is.
    public var jreURL: URL {
        let tag = jreTag.replacingOccurrences(of: "+", with: "%2B")
        return URL(
            string:
                "https://github.com/adoptium/temurin21-binaries/releases/download/\(tag)/OpenJDK21U-jre_aarch64_mac_hotspot_\(jreVersion).tar.gz"
        )!
    }
}

/// Why an Install stopped, with nothing replaced.
public enum KEmulatorInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't the download.
    case notFound(String, status: Int)
    /// A download isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The zip had no `KEmulator.jar` in it, or the JRE no `java`.
    case missing(String)
    /// `ditto` or `tar` couldn't unpack a download, with what it said.
    case couldntUnpack(String)
    /// The JRE's `java` didn't run, with what it said.
    case javaDoesntRun(String)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let what, let status): "Couldn't download \(what): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .missing(let what): "The download has no \(what) in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .javaDoesntRun(let why): "Its Java runtime didn't run: \(why)"
        }
    }
}

/// Installs the KEmulator Ludeum keeps (ADR 0044): fetches the pinned KEmulator nnmod zip and Java runtime, checks each
/// against its digest, unpacks both, checks the runtime's `java` runs, and makes them into `Emulators/KEmulator.app` in the
/// Ludeum folder, an app of Ludeum's own whose executable starts KEmulator on that runtime. What the replaced copy kept
/// beside its jar, its settings and per-game settings, comes across. Nothing is replaced until it all checks out.
public struct KEmulatorInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: KEmulatorRelease
    let transport: any HTTPTransport

    /// `release` and `transport` stand in for the pinned release and the real GitHub, in tests.
    public init(ludeum: LudeumFolder = .standard, release: KEmulatorRelease = .pinned, transport: any HTTPTransport = URLSessionTransport())
    {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
    }

    /// Where the downloads are unpacked and checked before they're swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing KEmulator", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: release.url.lastPathComponent)
        try await download(release.url, to: zip, sha256: release.sha256, what: "KEmulator v\(release.version)") { progress($0 * 0.4) }
        let jre = work.appending(path: "jre.tar.gz")
        try await download(release.jreURL, to: jre, sha256: release.jreSHA256, what: "its Java runtime") { progress(0.4 + $0 * 0.5) }

        let app = work.appending(path: "KEmulator.app", directoryHint: .isDirectory)
        let resources = app.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try files.createDirectory(at: resources, withIntermediateDirectories: true)
        let unzipped = work.appending(path: "unzipped", directoryHint: .isDirectory)
        do { try EmulatorInstall.unpack(zip, into: unzipped) } catch let error as EmulatorInstall.CouldntUnpack {
            throw KEmulatorInstallError.couldntUnpack(error.message)
        }
        guard let home = Self.folder(holding: "KEmulator.jar", in: unzipped) else { throw KEmulatorInstallError.missing("KEmulator.jar") }
        try files.moveItem(at: home, to: resources.appending(path: "KEmulator", directoryHint: .isDirectory))
        let untarred = work.appending(path: "untarred", directoryHint: .isDirectory)
        try files.createDirectory(at: untarred, withIntermediateDirectories: true)
        try run("/usr/bin/tar", ["-xzf", jre.path(percentEncoded: false), "-C", untarred.path(percentEncoded: false)])
        // The JRE is a bundle, `jdk-…-jre/Contents/Home/bin/java`.
        guard let java = Self.folder(holding: "java", in: untarred, under: "Contents/Home/bin") else {
            throw KEmulatorInstallError.missing("java")
        }
        let jreBundle = java.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try files.moveItem(at: jreBundle, to: resources.appending(path: "jre", directoryHint: .isDirectory))
        try writeLauncher(in: app)
        EmulatorInstall.removeQuarantine(app)
        progress(0.95)
        try checkJava(resources.appending(path: "jre/Contents/Home/bin/java"))
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in, with what the old one kept beside its jar; should it not go in,
        // the old one goes back.
        let installed = ludeum.kEmulatorApp
        let replaced = work.appending(path: "replaced KEmulator.app", directoryHint: .isDirectory)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne {
            let oldHome = installed.appending(path: "Contents/Resources/KEmulator", directoryHint: .isDirectory)
            for file in KEmulatorFile.allCases {
                let kept = oldHome.appending(path: file.rawValue)
                guard files.fileExists(atPath: kept.path(percentEncoded: false)) else { continue }
                try files.copyItem(at: kept, to: resources.appending(path: "KEmulator/\(file.rawValue)"))
            }
        }
        try files.createDirectory(at: ludeum.emulators, withIntermediateDirectories: true)
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: app, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        progress(1)
    }

    /// The executable's name, which its `Info.plist` names.
    static let executable = "KEmulator"

    /// Writes the app's `Info.plist` and its executable: a script that starts KEmulator on the bundled runtime with the
    /// settings KEmulator's own `kemulator.sh` gives a Mac, its folder the working one, and passes on what Play gives it.
    /// It becomes `java` (`exec`), so the app is the process KEmulator runs in, and quitting it ends the Play.
    func writeLauncher(in app: URL) throws {
        let info: [String: Any] = [
            "CFBundleExecutable": Self.executable,
            "CFBundleIdentifier": Emulator.kemulator.bundleIdentifier,
            "CFBundleName": "KEmulator",
            "CFBundleDisplayName": "KEmulator",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": release.version,
            "CFBundleVersion": release.version,
            "LSMinimumSystemVersion": "11.0",
            "NSHighResolutionCapable": true,
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appending(path: "Contents/Info.plist"))
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let launcher = macOS.appending(path: Self.executable)
        try Data(Self.launcher.utf8).write(to: launcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path(percentEncoded: false))
    }

    /// The executable's script.
    static let launcher = """
        #!/bin/sh
        # Made by Ludeum at Install (ADR 0044): KEmulator nnmod on the Java runtime beside it, with the settings its own
        # kemulator.sh gives a Mac on Java 9 and later. Ludeum opens it with `-jar <the game's jar> -s`.
        CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
        K="$CONTENTS/Resources/KEmulator"
        cd "$K" || exit 1
        exec "$CONTENTS/Resources/jre/Contents/Home/bin/java" \\
          -Xmx512M -Djna.nosys=true -Djava.library.path="$K" -Dfile.encoding=UTF-8 -Dswt.autoScale=false \\
          -javaagent:"$K/KEmulator.jar" -XX:+IgnoreUnrecognizedVMOptions -XstartOnFirstThread -Xdock:name=KEmulator \\
          --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED \\
          --add-opens java.base/java.lang.ref=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED \\
          --add-opens java.base/java.util=ALL-UNNAMED --add-opens jdk.unsupported/sun.misc=ALL-UNNAMED \\
          --add-opens java.desktop/com.sun.media.sound=ALL-UNNAMED --add-opens java.desktop/javax.sound.midi=ALL-UNNAMED \\
          --enable-native-access=ALL-UNNAMED \\
          -jar "$K/KEmulator.jar" "$@"

        """

    /// The folder holding `name` (inside `under`, when given), at most two levels down in `root`.
    static func folder(holding name: String, in root: URL, under: String? = nil) -> URL? {
        let files = FileManager.default
        let top = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in [root] + top {
            let holder = under.map { folder.appending(path: $0, directoryHint: .isDirectory) } ?? folder
            if files.fileExists(atPath: holder.appending(path: name).path(percentEncoded: false)) { return holder }
        }
        return nil
    }

    /// Runs `java -version`, which needs no display and touches nothing.
    private func checkJava(_ java: URL) throws {
        let process = Process()
        process.executableURL = java
        process.arguments = ["-version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { throw KEmulatorInstallError.javaDoesntRun(error.localizedDescription) }
        let said = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw KEmulatorInstallError.javaDoesntRun(String(decoding: said, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Downloads `url` and checks it against `sha256`.
    private func download(
        _ url: URL, to file: URL, sha256: String, what: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let response = try await transport.download(URLRequest(url: url), to: file, progress: progress)
        guard response.statusCode == 200 else { throw KEmulatorInstallError.notFound(what, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: file)
        guard digest == sha256.lowercased() else { throw KEmulatorInstallError.badChecksum(expected: sha256, found: digest) }
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
            throw KEmulatorInstallError.couldntUnpack(
                String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
