import Foundation
import Testing

@testable import LudeumCore

@Suite struct LibretroThumbnailsTests {
    let h: Harness

    init() throws { h = try Harness() }

    @Test func aROMGetsItsBoxartSnapAndTitleNames() async throws {
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (Japan, USA) (En)"])
        h.internet.addLibretro(
            "Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (Europe) (En,Fr,De)"], folders: ["Named_Snaps"])

        let names = try await h.libretro.names(platform: 19, fileName: "Super Metroid (E).sfc", titles: [])

        let repo = "Nintendo - Super Nintendo Entertainment System"
        #expect(names?.boxart == "\(repo)/Named_Boxarts/Super Metroid (Japan, USA) (En).png")
        #expect(names?.snap == "\(repo)/Named_Snaps/Super Metroid (Europe) (En,Fr,De).png")
        #expect(names?.title == "\(repo)/Named_Titles/Super Metroid (Japan, USA) (En).png")
    }

    @Test func eachPlatformLooksInItsOwnLibretroFolder() async throws {
        h.internet.addLibretro("Nintendo_-_Game_Boy", ["Looney Tunes (USA, Europe)"])
        h.internet.addLibretro("Nintendo_-_Game_Boy_Color", ["Looney Tunes (USA) (GB Compatible)"])
        h.internet.addLibretro("Nintendo_-_Nintendo_Entertainment_System", ["Zelda no Densetsu (Japan)"])

        let colour = try await h.libretro.names(platform: 22, fileName: "Looney Tunes (U) [C][!].7z", titles: [])
        let mono = try await h.libretro.names(platform: 33, fileName: "Looney Tunes (U) [!].7z", titles: [])
        let famicom = try await h.libretro.names(platform: 99, fileName: "Zelda no Densetsu (Japan).nes", titles: [])

        #expect(colour?.boxart == "Nintendo - Game Boy Color/Named_Boxarts/Looney Tunes (USA) (GB Compatible).png")
        #expect(mono?.boxart == "Nintendo - Game Boy/Named_Boxarts/Looney Tunes (USA, Europe).png")
        #expect(famicom?.boxart == "Nintendo - Nintendo Entertainment System/Named_Boxarts/Zelda no Densetsu (Japan).png")
    }

    @Test func aWiiWareWADLooksInWiisLibretroFolder() async throws {
        h.internet.addLibretro("Nintendo_-_Wii", ["World of Goo (USA) (WiiWare)"])

        let names = try await h.libretro.names(platform: 5, fileName: "World of Goo (USA) (WiiWare).wad", titles: [])

        #expect(names?.boxart == "Nintendo - Wii/Named_Boxarts/World of Goo (USA) (WiiWare).png")
    }

    @Test func eachPlatformsListingIsFetchedOnceNotPerROM() async throws {
        h.internet.addLibretro("Nintendo_-_Nintendo_Entertainment_System", ["Metroid (USA)", "Kid Icarus (USA, Europe)"])

        for file in ["Metroid (USA).nes", "Kid Icarus (UE).nes", "Zelda.nes"] {
            _ = try await h.libretro.names(platform: 18, fileName: file, titles: [])
        }
        try h.reopen()
        _ = try await h.libretro.names(platform: 18, fileName: "Metroid (USA).nes", titles: [])

        #expect(h.internet.sent(to: FakeInternet.Hosts.github).count == 1)
    }

    @Test func aPlatformWithoutARepoHasNoNames() async throws {
        #expect(try await h.libretro.names(platform: 9999, fileName: "x.bin", titles: []) == nil)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func imagesDontWaitTheirTurnAtGitHubsRateLimit() async throws {
        let games = ["Parasite Eve II (USA)", "Vagrant Story (USA)", "Xenogears (USA)"]
        h.internet.addLibretro("Sony_-_PlayStation", games)

        for game in games { _ = try await h.libretro.image("Sony - PlayStation/Named_Boxarts/\(game).png") }

        let times = h.internet.sent(to: FakeInternet.Hosts.libretro).map(\.at)
        #expect(times.count == 3)
        #expect(Set(times).count == 1)
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
