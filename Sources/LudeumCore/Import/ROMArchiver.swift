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

/// What an Unarchive will do, worked out from the archive's listing before anything is touched, so
/// discarded files and a rename can be confirmed first.
public struct UnarchivePlan: Sendable, Equatable {
    public let archive: URL
    public let romName: String
    /// The game: one image, or a cue sheet and its tracks.
    public let kept: [SevenZip.Entry]
    /// Everything else in the archive (a readme, say), left out of the Unarchive.
    public let discarded: [String]
    /// The image, or the cue sheet.
    public let mainFile: String

    /// The image's name doesn't match the ROM's, so as it stands it would come back as a different ROM.
    public var needsRename: Bool { (mainFile as NSString).deletingPathExtension != romName }
    /// The image named after the ROM, keeping its extension.
    public var renamedMainFile: String { "\(romName).\((mainFile as NSString).pathExtension)" }
    public var bytesNeeded: Int64 { kept.reduce(0) { $0 + $1.size } }
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

    public func planUnarchive(_ archive: URL, romName: String, in folder: ROMFolder) async throws -> UnarchivePlan {
        try Self.unarchivePlan(listing: try await sevenZip.list(archive), archive: archive, romName: romName, folder: folder)
    }

    static func unarchivePlan(listing: [SevenZip.Entry], archive: URL, romName: String, folder: ROMFolder) throws -> UnarchivePlan {
        func ext(_ e: SevenZip.Entry) -> String { (e.path as NSString).pathExtension.lowercased() }
        let images = listing.filter { folder.readyExtensions.contains(ext($0)) }
        let cues = images.filter { ext($0) == "cue" }
        let kept: [SevenZip.Entry]
        let main: SevenZip.Entry
        if cues.count == 1 {
            // A cue sheet's tracks are .bin files; another image beside it isn't part of this game.
            kept = images.filter { ["cue", "bin"].contains(ext($0)) }
            main = cues[0]
        } else if cues.isEmpty, images.count == 1 {
            kept = images
            main = images[0]
        } else if images.isEmpty {
            throw ArchiveError.noImage
        } else {
            throw ArchiveError.ambiguous(images.map(\.fileName))
        }
        // Unarchiving puts every file straight into the ROM folder, so two with one name can't both land.
        let names = kept.map(\.fileName)
        if Set(names).count != names.count { throw ArchiveError.ambiguous(names.filter { n in names.filter { $0 == n }.count > 1 }) }
        return UnarchivePlan(
            archive: archive, romName: romName, kept: kept, discarded: listing.filter { !kept.contains($0) }.map(\.fileName),
            mainFile: main.fileName)
    }

    /// Unarchives the plan's files: unpacks them, checks their sizes, moves them into the ROM folder (the image
    /// renamed after the ROM when `renaming`), then sends the archive to the Trash.
    public func unarchive(
        _ plan: UnarchivePlan, renaming: Bool, in folder: ROMFolder, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try checkSpace(plan.bytesNeeded, in: folder)
        let work = try workFolder(in: folder)
        defer { try? FileManager.default.removeItem(at: work) }
        let destinations = plan.kept.map { entry in
            folder.url.appending(path: renaming && entry.fileName == plan.mainFile ? plan.renamedMainFile : entry.fileName)
        }
        for destination in destinations where FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw ArchiveError.alreadyThere(destination.lastPathComponent)
        }
        try await sevenZip.extract(plan.archive, paths: plan.kept.map(\.path), to: work, progress: progress)
        for entry in plan.kept {
            let size = try? work.appending(path: entry.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size.map(Int64.init) == entry.size else { throw ArchiveError.checkFailed(entry.fileName) }
        }
        for (entry, destination) in zip(plan.kept, destinations) {
            try FileManager.default.moveItem(at: work.appending(path: entry.path), to: destination)
        }
        try moveToTrash(plan.archive)
    }

    // MARK: Archive

    /// Packs the ROM's ready file (a cue sheet with its tracks) into `<name>.7z` at maximum
    /// compression, tests it, moves it into the ROM folder, then sends the originals to the Trash.
    public func archive(_ name: String, in folder: ROMFolder, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let ready = try folder.readyFile(named: name) else { throw ArchiveError.nothingToDo }
        let destination = folder.url.appending(path: "\(name).7z")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw ArchiveError.alreadyThere(destination.lastPathComponent)
        }
        let tracks = ready.pathExtension.lowercased() == "cue" ? ROMFolder.cueTracks(ready) : []
        let files = [ready] + tracks.map { folder.url.appending(path: $0) }
        let sizes = try files.map { Int64(try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        try checkSpace(sizes.reduce(0, +), in: folder)
        let work = try workFolder(in: folder)
        defer { try? FileManager.default.removeItem(at: work) }
        let packed = work.appending(path: destination.lastPathComponent)
        try await sevenZip.create(packed, files: files.map(\.lastPathComponent), in: folder.url, progress: progress)
        try await sevenZip.test(packed)
        let listed = try await sevenZip.list(packed)
        guard Set(listed.map(\.fileName)) == Set(files.map(\.lastPathComponent)), listed.map(\.size).reduce(0, +) == sizes.reduce(0, +)
        else { throw ArchiveError.checkFailed(destination.lastPathComponent) }
        try FileManager.default.moveItem(at: packed, to: destination)
        for file in files { try moveToTrash(file) }
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
