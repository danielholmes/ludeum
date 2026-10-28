import Foundation

/// Moving what MesenCE kept for itself over to the copy Ludeum installs (ADR 0027), run by hand once through
/// `ludeum-import mesence` with MesenCE closed, then deleted: each Save state, Game save and screenshot in its own
/// folder goes into the Platform folder of the one MesenCE Platform with a ROM of its name, its Firmware into the
/// installed copy, and each MesenCE `.7z` whose file inside has another name gets the archive's, its saves following.
/// Nothing is overwritten: a file already there, or one it can't place, is left where it is and listed.
public struct MesenMigration: Sendable {
    let ludeum: LudeumFolder
    /// MesenCE's own data folder, where it kept everything before it was portable.
    let old: URL
    let sevenZip: SevenZip

    public init(
        ludeum: LudeumFolder = .standard,
        old: URL = URL.applicationSupportDirectory.appending(path: "MesenCE", directoryHint: .isDirectory),
        sevenZip: SevenZip
    ) {
        self.ludeum = ludeum
        self.old = old
        self.sevenZip = sevenZip
    }

    /// A MesenCE ROM: its Platform, its name in its ROM folder, and the name MesenCE keeps it by, or for one Dropbox
    /// keeps online only (not read, as that would download it) its own name, so a name it might have still counts.
    struct KnownROM: Sendable, Equatable {
        let platformId: Int64
        let romName: String
        let mesenName: String
        /// Its archive and the path of its file inside, when MesenCE names it by a file inside one.
        let archive: URL?
        let inArchive: String?
    }

    /// An archive whose file inside takes the archive's name, its saves following.
    public struct InnerRename: Sendable {
        public let archive: URL
        public let platformId: Int64
        /// The file's path inside, and MesenCE's name for it before and after.
        public let path: String
        public let from: String
        public let to: String
    }

    public struct Plan: Sendable {
        /// Files to move, each into its Platform's folder.
        public var moves: [(from: URL, to: URL)] = []
        /// Files to copy into the installed MesenCE's Firmware.
        public var firmware: [(from: URL, to: URL)] = []
        public var innerRenames: [InnerRename] = []
        /// What's left as it is, and why.
        public var left: [(file: String, why: String)] = []
        /// ROMs that couldn't be read, being kept online only by Dropbox.
        public var unread: [String] = []
    }

    /// The MesenCE Platforms' ROMs.
    func knownROMs(into plan: inout Plan) async throws -> [KnownROM] {
        var known: [KnownROM] = []
        for folder in ludeum.romFolders where Emulator.of(platformId: folder.platformId) == .mesenCE {
            guard FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)) else { continue }
            for rom in try folder.scan() {
                guard let ready = rom.ready else { continue }
                guard SevenZip.isOnDisk(ready) else {
                    plan.unread.append(ready.lastPathComponent)
                    known.append(
                        KnownROM(platformId: folder.platformId, romName: rom.name, mesenName: rom.name, archive: nil, inArchive: nil))
                    continue
                }
                guard let name = await MesenROMName.of(ready, platformId: folder.platformId, sevenZip: sevenZip) else { continue }
                known.append(
                    KnownROM(
                        platformId: folder.platformId, romName: rom.name, mesenName: name.name,
                        archive: name.inArchive == nil ? nil : ready, inArchive: name.inArchive))
            }
        }
        return known
    }

    public func plan() async throws -> Plan {
        var plan = Plan()
        let known = try await knownROMs(into: &plan)
        let files = FileManager.default
        for (oldFolder, folder) in [("SaveStates", MesenFolder.saveStates), ("Saves", .saves), ("Screenshots", .screenshots)] {
            let source = old.appending(path: oldFolder, directoryHint: .isDirectory)
            for name in ((try? files.contentsOfDirectory(atPath: source.path(percentEncoded: false))) ?? []).sorted()
            where !name.hasPrefix(".") {
                let file = source.appending(path: name)
                let stem = (name as NSString).deletingPathExtension
                var matches = known.filter { rom in
                    switch folder {
                    case .saves: name.hasPrefix(rom.mesenName + ".")
                    case .saveStates: MesenSaveStates.slot(stem, of: rom.mesenName) != nil
                    case .screenshots: MesenSaveStates.isScreenshot(stem, of: rom.mesenName)
                    }
                }
                // The longest name, should one begin another's: "Foo" and "Foo (USA)" for "Foo (USA).srm".
                if let longest = matches.map(\.mesenName.count).max() { matches = matches.filter { $0.mesenName.count == longest } }
                // A state says which console it's from.
                if folder == .saveStates, let console = (try? Data(contentsOf: file)).flatMap(MesenStateHeader.init)?.console {
                    matches = matches.filter { console.platforms.contains($0.platformId) }
                }
                let platforms = Set(matches.map(\.platformId))
                guard platforms.count == 1, let platform = platforms.first, let target = ludeum.mesen(folder, platform: platform) else {
                    plan.left.append(
                        (name, platforms.isEmpty ? "no MesenCE ROM has its name" : "ROMs of its name are on more than one Platform"))
                    continue
                }
                let to = target.appending(path: name)
                if files.fileExists(atPath: to.path(percentEncoded: false)) {
                    plan.left.append((name, "one of its name is already in the Data folder"))
                    continue
                }
                plan.moves.append((file, to))
            }
        }
        let firmware = old.appending(path: "Firmware", directoryHint: .isDirectory)
        let installedFirmware = MesenSettings(ludeum: ludeum).dataFolder.appending(path: "Firmware", directoryHint: .isDirectory)
        for name in ((try? files.contentsOfDirectory(atPath: firmware.path(percentEncoded: false))) ?? []).sorted()
        where !name.hasPrefix(".") {
            let to = installedFirmware.appending(path: name)
            if files.fileExists(atPath: to.path(percentEncoded: false)) { continue }
            plan.firmware.append((firmware.appending(path: name), to))
        }
        for rom in known {
            guard let archive = rom.archive, let path = rom.inArchive, rom.mesenName != rom.romName else { continue }
            plan.innerRenames.append(
                InnerRename(archive: archive, platformId: rom.platformId, path: path, from: rom.mesenName, to: rom.romName))
        }
        return plan
    }

    /// Carries out `plan`: the moves and Firmware first, then the archives' files inside, each one's saves following it
    /// unless one of the new name is already there, when that archive is left and listed.
    public func run(_ plan: Plan) async throws -> [(file: String, why: String)] {
        let files = FileManager.default
        var left: [(file: String, why: String)] = []
        for move in plan.moves {
            try files.createDirectory(at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.moveItem(at: move.from, to: move.to)
        }
        for copy in plan.firmware {
            try files.createDirectory(at: copy.to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: copy.from, to: copy.to)
        }
        for rename in plan.innerRenames {
            guard let saves = MesenSaveStates(ludeum: ludeum, platformId: rename.platformId) else { continue }
            if let taken = saves.files(of: rename.to).first {
                left.append((rename.archive.lastPathComponent, "MesenCE already keeps \(taken.lastPathComponent) under its name"))
                continue
            }
            try await sevenZip.rename(rename.path, to: MesenROMName.path(rename.path, renamedTo: rename.to), in: rename.archive)
            try saves.move(rename.from, to: rename.to)
        }
        return left
    }
}
