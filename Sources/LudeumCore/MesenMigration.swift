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

    /// A MesenCE ROM: its Platform, and the name MesenCE keeps it by.
    struct KnownROM: Sendable, Equatable {
        let platformId: Int64
        let name: MesenROMName
        let archive: URL?
        /// Its name in its ROM folder.
        let romName: String
    }

    public struct Plan: Sendable {
        /// Files to move, each into its Platform's folder.
        public var moves: [(from: URL, to: URL)] = []
        /// Files to copy into the installed MesenCE's Firmware.
        public var firmware: [(from: URL, to: URL)] = []
        /// Archives whose file inside takes the archive's name: the archive, the file's path inside and its new path,
        /// with MesenCE's old and new names for it.
        public var innerRenames: [(archive: URL, path: String, to: String, platformId: Int64, from: String, name: String)] = []
        /// What's left as it is, and why.
        public var left: [(file: String, why: String)] = []
        /// ROMs that couldn't be read, being kept online only by Dropbox.
        public var unread: [String] = []
    }

    /// The MesenCE Platforms' ROMs, by the name MesenCE keeps each by. Archives Dropbox keeps online only aren't read.
    func knownROMs(into plan: inout Plan) async throws -> [KnownROM] {
        var known: [KnownROM] = []
        for folder in ludeum.romFolders where Emulator.of(platformId: folder.platformId) == .mesenCE {
            guard FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)) else { continue }
            for rom in try folder.scan() {
                guard let ready = rom.ready else { continue }
                if !SevenZip.isOnDisk(ready) {
                    plan.unread.append(ready.lastPathComponent)
                    continue
                }
                guard let name = await MesenROMName.of(ready, platformId: folder.platformId, sevenZip: sevenZip) else { continue }
                let archive = name.inArchive == nil ? nil : ready
                known.append(KnownROM(platformId: folder.platformId, name: name, archive: archive, romName: rom.name))
            }
        }
        return known
    }

    /// The Platforms each MesenCE console's states come from (`ConsoleType`).
    static let consoles: [Int: Set<Int64>] = [0: [19, 58], 1: [33, 22], 2: [18, 99], 3: [86, 150], 4: [64, 35], 5: [24]]

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
                    case .saves: name.hasPrefix(rom.name.name + ".")
                    case .saveStates: MesenSaveStates.slot(stem, of: rom.name.name) != nil
                    case .screenshots: MesenSaveStates.isScreenshot(stem, of: rom.name.name)
                    }
                }
                // The longest name, should one begin another's: "Foo" and "Foo (USA)" for "Foo (USA).srm".
                if let longest = matches.map(\.name.name.count).max() { matches = matches.filter { $0.name.name.count == longest } }
                // A state says which console it's from.
                if folder == .saveStates, let data = try? Data(contentsOf: file), let console = Self.console(inState: data),
                    let platforms = Self.consoles[console]
                {
                    matches = matches.filter { platforms.contains($0.platformId) }
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
            guard let archive = rom.archive, let inside = rom.name.inArchive, rom.name.name != rom.romName else { continue }
            let renamed = ((inside as NSString).deletingLastPathComponent as NSString).appendingPathComponent(
                rom.romName + "." + (inside as NSString).pathExtension)
            plan.innerRenames.append((archive, inside, renamed, rom.platformId, rom.name.name, rom.romName))
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
            if let taken = saves.files(of: rename.name).first {
                left.append((rename.archive.lastPathComponent, "MesenCE already keeps \(taken.lastPathComponent) under its name"))
                continue
            }
            try await sevenZip.rename(rename.path, to: rename.to, in: rename.archive)
            for file in saves.files(of: rename.from) {
                let rest = file.lastPathComponent.dropFirst(rename.from.count)
                try files.moveItem(at: file, to: file.deletingLastPathComponent().appending(path: rename.name + rest))
            }
        }
        return left
    }

    /// The console a state was saved on (`ConsoleType`), from its header.
    static func console(inState data: Data) -> Int? {
        guard data.count >= 15, data.prefix(3) == Data("MSS".utf8) else { return nil }
        func u32(_ offset: Int) -> Int {
            let start = data.startIndex + offset
            return Int(data[start..<start + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }
        let format = u32(7)
        let at = format <= 3 ? 51 : 11
        return data.count >= at + 4 ? u32(at) : nil
    }
}
