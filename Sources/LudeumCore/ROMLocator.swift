import Foundation

/// Where a ROM's files are on disk: in OpenEmu's library, or in its Platform's ROM folder.
public struct ROMLocator: Sendable {
    public let openEmuLibrary: URL
    public let romFolders: [ROMFolder]

    public init(openEmuLibrary: URL, romFolders: [ROMFolder]) {
        self.openEmuLibrary = openEmuLibrary
        self.romFolders = romFolders
    }

    /// The ROM folder a ROM lives in; nil for an OpenEmu ROM, or when its folder isn't set.
    public func folder(of rom: LudeumROM) -> ROMFolder? {
        guard rom.folderName != nil else { return nil }
        return romFolders.first { $0.systemId == rom.systemId }
    }

    /// The ROM's file. `ready` asks for the file a Play opens, so an archived ROM has none.
    public func file(of rom: LudeumROM, ready: Bool = false) throws -> URL? {
        if let pk = rom.openEmuPk { return try OpenEmuLibrary.romFile(library: openEmuLibrary, openEmuPk: pk) }
        guard let name = rom.folderName, let folder = folder(of: rom) else { return nil }
        if ready { return try folder.readyFile(named: name) }
        let file = folder.url.appending(path: rom.fileName)
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    /// Every file of the ROM, the file a Play opens first. Empty when it can't be found.
    public func files(of rom: LudeumROM) -> [ROMFileInfo] {
        let files: [URL]
        let base: URL
        if let pk = rom.openEmuPk {
            guard let main = try? OpenEmuLibrary.romFile(library: openEmuLibrary, openEmuPk: pk) else { return [] }
            files = ROMFiles.files(of: main)
            base = main.deletingLastPathComponent()
        } else if let name = rom.folderName, let folder = folder(of: rom) {
            files = (try? folder.files(named: name)) ?? []
            base = folder.url
        } else {
            return []
        }
        let basePath = base.standardizedFileURL.path(percentEncoded: false)
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
    /// Its path from the ROM's own folder (the ROM folder, or the folder OpenEmu keeps it in).
    public let name: String
    public let size: Int64?
    public let created: Date?
    public let modified: Date?
}
