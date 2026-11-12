import Foundation

extension LudeumFolder {
    /// The KEmulator Ludeum makes at Install (ADR 0044): KEmulator nnmod and a Java runtime inside an app of Ludeum's own.
    public var kEmulatorApp: URL { emulators.appending(path: "KEmulator.app", directoryHint: .isDirectory) }

    /// KEmulator's own folder inside the app: `KEmulator.jar`, its libraries, and the settings it keeps beside them.
    var kEmulatorHome: URL { kEmulatorApp.appending(path: "Contents/Resources/KEmulator", directoryHint: .isDirectory) }

    /// The Java runtime's home inside the app.
    var kEmulatorJRE: URL { kEmulatorApp.appending(path: "Contents/Resources/jre", directoryHint: .isDirectory) }

    /// What KEmulator keeps that has to survive: `Emulators/KEmulator/` in the Data folder.
    var kEmulatorData: URL { data.appending(path: "Emulators/KEmulator", directoryHint: .isDirectory) }

    /// Every Java phone game's Game saves, a folder per MIDlet, as KEmulator names them.
    public var mobileGameSaves: URL { kEmulatorData.appending(path: "Game Saves", directoryHint: .isDirectory) }
}

/// The settings files KEmulator keeps beside its jar, which Ludeum copies into the Data folder (ADR 0044).
enum KEmulatorFile: String, CaseIterable, Sendable {
    /// Its settings: the key map, the window, and Ludeum's Standing settings.
    case property = "property.txt"
    /// Its per-game settings, by each jar's SHA-256: phone model, screen size, keys.
    case midlets = "midlets.ini"
}

/// What a Play of a Java phone game needs (ADR 0044): KEmulator's Standing settings written into its `property.txt`, and
/// its own settings files copied into the Data folder, or back from it, first. Every Play opens one jar, a Disc's when the
/// ROM is several.
public struct KEmulatorSettings: Sendable {
    /// The KEmulator.app Ludeum makes.
    public let app: URL
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.kEmulatorApp
        self.ludeum = ludeum
    }

    /// Its launcher, KEmulator's jar and the Java runtime are there.
    public var isInstalled: Bool {
        let files = FileManager.default
        return files.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/KEmulator").path(percentEncoded: false))
            && files.fileExists(atPath: ludeum.kEmulatorHome.appending(path: "KEmulator.jar").path(percentEncoded: false))
            && files.isExecutableFile(atPath: ludeum.kEmulatorJRE.appending(path: "Contents/Home/bin/java").path(percentEncoded: false))
    }

    /// The Standing settings, by key: where Game saves go, no updates of itself, and no settings dialog on a game's first
    /// Play. `file://` is what makes KEmulator take the path as it is: a value starting `/` it puts its own folder in front
    /// of.
    static func standing(ludeum: LudeumFolder) -> [(key: String, value: String)] {
        [
            ("RMSFolder", "file://" + ludeum.mobileGameSaves.path(percentEncoded: false)),
            ("AutoUpdate", "1"),
            ("ShowAppSettingsOnStart", "false"),
        ]
    }

    /// Gets KEmulator ready for a Play and returns its arguments: copies its settings files into the Data folder, or back
    /// from it where the app's are missing or empty, then writes the Standing settings into `property.txt`.
    public func arguments(jar: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: ludeum.mobileGameSaves, withIntermediateDirectories: true)
        try keepSettingsFiles()
        let property = ludeum.kEmulatorHome.appending(path: KEmulatorFile.property.rawValue)
        // ISO 8859-1 both ways, as `java.util.Properties` reads and writes it, so nothing else in it changes.
        let text = (try? String(contentsOf: property, encoding: .isoLatin1)) ?? ""
        let written = Self.writing(Self.standing(ludeum: ludeum), into: text)
        try (written.data(using: .isoLatin1) ?? Data(written.utf8)).write(to: property, options: .atomic)
        // `-s`: it would otherwise start itself again with the JVM settings it wants, and quit, ending the Play at once.
        return ["-jar", jar.path(percentEncoded: false), "-s"]
    }

    /// Copies each of KEmulator's settings files that isn't empty into the Data folder, so its key map and per-game
    /// settings survive losing this Mac; one that's missing or empty in the app (a new install, or a forced quit's) comes
    /// back from there.
    func keepSettingsFiles() throws {
        let files = FileManager.default
        try files.createDirectory(at: ludeum.kEmulatorData, withIntermediateDirectories: true)
        for file in KEmulatorFile.allCases {
            let installed = ludeum.kEmulatorHome.appending(path: file.rawValue)
            let kept = ludeum.kEmulatorData.appending(path: file.rawValue)
            if Self.size(of: installed) > 0 {
                try Self.replace(kept, with: installed)
            } else if Self.size(of: kept) > 0 {
                try Self.replace(installed, with: kept)
            }
        }
    }

    private static func size(of file: URL) -> Int {
        (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// `destination` replaced by a copy of `source`.
    static func replace(_ destination: URL, with source: URL) throws {
        let files = FileManager.default
        let copy = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).ludeum")
        try? files.removeItem(at: copy)
        try files.copyItem(at: source, to: copy)
        if files.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try files.replaceItemAt(destination, withItemAt: copy)
        } else {
            try files.moveItem(at: copy, to: destination)
        }
    }

    /// `text`, a `java.util.Properties` file, with each of `settings` set: every line of its key taken out, and the
    /// settings put at the end. Everything else stays as it was.
    static func writing(_ settings: [(key: String, value: String)], into text: String) -> String {
        let keys = Set(settings.map(\.key))
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        // A key's line can go on to the next with a backslash at its end: the whole of it goes.
        var kept: [String] = []
        var continuing = false
        var dropping = false
        for line in lines {
            if !continuing { dropping = key(of: line).map(keys.contains) ?? false }
            if !dropping { kept.append(line) }
            continuing = endsInContinuation(line)
        }
        lines = kept
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines += settings.map { "\($0.key)=\(escaped($0.value))" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The key of a `java.util.Properties` line, or nil for a comment or a blank line.
    static func key(of line: String) -> String? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" || $0 == "\u{0C}" }
        guard let first = trimmed.first, first != "#", first != "!" else { return nil }
        var key = ""
        var escaping = false
        for c in trimmed {
            if escaping {
                key.append(c)
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else if c == "=" || c == ":" || c == " " || c == "\t" {
                break
            } else {
                key.append(c)
            }
        }
        return key
    }

    /// Whether a line ends in an odd number of backslashes, so goes on to the next.
    private static func endsInContinuation(_ line: String) -> Bool {
        line.reversed().prefix { $0 == "\\" }.count % 2 == 1
    }

    /// A value as `java.util.Properties` reads it: backslashes, colons and equals signs escaped, and anything outside
    /// Latin-1's printable ASCII as `\uXXXX`, as it reads the file as ISO 8859-1.
    static func escaped(_ value: String) -> String {
        var out = ""
        for (i, unit) in value.utf16.enumerated() {
            switch unit {
            case 0x5C: out += "\\\\"
            case 0x3A: out += "\\:"
            case 0x3D: out += "\\="
            case 0x20 where i == 0: out += "\\ "
            case 0x20...0x7E: out.append(Character(UnicodeScalar(unit)!))
            default: out += String(format: "\\u%04X", unit)
            }
        }
        return out
    }
}

/// What a Java phone game has saved (ADR 0044): KEmulator's record stores for one MIDlet, in the Data folder's
/// `Emulators/KEmulator/Game Saves/`, in a folder named from the vendor and name its jar's manifest gives, as KEmulator
/// names it. So a renamed jar keeps them, and two builds of a game with the same vendor and name share them.
public struct MobileGameSave: Sendable, Equatable {
    /// The MIDlet's name, as its manifest gives it.
    public let midlet: String
    public let folder: URL
    public let size: Int64
    public let written: Date

    /// A Java phone ROM's jars: its one, or each of its Discs' in its playlist's order. None when it isn't there.
    public static func jars(of rom: LudeumROM, locator: ROMLocator) -> [URL] {
        guard let file = try? locator.file(of: rom, ready: true) else { return [] }
        if file.pathExtension.lowercased() == "m3u" {
            return ROMFiles.playlistEntries(file).map { file.deletingLastPathComponent().appending(path: $0) }
                .filter { $0.pathExtension.lowercased() == "jar" }
        }
        return file.pathExtension.lowercased() == "jar" ? [file] : []
    }

    /// The jar's, or nil while its game has saved nothing, or its manifest can't be read.
    public static func of(jar: URL, ludeum: LudeumFolder) -> MobileGameSave? {
        guard let manifest = JarManifest.read(jar) else { return nil }
        let folder = ludeum.mobileGameSaves.appending(path: manifest.saveFolderName, directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return nil }
        var size: Int64 = 0
        var written: Date?
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            size += Int64(values.fileSize ?? 0)
            if let modified = values.contentModificationDate, modified > written ?? .distantPast { written = modified }
        }
        return written.map {
            MobileGameSave(midlet: manifest.name ?? jar.deletingPathExtension().lastPathComponent, folder: folder, size: size, written: $0)
        }
    }
}

/// What a jar's `META-INF/MANIFEST.MF` says of its MIDlet suite.
struct JarManifest: Sendable, Equatable {
    var vendor: String?
    var name: String?

    /// The folder KEmulator keeps the suite's record stores in: Base64 of its UTF-8 `vendor_name`, `/` written `-`. A
    /// missing attribute is Java's "null".
    var saveFolderName: String {
        Data("\(vendor ?? "null")_\(name ?? "null")".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "-")
    }

    /// Reads it out of the jar with `unzip`, which every Mac has; nil when it can't.
    static func read(_ jar: URL) -> JarManifest? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-p", jar.path(percentEncoded: false), "META-INF/MANIFEST.MF"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// A manifest's main section, as KEmulator reads it with Java's `Manifest`: `Name: value` lines up to the first blank
    /// one, a line starting with a space going on from the one before, the space after the colon not part of the value.
    static func parse(_ text: String) -> JarManifest {
        var attributes: [String: String] = [:]
        var last: String?
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            if line.isEmpty {
                if attributes.isEmpty { continue } else { break }
            }
            if line.hasPrefix(" "), let key = last {
                attributes[key, default: ""] += line.dropFirst()
            } else if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon])
                attributes[key] = String(line[line.index(after: colon)...].drop { $0 == " " })
                last = key
            } else {
                last = nil
            }
        }
        return JarManifest(vendor: attributes["MIDlet-Vendor"], name: attributes["MIDlet-Name"])
    }
}
