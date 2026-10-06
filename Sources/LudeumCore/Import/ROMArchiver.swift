import Foundation

public enum ArchiveError: Error, Equatable {
    /// 7-Zip's `7zz` isn't installed.
    case noSevenZip
    /// Several images and no cue sheet: which is the game isn't clear.
    case ambiguous([String])
    /// Nothing in the archive is a file the Emulator opens.
    case noImage
    case notEnoughSpace(needed: Int64)
    /// The ROM has no file to Archive, or no archive to Unarchive.
    case nothingToDo
    /// A file with the new file's name is already in the ROM folder.
    case alreadyThere(String)
    /// What was written doesn't match what it should be, so the original is kept.
    case checkFailed(String)
    case sevenZipFailed(String)
}

extension ArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noSevenZip: "7-Zip isn't installed. Run `brew install sevenzip`, then try again."
        case .ambiguous(let images): "Several images and no cue sheet: \(images.joined(separator: ", "))."
        case .noImage: "Nothing in the archive is a game image."
        case .notEnoughSpace(let needed):
            "Needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) free."
        case .nothingToDo: "There's no file to work on. Check again, then try again."
        case .alreadyThere(let name): "\(name) is already in the ROM folder."
        case .checkFailed(let name): "\(name) didn't check out, so the original is kept."
        case .sevenZipFailed(let message): "7-Zip failed: \(message)"
        }
    }
}

/// What an Unarchive will do, worked out from the archive's listing before anything is touched.
public struct UnarchivePlan: Sendable, Equatable {
    public let archive: URL
    public let romName: String
    /// Everything in the archive, all of it kept.
    public let entries: [SevenZip.Entry]
    /// The ROM's folder, named after it, that the archive's contents go into.
    public let destination: URL

    public var bytesNeeded: Int64 { entries.reduce(0) { $0 + $1.size } }
}

/// Archive and Unarchive for a ROM folder's ROMs. Work happens in a hidden folder inside the ROM
/// folder (on the same disk, and ignored as a subfolder) and moves into place only once checked;
/// the file it replaces goes to the Trash last of all.
public struct ROMArchiver: Sendable {
    let sevenZip: SevenZip
    let freeSpace: @Sendable (URL) -> Int64?
    let moveToTrash: @Sendable (URL) throws -> Void

    static let workFolderName = ".ludeum-work"

    public init(
        sevenZip: SevenZip,
        freeSpace: @escaping @Sendable (URL) -> Int64? = ROMArchiver.availableSpace,
        moveToTrash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.sevenZip = sevenZip
        self.freeSpace = freeSpace
        self.moveToTrash = moveToTrash
    }

    /// With Homebrew's `7zz`; throws when it isn't installed.
    public static func installed() throws -> ROMArchiver {
        guard let sevenZip = SevenZip.find() else { throw ArchiveError.noSevenZip }
        return ROMArchiver(sevenZip: sevenZip)
    }

    public static func availableSpace(_ url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    /// Removes what an interrupted Archive or Unarchive left behind. Its originals were never touched.
    public static func cleanUp(_ folder: ROMFolder) {
        try? FileManager.default.removeItem(at: folder.url.appending(path: workFolderName, directoryHint: .isDirectory))
    }

    // MARK: Unarchive

    static func unarchivePlan(listing: [SevenZip.Entry], archive: URL, romName: String, folder: ROMFolder) throws -> UnarchivePlan {
        // The folder only plays if it holds the game: one cue sheet, or one image.
        let images = listing.filter { folder.readyExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
        let cues = images.filter { ($0.path as NSString).pathExtension.lowercased() == "cue" }
        if images.isEmpty { throw ArchiveError.noImage }
        if cues.count > 1 || (cues.isEmpty && images.count > 1) { throw ArchiveError.ambiguous(images.map(\.fileName)) }
        return UnarchivePlan(
            archive: archive, romName: romName, entries: listing,
            destination: folder.url.appending(path: romName, directoryHint: .isDirectory))
    }

    /// Unarchives everything in the archive into a folder named after the ROM, checks every file's
    /// size against the listing, then sends the archive to the Trash.
    public func unarchive(
        _ archive: URL, romName: String, in folder: ROMFolder, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let plan = try Self.unarchivePlan(listing: try await sevenZip.list(archive), archive: archive, romName: romName, folder: folder)
        if FileManager.default.fileExists(atPath: plan.destination.path(percentEncoded: false)) {
            throw ArchiveError.alreadyThere(romName)
        }
        try checkSpace(plan.bytesNeeded, in: folder)
        let work = try workFolder(in: folder)
        defer { try? FileManager.default.removeItem(at: work) }
        let unpacked = work.appending(path: romName, directoryHint: .isDirectory)
        try await sevenZip.extract(archive, paths: [], to: unpacked, progress: progress)
        for entry in plan.entries {
            let size = try? unpacked.appending(path: entry.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size.map(Int64.init) == entry.size else { throw ArchiveError.checkFailed(entry.fileName) }
        }
        try FileManager.default.moveItem(at: unpacked, to: plan.destination)
        try moveToTrash(archive)
    }

    // MARK: Archive

    /// Packs the ROM into `<name>.7z` at maximum compression: its folder's contents, or a loose
    /// file (a cue sheet with its tracks). Tests the archive and checks its listing, moves it into the
    /// ROM folder, then sends what it packed to the Trash.
    public func archive(_ name: String, in folder: ROMFolder, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let ready = try folder.readyFile(named: name) else { throw ArchiveError.nothingToDo }
        let destination = folder.url.appending(path: "\(name).7z")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw ArchiveError.alreadyThere(destination.lastPathComponent)
        }
        let romFolder = folder.url.appending(path: name, directoryHint: .isDirectory)
        let packing: (root: URL, items: [String], trash: [URL])
        if (try? romFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            packing = (romFolder, try FileManager.default.contentsOfDirectory(atPath: romFolder.path(percentEncoded: false)), [romFolder])
        } else {
            let tracks = ready.pathExtension.lowercased() == "cue" ? ROMFolder.cueTracks(ready) : []
            let names = [ready.lastPathComponent] + tracks
            packing = (folder.url, names, names.map { folder.url.appending(path: $0) })
        }
        let sizes = try Self.fileSizes(packing.items.map { packing.root.appending(path: $0) })
        try checkSpace(sizes.values.reduce(0, +), in: folder)
        let work = try workFolder(in: folder)
        defer { try? FileManager.default.removeItem(at: work) }
        let packed = work.appending(path: destination.lastPathComponent)
        try await sevenZip.create(packed, files: packing.items, in: packing.root, progress: progress)
        try await sevenZip.test(packed)
        let listed = try await sevenZip.list(packed)
        guard listed.count == sizes.count, listed.map(\.size).reduce(0, +) == sizes.values.reduce(0, +) else {
            throw ArchiveError.checkFailed(destination.lastPathComponent)
        }
        try FileManager.default.moveItem(at: packed, to: destination)
        for item in packing.trash { try moveToTrash(item) }
    }

    /// Every file's size, looking inside folders.
    private static func fileSizes(_ items: [URL]) throws -> [URL: Int64] {
        var sizes: [URL: Int64] = [:]
        for item in items {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                for path in try FileManager.default.subpathsOfDirectory(atPath: item.path(percentEncoded: false)) {
                    let file = item.appending(path: path)
                    if let size = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]).fileSize,
                        (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    {
                        sizes[file] = Int64(size)
                    }
                }
            } else {
                sizes[item] = Int64(try item.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        return sizes
    }

    // MARK: -

    private func checkSpace(_ needed: Int64, in folder: ROMFolder) throws {
        if let free = freeSpace(folder.url), free < needed { throw ArchiveError.notEnoughSpace(needed: needed) }
    }

    private func workFolder(in folder: ROMFolder) throws -> URL {
        let url = folder.url.appending(path: Self.workFolderName, directoryHint: .isDirectory).appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
