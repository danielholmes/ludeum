import CryptoKit
import Foundation

/// What Hasheous looks a ROM up by (ADR 0004): the MD5 of its file as the DATs have it (No-Intro, Redump), or, for a ROM
/// in a `.7z` or `.zip`, the CRC32 the archive's index already holds, so nothing is unpacked.
public enum ROMChecksum: Sendable, Equatable {
    case md5(String)
    case crc(String)

    public var md5: String? { if case .md5(let hash) = self { hash } else { nil } }
    public var crc: String? { if case .crc(let hash) = self { hash } else { nil } }

    /// Images no DAT has a hash for, since they're compressed or reworked from the dump, and the playlists and cue sheets
    /// that only point at the dump.
    static let notDumps: Set<String> = ["chd", "rvz", "wia", "cso", "zso", "gz", "gcz", "wbfs", "ciso", "pbp", "m3u", "cue"]

    /// The ROM's checksum, from its ready file else its archive. Nil when it has none to give: an image no DAT knows,
    /// a file Dropbox keeps online-only (reading it would download it all), an archive with no 7-Zip to read it, or
    /// a file that can't be read. A large disc image takes seconds; cancelling stops it, giving nil.
    static func of(_ rom: FolderROMFile, platformId: Int64, sevenZip: SevenZip?) async -> ROMChecksum? {
        guard let file = rom.ready ?? rom.archive, SevenZip.isOnDisk(file) else { return nil }
        if ["7z", "zip"].contains(file.pathExtension.lowercased()) {
            guard let sevenZip, let entries = try? await sevenZip.contents(of: file) else { return nil }
            return crc(of: entries).map(ROMChecksum.crc)
        }
        guard let dump = dump(of: file), SevenZip.isOnDisk(dump),
            let hash = try? md5(of: dump, skipping: headerLength(of: dump, platformId: platformId))
        else { return nil }
        return .md5(hash)
    }

    /// The file a DAT hashes for a ready file: a playlist's first Disc, a cue sheet's first track (the data track),
    /// else the file itself. Nil for an image no DAT knows.
    static func dump(of file: URL) -> URL? {
        let folder = file.deletingLastPathComponent()
        switch file.pathExtension.lowercased() {
        case "m3u": return ROMFiles.playlistEntries(file).first.flatMap { dump(of: folder.appending(path: $0)) }
        case "cue": return ROMFolder.cueTracks(file).first.flatMap { dump(of: folder.appending(path: $0)) }
        default:
            let exists = FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
            return exists && !notDumps.contains(file.pathExtension.lowercased()) ? file : nil
        }
    }

    /// The CRC32 of the archive's dump: its largest file a DAT knows, which for a cue sheet and its tracks is the data
    /// track, and for a multi-disc archive one of its Discs, each of which Hasheous knows as the same game.
    static func crc(of entries: [SevenZip.Entry]) -> String? {
        entries.filter { !notDumps.contains(($0.path as NSString).pathExtension.lowercased()) }.max { $0.size < $1.size }?.crc
    }

    /// The bytes a dumper or copier put before the ROM, which the DATs leave out: an iNES or FDS header (16 bytes), or
    /// on the SNES and Super Famicom a copier header (512 bytes, leaving the size a multiple of 1 KB without it).
    static func headerLength(of file: URL, platformId: Int64) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 4) ?? Data()
        if magic == Data("NES\u{1A}".utf8) || magic == Data("FDS\u{1A}".utf8) { return 16 }
        let size = try handle.seekToEnd()
        if [19, 58].contains(platformId), size % 1024 == 512 { return 512 }
        return 0
    }

    static func md5(of file: URL, skipping header: UInt64 = 0) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: header)
        var hash = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
