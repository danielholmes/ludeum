import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LudeumCore

/// A solid-colour image of the given size, encoded as `type`.
func testImage(width: Int, height: Int, type: UTType = .png) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

@Suite struct CoverNormalisingTests {
    @Test func aLargeImageShrinksToA1200PixelLongEdgeAsJPEG() throws {
        let cover = try CoverImage.normalise(testImage(width: 2400, height: 3000))

        #expect(cover.height == 1200)
        #expect(cover.width == 960)
        #expect(UTType(CGImageSourceGetType(CGImageSourceCreateWithData(cover.jpeg as CFData, nil)!)! as String) == .jpeg)
    }

    @Test func aSmallImageIsNeverEnlarged() throws {
        let cover = try CoverImage.normalise(testImage(width: 300, height: 400, type: .tiff))

        #expect(cover.width == 300)
        #expect(cover.height == 400)
    }

    @Test func theSameImageGivesTheSameHash() throws {
        let image = testImage(width: 100, height: 100)
        let a = try CoverImage.normalise(image)
        let b = try CoverImage.normalise(image)

        #expect(a.sha256 == b.sha256)
        #expect(a.sha256.count == 64)
    }

    @Test func transparencyBecomesWhiteNotBlack() throws {
        let context = CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let png = NSMutableData()
        let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)

        let cover = try CoverImage.normalise(png as Data)

        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(cover.jpeg as CFData, nil)!, 0, nil)!
        let pixel = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixel.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let red = pixel.data!.load(as: UInt8.self)
        #expect(red > 240)
    }

    @Test func somethingThatIsntAnImageIsRefused() {
        #expect(throws: CoverError.notAnImage) { try CoverImage.normalise(Data("not an image".utf8)) }
    }
}

/// The Cover order: upload, libretro Box art, LaunchBox Box art, a Bundle's Cover, IGDB Cover art, placeholder.
@Suite struct CoverOrderTests {
    let h: Harness
    let j: LudeumHarness
    static let snes = "Nintendo_-_Super_Nintendo_Entertainment_System"

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        let snes: [String: Any] = ["id": 19, "name": "SNES"]
        h.internet.addPlatform(19, "SNES")
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes], "cover": ["image_id": "co1"]])
        try j.journal.addPlatform(id: 19, name: "SNES")
    }

    var covers: Covers { h.covers(j.journal) }

    /// Super Metroid, linked to IGDB, with these ROM files (present unless `missing`) looked up in libretro.
    func superMetroid(_ roms: [String], missing: Set<String> = []) async throws -> GameID {
        let game = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        for file in roms { try j.journal.recordROM(game: game, fileName: file, missing: missing.contains(file)) }
        await BoxArtImport(journal: j.journal, libretro: h.libretro).run()
        return game
    }

    @Test func libretroBoxArtComesFirst() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan, USA) (En)"])
        let game = try await superMetroid(["Super Metroid (USA).sfc"])

        let cover = try await covers.cover(for: game)

        let path = "Nintendo - Super Nintendo Entertainment System/Named_Boxarts/Super Metroid (Japan, USA) (En).png"
        guard case .libretro(let file, path) = cover else {
            Issue.record("expected libretro's Box art, got \(cover)")
            return
        }
        #expect(try Data(contentsOf: file) == FakeInternet.boxartPNG)
    }

    @Test func withNoBoxArtIGDBsCoverArtShows() async throws {
        let game = try await superMetroid(["Super Metroid (USA).sfc"])

        guard case .igdb(let file, "co1") = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
        #expect(file.lastPathComponent == "co1.jpg")
    }

    @Test func aCoverWhoseIGDBRecordHasExpiredShowsWithoutWaitingOnIGDB() async throws {
        let game = try await superMetroid([])
        _ = try await covers.cover(for: game)
        h.clock.advance(days: 61)
        h.internet.resetSent()

        guard case .igdb(_, "co1") = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
        #expect(h.internet.sent(to: FakeInternet.Hosts.igdb).isEmpty)
    }

    @Test func aRecordFetchedAgainGivesItsNewCoverArt() async throws {
        let game = try await superMetroid([])
        _ = try await covers.cover(for: game)
        h.internet.addGame(1103, "Super Metroid", fields: ["cover": ["image_id": "co2"]])
        h.clock.advance(days: 61)

        _ = try await h.igdb.games(ids: [1103])

        guard case .igdb(_, "co2") = try await covers.cover(for: game) else {
            Issue.record("expected the new Cover art")
            return
        }
    }

    @Test func aGameWithNoROMShowsIGDBsCoverArtAndAHandMadeOneAPlaceholder() async throws {
        let pc = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        let hand = try j.journal.addGameByHand(name: "Hermano", platformId: 19)

        guard case .igdb = try await covers.cover(for: pc) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
        #expect(try await covers.cover(for: hand) == .placeholder)
    }

    @Test func aGameWithNoBoxArtShowsItsFirstBundlesCoverBeforeItsOwnCoverArt() async throws {
        h.internet.addGame(1104, "Metroid Collection", fields: ["cover": ["image_id": "co9"]])
        let bundle = try j.journal.addBundle(platformId: 19, name: "Metroid Collection", igdbGameId: 1104, igdbName: "Metroid Collection")
        let other = try j.journal.addBundle(platformId: 19, name: "Metroid Deluxe")
        let game = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        try j.journal.addToBundle(bundle, game)
        try j.journal.addToBundle(other, game)

        guard case .igdb(_, "co9") = try await covers.cover(for: game) else {
            Issue.record("expected its Bundle's Cover")
            return
        }
    }

    @Test func aGameWhoseBundleHasNoCoverShowsItsOwnCoverArt() async throws {
        let bundle = try j.journal.addBundle(platformId: 19, name: "Metroid Deluxe")
        let game = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        try j.journal.addToBundle(bundle, game)

        guard case .igdb(_, "co1") = try await covers.cover(for: game) else {
            Issue.record("expected its own Cover art")
            return
        }
    }

    @Test func anUploadWinsOnAnyGameAndRemovingItFallsBack() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        let game = try await superMetroid(["Super Metroid (USA).sfc"])

        try covers.upload(testImage(width: 600, height: 800), for: game)
        guard case .upload(let upload) = try await covers.cover(for: game) else {
            Issue.record("expected the upload")
            return
        }
        #expect(upload.width == 600)

        try covers.remove(for: game)
        guard case .libretro = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
    }

    @Test func thePresentVersionsBoxArtWinsOverAMissingOnes() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan)", "Super Metroid (Europe)"])
        let game = try await superMetroid(
            ["Super Metroid (Japan).sfc", "Super Metroid (Europe).sfc"], missing: ["Super Metroid (Japan).sfc"])

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path.hasSuffix("Super Metroid (Europe).png"))
    }

    @Test func withNothingPresentTheMostRecentlyAddedMissingROMsBoxArtShows() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan)", "Super Metroid (Europe)"])
        let roms = ["Super Metroid (Japan).sfc", "Super Metroid (Europe).sfc"]
        let game = try await superMetroid(roms, missing: Set(roms))

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path.hasSuffix("Super Metroid (Europe).png"))
    }

    @Test func aMultiDiscGameShowsItsDisclessBoxArt() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)", "Super Metroid (USA) (Disc 2)"])
        let game = try await superMetroid(["Super Metroid (USA) (Disc 2).cue", "Super Metroid (USA) (Disc 1).cue"])

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path.hasSuffix("/Super Metroid (USA).png"))
    }

    @Test func aFailedDownloadThrowsRatherThanFallingBack() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        let game = try await superMetroid(["Super Metroid (USA).sfc"])
        h.internet.setDown(FakeInternet.Hosts.libretro, true)

        await #expect(throws: (any Error).self) { try await covers.cover(for: game) }
    }

    @Test func aGameWithNoROMShowsBoxArtFoundByItsName() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan, USA) (En)"])
        let game = try await superMetroid([])

        guard case .libretro(let file, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path == "Nintendo - Super Nintendo Entertainment System/Named_Boxarts/Super Metroid (Japan, USA) (En).png")
        #expect(try Data(contentsOf: file) == FakeInternet.boxartPNG)
    }

    @Test func aGameWithNoROMGetsTheBoxForItsCopysRegionsElseUSAs() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan)", "Super Metroid (Europe)", "Super Metroid (USA)"])
        let game = try await superMetroid([])

        guard case .libretro(_, let usa) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(usa.hasSuffix("/Super Metroid (USA).png"))

        try j.journal.addCopy(game, CopyDraft(kind: .physical, details: CopyDetails(regions: ["Australia"]), gone: Gone()))
        guard case .libretro(_, let pal) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(pal.hasSuffix("/Super Metroid (Europe).png"))
    }

    @Test func aGameWithNoROMIsFoundByIGDBsNameWhenItsShownNameDiffers() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        let game = try await superMetroid([])
        try j.journal.setNameOverride(game, "Metroid 3")

        guard case .libretro = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
    }

    @Test func aGameWithNoROMAndNoMatchShowsIGDBsCoverArt() async throws {
        h.internet.addLibretro(Self.snes, ["Super Mario World (USA)"])
        let game = try await superMetroid([])

        guard case .igdb(_, "co1") = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
    }

    @Test func aGameWithNoROMWhoseListingCantBeReadShowsIGDBsCoverArtAndTriesAgainNextTime() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        let game = try await superMetroid([])
        h.internet.setLibretroDown(true)

        guard case .igdb = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }

        h.internet.setLibretroDown(false)
        guard case .libretro = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
    }

    @Test func aGameOnAPlatformWithNoROMFolderShowsBoxArtFoundByItsName() async throws {
        h.internet.addGame(2001, "Max Payne", fields: ["cover": ["image_id": "co8"]])
        h.internet.addLibretro("Microsoft_-_Xbox", ["Max Payne (USA)"])
        try j.journal.addPlatform(id: 11, name: "Xbox")
        let game = try j.journal.addGame(platformId: 11, name: "Max Payne", igdbGameId: 2001, igdbName: "Max Payne")

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path == "Microsoft - Xbox/Named_Boxarts/Max Payne (USA).png")
    }

    @Test func aGameOnAPlatformLibretroHasNoBoxesForNeverAsksLibretro() async throws {
        h.internet.addGame(2000, "Myst", fields: ["cover": ["image_id": "co9"]])
        try j.journal.addPlatform(id: 14, name: "Mac")
        let game = try j.journal.addGame(platformId: 14, name: "Myst", igdbGameId: 2000, igdbName: "Myst")

        guard case .igdb(_, "co9") = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
        #expect(h.internet.sent(to: FakeInternet.Hosts.github).isEmpty)
    }

    @Test func aPCGameShowsItsDOSBoxArt() async throws {
        h.internet.addGame(2002, "Command & Conquer: Red Alert", fields: ["cover": ["image_id": "co9"]])
        h.internet.addLibretro("DOS", ["Command and Conquer - Red Alert (1997)"])
        try j.journal.addPlatform(id: 6, name: "PC (Microsoft Windows)")
        let game = try j.journal.addGame(
            platformId: 6, name: "Command & Conquer: Red Alert", igdbGameId: 2002,
            igdbName: "Command & Conquer: Red Alert")

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's DOS Box art")
            return
        }
        #expect(path == "DOS/Named_Boxarts/Command and Conquer - Red Alert (1997).png")
    }

    @Test func aPCGameDOSHasNoBoxForShowsIGDBsCoverArt() async throws {
        h.internet.addGame(2000, "Half-Life", fields: ["cover": ["image_id": "co9"]])
        h.internet.addLibretro("DOS", ["Command and Conquer - Red Alert (1997)"])
        try j.journal.addPlatform(id: 6, name: "PC (Microsoft Windows)")
        let game = try j.journal.addGame(platformId: 6, name: "Half-Life", igdbGameId: 2000, igdbName: "Half-Life")

        guard case .igdb(_, "co9") = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
    }

    @Test func aGameWithNoLibretroBoxArtShowsLaunchBoxsBeforeItsBundlesCoverAndItsCoverArt() async throws {
        h.internet.addGame(2003, "Command & Conquer: Red Alert 2", fields: ["cover": ["image_id": "co9"]])
        h.internet.addGame(2004, "Command & Conquer: The First Decade", fields: ["cover": ["image_id": "co8"]])
        h.internet.setLaunchBox([
            LaunchBoxGame(id: 1, name: "Command & Conquer: Red Alert 2", platform: "Windows", boxes: [(nil, "ra2.jpg")])
        ])
        try await h.launchBox.refresh()
        try j.journal.addPlatform(id: 6, name: "PC (Microsoft Windows)")
        let bundle = try j.journal.addBundle(
            platformId: 6, name: "Command & Conquer: The First Decade", igdbGameId: 2004,
            igdbName: "Command & Conquer: The First Decade")
        let game = try j.journal.addGame(
            platformId: 6, name: "Command & Conquer: Red Alert 2", igdbGameId: 2003, igdbName: "Command & Conquer: Red Alert 2")
        try j.journal.addToBundle(bundle, game)

        guard case .launchBox(_, file: "ra2.jpg") = try await covers.cover(for: game) else {
            Issue.record("expected LaunchBox's Box art")
            return
        }
    }

    @Test func libretroBoxArtComesBeforeLaunchBoxs() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        h.internet.setLaunchBox([
            LaunchBoxGame(id: 1, name: "Super Metroid", platform: "Super Nintendo Entertainment System", boxes: [(nil, "sm.jpg")])
        ])
        try await h.launchBox.refresh()
        let game = try await superMetroid(["Super Metroid (USA).sfc"])

        guard case .libretro = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
    }

    @Test func aGameFindsLaunchBoxsBoxForItsIGDBYear() async throws {
        h.internet.addGame(2005, "Doom", fields: ["first_release_date": 1_463_097_600])  // 13 May 2016
        h.internet.setLaunchBox([
            LaunchBoxGame(id: 1, name: "Doom", platform: "Windows", released: "1993-12-10", boxes: [(nil, "doom93.jpg")]),
            LaunchBoxGame(id: 2, name: "Doom", platform: "Windows", released: "2016-05-13", boxes: [(nil, "doom16.jpg")]),
        ])
        try await h.launchBox.refresh()
        try j.journal.addPlatform(id: 6, name: "PC (Microsoft Windows)")
        let game = try j.journal.addGame(platformId: 6, name: "Doom", igdbGameId: 2005, igdbName: "Doom")

        guard case .launchBox(_, file: "doom16.jpg") = try await covers.cover(for: game) else {
            Issue.record("expected LaunchBox's Box art for 2016's Doom")
            return
        }
    }

    @Test func aCoverGoesWithItsGame() async throws {
        let game = try j.journal.addGameByHand(name: "Hermano", platformId: 19)
        try covers.upload(testImage(width: 60, height: 80), for: game)

        try j.journal.deleteGame(game)

        #expect(try j.journal.uploadedCover(game) == nil)
    }
}
