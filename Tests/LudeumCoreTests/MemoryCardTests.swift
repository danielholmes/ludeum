import Foundation
import Testing

@testable import LudeumCore

/// A memory card, 128 KB as DuckStation keeps one: its header, then for each save one directory frame per block and the
/// blocks themselves. `saves` are each a title, an icon of `frames` frames and how many blocks it takes.
func memoryCard(_ saves: [(name: String, title: String, frames: Int, blocks: Int)], deleted: [String] = []) -> Data {
    var card = Data(count: 128 * 1024)
    card.replaceSubrange(0..<2, with: Data("MC".utf8))
    func u32(_ value: UInt32, at offset: Int) {
        for i in 0..<4 { card[offset + i] = UInt8(value >> (8 * UInt32(i)) & 0xFF) }
    }
    func u16(_ value: UInt16, at offset: Int) {
        card[offset] = UInt8(value & 0xFF)
        card[offset + 1] = UInt8(value >> 8)
    }
    var block = 1
    for save in saves {
        for i in 0..<save.blocks {
            let frame = (block + i) * 128
            u32(i == 0 ? 0x51 : i == save.blocks - 1 ? 0x53 : 0x52, at: frame)
            if i == 0 { u32(UInt32(save.blocks * 8192), at: frame + 4) }
            u16(i == save.blocks - 1 ? 0xFFFF : UInt16(block + i), at: frame + 8)
            if i == 0 { card.replaceSubrange(frame + 0x0A..<frame + 0x0A + save.name.utf8.count, with: Data(save.name.utf8)) }
        }
        let start = block * 8192
        card.replaceSubrange(start..<start + 2, with: Data("SC".utf8))
        card[start + 2] = UInt8(0x10 + save.frames)
        card[start + 3] = UInt8(save.blocks)
        let title = save.title.data(using: .shiftJIS)!
        card.replaceSubrange(start + 4..<start + 4 + title.count, with: title)
        // Colour 1 is red; colour 0, transparent.
        u16(0x001F, at: start + 0x60 + 2)
        // Each frame's first pixel is colour 1, the rest colour 0.
        for f in 0..<save.frames { card[start + 128 * (1 + f)] = 0x01 }
        block += save.blocks
    }
    for name in deleted {
        let frame = block * 128
        u32(0xA1, at: frame)
        u32(8192, at: frame + 4)
        u16(0xFFFF, at: frame + 8)
        card.replaceSubrange(frame + 0x0A..<frame + 0x0A + name.utf8.count, with: Data(name.utf8))
        block += 1
    }
    return card
}

@Suite struct MemoryCardTests {
    @Test func aCardsSavesAreItsTitlesIconsAndBlocks() throws {
        let card = memoryCard(
            [
                ("BASLUS-00551RE001", "Ｒ．Ｅ　１．Ｃｈｒｉｓ", 3, 1),
                ("BASLUS-00594MGS01", "METAL GEAR SOLID", 1, 2),
            ], deleted: ["BASCUS-94163FF7-S01"])

        let saves = try #require(MemoryCard.saves(in: card))

        #expect(saves.map(\.title) == ["R.E 1.Chris", "METAL GEAR SOLID"])
        #expect(saves.map(\.fileName) == ["BASLUS-00551RE001", "BASLUS-00594MGS01"])
        #expect(saves.map(\.blocks) == [1, 2])
        #expect(saves.map(\.icon.count) == [3, 1])
        let frame = saves[0].icon[0]
        #expect(frame.count == 16 * 16 * 4)
        #expect(Array(frame.prefix(8)) == [0xFF, 0, 0, 0xFF, 0, 0, 0, 0])
    }

    @Test func anEmptyCardHasNoSavesAndAnythingElseIsntACard() {
        #expect(MemoryCard.saves(in: memoryCard([])) == [])
        #expect(MemoryCard.saves(in: Data(count: 1000)) == nil)
        var notACard = memoryCard([])
        notACard[0] = 0
        #expect(MemoryCard.saves(in: notACard) == nil)
    }
}

/// Each PlayStation ROM's card, in the Data folder where every Play points DuckStation at it (ADR 0023).
@Suite struct DuckStationMemoryCardTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "memory cards \(UUID().uuidString)", directoryHint: .isDirectory)
    var duckStation: URL { root.appending(path: "DuckStation", directoryHint: .isDirectory) }
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var resources: URL { root.appending(path: "DuckStation.app/Contents/Resources", directoryHint: .isDirectory) }
    var settings: DuckStationSettings {
        DuckStationSettings(dataFolder: duckStation, oldCopy: root.appending(path: "old.ini"), ludeum: ludeum)
    }
    var cards: DuckStationMemoryCards { DuckStationMemoryCards(duckStation: settings) }
    let rom = URL(filePath: "/Games/PS1/Resident Evil - Director's Cut (USA)/Resident Evil - Director's Cut (USA).cue")

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        try write(
            """
            SLUS-00551:
              name: "Resident Evil - Director's Cut (USA)"
              trackData:
                - tracks:
                    - size: 707027664
            SLUS-00594:
              name: "Metal Gear Solid (USA) (Disc 1)"
              saveName: "Metal Gear Solid (USA) (Disc 1)"
            SLUS-00776:
              name: "Metal Gear Solid (USA) (Disc 2)"
            SLPS-00001:
              name: "Colon: The Game"
            """, to: resources.appending(path: "discdb.yaml"))
        try write(
            """
            - name: "3x3 Eyes"
              saveName: "3x3 Eyes (Japan)"
              serials:
                - SLPS-00071
                - SLPS-00072
            - name: "Metal Gear Solid"
              localizedName: "メタルギアソリッド"
              saveName: "Metal Gear Solid (USA)"
              serials:
                - SLUS-00594
                - SLUS-00776
            """, to: resources.appending(path: "discsets.yaml"))
    }

    func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func memcard(_ name: String) -> URL { duckStation.appending(path: "memcards/\(name)") }

    func own(_ serial: String, rom: URL? = nil) -> String? {
        cards.duckStationsCard(serial: serial, rom: rom ?? self.rom, resources: resources).map {
            $0.path(percentEncoded: false).replacingOccurrences(of: duckStation.path(percentEncoded: false), with: "")
        }
    }

    @Test func aROMsCardIsNamedByDisc1sSerialInTheDataFolder() {
        #expect(cards.card(of: "SLUS-00551") == ludeum.data.appending(path: "Emulators/DuckStation/Memory Cards/SLUS-00551.mcd"))
    }

    @Test func duckStationsOwnCardIsNamedByItsTitleAsItsSettingsSay() throws {
        // By default, its title in DuckStation's game database.
        #expect(own("SLUS-00551") == "memcards/Resident Evil - Director's Cut (USA)_1.mcd")
        // A disc set's discs share its card, unless a card of the disc's own is there already.
        #expect(own("SLUS-00594") == "memcards/Metal Gear Solid (USA)_1.mcd")
        try write("", to: memcard("Metal Gear Solid (USA) (Disc 1)_1.mcd"))
        #expect(own("SLUS-00594") == "memcards/Metal Gear Solid (USA) (Disc 1)_1.mcd")
        // A disc DuckStation doesn't know is named by its file, and what macOS can't have in a name is replaced.
        #expect(own("SLUS-99999", rom: URL(filePath: "/Games/Homebrew*.cue")) == "memcards/Homebrew__1.mcd")
        #expect(own("SLPS-00001") == "memcards/Colon_ The Game_1.mcd")

        try write("[MemoryCards]\nCard1Type = PerGame\nDirectory = cards\n", to: duckStation.appending(path: "settings.ini"))
        #expect(own("SLUS-00551") == "cards/SLUS-00551_1.mcd")
        try write("[MemoryCards]\nCard1Type = PerGameFileTitle\n", to: duckStation.appending(path: "settings.ini"))
        #expect(own("SLUS-00551") == "memcards/Resident Evil - Director's Cut (USA)_1.mcd")
        try write("[MemoryCards]\nCard1Type = Shared\n", to: duckStation.appending(path: "settings.ini"))
        #expect(own("SLUS-00551") == "memcards/shared_card_1.mcd")
        try write(
            "[MemoryCards]\nCard1Type = Shared\nCard1Path = /Volumes/Cards/mine.mcd\n", to: duckStation.appending(path: "settings.ini"))
        #expect(cards.duckStationsCard(serial: "SLUS-00551", rom: rom, resources: resources) == URL(filePath: "/Volumes/Cards/mine.mcd"))
        try write("[MemoryCards]\nCard1Type = None\n", to: duckStation.appending(path: "settings.ini"))
        #expect(own("SLUS-00551") == nil)

        // A setting of the game's own wins.
        try write("[MemoryCards]\nCard1Type = PerGame\n", to: duckStation.appending(path: "gamesettings/SLUS-00551.ini"))
        #expect(own("SLUS-00551") == "memcards/SLUS-00551_1.mcd")
    }

    @Test func withoutItsGameDatabaseItsOwnCardIsNamedByTheFile() {
        let unknown = cards.duckStationsCard(serial: "SLUS-00551", rom: rom, resources: nil)
        #expect(unknown == memcard("Resident Evil - Director's Cut (USA)_1.mcd"))
    }

    @Test func duckStationsCardIsCopiedInWhenTheDataFolderHasNone() throws {
        let saved = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.createDirectory(at: memcard(""), withIntermediateDirectories: true)
        try memoryCard([("BASLUS-00551RE001", "RE", 1, 1)]).write(to: memcard("Resident Evil - Director's Cut (USA)_1.mcd"))
        try FileManager.default.setAttributes(
            [.modificationDate: saved], ofItemAtPath: memcard("Resident Evil - Director's Cut (USA)_1.mcd").path(percentEncoded: false))

        #expect(cards.memoryCard(serial: "SLUS-00551", rom: rom, resources: resources)?.inDataFolder == false)
        try cards.moveIn(serial: "SLUS-00551", rom: rom, resources: resources)

        let copy = cards.card(of: "SLUS-00551")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: memcard("Resident Evil - Director's Cut (USA)_1.mcd")))
        #expect(try copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == saved)
        let shown = try #require(cards.memoryCard(serial: "SLUS-00551", rom: rom, resources: resources))
        #expect(shown.inDataFolder && shown.file == copy && shown.saved == saved && shown.saves?.map(\.title) == ["RE"])

        // Once it's there, it's the card: DuckStation's is never copied over it.
        try memoryCard([]).write(to: memcard("Resident Evil - Director's Cut (USA)_1.mcd"))
        try cards.moveIn(serial: "SLUS-00551", rom: rom, resources: resources)
        #expect(MemoryCard.saves(in: try Data(contentsOf: copy))?.count == 1)
    }

    @Test func aROMWithNoCardAnywhereHasNoneToShowOrCopy() throws {
        try cards.moveIn(serial: "SLUS-00551", rom: rom, resources: resources)
        #expect(!FileManager.default.fileExists(atPath: cards.card(of: "SLUS-00551").path(percentEncoded: false)))
        #expect(cards.memoryCard(serial: "SLUS-00551", rom: rom, resources: resources) == nil)
    }

    @Test func everyPlayPointsEachDiscsCard1AtTheDataFoldersCard() throws {
        let ini = { (serial: String) in
            try? String(contentsOf: duckStation.appending(path: "gamesettings/\(serial).ini"), encoding: .utf8)
        }
        let path = cards.card(of: "SLUS-00594").path(percentEncoded: false)
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: .read(["SLUS-00594", "SLUS-00776"]))

        let disc1 = try #require(ini("SLUS-00594"))
        #expect(Ini.value("Card1Type", in: "MemoryCards", of: disc1) == "Shared")
        #expect(Ini.value("Card1Path", in: "MemoryCards", of: disc1) == path)
        #expect(Ini.value("RunaheadFrameCount", in: "Main", of: disc1) == "1")
        // Disc 2's file has the card alone, as its settings are Disc 1's.
        #expect(ini("SLUS-00776") == "[MemoryCards]\nCard1Path = \(path)\nCard1Type = Shared\n\n")
        // The folder's there for DuckStation to write the card into.
        #expect(FileManager.default.fileExists(atPath: cards.folder.path(percentEncoded: false)))
    }

    @Test func noCardIsPointedAtWhileTheDataFolderIsMissing() throws {
        try FileManager.default.removeItem(at: ludeum.data)
        #expect(throws: DataFolderMissing.self) { try settings.write(EmulatorSettings(), serials: .read(["SLUS-00551"])) }
        #expect(!FileManager.default.fileExists(atPath: ludeum.data.path(percentEncoded: false)))
    }
}
