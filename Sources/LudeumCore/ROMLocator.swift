import Foundation

/// Where a ROM's files are on disk: in its Platform's ROM folder.
public struct ROMLocator: Sendable {
    public let romFolders: [ROMFolder]

    public init(romFolders: [ROMFolder]) {
        self.romFolders = romFolders
    }

    /// The ROM folder a ROM lives in; nil when its Platform has none.
    public func folder(of rom: LudeumROM) -> ROMFolder? {
        romFolders.first { $0.platformId == rom.platformId }
    }

    /// The ROM's file. `ready` asks for the file a Play opens, so an archived ROM has none.
    public func file(of rom: LudeumROM, ready: Bool = false) throws -> URL? {
        guard let folder = folder(of: rom) else { return nil }
        if ready { return try folder.readyFile(named: rom.folderName) }
        let file = folder.url.appending(path: rom.fileName)
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    /// Every file of the ROM, the file a Play opens first. Empty when it can't be found.
    public func files(of rom: LudeumROM) -> [ROMFileInfo] {
        guard let folder = folder(of: rom) else { return [] }
        let files = (try? folder.files(named: rom.folderName)) ?? []
        let basePath = folder.url.standardizedFileURL.path(percentEncoded: false)
        let subfolderPath = folder.url.appending(path: rom.folderName, directoryHint: .isDirectory).standardizedFileURL
            .path(percentEncoded: false)
        // Inside its subfolder, from there; anything beside it (its `.7z`), from the ROM folder.
        func name(of file: URL) -> String {
            let path = file.standardizedFileURL.path(percentEncoded: false)
            guard let base = [subfolderPath, basePath].first(where: path.hasPrefix) else { return file.lastPathComponent }
            return String(path.dropFirst(base.count)).trimmingPrefix("/").description
        }
        return files.map { file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
            return ROMFileInfo(
                url: file, name: name(of: file),
                size: values?.fileSize.map(Int64.init), created: values?.creationDate, modified: values?.contentModificationDate)
        }
    }
}

/// One file of a ROM, as Game detail lists it.
public struct ROMFileInfo: Sendable, Equatable {
    public let url: URL
    /// Its path from its ROM's subfolder, if it's inside it, else from its ROM folder.
    public let name: String
    public let size: Int64?
    public let created: Date?
    public let modified: Date?

    /// A `.7z` or `.zip` (an Archived or Compacted ROM's, or one inside its subfolder), whose contents can be listed
    /// from its index.
    public var isArchive: Bool { ["7z", "zip"].contains(url.pathExtension.lowercased()) }
}
