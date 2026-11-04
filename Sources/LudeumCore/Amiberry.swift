import Foundation

extension LudeumFolder {
    /// The Amiberry Ludeum installs (ADR 0035).
    public var amiberryApp: URL { emulators.appending(path: "Amiberry.app", directoryHint: .isDirectory) }

    /// What Amiberry keeps, its home folder for every Play: `Emulators/Amiberry/` in the Data folder. Its `ROMs` folder is
    /// where a Kickstart goes.
    public var amiberryHome: URL { data.appending(path: "Emulators/Amiberry", directoryHint: .isDirectory) }

    /// Where a Kickstart goes for Amiberry to find it.
    public var amiberryKickstarts: URL { amiberryHome.appending(path: "ROMs", directoryHint: .isDirectory) }

    /// The Game saves of the ROM `name`: its disks' save images, in a folder of its own.
    public func amiberrySavedDisks(ofROM name: String) -> URL {
        amiberryHome.appending(path: "Saved Disks", directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
    }
}

/// The Amiberry Ludeum installs and keeps (ADR 0035): `Emulators/Amiberry.app` in the Ludeum folder.
///
/// A ROM is a `.7z` of its disks, so nothing writes to it. A game saves to its disk, and Amiberry keeps what's written to
/// a disk in an archive in its **save image**, `<disk>_save.adf`, which is read over the disk at every Play. It only makes
/// one when told to mid-Play, and until there's one the disk is write-protected, so a Play makes each disk's empty one first.
///
/// Its Standing settings are all for the one launch, so there's no settings file to keep in step: its home folder in the
/// environment (`AMIBERRY_HOME_DIR`), then on the command line where it keeps its settings and the ROM's save images.
public struct AmiberrySettings: Sendable {
    /// The Amiberry.app Ludeum installs.
    public let app: URL
    /// The Ludeum folder, whose Data folder holds what Amiberry keeps.
    let ludeum: LudeumFolder
    /// Reads a ROM's archive; nil where 7-Zip isn't installed.
    let sevenZip: SevenZip?

    public init(ludeum: LudeumFolder = .standard, sevenZip: SevenZip? = SevenZip.find()) {
        self.app = ludeum.amiberryApp
        self.ludeum = ludeum
        self.sevenZip = sevenZip
    }

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/Amiberry").path(percentEncoded: false))
    }

    /// What a Play's environment needs: every folder Amiberry keeps follows this one, Amiberry being unable to run portably
    /// on a Mac.
    public var environment: [String: String] { ["AMIBERRY_HOME_DIR": Self.withoutSlash(ludeum.amiberryHome)] }

    /// A folder's path without a trailing `/`.
    private static func withoutSlash(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The disks in an archive's listing, in Disc order: its files Amiberry opens, by their `(Disk N)`, else by name.
    static func disks(in entries: [SevenZip.Entry]) -> [SevenZip.Entry] {
        let opens = ROMPlatform.all[ROMPlatform.amiga]?.readyExtensions ?? []
        func number(_ entry: SevenZip.Entry) -> Int { ROMName((entry.fileName as NSString).deletingPathExtension).disc ?? Int.max }
        return
            entries
            .filter { opens.contains(($0.path as NSString).pathExtension.lowercased()) }
            .sorted {
                number($0) != number($1) ? number($0) < number($1) : $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
    }

    /// A disk's save image's name, as Amiberry works it out from the disk's: its file's without its extension.
    static func saveImageName(ofDisk path: String) -> String {
        (((path as NSString).lastPathComponent as NSString).deletingPathExtension) + "_save.adf"
    }

    /// A save image with nothing written to it yet, as Amiberry makes one: an extended ADF of 166 tracks, each 12,784
    /// bytes of zeros with no bits in use, so the disk under it is read instead.
    static let emptySaveImage: Data = {
        let tracks = 166
        let trackBytes = 12_784
        var image = Data("UAE-1ADF".utf8)
        image += [0, 0, UInt8(tracks >> 8), UInt8(tracks & 0xFF)]
        let row: [UInt8] = [0, 0, 0, 1, 0, 0, UInt8(trackBytes >> 8), UInt8(trackBytes & 0xFF), 0, 0, 0, 0]
        for _ in 0..<tracks { image += row }
        image += Data(count: tracks * trackBytes)
        return image
    }()

    /// The longest path of a disk Amiberry opens, in bytes, archive and all. Past it the drive just stays empty, with
    /// nothing said, so a Play is refused instead. Tried on 8.5.0, which opened one of 255 and not one of 256.
    static let longestDiskPath = 255

    /// Gives every disk its save image, leaving one that's there alone, and gives the command line. The first disk goes
    /// in the first drive and the second in the second, which is as far as many games look; every disk is in the Disk
    /// Swapper, from Amiberry's menu, for a game that asks for another. Amiberry's Kickstarts are scanned each time, so
    /// one put in the folder is found. Refused while the Data folder is missing, and when the archive can't be read.
    func arguments(rom: URL, romName: String) throws -> [String] {
        try ludeum.checkData()
        guard let sevenZip else { throw ArchiveError.noSevenZip }
        let disks = Self.disks(in: try sevenZip.listNow(rom))
        guard !disks.isEmpty else { throw ArchiveError.noImage }
        // A disk in an archive is named by the archive's path and its path inside.
        let paths = disks.map { rom.path(percentEncoded: false) + "/" + $0.path }
        if let longest = paths.map(\.utf8.count).max(), longest > Self.longestDiskPath {
            throw AmiberryPlayError.pathTooLong(longest)
        }

        let savedDisks = ludeum.amiberrySavedDisks(ofROM: romName)
        try FileManager.default.createDirectory(at: savedDisks, withIntermediateDirectories: true)
        for disk in disks {
            let image = savedDisks.appending(path: Self.saveImageName(ofDisk: disk.path), directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: image.path(percentEncoded: false)) {
                try Self.emptySaveImage.write(to: image, options: .withoutOverwriting)
            }
        }

        // As configuration, not `-0`, `-1` and `-diskswapper=`, whose list would need its paths quoted and its commas guessed.
        var arguments = [
            "--rescan-roms", "--model", "A500", "-G",
            "-o", "amiberry_config=\(Self.withoutSlash(ludeum.amiberryHome))/amiberry.conf",
            "-o", "saveimage_dir=\(savedDisks.path(percentEncoded: false))",
            "-s", "floppy0=\(paths[0])",
        ]
        if paths.count > 1 {
            arguments += ["-s", "floppy1=\(paths[1])"]
            for (slot, path) in paths.enumerated() { arguments += ["-s", "diskimage\(slot)=\(path)"] }
        }
        return arguments
    }
}

/// Why a Play in Amiberry was refused.
public enum AmiberryPlayError: LocalizedError, Equatable {
    /// A disk's path, this long, is more than Amiberry opens.
    case pathTooLong(Int)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong(let length):
            "A disk's path is \(length) characters, and Amiberry opens only up to \(AmiberrySettings.longestDiskPath). "
                + "Rename the ROM with fewer of its tags."
        }
    }
}

/// Why an Amiberry ROM's Rename was refused, with nothing renamed.
public enum AmiberryRenameError: LocalizedError, Equatable {
    /// Amiberry already keeps saved disks under the new name.
    case savedDisksInTheWay(String)

    public var errorDescription: String? {
        switch self {
        case .savedDisksInTheWay(let name): "Amiberry already keeps saved disks for \(name), so nothing was renamed."
        }
    }
}

extension LudeumStore {
    /// Renames an Amiberry ROM as `renameROM(_:to:in:)` does, and the folder of its disks' save images. The disks keep
    /// their names inside its archive, and so do the save images. Refused, with nothing renamed, when there's a folder of
    /// the new name.
    public func renameAmiberryROM(
        _ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard
    )
        throws
    {
        let old = ludeum.amiberrySavedDisks(ofROM: oldName)
        let new = ludeum.amiberrySavedDisks(ofROM: name)
        let files = FileManager.default
        // Differing only in case, they're the one folder.
        let sameFolder = oldName.caseInsensitiveCompare(name) == .orderedSame
        if !sameFolder, files.fileExists(atPath: new.path(percentEncoded: false)) { throw AmiberryRenameError.savedDisksInTheWay(name) }
        try renameROM(rom, to: name, in: folder)
        if files.fileExists(atPath: old.path(percentEncoded: false)) { try files.moveItem(at: old, to: new) }
    }
}
