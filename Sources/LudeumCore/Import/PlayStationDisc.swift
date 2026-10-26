import Foundation

/// A PlayStation disc's Serial, read off its data track as DuckStation reads it (`System::GetGameDetailsFromImage`), so
/// it's the name DuckStation gives the disc's per-game settings file (ADR 0021).
enum PlayStationDisc {
    /// Bytes of the image that weren't read are needed.
    struct NeedsMore: Error, Equatable {
        let range: Range<Int>
    }

    /// The executable DuckStation boots when `SYSTEM.CNF` names none.
    static let fallbackExecutable = "PSX.EXE"

    /// The disc's Serial, reading its data track through `read`, which gives the bytes in a range (fewer at the end of
    /// the image), or throws `NeedsMore` for a range it hasn't read. Nil when DuckStation would name it by a hash instead: no ISO
    /// 9660 volume, no `SYSTEM.CNF` or `BOOT` line, `PSX.EXE`, or an executable that isn't on the disc.
    static func serial(read: @escaping (Range<Int>) throws -> Data) throws -> String? {
        guard let volume = try Volume(read: read), let cnf = try volume.file("SYSTEM.CNF") else { return nil }
        let executable = executable(systemCNF: try volume.contents(of: cnf))
        guard let serial = serial(booting: executable), let found = try volume.file(executable), !found.isDirectory else { return nil }
        return serial
    }

    /// The executable `SYSTEM.CNF`'s `BOOT` line names, as a path on the disc: `SLUS_005.51` from `BOOT = cdrom:\SLUS_005.51;1`
    /// (or `cdrom:SLUS_005.51;1`), without `cdrom:`, leading slashes or `;1`, and with all whitespace dropped. `PSX.EXE`
    /// when there's no `BOOT` line.
    static func executable(systemCNF: Data) -> String {
        var lines: [(key: String, value: String)] = []
        var key = ""
        var value = ""
        var readingValue = false
        for byte in systemCNF {
            switch byte {
            case 0x0D, 0x0A:
                if !key.isEmpty { lines.append((key, value)) }
                (key, value, readingValue) = ("", "", false)
            case 0x20, 0x09...0x0D: continue
            case UInt8(ascii: "=") where !readingValue: readingValue = true
            default:
                if readingValue { value.append(Character(UnicodeScalar(byte))) } else { key.append(Character(UnicodeScalar(byte))) }
            }
        }
        if !key.isEmpty { lines.append((key, value)) }
        guard var code = lines.first(where: { $0.key.lowercased() == "boot" })?.value else { return fallbackExecutable }
        if code.hasPrefix("cdrom:") { code.removeFirst(6) }
        while code.first == "/" || code.first == "\\" { code.removeFirst() }
        if let version = code.lastIndex(of: ";") { code = String(code[..<version]) }
        return code
    }

    /// The Serial of a disc booting `executable`: its file name upper-cased, without dots and with `_` as `-`
    /// (`SLUS_005.51` is `SLUS-00551`). Nil for `PSX.EXE`.
    static func serial(booting executable: String) -> String? {
        guard executable != fallbackExecutable else { return nil }
        let name = executable.split(separator: "\\", omittingEmptySubsequences: false).last.map(String.init) ?? executable
        return String(name.filter { $0 != "." }.map { $0 == "_" ? "-" : Character($0.uppercased()) })
    }

    /// An ISO 9660 volume on a data track of 2048-byte sectors, or of raw 2352-byte ones of Mode 1 or Mode 2 Form 1.
    struct Volume {
        let read: (Range<Int>) throws -> Data
        let sectorSize: Int
        let dataOffset: Int
        let root: Entry

        struct Entry {
            let sector: Int
            let size: Int
            let isDirectory: Bool

            /// The 2048-byte sectors it takes up, at least one.
            var sectors: Range<Int> { sector..<(sector + max(1, (size + 2047) / 2048)) }
        }

        /// Nil when it's neither kind of track, or has no Primary Volume Descriptor in the 256 sectors from 16.
        init?(read: @escaping (Range<Int>) throws -> Data) throws {
            self.read = read
            let sync = Data([0] + [UInt8](repeating: 0xFF, count: 10) + [0])
            let raw = try read((16 * 2352)..<(16 * 2352 + 16))
            if raw.count == 16, raw.prefix(12) == sync, [1, 2].contains(raw[raw.startIndex + 15]) {
                (sectorSize, dataOffset) = (2352, raw[raw.startIndex + 15] == 1 ? 16 : 24)
            } else {
                (sectorSize, dataOffset) = (2048, 0)
            }
            var found: Entry?
            for lsn in 16..<(16 + 256) {
                let sector = try Self.sector(lsn, read: read, size: sectorSize, offset: dataOffset)
                guard sector.count == 2048 else { break }
                guard sector[1..<6] == Data("CD001".utf8) else { continue }
                if sector[0] == 255 { break }
                if sector[0] == 1 {
                    found = Self.entry(sector, at: 156)
                    break
                }
            }
            guard let found else { return nil }
            root = found
        }

        /// The file or directory at `path` (`\` or `/` separated), its names matched ignoring case and any `;1`.
        func file(_ path: String) throws -> Entry? {
            var current = root
            let parts = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).map { $0.lowercased() }
            guard !parts.isEmpty else { return nil }
            for (i, part) in parts.enumerated() {
                guard current.isDirectory, let next = try entries(of: current)[part] else { return nil }
                if i < parts.count - 1 && !next.isDirectory { return nil }
                current = next
            }
            return current
        }

        func contents(of file: Entry) throws -> Data {
            var data = Data()
            for lsn in file.sectors {
                data += try Self.sector(lsn, read: read, size: sectorSize, offset: dataOffset)
            }
            return data.prefix(file.size)
        }

        /// A directory's entries by lower-cased name, without `;1`.
        private func entries(of directory: Entry) throws -> [String: Entry] {
            var out: [String: Entry] = [:]
            for lsn in directory.sectors {
                let sector = [UInt8](try Self.sector(lsn, read: read, size: sectorSize, offset: dataOffset))
                guard sector.count == 2048 else { break }
                var offset = 0
                while offset + 33 < 2048 {
                    let length = Int(sector[offset])
                    guard length >= 33 else { break }
                    let nameLength = Int(sector[offset + 32])
                    if 33 + nameLength <= length, offset + 33 + nameLength <= 2048, nameLength > 1 || sector[offset + 33] > 1 {
                        let name = String(decoding: sector[(offset + 33)..<(offset + 33 + nameLength)], as: UTF8.self)
                        let base = name.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
                        if let entry = Self.entry(Data(sector), at: offset) { out[base.lowercased()] = entry }
                    }
                    offset += length
                }
            }
            return out
        }

        private static func entry(_ data: Data, at offset: Int) -> Entry? {
            let bytes = [UInt8](data)
            guard offset + 33 <= bytes.count else { return nil }
            func le(_ at: Int) -> Int { (0..<4).reduce(0) { $0 | Int(bytes[offset + at + $1]) << ($1 * 8) } }
            return Entry(sector: le(2), size: le(10), isDirectory: bytes[offset + 25] & 2 != 0)
        }

        private static func sector(_ lsn: Int, read: (Range<Int>) throws -> Data, size: Int, offset: Int) throws -> Data {
            let start = lsn * size + offset
            // Indexed from 0, whatever `read` gives.
            return Data(try read(start..<(start + 2048)))
        }
    }
}
