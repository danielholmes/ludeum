import Foundation

/// A tiny ISO 9660 disc image, as a PlayStation disc's data track is laid out: the Primary Volume Descriptor at sector
/// 16, the root directory at 18, then each file (and each subdirectory) in sectors of its own.
struct FakeDisc {
    enum Sectors {
        /// 2048-byte sectors, as an `.iso` has them.
        case cooked
        /// 2352-byte raw sectors of `mode` 1 or 2 (Form 1), as a Redump `.bin` has them.
        case raw(mode: UInt8)
    }

    /// Files by path from the root, `\`-separated: `SYSTEM.CNF`, `SLUS_005.51`, `DATA\GAME.EXE`.
    var files: [String: Data]

    init(_ files: [String: String]) {
        self.files = files.mapValues { Data($0.utf8) }
    }

    /// A disc booting `executable` (`cdrom:\SLUS_005.51;1`, say) with that file on it.
    static func booting(_ boot: String, executable: String? = nil) -> FakeDisc {
        var files = ["SYSTEM.CNF": "BOOT = \(boot)\r\nTCB = 4\r\nEVENT = 10\r\nSTACK = 801FFFF0\r\n"]
        if let executable { files[executable] = "PS-X EXE" }
        return FakeDisc(files)
    }

    func image(_ sectors: Sectors = .raw(mode: 2)) -> Data {
        var data: [[UInt8]] = Array(repeating: [UInt8](repeating: 0, count: 2048), count: 16)
        // Directories first, each a sector, then the files: every path's place is known before any record is written.
        let directories = Set(
            files.keys.flatMap { path in
                let parts = path.split(separator: "\\").dropLast()
                return parts.indices.map { parts[...($0)].joined(separator: "\\") }
            }
        ).sorted()
        var lba: [String: Int] = ["": 18]
        var next = 19
        for directory in directories {
            lba[directory] = next
            next += 1
        }
        for path in files.keys.sorted() {
            lba[path] = next
            next += max(1, (files[path]!.count + 2047) / 2048)
        }
        func record(_ name: [UInt8], at sector: Int, size: Int, directory: Bool) -> [UInt8] {
            var r = [UInt8](repeating: 0, count: 33)
            r[2...5] = ArraySlice(le(sector))
            r[6...9] = ArraySlice(le(sector).reversed())
            r[10...13] = ArraySlice(le(size))
            r[14...17] = ArraySlice(le(size).reversed())
            r[25] = directory ? 2 : 0
            r[28] = 1
            r[31] = 1
            r[32] = UInt8(name.count)
            r += name
            if r.count % 2 == 1 { r.append(0) }
            r[0] = UInt8(r.count)
            return r
        }
        func listing(of directory: String) -> [UInt8] {
            var out = record([0], at: lba[directory]!, size: 2048, directory: true) + record([1], at: 18, size: 2048, directory: true)
            let prefix = directory.isEmpty ? "" : directory + "\\"
            for sub in directories where sub.hasPrefix(prefix) && !sub.dropFirst(prefix.count).contains("\\") {
                out += record(Array(sub.dropFirst(prefix.count).utf8), at: lba[sub]!, size: 2048, directory: true)
            }
            for path in files.keys.sorted() where path.hasPrefix(prefix) && !path.dropFirst(prefix.count).contains("\\") {
                out += record(Array((path.dropFirst(prefix.count) + ";1").utf8), at: lba[path]!, size: files[path]!.count, directory: false)
            }
            return out
        }
        var pvd = [UInt8](repeating: 0, count: 2048)
        pvd[0] = 1
        pvd[1...5] = ArraySlice("CD001".utf8)
        pvd[6] = 1
        let root = record([0], at: 18, size: 2048, directory: true)
        pvd[156..<(156 + root.count)] = ArraySlice(root)
        var terminator = [UInt8](repeating: 0, count: 2048)
        terminator[0] = 255
        terminator[1...5] = ArraySlice("CD001".utf8)
        data += [pvd, terminator, padded(listing(of: ""))]
        for directory in directories { data.append(padded(listing(of: directory))) }
        for path in files.keys.sorted() {
            let bytes = [UInt8](files[path]!)
            for start in stride(from: 0, to: max(bytes.count, 1), by: 2048) {
                data.append(padded(Array(bytes[start..<min(start + 2048, bytes.count)])))
            }
        }
        switch sectors {
        case .cooked: return Data(data.joined())
        case .raw(let mode):
            return Data(
                data.map { sector -> [UInt8] in
                    let header: [UInt8] = [0] + [UInt8](repeating: 0xFF, count: 10) + [0, 0, 2, 0, mode]
                    let raw = header + (mode == 2 ? [UInt8](repeating: 0, count: 8) : []) + sector
                    return raw + [UInt8](repeating: 0, count: 2352 - raw.count)
                }.joined())
        }
    }

    private func le(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
    private func padded(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: 2048 - bytes.count) }
}
