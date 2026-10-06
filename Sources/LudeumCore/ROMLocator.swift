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
        return files.map { file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
            let path = file.standardizedFileURL.path(percentEncoded: false)
            return ROMFileInfo(
                url: file,
                name: path.hasPrefix(basePath)
                    ? String(path.dropFirst(basePath.count)).trimmingPrefix("/").description : file.lastPathComponent,
                size: values?.fileSize.map(Int64.init), created: values?.creationDate, modified: values?.contentModificationDate)
        }
    }
}

/// One file of a ROM, as Game detail lists it.
public struct ROMFileInfo: Sendable, Equatable {
    public let url: URL
    /// Its path from its ROM folder.
    public let name: String
    public let size: Int64?
    public let created: Date?
    public let modified: Date?

    /// A `.7z` or `.zip` (an Archived or Compacted ROM's, or one inside its subfolder), whose contents can be listed
    /// from its index.
    public var isArchive: Bool { ["7z", "zip"].contains(url.pathExtension.lowercased()) }
}
