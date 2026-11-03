import Foundation
import Testing

@testable import LudeumCore

/// PCSX2's Save states and memory cards, in the Data folder where its Standing settings keep them (ADR 0032).
@Suite struct PCSX2SavesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "pcsx2 saves \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var folder: URL { ludeum.pcsx2SaveStates }
    var states: PCSX2SaveStates { PCSX2SaveStates(ludeum: ludeum) }
    var cards: URL { ludeum.pcsx2MemoryCards }

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cards, withIntermediateDirectories: true)
    }

    /// A state file, saved at `saved`.
    @discardableResult
    func save(_ name: String, _ contents: Data = Data("state".utf8), saved: Date = Date(timeIntervalSince1970: 1_000_000)) throws -> URL {
        let url = folder.appending(path: name)
        try contents.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    @Test func aStatesFileNameSaysItsSerialAndSlot() {
        let serials = ["SLUS-20062", "SLUS-2006"]
        #expect(PCSX2SaveStates.parse("SLUS-20062 (2C9A8B3F).01.p2s", serials: serials)! == ("SLUS-20062", .numbered(1), false))
        #expect(PCSX2SaveStates.parse("SLUS-20062 (2C9A8B3F).10.p2s", serials: serials)! == ("SLUS-20062", .numbered(10), false))
        #expect(PCSX2SaveStates.parse("SLUS-20062 (2C9A8B3F).03.p2s.backup", serials: serials)! == ("SLUS-20062", .numbered(3), true))
        #expect(PCSX2SaveStates.parse("SLUS-20062 (2c9a8b3f).resume.p2s", serials: serials)! == ("SLUS-20062", .resume, false))
        for other in [
            "SLUS-20063 (2C9A8B3F).01.p2s", "SLUS-20062 (2C9A8B3).01.p2s", "SLUS-20062 (2C9A8B3F).1.p2s",
            "SLUS-20062 (2C9A8B3F).01.p2s.tmp",
            "SLUS-20062 (2C9A8B3F).resume.p2s.backup", "SLUS-20062_1.sav", "SLUS-20062 (XYZ12345).01.p2s",
        ] {
            #expect(PCSX2SaveStates.parse(other, serials: serials) == nil, "\(other)")
        }
    }

    @Test func theStatesAreWhereTheStandingSettingsKeepThemInTheDataFolder() {
        #expect(states.folder == ludeum.data.appending(path: "Emulators/PCSX2/Save States", directoryHint: .isDirectory))
    }

    @Test func aGamesStatesAreListedByDiscThenResumeThenSlotWithEachPreviousAfterItsSlot() throws {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        try save("SLES-50001 (0000ABCD).01.p2s")
        try save("SLUS-20062 (2C9A8B3F).02.p2s", saved: saved)
        try save("SLUS-20062 (2C9A8B3F).10.p2s")
        try save("SLUS-20062 (2C9A8B3F).02.p2s.backup")
        try save("SLUS-20062 (2C9A8B3F).resume.p2s")
        // Another game's, and another dump's of the same game.
        try save("SLUS-20594 (12345678).01.p2s")
        try save("SLUS-20062 (00000001).05.p2s")

        let listed = states.states(of: ["SLUS-20062", "SLES-50001"])

        #expect(
            listed.map(\.fileName) == [
                "SLUS-20062 (2C9A8B3F).resume.p2s", "SLUS-20062 (2C9A8B3F).02.p2s", "SLUS-20062 (2C9A8B3F).02.p2s.backup",
                "SLUS-20062 (00000001).05.p2s", "SLUS-20062 (2C9A8B3F).10.p2s", "SLES-50001 (0000ABCD).01.p2s",
            ])
        #expect(listed.map(\.title) == ["Resume", "Slot 2", "Slot 2 (previous)", "Slot 5", "Slot 10", "Slot 1"])
        #expect(listed[1].saved == saved)
        #expect(listed.map(\.serial) == ["SLUS-20062", "SLUS-20062", "SLUS-20062", "SLUS-20062", "SLUS-20062", "SLES-50001"])
    }

    @Test func deletingOneSendsItToTheTrash() throws {
        let file = try save("SLUS-20062 (2C9A8B3F).01.p2s")
        let state = states.states(of: ["SLUS-20062"])[0]
        var trashed: [URL] = []

        try states.delete(state) { trashed.append($0) }

        #expect(trashed == [file])
    }

    /// A zip with one stored entry, as PCSX2 stores a state's screenshot.
    func zip(storing entries: [(name: String, data: Data)]) -> Data {
        func le16(_ n: Int) -> [UInt8] { [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF)] }
        func le32(_ n: Int) -> [UInt8] { le16(n & 0xFFFF) + le16(n >> 16 & 0xFFFF) }
        var zip = Data()
        var directory = Data()
        for (name, data) in entries {
            let offset = zip.count
            let nameBytes = Array(name.utf8)
            zip +=
                [0x50, 0x4B, 0x03, 0x04] + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(data.count) + le32(data.count)
                + le16(nameBytes.count) + le16(0) + nameBytes
            zip += data
            directory +=
                [0x50, 0x4B, 0x01, 0x02] + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(data.count)
                + le32(data.count) + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameBytes
        }
        let directoryOffset = zip.count
        zip += directory
        zip +=
            [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(entries.count) + le16(entries.count) + le32(directory.count)
            + le32(directoryOffset) + le16(0)
        return zip
    }

    @Test func aStatesScreenshotIsThePNGStoredInIt() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + (0..<500).map { UInt8($0 % 251) })
        let state = try save(
            "SLUS-20062 (2C9A8B3F).01.p2s",
            zip(storing: [
                ("PCSX2 Savestate Version.id", Data([0x59, 0x9A, 0, 0])), ("Screenshot.png", png),
                ("eeMemory.bin", Data(repeating: 7, count: 100)),
            ]))

        #expect(PCSX2SaveStates.screenshotPNG(of: state) == png)
        #expect(
            PCSX2SaveStates.screenshotPNG(of: try save("SLUS-20062 (2C9A8B3F).02.p2s", zip(storing: [("eeMemory.bin", Data())]))) == nil)
        #expect(PCSX2SaveStates.screenshotPNG(of: try save("SLUS-20062 (2C9A8B3F).03.p2s", Data("not a zip".utf8))) == nil)
    }

    @Test func aDeflatedEntryIsInflated() throws {
        let staging = root.appending(path: "zip", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let png = Data(repeating: 0x41, count: 10_000)
        try png.write(to: staging.appending(path: "Screenshot.png"))
        let zipped = root.appending(path: "ditto.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", staging.path(percentEncoded: false), zipped.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()

        #expect(Zip.entry(named: "Screenshot.png", in: zipped) == png)
    }

    /// A save on a folder card: its folder, `icon.sys` with `title` and `_pcsx2_index`.
    func cardSave(
        _ card: String, _ name: String, title: (String, String)? = ("ＯＫＡＭＩ", "ＤＡＴＡ"),
        saved: Date = Date(timeIntervalSince1970: 1_700_000_000)
    )
        throws
    {
        let save = cards.appending(path: "\(card)/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        if let (first, second) = title {
            var icon = Data("PS2D".utf8) + [0, 0]
            let firstBytes = first.data(using: .shiftJIS)!
            icon += [UInt8(firstBytes.count), 0]
            icon += Data(repeating: 0, count: 0xC0 - icon.count)
            var titleBytes = firstBytes + second.data(using: .shiftJIS)!
            titleBytes += Data(repeating: 0, count: 68 - titleBytes.count)
            icon += titleBytes
            icon += Data(repeating: 0, count: 964 - icon.count)
            try icon.write(to: save.appending(path: "icon.sys"))
        }
        let index = save.appending(path: "_pcsx2_index")
        try "$ROOT:\n  timeCreated: 1\n".write(to: index, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: index.path(percentEncoded: false))
    }

    @Test func aGamesCardSavesAreTheFoldersOnItsFolderCardsNamedWithItsSerials() throws {
        try cardSave("Mcd001.ps2", "BASLUS-20062GAME")
        try cardSave("Mcd001.ps2", "BASLUS-20062OPT", title: nil, saved: Date(timeIntervalSince1970: 1_600_000_000))
        try cardSave("Mcd002.ps2", "BESLES-50001", title: ("ＯＫＡＭＩ", ""))
        try cardSave("Mcd001.ps2", "BASLUS-20594")
        try "superblock".write(to: cards.appending(path: "Mcd001.ps2/_pcsx2_superblock"), atomically: true, encoding: .utf8)
        try Data(repeating: 0xFF, count: 64).write(to: cards.appending(path: "Mcd003.ps2"))

        let saves = PCSX2MemoryCards(folder: cards, resources: nil).saves(of: ["SLUS-20062", "SLES-50001"])

        #expect(saves.map(\.name) == ["BASLUS-20062GAME", "BASLUS-20062OPT", "BESLES-50001"])
        #expect(saves.map(\.card) == ["Mcd001.ps2", "Mcd001.ps2", "Mcd002.ps2"])
        #expect(saves.map(\.title) == ["OKAMI DATA", nil, "OKAMI"])
        #expect(saves[1].saved == Date(timeIntervalSince1970: 1_600_000_000))
        #expect(saves[0].folder == cards.appending(path: "Mcd001.ps2/BASLUS-20062GAME", directoryHint: .isDirectory))
    }

    @Test func discsPCSX2sGameDatabaseSaysShareSavesAreCountedIn() throws {
        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try """
        PBPX-95502:
          name: "GRAN TURISMO 3"
          region: "NTSC-J"
        PBPX-95503:
          name: "Gran Turismo 3 - A-Spec [PS2 Bundle]"
          region: "NTSC-U"
          gsHWFixes: *gran-turismo-3-gs-fixes
          memcardFilters:
            - "PBPX-95503"
            - "SCUS-97102" # the retail disc
            - "SCUS-97512"
        SCUS-97113:
          name: "Ico"

        """.write(to: resources.appending(path: "GameIndex.yaml"), atomically: true, encoding: .utf8)
        try cardSave("Mcd001.ps2", "BASCUS-97102GT3")
        try cardSave("Mcd001.ps2", "BAPBPX-95503")
        try cardSave("Mcd001.ps2", "BASCUS-97113")

        #expect(PCSX2MemoryCards.filters(for: ["PBPX-95503"], in: resources) == ["PBPX-95503", "SCUS-97102", "SCUS-97512"])
        #expect(PCSX2MemoryCards.filters(for: ["SCUS-97113"], in: resources) == ["SCUS-97113"])
        #expect(PCSX2MemoryCards.filters(for: ["PBPX-95502"], in: resources) == ["PBPX-95502"])
        #expect(
            PCSX2MemoryCards(folder: cards, resources: resources).saves(of: ["PBPX-95503"]).map(\.name) == [
                "BAPBPX-95503", "BASCUS-97102GT3",
            ])
    }

    @Test func aSavesTitleIsReadFromItsIconSysInPlainCharacters() {
        // The second line starts 10 bytes in: five Shift JIS full-width characters.
        var icon = Data("PS2D".utf8) + [0, 0, 10, 0] + Data(repeating: 0, count: 0xC0 - 8)
        var title = "ＦＩＮＡＬ".data(using: .shiftJIS)! + "ＦＡＮＴＡＳＹ Ｘ".data(using: .shiftJIS)!
        title += Data(repeating: 0, count: 68 - title.count)
        icon += title
        #expect(IconSys.title(in: icon) == "FINAL FANTASY X")
    }
}
