import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// DuckStation's save states, in the Data folder where its Standing settings keep them (ADR 0024).
@Suite struct SaveStatesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "save states \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var folder: URL { ludeum.data.appending(path: "Emulators/DuckStation/Save States", directoryHint: .isDirectory) }
    var states: DuckStationSaveStates { DuckStationSaveStates(ludeum: ludeum) }

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A state file, saved at `saved`.
    @discardableResult
    func save(_ name: String, _ contents: String = "state", saved: Date = Date(timeIntervalSince1970: 1_000_000)) throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: url.path(percentEncoded: false))
        return url
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

    @Test func theStatesAreWhereTheStandingSettingsKeepThemInTheDataFolder() {
        #expect(states.folder == ludeum.duckStationSaveStates)
        #expect(states.folder == folder)
    }

    @Test func aGamesStatesAreListedByDiscThenResumeThenSlotWithEachPreviousAfterItsSlot() throws {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        try save("SLUS-00663_1.sav")
        try save("SLUS-00662_2.sav", saved: saved)
        try save("SLUS-00662_10.sav")
        try save("SLUS-00662_2.bak")
        try save("SLUS-00662_resume.sav")
        // Another game's, a global slot's, and one DuckStation is still writing.
        try save("SLUS-00594_1.sav")
        try save("savestate_1.sav")
        try save("SLUS-00662_3.sav.tmp")

        let listed = states.states(of: ["SLUS-00662", "SLUS-00663"])

        #expect(
            listed.map(\.fileName) == [
                "SLUS-00662_resume.sav", "SLUS-00662_2.sav", "SLUS-00662_2.bak", "SLUS-00662_10.sav", "SLUS-00663_1.sav",
            ])
        #expect(listed.map(\.title) == ["Resume", "Slot 2", "Slot 2 (previous)", "Slot 10", "Slot 1"])
        #expect(listed[1].saved == saved)
        #expect(listed[1].file == folder.appending(path: "SLUS-00662_2.sav"))
    }

    @Test func deletingAStateTrashesIt() throws {
        try save("SLUS-00551_1.sav")
        try save("SLUS-00551_2.sav")
        let state = try #require(states.states(of: ["SLUS-00551"]).first)
        var trashed: [String] = []

        try states.delete(state) { url in
            trashed.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }

        #expect(trashed == ["SLUS-00551_1.sav"])
        #expect(states.states(of: ["SLUS-00551"]).map(\.fileName) == ["SLUS-00551_2.sav"])
    }

    @Test func withNoStatesFolderYetThereAreNone() throws {
        try FileManager.default.removeItem(at: folder)
        #expect(states.states(of: ["SLUS-00551"]).isEmpty)
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
        let url = folder.appending(path: "SLUS-00551_1.sav")
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

    // MARK: Playing

    @Test func playingFromAStateOpensItWithTheROM() throws {
        let rom = URL(filePath: "/Games/PSX/Resident Evil - Director's Cut (USA).m3u")
        let state = URL(filePath: "/States/SLUS-00551_1.sav")
        let settings = DuckStationSettings(
            app: root.appending(path: "DuckStation.app"), dataFolder: root.appending(path: "DuckStation Data"), ludeum: ludeum)

        #expect(
            try Emulator.duckStation.arguments(
                rom: rom, platformId: 7, settings: EmulatorSettings(), saveState: state, duckStation: settings)
                == ["-statefile", "/States/SLUS-00551_1.sav", "--", "/Games/PSX/Resident Evil - Director's Cut (USA).m3u"])
        #expect(
            try Emulator.duckStation.arguments(rom: rom, platformId: 7, settings: EmulatorSettings(), duckStation: settings)
                == ["--", "/Games/PSX/Resident Evil - Director's Cut (USA).m3u"])
    }
}
