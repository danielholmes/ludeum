import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct SaveStatesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "save states \(UUID().uuidString)", directoryHint: .isDirectory)
    var duckStation: URL { root.appending(path: "DuckStation/savestates", directoryHint: .isDirectory) }
    var data: URL { root.appending(path: "Data", directoryHint: .isDirectory) }
    var states: DuckStationSaveStates {
        DuckStationSaveStates(folder: duckStation, backup: data.appending(path: "Emulators/DuckStation/Save States"), data: data)
    }

    init() throws {
        try FileManager.default.createDirectory(at: duckStation, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    }

    /// A state file in `folder`, saved at `saved`.
    @discardableResult
    func save(_ name: String, in folder: URL? = nil, _ contents: String = "state", saved: Date = Date(timeIntervalSince1970: 1_000_000))
        throws -> URL
    {
        let url = (folder ?? duckStation).appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    func backedUp() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: states.backup.path(percentEncoded: false)).sorted()
    }

    @Test func aStatesFileNameSaysItsSerialAndSlot() {
        let serials = ["SLUS-00551", "SLUS-0055"]
        #expect(SaveState.parse("SLUS-00551_3.sav", serials: serials)! == ("SLUS-00551", .numbered(3), false))
        #expect(SaveState.parse("SLUS-00551_10.bak", serials: serials)! == ("SLUS-00551", .numbered(10), true))
        #expect(SaveState.parse("SLUS-00551_resume.sav", serials: serials)! == ("SLUS-00551", .resume, false))
        for other in ["SLUS-00594_1.sav", "savestate_1.sav", "resume.sav", "SLUS-00551_1.sav.tmp", "SLUS-00551_x.sav", "SLUS-00551_0.sav"] {
            #expect(SaveState.parse(other, serials: serials) == nil)
        }
    }

    @Test func aGamesStatesAreBackedUpUnderTheirOwnNamesKeepingWhenTheyWereSaved() throws {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        try save("SLUS-00551_1.sav", saved: saved)
        try save("SLUS-00551_1.bak")
        try save("SLUS-00551_resume.sav")
        // Another game's, a global slot's, and one DuckStation is still writing.
        try save("SLUS-00594_1.sav")
        try save("savestate_1.sav")
        try save("SLUS-00551_2.sav.tmp")

        #expect(try states.backUp(["SLUS-00551"]))
        #expect(try backedUp() == ["SLUS-00551_1.bak", "SLUS-00551_1.sav", "SLUS-00551_resume.sav"])
        let copy = states.backup.appending(path: "SLUS-00551_1.sav")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "state")
        let modified = try FileManager.default.attributesOfItem(atPath: copy.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(modified == saved)
        // Nothing new: nothing's copied.
        #expect(try !states.backUp(["SLUS-00551"]))
    }

    @Test func savingOverASlotIsBackedUpAgain() throws {
        try save("SLUS-00551_1.sav", "first")
        try states.backUp(["SLUS-00551"])
        try save("SLUS-00551_1.sav", "second", saved: Date(timeIntervalSince1970: 2_000_000))

        #expect(try states.backUp(["SLUS-00551"]))
        #expect(try String(contentsOf: states.backup.appending(path: "SLUS-00551_1.sav"), encoding: .utf8) == "second")
    }

    @Test func nothingIsBackedUpWhileTheDataFolderIsMissing() throws {
        try save("SLUS-00551_1.sav")
        try FileManager.default.removeItem(at: data)

        #expect(try !states.backUp(["SLUS-00551"]))
        #expect(!FileManager.default.fileExists(atPath: data.path(percentEncoded: false)))
    }

    @Test func aGamesStatesAreListedByDiscThenResumeThenSlotWithEachPreviousAfterItsSlot() throws {
        try save("SLUS-00663_1.sav")
        try save("SLUS-00662_2.sav")
        try save("SLUS-00662_10.sav")
        try save("SLUS-00662_2.bak")
        try save("SLUS-00662_resume.sav")
        try save("SLUS-00594_1.sav")

        let listed = states.states(of: ["SLUS-00662", "SLUS-00663"])

        #expect(
            listed.map(\.fileName) == [
                "SLUS-00662_resume.sav", "SLUS-00662_2.sav", "SLUS-00662_2.bak", "SLUS-00662_10.sav", "SLUS-00663_1.sav",
            ])
        #expect(listed.map(\.title) == ["Resume", "Slot 2", "Slot 2 (previous)", "Slot 10", "Slot 1"])
        #expect(listed.allSatisfy { $0.inDuckStation && !$0.backedUp })
    }

    @Test func aStateDeletedInDuckStationStaysInTheBackupAndCanBeRestored() throws {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        let live = try save("SLUS-00551_1.sav", saved: saved)
        try states.backUp(["SLUS-00551"])
        try FileManager.default.removeItem(at: live)
        // Backing up again leaves it be.
        try states.backUp(["SLUS-00551"])

        let state = try #require(states.states(of: ["SLUS-00551"]).first)
        #expect(!state.inDuckStation && state.backedUp)
        #expect(state.file == states.backup.appending(path: "SLUS-00551_1.sav"))
        #expect(state.saved == saved)

        try states.restore(state)
        let restored = try #require(states.states(of: ["SLUS-00551"]).first)
        #expect(restored.inDuckStation && restored.backedUp && restored.saved == saved)
        #expect(try String(contentsOf: live, encoding: .utf8) == "state")
    }

    @Test func deletingAStateTrashesItFromDuckStationAndTheBackup() throws {
        try save("SLUS-00551_1.sav")
        try save("SLUS-00551_2.sav")
        try states.backUp(["SLUS-00551"])
        let state = try #require(states.states(of: ["SLUS-00551"]).first)
        var trashed: [String] = []

        try states.delete(state) { url in
            trashed.append(url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }

        #expect(trashed == ["savestates/SLUS-00551_1.sav", "Save States/SLUS-00551_1.sav"])
        #expect(states.states(of: ["SLUS-00551"]).map(\.fileName) == ["SLUS-00551_2.sav"])
    }

    @Test func aStatesFolderComesFromDuckStationsSettings() throws {
        let duckStationData = root.appending(path: "DuckStation Data", directoryHint: .isDirectory)
        let ludeum = LudeumFolder(url: root.appending(path: "Ludeum"), data: data)
        try FileManager.default.createDirectory(at: duckStationData, withIntermediateDirectories: true)
        let settings = duckStationData.appending(path: "settings.ini")
        func folder() -> URL { DuckStationSaveStates(ludeum: ludeum, duckStation: DuckStationSettings(dataFolder: duckStationData)).folder }

        #expect(folder() == duckStationData.appending(path: "savestates", directoryHint: .isDirectory))
        try "[Folders]\nSaveStates = states\n".write(to: settings, atomically: true, encoding: .utf8)
        #expect(folder() == duckStationData.appending(path: "states", directoryHint: .isDirectory))
        try "[Folders]\nSaveStates = /Volumes/Games/States\n".write(to: settings, atomically: true, encoding: .utf8)
        #expect(folder() == URL(filePath: "/Volumes/Games/States", directoryHint: .isDirectory))
        #expect(
            DuckStationSaveStates(ludeum: ludeum).backup
                == data.appending(path: "Emulators/DuckStation/Save States", directoryHint: .isDirectory))
    }

    // MARK: Screenshots

    /// A state file as DuckStation writes it: its header, then a `width` by `height` screenshot packed by `compression`.
    func stateFile(version: UInt32 = 92, compression: UInt32, width: Int = 2, height: Int = 1, pack: (Data) -> Data) throws -> (URL, Data) {
        let pixels = Data((0..<(width * height * 4)).map { UInt8($0 % 256) })
        let packed = pack(pixels)
        var header = Data()
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        u32(0x4343_5544)
        u32(version)
        header.append(Data(count: 128 + 32))
        u32(0)
        u32(0)
        u32(0)
        u32(compression)
        u32(UInt32(width))
        u32(UInt32(height))
        u32(UInt32(packed.count))
        u32(216)
        header.append(Data(count: 216 - header.count))
        let url = duckStation.appending(path: "SLUS-00551_1.sav")
        try (header + packed + Data("the state".utf8)).write(to: url)
        return (url, pixels)
    }

    @Test func aStatesScreenshotIsReadFromItsHeader() throws {
        let (plain, pixels) = try stateFile(compression: 0) { $0 }
        #expect(DuckStationSaveStates.screenshot(of: plain) == SaveStateScreenshot(width: 2, height: 1, rgba: pixels))

        let (xz, _) = try stateFile(compression: 3) { try! ($0 as NSData).compressed(using: .lzma) as Data }
        #expect(DuckStationSaveStates.screenshot(of: xz)?.rgba == pixels)

        // zlib's header, deflate, then its checksum.
        let (deflate, _) = try stateFile(compression: 1) {
            Data([0x78, 0x9C]) + (try! ($0 as NSData).compressed(using: .zlib) as Data) + Data(count: 4)
        }
        #expect(DuckStationSaveStates.screenshot(of: deflate)?.rgba == pixels)
    }

    @Test(.enabled(if: Zstd.find() != nil, "needs zstd"))
    func aZstandardScreenshotIsReadWithZstd() throws {
        let (url, pixels) = try stateFile(compression: 2) { pixels in
            let process = Process()
            process.executableURL = URL(filePath: "/opt/homebrew/bin/zstd")
            process.arguments = ["-cq"]
            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try! process.run()
            input.fileHandleForWriting.write(pixels)
            try! input.fileHandleForWriting.close()
            let packed = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return packed
        }
        #expect(DuckStationSaveStates.screenshot(of: url)?.rgba == pixels)
        #expect(DuckStationSaveStates.screenshot(of: url, zstd: nil) == nil)
    }

    @Test func aStateWithoutAReadableScreenshotHasNone() throws {
        let (old, _) = try stateFile(version: 68, compression: 0) { $0 }
        #expect(DuckStationSaveStates.screenshot(of: old) == nil)
        let (short, _) = try stateFile(compression: 0) { $0.dropLast() }
        #expect(DuckStationSaveStates.screenshot(of: short) == nil)
        #expect(DuckStationSaveStates.screenshot(of: try save("SLUS-00551_2.sav", "not a state")) == nil)
    }

    // MARK: Playing and the journal

    @Test func playingFromAStateOpensItWithTheROM() throws {
        let rom = URL(filePath: "/Games/PSX/Resident Evil - Director's Cut (USA).m3u")
        let state = URL(filePath: "/States/SLUS-00551_1.sav")
        let settings = DuckStationSettings(dataFolder: root.appending(path: "DuckStation Data"), oldCopy: root.appending(path: "old.ini"))

        #expect(
            try Emulator.duckStation.arguments(
                rom: rom, platformId: 7, settings: EmulatorSettings(), saveState: state, duckStation: settings)
                == ["-statefile", "/States/SLUS-00551_1.sav", "--", "/Games/PSX/Resident Evil - Director's Cut (USA).m3u"])
        #expect(
            try Emulator.duckStation.arguments(rom: rom, platformId: 7, settings: EmulatorSettings(), duckStation: settings)
                == ["--", "/Games/PSX/Resident Evil - Director's Cut (USA).m3u"])
    }

    @Test func theSerialsBackedUpAreEveryGamesROMs() throws {
        let h = try LudeumHarness()
        try h.journal.addPlatform(id: 7, name: "PlayStation")
        let game = try h.journal.addGame(platformId: 7, name: "Parasite Eve")
        try h.journal.db.write { db in
            for (name, gameId, serials, read) in [
                ("Parasite Eve (USA)", game as Int64?, #"["SLUS-00662","SLUS-00668"]"# as String?, true),
                ("Unmatched (USA)", nil, #"["SLUS-09999"]"#, true),
                ("Not read (USA)", game, nil, false),
                ("No serial (USA)", game, nil, true),
            ] {
                try db.execute(
                    sql: """
                        INSERT INTO rom (folderName, fileName, name, platformId, gameId, matchKind, matchedAt, serials, serialsLookedUp)
                        VALUES (?, ?, ?, 7, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        name, "\(name).cue", name, gameId, gameId.map { _ in "confirmed" }, gameId.map { _ in Date() }, serials, read,
                    ])
            }
        }

        #expect(try h.journal.gameSerials() == ["SLUS-00662", "SLUS-00668"])
    }
}
