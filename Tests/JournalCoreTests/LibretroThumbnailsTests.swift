import Foundation
import Testing

@testable import JournalCore

@Suite struct LibretroThumbnailsTests {
    let h: Harness

    init() throws { h = try Harness() }

    @Test func aROMGetsItsBoxartSnapAndTitleNames() async throws {
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (Japan, USA) (En)"])
        h.internet.addLibretro(
            "Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (Europe) (En,Fr,De)"], folders: ["Named_Snaps"])

        let names = try await h.libretro.names(system: "openemu.system.snes", fileName: "Super Metroid (E).sfc", titles: [])

        let repo = "Nintendo - Super Nintendo Entertainment System"
        #expect(names?.boxart == "\(repo)/Named_Boxarts/Super Metroid (Japan, USA) (En).png")
        #expect(names?.snap == "\(repo)/Named_Snaps/Super Metroid (Europe) (En,Fr,De).png")
        #expect(names?.title == "\(repo)/Named_Titles/Super Metroid (Japan, USA) (En).png")
    }

    @Test func gameBoyROMsAlsoLookInGameBoyColor() async throws {
        h.internet.addLibretro("Nintendo_-_Game_Boy", ["Tetris (World) (Rev 1)"])
        h.internet.addLibretro("Nintendo_-_Game_Boy_Color", ["Tetris DX (World)"])

        let dx = try await h.libretro.names(system: "openemu.system.gb", fileName: "Tetris DX (World).gbc", titles: [])
        let tetris = try await h.libretro.names(system: "openemu.system.gb", fileName: "Tetris (W) (V1.1) [!].gb", titles: [])

        #expect(dx?.boxart == "Nintendo - Game Boy Color/Named_Boxarts/Tetris DX (World).png")
        #expect(tetris?.boxart == "Nintendo - Game Boy/Named_Boxarts/Tetris (World) (Rev 1).png")
    }

    @Test func aColourROMPrefersGameBoyColourOverAGameBoyGameOfTheSameName() async throws {
        h.internet.addLibretro("Nintendo_-_Game_Boy", ["Looney Tunes (USA, Europe)"])
        h.internet.addLibretro("Nintendo_-_Game_Boy_Color", ["Looney Tunes (USA) (GB Compatible)"])

        let colour = try await h.libretro.names(system: "openemu.system.gb", fileName: "Looney Tunes (U) [C][!].7z", titles: [])
        let mono = try await h.libretro.names(system: "openemu.system.gb", fileName: "Looney Tunes (U) [!].7z", titles: [])

        #expect(colour?.boxart == "Nintendo - Game Boy Color/Named_Boxarts/Looney Tunes (USA) (GB Compatible).png")
        #expect(mono?.boxart == "Nintendo - Game Boy/Named_Boxarts/Looney Tunes (USA, Europe).png")
    }

    @Test func eachSystemsListingIsFetchedOnceNotPerROM() async throws {
        h.internet.addLibretro("Nintendo_-_Nintendo_Entertainment_System", ["Metroid (USA)", "Kid Icarus (USA, Europe)"])

        for file in ["Metroid (USA).nes", "Kid Icarus (UE).nes", "Zelda.nes"] {
            _ = try await h.libretro.names(system: "openemu.system.nes", fileName: file, titles: [])
        }
        try h.reopen()
        _ = try await h.libretro.names(system: "openemu.system.nes", fileName: "Metroid (USA).nes", titles: [])

        #expect(h.internet.sent(to: FakeInternet.Hosts.github).count == 1)
    }

    @Test func aSystemWithoutARepoHasNoNames() async throws {
        #expect(try await h.libretro.names(system: "openemu.system.unknown", fileName: "x.bin", titles: []) == nil)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func imagesComeFromTheCDNOnceAndAreCached() async throws {
        h.internet.addLibretro("Sony_-_PlayStation", ["Parasite Eve II (USA)"])
        let path = "Sony - PlayStation/Named_Boxarts/Parasite Eve II (USA).png"

        let file = try await h.libretro.image(path)
        _ = try await h.libretro.image(path)

        #expect(try Data(contentsOf: file) == FakeInternet.boxartPNG)
        #expect(h.internet.sent(to: FakeInternet.Hosts.libretro).count == 1)
    }

    @Test func anImageTheCDNHasntCaughtUpWithComesFromGitHub() async throws {
        h.internet.addLibretro("Sony_-_PlayStation", ["Evil Dead - Hail to the King (USA)"])
        let path = "Sony - PlayStation/Named_Boxarts/Evil Dead - Hail to the King (USA).png"
        _ = h.internet.state.withLock { $0.libretroCDNMissing.insert(path) }

        let file = try await h.libretro.image(path)

        #expect(try Data(contentsOf: file) == FakeInternet.boxartPNG)
        #expect(h.internet.sent(to: FakeInternet.Hosts.githubRaw).count == 1)
    }

    @Test func aSymlinkFromGitHubIsntTakenForAnImage() async throws {
        h.internet.addLibretro("Sony_-_PlayStation", ["X (USA) (Disc 2)"])
        let path = "Sony - PlayStation/Named_Boxarts/X (USA) (Disc 2).png"
        h.internet.state.withLock {
            $0.libretroCDNMissing.insert(path)
            $0.libretroSymlinks.insert(path)
        }

        await #expect(throws: HTTPStatusError.self) { try await h.libretro.image(path) }
    }

    @Test func aMissingImageThrows() async throws {
        await #expect(throws: HTTPStatusError.self) { try await h.libretro.image("Sony - PlayStation/Named_Boxarts/Nope.png") }
    }
}
