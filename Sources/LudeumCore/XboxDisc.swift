import Foundation

/// What an Xbox disc image holds, which its name can't say: xemu boots only an XISO.
public enum XboxDisc: Sendable, Equatable {
    /// The game partition alone, as xemu needs.
    case xiso
    /// A full Redump image: the video partition, then the game partition 387 MiB in.
    case redump
    /// Neither, or it couldn't be read.
    case unknown

    /// How far into the game partition its media header is, which is the start of an XISO.
    private static let headerOffset: UInt64 = 0x10000
    /// How far into a Redump image its game partition is: 387 MiB, after the video partition.
    private static let redumpGamePartition: UInt64 = 0x1830_0000
    private static let magic = Data("MICROSOFT*XBOX*MEDIA".utf8)

    /// Reads the media header where each kind has it: a few bytes, not the image. Unknown for a file kept online only,
    /// as reading it would download it all.
    public static func kind(of file: URL) -> XboxDisc {
        guard SevenZip.isOnDisk(file), let handle = try? FileHandle(forReadingFrom: file) else { return .unknown }
        defer { try? handle.close() }
        func hasHeader(at offset: UInt64) -> Bool {
            (try? handle.seek(toOffset: offset)) != nil && (try? handle.read(upToCount: magic.count)) == magic
        }
        if hasHeader(at: headerOffset) { return .xiso }
        if hasHeader(at: redumpGamePartition + headerOffset) { return .redump }
        return .unknown
    }
}
