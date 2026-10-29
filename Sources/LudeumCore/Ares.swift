import Foundation

extension LudeumFolder {
    /// The folder of the ares Ludeum installs (ADR 0028): the app, and beside it the `settings.bml` that makes it
    /// portable.
    public var aresFolder: URL { emulators.appending(path: "ares", directoryHint: .isDirectory) }

    /// The ares Ludeum installs.
    public var aresApp: URL { aresFolder.appending(path: "ares.app", directoryHint: .isDirectory) }

    /// Where ares keeps Save states and Game saves, in a folder of its own for each kind of machine it plays (`AresSaves`):
    /// `Emulators/ares/Saves/` in the Data folder.
    public var aresSaves: URL { data.appending(path: "Emulators/ares/Saves", directoryHint: .isDirectory) }

    /// Where ares keeps screenshots, in a folder for each kind of machine it plays, as its saves.
    public var aresScreenshots: URL { data.appending(path: "Emulators/ares/Screenshots", directoryHint: .isDirectory) }
}

/// The ares Ludeum installs and keeps (ADR 0028): `Emulators/ares/ares.app` in the Ludeum folder, made portable by a
/// `settings.bml` beside it, which ares finds there before its own in Application Support, so no other ares shares it.
///
/// Its **Standing settings** are written before every Play: its Saves path (Save states and Game saves alike) and its
/// screenshots into the Data folder, where ares makes a folder for each kind of machine it plays, and Game saves written every 30
/// seconds of play. ares rewrites the whole file when it starts and quits, so they're only written while it isn't
/// running. Everything else in the file is ares's own, and what's changed in it during a Play lasts. Run-ahead, the
/// Game's own, is a `--setting` for that launch, which ares puts back when it quits.
public struct AresSettings: Sendable {
    /// The ares.app Ludeum installs.
    public let app: URL
    /// The Ludeum folder, whose Data folder holds what ares keeps.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.aresApp
        self.ludeum = ludeum
    }

    /// The name ares looks for beside its app.
    static let fileName = "settings.bml"

    /// Its `settings.bml`, beside it.
    var settingsFile: URL { app.deletingLastPathComponent().appending(path: Self.fileName) }

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/ares").path(percentEncoded: false))
    }

    /// Its `settings.bml` is beside it, so its settings are its own.
    public var isPortable: Bool { FileManager.default.fileExists(atPath: settingsFile.path(percentEncoded: false)) }

    /// The system ares plays a Platform's Games as, which `--system` names.
    static func system(_ platformId: Int64) -> String {
        switch platformId {
        case 4: "Nintendo 64"
        case 78: "Mega CD"  // Sega CD
        default: "Mega Drive"
        }
    }

    /// Writes the Standing settings, then gives the ROM to open as its Platform's system, starting from `saveState`'s
    /// slot if given (`<name>.bs<slot>`, which ares finds by the ROM's name). Run-ahead is on or off (one frame): any
    /// run-ahead frames turn it on, for this launch only.
    func arguments(rom: URL, platformId: Int64, settings: EmulatorSettings, saveState: URL? = nil) throws -> [String] {
        try writeStanding()
        let slot = saveState.flatMap { AresSaves.slot(ofExtension: $0.pathExtension) }
        return ["--system", Self.system(platformId), "--setting", "General/RunAhead=\((settings.runAheadFrames ?? 0) > 0)"]
            + (slot.map { ["--save-state", String($0)] } ?? []) + [rom.path(percentEncoded: false)]
    }

    /// Writes the Standing settings into `settings.bml`, making the folders they name. Refused while the Data folder is
    /// missing, so nothing is kept somewhere Dropbox doesn't see, and while the file is there but can't be read, so my
    /// controls aren't written over. The file is left alone when it already says so.
    public func writeStanding() throws {
        try ludeum.checkData()
        for folder in [ludeum.aresSaves, ludeum.aresScreenshots] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let original = isPortable ? try String(contentsOf: settingsFile, encoding: .utf8) : nil
        let updated = Self.standing(in: original ?? "", ludeum: ludeum)
        guard updated != original else { return }
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// `bml` with the Standing settings. ares appends a system's name to a path, so each ends in `/`.
    static func standing(in bml: String, ludeum: LudeumFolder) -> String {
        func path(_ folder: URL) -> String {
            let path = folder.path(percentEncoded: false)
            return path.hasSuffix("/") ? path : path + "/"
        }
        var bml = BML.setting("Paths/Saves", to: path(ludeum.aresSaves), in: bml)
        bml = BML.setting("Paths/Screenshots", to: path(ludeum.aresScreenshots), in: bml)
        return BML.setting("General/AutoSaveMemory", to: "true", in: bml)
    }
}

/// ares's settings format: a node a line, `Name` or `Name: value`, its children indented two spaces under it.
enum BML {
    /// `bml` with the node at `path` (`Paths/Saves`) set to `value`, the rest as it was: an empty one given its value, and
    /// one that's missing added at the end of its parent's children, its parent too if that's missing.
    static func setting(_ path: String, to value: String, in bml: String) -> String {
        var lines = bml.isEmpty ? [] : bml.components(separatedBy: "\n")
        // The file's last newline leaves an empty last line, which stays last.
        let trailing = lines.last == "" ? lines.removeLast() : nil
        let names = path.split(separator: "/").map(String.init)
        var start = 0
        var end = lines.count
        for (depth, name) in names.enumerated() {
            let indent = String(repeating: "  ", count: depth)
            let line = indent + name + (depth == names.count - 1 ? ": \(value)" : "")
            if let found = (start..<end).first(where: { node(lines[$0], depth: depth) == name }) {
                if depth == names.count - 1 { lines[found] = line }
                start = found + 1
                end = (start..<end).first { lines[$0].isEmpty || indentation(lines[$0]) <= depth * 2 } ?? end
            } else {
                // At the end of the parent's children, before any blank lines that close them.
                var at = end
                while at > start, lines[at - 1].isEmpty { at -= 1 }
                lines.insert(line, at: at)
                start = at + 1
                end = start
            }
        }
        if let trailing { lines.append(trailing) } else if !lines.isEmpty { lines.append("") }
        return lines.joined(separator: "\n")
    }

    /// The name of the node on `line`, when it's at `depth`.
    private static func node(_ line: String, depth: Int) -> String? {
        guard indentation(line) == depth * 2, !line.isEmpty else { return nil }
        let rest = line.dropFirst(depth * 2)
        return String(rest.prefix { $0 != ":" }).trimmingCharacters(in: .whitespaces)
    }

    private static func indentation(_ line: String) -> Int { line.prefix { $0 == " " }.count }
}
