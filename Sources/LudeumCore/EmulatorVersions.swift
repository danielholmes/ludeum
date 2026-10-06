import Foundation

/// How an installed Emulator compares with the version Ludeum's launch code was written against.
public enum VersionCheck: Sendable, Equatable {
    case ok
    /// Older than expected: its command line may not take what Play sends, so Play is refused.
    case tooOld(found: String)
    /// A newer major version, which may have changed its command line: Play goes ahead, with a warning.
    case newerMajor(found: String)
    /// Its version couldn't be read: Play goes ahead, with a warning.
    case unreadable
}

/// What each Emulator's version is expected to be, and where to read it.
struct EmulatorVersionSpec: Sendable {
    enum Source: Sendable {
        /// Run the app's executable with this flag; it prints its version and exits.
        case commandLine(String)
        /// The app's `CFBundleShortVersionString`.
        case appVersion
        /// MesenCE's app version is a placeholder; its settings file records the version that last ran.
        case mesenSettings
    }

    enum Format: Sendable {
        /// `2.9.103`, `v148`, `2609`: dotted numbers, an optional leading "v".
        case dotted
        /// DuckStation's rolling builds, `0.1-12070-g4122fed9a`: the build number.
        case buildNumber
    }

    /// The minimum: the version the launch code was written and checked against.
    let expected: String
    let source: Source
    var format = Format.dotted
    /// False where the first number isn't a major version (Dolphin's year-month, ares' and DuckStation's counts).
    var warnsOnNewerMajor = true
}

extension Emulator {
    /// The version Ludeum's launch code was written against: anything older can't be Played.
    public var expectedVersion: String? { versionSpec?.expected }

    /// Nil for an Emulator with no expected version yet: it isn't checked.
    var versionSpec: EmulatorVersionSpec? {
        switch self {
        case .mesenCE: EmulatorVersionSpec(expected: "2.2.1", source: .mesenSettings)
        case .duckStation:
            EmulatorVersionSpec(expected: "12070", source: .commandLine("-version"), format: .buildNumber, warnsOnNewerMajor: false)
        // Its `--version` works, but the app version is the same and needs no process.
        case .dolphin: EmulatorVersionSpec(expected: "2609", source: .appVersion, warnsOnNewerMajor: false)
        case .ares: EmulatorVersionSpec(expected: "148", source: .commandLine("--version"), warnsOnNewerMajor: false)
        case .melonDS: EmulatorVersionSpec(expected: "1.1", source: .appVersion)
        case .ymir: EmulatorVersionSpec(expected: "0.3.3", source: .appVersion)
        case .ppsspp: EmulatorVersionSpec(expected: "1.20.4", source: .commandLine("--version"))
        case .pcsx2: EmulatorVersionSpec(expected: "2.9.103", source: .commandLine("-version"))
        default: nil
        }
    }
}

public enum EmulatorVersions {
    static var mesenSettings: URL { URL.applicationSupportDirectory.appending(path: "MesenCE/settings.json") }

    /// Reads and checks the installed app's version. Runs a process for some Emulators, so not on the main thread.
    /// The installed app's version (as `shown(found:for:)` gives it) and how it compares. Runs a
    /// process for some Emulators, so not on the main thread. Nil for an Emulator that isn't checked.
    public static func check(_ emulator: Emulator, app: URL) -> (installed: String?, check: VersionCheck)? {
        guard emulator.versionSpec != nil else { return nil }
        let found = read(emulator, app: app)
        return (shown(found: found, for: emulator), check(found: found, for: emulator))
    }

    /// `found` (whatever the source printed) against what's expected.
    /// The version `found` names, as compared: "2.9.103", or DuckStation's build number. Nil when it can't be read.
    public static func shown(found: String?, for emulator: Emulator) -> String? {
        guard let spec = emulator.versionSpec, let text = found, let version = parse(text, spec.format) else { return nil }
        return version.map(String.init).joined(separator: ".")
    }

    static func check(found: String?, for emulator: Emulator) -> VersionCheck {
        guard let spec = emulator.versionSpec, let text = found, let version = parse(text, spec.format),
            let expected = parse(spec.expected, spec.format)
        else {
            return .unreadable
        }
        let shown = version.map(String.init).joined(separator: ".")
        if compare(version, expected) < 0 { return .tooOld(found: shown) }
        if spec.warnsOnNewerMajor, version[0] > expected[0] { return .newerMajor(found: shown) }
        return .ok
    }

    /// The version text from the Emulator's source, or nil when it can't be had.
    static func read(_ emulator: Emulator, app: URL, mesenSettings: URL = mesenSettings) -> String? {
        let info = Bundle(url: app)?.infoDictionary
        switch emulator.versionSpec?.source {
        case nil:
            return nil
        case .appVersion:
            return info?["CFBundleShortVersionString"] as? String
        case .mesenSettings:
            guard let data = try? Data(contentsOf: mesenSettings),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return json["Version"] as? String
        case .commandLine(let flag):
            guard let executable = info?["CFBundleExecutable"] as? String else { return nil }
            return run(app.appending(path: "Contents/MacOS/\(executable)"), flag)
        }
    }

    /// Its output, given 10 seconds before it's stopped.
    private static func run(_ executable: URL, _ flag: String) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = [flag]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        // Read on its own thread while it runs, so a chatty one can't fill the pipe and stall, and a
        // hung one can't hold this up past the timeout. Not the shared pool: a busy machine can leave
        // the read queued there until the timeout.
        let read = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var output = Data()
        Thread {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }.start()
        if done.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            return nil
        }
        // Something it started may still hold the pipe open: don't wait on that for long.
        guard read.wait(timeout: .now() + 2) == .success else { return nil }
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ text: String, _ format: EmulatorVersionSpec.Format) -> [Int]? {
        switch format {
        case .dotted:
            // A dotted number first, so the 2 in "PCSX2 v2.9.103" isn't taken for the version.
            let match = text.firstMatch(of: /(\d+(?:\.\d+)+)/)?.output.1 ?? text.firstMatch(of: /(?:^|[^A-Za-z\d])v?(\d+)/)?.output.1
            return match.map { $0.split(separator: ".").compactMap { Int($0) } }
        case .buildNumber:
            if let match = text.firstMatch(of: /\d+\.\d+-(\d+)/) { return Int(match.output.1).map { [$0] } }
            return text.wholeMatch(of: /\d+/).flatMap { Int($0.output) }.map { [$0] }
        }
    }

    /// Dotted versions compared number by number, missing numbers counting as 0.
    private static func compare(_ a: [Int], _ b: [Int]) -> Int {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
