import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// The Serials step of each Import: a PlayStation ROM has its Discs' Serials read off them, once.
@Suite struct SerialsImportTests {
    let h: Harness
    let j: LudeumHarness
    let ps1: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        ps1 = try FakeROMFolder(in: h.directory, platform: ROMPlatform.ps1)
        h.internet.addPlatform(Int(ROMPlatform.ps1), "PlayStation")
    }

    /// A disc, as a cue sheet and its data track, in `folder` of the ROM folder; with `padding`, that many more bytes
    /// on it after its executable, or before `SYSTEM.CNF` with `systemCNFLast`.
    func addDisc(_ name: String, booting serial: String?, in folder: String, padding: Int = 0, systemCNFLast: Bool = false) throws {
        var disc =
            serial.map { serial in
                let executable = serial.replacingOccurrences(of: "-", with: "_").prefix(8) + "." + serial.suffix(2)
                return FakeDisc.booting("cdrom:\\\(executable);1", executable: String(executable))
            } ?? FakeDisc(["PSX.EXE": "PS-X EXE"])
        if padding > 0 { disc.files[systemCNFLast ? "PAD.DAT" : "ZZ.DAT"] = Data(count: padding) }
        try ps1.add("\(folder)/\(name).bin", data: disc.image())
        try ps1.add("\(folder)/\(name).cue", "FILE \"\(name).bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n")
    }

    func importNow(sevenZip: SevenZip? = nil) async throws {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, sevenZip: sevenZip)
            .run(addingEveryFileIn: [ps1.folder])
    }

    func serials() throws -> [String: Serials] {
        try j.journal.db.read { db in
            try Row.fetchAll(db, sql: "SELECT folderName, serials, serialsLookedUp FROM rom").reduce(into: [:]) {
                $0[$1["folderName"] as String] = Serials($1)
            }
        }
    }

    @Test func aPlayStationROMsSerialIsReadOffItsDisc() async throws {
        try addDisc("Resident Evil - Director's Cut (USA)", booting: "SLUS-00551", in: "Resident Evil - Director's Cut (USA)")

        try await importNow()

        #expect(try serials() == ["Resident Evil - Director's Cut (USA)": .read(["SLUS-00551"])])
    }

    @Test func aMultiDiscVersionHasEachDiscsInPlaylistOrder() async throws {
        let folder = "Final Fantasy VII (USA)"
        for (disc, serial) in [(1, "SCUS-94163"), (2, "SCUS-94164"), (3, "SCUS-94165")] {
            try addDisc("Final Fantasy VII (USA) (Disc \(disc))", booting: serial, in: folder)
        }
        try ps1.add(
            "\(folder)/\(folder).m3u",
            "Final Fantasy VII (USA) (Disc 2).cue\nFinal Fantasy VII (USA) (Disc 1).cue\nFinal Fantasy VII (USA) (Disc 3).cue\n")

        try await importNow()

        #expect(try serials() == [folder: .read(["SCUS-94164", "SCUS-94163", "SCUS-94165"])])
        let stored = try await j.journal.db.read { try String.fetchOne($0, sql: "SELECT serials FROM rom") }
        #expect(stored == #"["SCUS-94164","SCUS-94163","SCUS-94165"]"#)
    }

    @Test func aDiscWithNoSerialIsReadOnceAndKeepsItsPlace() async throws {
        let folder = "Game (USA)"
        try addDisc("Game (USA) (Disc 1)", booting: nil, in: folder)
        try addDisc("Game (USA) (Disc 2)", booting: "SLUS-01234", in: folder)
        try ps1.add("\(folder)/\(folder).m3u", "Game (USA) (Disc 1).cue\nGame (USA) (Disc 2).cue\n")
        try addDisc("Demo (USA)", booting: nil, in: "Demo (USA)")

        try await importNow()

        #expect(try serials() == ["Game (USA)": .read([nil, "SLUS-01234"]), "Demo (USA)": .read([])])
        let stored = try await j.journal.db.read { try String?.fetchAll($0, sql: "SELECT serials FROM rom ORDER BY folderName") }
        #expect(stored == [nil, #"[null,"SLUS-01234"]"#])
    }

    @Test func aFormNotReadYetIsLeftForALaterImport() async throws {
        try ps1.add("Ape Escape (USA)/Ape Escape (USA).chd", "not read")

        try await importNow()

        #expect(try serials() == ["Ape Escape (USA)": .notRead])
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func anArchivedROMsSerialIsReadInsideItsArchive() async throws {
        let name = "Crash Bandicoot (USA)"
        // More than is read at first, so 7-Zip is stopped part way.
        try addDisc(name, booting: "SCUS-94900", in: "work", padding: ROMSerials.firstRead * 2)
        try await SevenZip.find()!.create(
            ps1.url.appending(path: "\(name).7z"), files: ["\(name).cue", "\(name).bin"], in: ps1.url.appending(path: "work"),
            progress: { _ in })
        try ps1.remove("work")

        try await importNow(sevenZip: SevenZip.find())

        #expect(try serials() == [name: .read(["SCUS-94900"])])
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func aDiscWhoseSYSTEMCNFIsFarInIsReadAsWell() async throws {
        // As Resident Evil – Director's Cut's is, 660 MB in.
        try addDisc("Resident Evil (USA)", booting: "SLUS-00170", in: "Resident Evil (USA)", padding: 10 << 20, systemCNFLast: true)
        let name = "Resident Evil (Europe)"
        try addDisc(name, booting: "SLES-00227", in: "work", padding: ROMSerials.firstRead * 3, systemCNFLast: true)
        try await SevenZip.find()!.create(
            ps1.url.appending(path: "\(name).7z"), files: ["\(name).cue", "\(name).bin"], in: ps1.url.appending(path: "work"),
            progress: { _ in })
        try ps1.remove("work")

        try await importNow(sevenZip: SevenZip.find())

        #expect(try serials() == ["Resident Evil (USA)": .read(["SLUS-00170"]), name: .read(["SLES-00227"])])
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func anArchivedMultiDiscVersionsDiscsAreFoundByTheirNames() async throws {
        let name = "Parasite Eve (USA)"
        try addDisc("\(name) (Disc 1)", booting: "SLUS-00662", in: "work")
        try addDisc("\(name) (Disc 2)", booting: "SLUS-00668", in: "work")
        // A track not named after its cue sheet is found by reading it.
        try FileManager.default.moveItem(
            at: ps1.url.appending(path: "work/\(name) (Disc 2).bin"), to: ps1.url.appending(path: "work/Second.bin"))
        try ps1.add("work/\(name) (Disc 2).cue", "FILE \"Second.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
        try ps1.add("work/\(name).m3u", "\(name) (Disc 1).cue\n\(name) (Disc 2).cue\n")
        try await SevenZip.find()!.create(
            ps1.url.appending(path: "\(name).7z"),
            files: ["\(name).m3u", "\(name) (Disc 1).cue", "\(name) (Disc 1).bin", "\(name) (Disc 2).cue", "Second.bin"],
            in: ps1.url.appending(path: "work"), progress: { _ in })
        try ps1.remove("work")

        try await importNow(sevenZip: SevenZip.find())

        #expect(try serials() == [name: .read(["SLUS-00662", "SLUS-00668"])])
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func anArchivedSetOfDiscsInAFormNotReadYetIsLeftWithoutReadingItsPlaylist() async throws {
        let name = "Final Fantasy IX (USA)"
        try ps1.add("work/\(name) (Disc 1).chd", "not read")
        try ps1.add("work/\(name) (Disc 2).chd", "not read")
        try ps1.add("work/\(name).m3u", "\(name) (Disc 1).chd\n\(name) (Disc 2).chd\n")
        try await SevenZip.find()!.create(
            ps1.url.appending(path: "\(name).7z"), files: ["\(name).m3u", "\(name) (Disc 1).chd", "\(name) (Disc 2).chd"],
            in: ps1.url.appending(path: "work"), progress: { _ in })
        try ps1.remove("work")

        try await importNow(sevenZip: SevenZip.find())

        #expect(try serials() == [name: .notRead])
    }

    @Test func aROMAlreadyInTheJournalHasItsReadAtTheNextImportAndOnlyOnce() async throws {
        let name = "Resident Evil - Director's Cut (USA)"
        try addDisc(name, booting: "SLUS-00551", in: name)
        try await importNow()
        // Changed on the disc, as no dump is: what was read stands.
        try addDisc(name, booting: "SLUS-99999", in: name)
        try await importNow()
        #expect(try serials() == [name: .read(["SLUS-00551"])])

        try await j.journal.db.write { try $0.execute(sql: "UPDATE rom SET serials = NULL, serialsLookedUp = 0") }
        try await importNow()
        #expect(try serials() == [name: .read(["SLUS-99999"])])
    }

    @Test func givingAMissingROMAStrayFileReadsItsSerialsAgain() async throws {
        try addDisc("Okami (USA)", booting: "SLUS-00551", in: "Okami (USA)")
        try await importNow()
        try FileManager.default.moveItem(at: ps1.url.appending(path: "Okami (USA)"), to: ps1.url.appending(path: "Okami"))
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [ps1.folder])
        let rom = try #require(try await j.journal.db.read { try Int64.fetchOne($0, sql: "SELECT id FROM rom") })
        let stray = try #require(try j.journal.strayFiles().first)

        try j.journal.giveStrayFile(stray, to: rom, in: ps1.folder)

        #expect(try serials() == ["Okami": .notRead])
    }
}
