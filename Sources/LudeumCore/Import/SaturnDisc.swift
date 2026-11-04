import Foundation

/// A Saturn disc's header, at the start of its first sector, read as Ymir reads it (`SaturnHeader::ReadFrom`): the
/// Product Number that's its Serial, which Ymir's `meta.txt` and per-Game backup RAM images name it by (ADR 0036), and
/// the peripherals it says it works with.
enum SaturnDisc {
    struct Header: Equatable {
        /// `MK-81802`. Empty on a disc that has none.
        let productNumber: String
        /// A letter for each peripheral it works with: `JEG` is the Control Pad, the 3D Control Pad and the Virtua Gun.
        let peripherals: String

        /// It's played with a light gun.
        var takesVirtuaGun: Bool { peripherals.contains("G") }
    }

    /// What a Saturn disc's first 16 bytes say.
    private static let hardwareID = "SEGA SEGASATURN"
    private static let headerSize = 256
    private static let rawSectorSync = Data([0] + [UInt8](repeating: 0xFF, count: 10) + [0])

    /// The header of an image's first sector through `read`, which gives the bytes in a range (fewer at the end of the
    /// image). The sector is 2048 bytes, or raw (2352) of Mode 1 or Mode 2 Form 1. Nil when it isn't a Saturn disc.
    static func header(read: (Range<Int>) throws -> Data) throws -> Header? {
        let start = Data(try read(0..<16))
        var offset = 0
        if start.count == 16, start.prefix(12) == rawSectorSync, [1, 2].contains(start[15]) {
            offset = start[15] == 1 ? 16 : 24
        }
        let header = Data(try read(offset..<(offset + headerSize)))
        guard header.count == headerSize, text(header, 0x00...0x0F) == hardwareID else { return nil }
        return Header(productNumber: text(header, 0x20...0x29), peripherals: text(header, 0x50...0x5F))
    }

    /// The disc's Serial, its Product Number. Nil when it has none or it isn't a Saturn disc.
    static func serial(read: @escaping (Range<Int>) throws -> Data) throws -> String? {
        guard let number = try header(read: read)?.productNumber, !number.isEmpty else { return nil }
        return number
    }

    /// The header of the Disc a Play opens: a cue sheet's first track, or an `.iso`. Nil for a form not read yet (`.chd`),
    /// one that can't be read, or one Dropbox keeps online only, as reading it would stall Play while it all downloads.
    static func header(of disc: URL) -> Header? {
        let image: URL
        switch disc.pathExtension.lowercased() {
        case "cue":
            guard let track = ROMFolder.cueTracks(disc).first else { return nil }
            image = disc.deletingLastPathComponent().appending(path: track)
        case "iso": image = disc
        default: return nil
        }
        guard SevenZip.isOnDisk(image), let handle = try? FileHandle(forReadingFrom: image) else { return nil }
        defer { try? handle.close() }
        return try? header { range in
            try handle.seek(toOffset: UInt64(range.lowerBound))
            return try handle.read(upToCount: range.count) ?? Data()
        }
    }

    /// The bytes as Ymir reads a header's text: a NUL counts as a space, and the ends are trimmed.
    private static func text(_ data: Data, _ range: ClosedRange<Int>) -> String {
        String(decoding: data[range].map { $0 == 0 ? UInt8(ascii: " ") : $0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
