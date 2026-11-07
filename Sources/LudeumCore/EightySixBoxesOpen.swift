import Foundation

/// Which ROMs the open 86Boxes are playing, told by the machine folder each was opened on (`-P`), one per ROM (ADR 0041).
/// Nothing a Play writes is shared between ROMs, and the Windows base is only read, so Windows Games Play side by side; a
/// game disk can be in use by only one machine, so a ROM can't be Played twice at once, nor renamed or have its game disk
/// deleted while it's being Played.
public struct EightySixBoxesOpen: Sendable, Equatable {
    /// The ROMs whose machines are open.
    let roms: Set<String>
    /// An open 86Box's command line couldn't be read, so it could be playing any ROM.
    let anyUnreadable: Bool

    /// No 86Box open.
    public static let none = EightySixBoxesOpen(roms: [], anyUnreadable: false)

    private init(roms: Set<String>, anyUnreadable: Bool) {
        self.roms = roms
        self.anyUnreadable = anyUnreadable
    }

    /// From each open 86Box's command line, or nil for one that couldn't be read. One opened on a machine folder that
    /// isn't a ROM's, or on none, plays no ROM.
    public init(commandLines: [[String]?], ludeum: LudeumFolder) {
        let machines = ludeum.eightySixBoxMachines.standardizedFileURL.path(percentEncoded: false)
        var roms: Set<String> = []
        var anyUnreadable = false
        for commandLine in commandLines {
            guard let commandLine else {
                anyUnreadable = true
                continue
            }
            guard let path = Self.machinePath(in: commandLine) else { continue }
            let machine = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
            if machine.deletingLastPathComponent().path(percentEncoded: false) == machines { roms.insert(machine.lastPathComponent) }
        }
        self.init(roms: roms, anyUnreadable: anyUnreadable)
    }

    /// The machine folder a command line opens 86Box on: `-P <path>`, `--vmpath <path>` or `--vmpath=<path>`.
    private static func machinePath(in commandLine: [String]) -> String? {
        for (i, argument) in commandLine.enumerated() {
            if argument == "-P" || argument == "--vmpath" { return i + 1 < commandLine.count ? commandLine[i + 1] : nil }
            if argument.hasPrefix("--vmpath=") { return String(argument.dropFirst("--vmpath=".count)) }
        }
        return nil
    }

    /// An open 86Box is, or may be, playing the ROM `name`.
    public func isPlaying(_ name: String) -> Bool { anyUnreadable || roms.contains(name) }
}
