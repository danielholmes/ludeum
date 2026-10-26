import Foundation
import GRDB

/// The Serials step of every Import, after Regions, and of Add ROM: each ROM on a Platform with a reader has its Discs'
/// Serials read off them once, whether or not they have any. One whose files can't be read yet is left for the next
/// Import: kept online only by Dropbox, in a form not read yet (`.chd`, `.pbp`), in a `.7z` with no 7-Zip to read it, or
/// failing to read.
struct SerialsImport {
    let journal: LudeumStore
    let sevenZip: SevenZip?

    /// Never fails the Import. With `only`, just those ROMs are read: the one Add ROM has just put in.
    func run(in folders: [ROMFolder], only romIds: [Int64]? = nil) async {
        let byPlatform = Dictionary(folders.map { ($0.platformId, $0) }, uniquingKeysWith: { a, _ in a })
        guard
            let roms = try? await journal.db.read({ db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, platformId, folderName FROM rom
                        WHERE NOT serialsLookedUp AND NOT missing AND folderName IS NOT NULL
                            AND platformId IN (\(Serials.platforms.map(String.init).joined(separator: ", ")))
                        \(romIds.map { "AND id IN (\(databaseQuestionMarks(count: $0.count)))" } ?? "")
                        ORDER BY id
                        """, arguments: StatementArguments(romIds ?? [])
                ).map { (id: $0["id"] as Int64, platformId: $0["platformId"] as Int64, name: $0["folderName"] as String) }
            })
        else { return }
        for rom in roms {
            guard !Task.isCancelled else { return }
            guard let folder = byPlatform[rom.platformId], let file = try? folder.rom(named: rom.name),
                let serials = await ROMSerials.read(file, in: folder, sevenZip: sevenZip)
            else { continue }
            // Only while it's still the ROM that was read: a relink while it was being read gives it another dump.
            _ = try? await journal.db.write { db in
                try db.execute(
                    sql: "UPDATE rom SET serials = ?, serialsLookedUp = 1 WHERE id = ? AND NOT serialsLookedUp AND folderName = ?",
                    arguments: [Serials.encode(serials), rom.id, rom.name])
            }
        }
    }
}

/// Reading a ROM's Serials off its Discs, from its ready files or inside its `.7z`.
enum ROMSerials {
    /// How much of an archived data track is unpacked at first: enough for the volume, its root directory and usually
    /// `SYSTEM.CNF`. Anything further in (Resident Evil – Director's Cut's `SYSTEM.CNF` is 660 MB in) is unpacked a
    /// `window` at a time, at most `windows` times.
    static let firstRead = 4 << 20
    static let window = 1 << 20
    static let windows = 8
    /// How much of a playlist or cue sheet is read.
    static let textRead = 1 << 20

    /// Each Disc's Serial, in Disc order, or nil when its files can't be read yet.
    static func read(_ rom: FolderROMFile, in folder: ROMFolder, sevenZip: SevenZip?) async -> [String?]? {
        let files: Files
        let main: String
        var discs: [String]
        if let ready = rom.ready {
            files = .folder
            main = ready.path(percentEncoded: false)
            discs = rom.discsWithoutPlaylist.map { $0.path(percentEncoded: false) }
        } else if let archive = rom.archive, let sevenZip, SevenZip.isOnDisk(archive),
            let entries = try? await sevenZip.contents(of: archive)
        {
            files = .archive(archive, sevenZip, sizes: Dictionary(entries.map { ($0.path, Int($0.size)) }, uniquingKeysWith: { a, _ in a }))
            let root = URL(filePath: "/", directoryHint: .isDirectory)
            guard let game = folder.game(among: entries.map { root.appending(path: $0.path, directoryHint: .notDirectory) }) else {
                return nil
            }
            func inArchive(_ url: URL) -> String { String(url.path(percentEncoded: false).dropFirst()) }
            main = inArchive(game.file)
            discs = game.discsWithoutPlaylist.map(inArchive)
        } else {
            return nil
        }
        do {
            if (main as NSString).pathExtension.lowercased() == "m3u" { discs = try await files.discs(of: main) }
            if discs.isEmpty { discs = [main] }
            var serials: [String?] = []
            for disc in discs {
                guard let track = try await dataTrack(of: disc, in: files) else { return nil }
                serials.append(try await serial(of: track, in: files))
            }
            return serials
        } catch {
            return nil
        }
    }

    /// The image a Disc's Serial is read from: a cue sheet's first track, else the Disc itself. Nil for a form not
    /// read yet.
    private static func dataTrack(of disc: String, in files: Files) async throws -> String? {
        let ext = (disc as NSString).pathExtension.lowercased()
        if Serials.unreadForms.contains(ext) { return nil }
        guard ext == "cue" else { return disc }
        return try await files.firstTrack(of: disc)
    }

    private static func serial(of track: String, in files: Files) async throws -> String? {
        switch files {
        case .folder:
            let handle = try Files.open(track)
            defer { try? handle.close() }
            return try PlayStationDisc.serial { range in
                try handle.seek(toOffset: UInt64(range.lowerBound))
                return try handle.read(upToCount: range.count) ?? Data()
            }
        case .archive(let archive, let sevenZip, let sizes):
            let size = sizes[track] ?? .max
            var read = [(start: 0, data: try await sevenZip.bytes(of: track, in: archive, count: firstRead))]
            for _ in 0...windows {
                do {
                    return try PlayStationDisc.serial { range in
                        let range = range.clamped(to: 0..<max(size, 0))
                        guard !range.isEmpty else { return Data() }
                        guard
                            let window = read.first(where: { $0.start <= range.lowerBound && range.upperBound <= $0.start + $0.data.count })
                        else { throw PlayStationDisc.NeedsMore(range: range) }
                        return window.data.subdata(in: (range.lowerBound - window.start)..<(range.upperBound - window.start))
                    }
                } catch let more as PlayStationDisc.NeedsMore {
                    guard read.count <= windows else { throw more }
                    let start = more.range.lowerBound / 2048 * 2048
                    let count = max(window, more.range.upperBound - start)
                    read.append((start, try await sevenZip.bytes(of: track, in: archive, from: start, count: count)))
                }
            }
            throw CocoaError(.fileReadUnknown)
        }
    }

    /// A file a playlist or cue sheet names, beside it.
    fileprivate static func path(_ name: String, beside file: String) -> String {
        let folder = (file as NSString).deletingLastPathComponent
        return folder.isEmpty ? name : (folder as NSString).appendingPathComponent(name)
    }

    private enum Files {
        case folder
        /// Its `.7z`, with the size of each path in it.
        case archive(URL, SevenZip, sizes: [String: Int])

        /// A playlist's Discs. In an archive, the Discs beside it in Disc order when their names number them (their cue
        /// sheets, else their images): 7-Zip packs a playlist after the images, so reading it means unpacking them all.
        func discs(of playlist: String) async throws -> [String] {
            if case .archive(_, _, let sizes) = self {
                let folder = (playlist as NSString).deletingLastPathComponent
                let beside = sizes.keys.filter { ($0 as NSString).deletingLastPathComponent == folder }
                func ext(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }
                let cues = beside.filter { ext($0) == "cue" }
                let discs = cues.isEmpty ? beside.filter { ext($0) != "m3u" } : cues
                let numbered = ROMFolder.discs(discs.map { URL(filePath: "/" + $0) })
                if !numbered.isEmpty { return numbered.map { String($0.path(percentEncoded: false).dropFirst()) } }
            }
            return ROMFiles.playlistEntries(text: try await text(of: playlist)).map { ROMSerials.path($0, beside: playlist) }
        }

        /// A cue sheet's first track, its data track. In an archive, the image named after it, or after it as Track 1,
        /// when there is one, for the same reason.
        func firstTrack(of cue: String) async throws -> String? {
            if case .archive(_, _, let sizes) = self {
                let base = (cue as NSString).deletingPathExtension.lowercased()
                let named = ["", " (track 1)", " (track 01)"].map { base + $0 + ".bin" }
                if let track = named.lazy.compactMap({ name in sizes.keys.first { $0.lowercased() == name } }).first { return track }
            }
            return ROMFolder.cueTracks(text: try await text(of: cue)).first.map { ROMSerials.path($0, beside: cue) }
        }

        /// The first MB of a playlist or cue sheet, as text.
        func text(of path: String) async throws -> String {
            let data: Data
            switch self {
            case .folder:
                let handle = try Files.open(path)
                defer { try? handle.close() }
                data = try handle.read(upToCount: textRead) ?? Data()
            case .archive(let archive, let sevenZip, _):
                data = try await sevenZip.bytes(of: path, in: archive, count: textRead)
            }
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }

        /// A ready file to read, unless Dropbox keeps it online only: reading it would download it all.
        static func open(_ path: String) throws -> FileHandle {
            let url = URL(filePath: path)
            guard SevenZip.isOnDisk(url) else { throw CocoaError(.fileReadUnknown) }
            return try FileHandle(forReadingFrom: url)
        }
    }
}
