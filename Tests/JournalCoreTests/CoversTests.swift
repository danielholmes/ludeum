import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import JournalCore

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

/// The Cover order: upload, libretro Box art, OpenEmu Box art, IGDB Cover art, placeholder.
@Suite struct CoverOrderTests {
    let h: Harness
    let j: JournalHarness
    let oe: FakeOpenEmu
    static let snes = "Nintendo_-_Super_Nintendo_Entertainment_System"

    init() throws {
        h = try Harness()
        j = try JournalHarness()
        oe = try FakeOpenEmu(in: h.directory)
        let snes: [String: Any] = ["id": 19, "name": "SNES"]
        h.internet.addPlatform(19, "SNES")
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes], "cover": ["image_id": "co1"]])
        for md5 in ["aa", "a2", "a3"] { h.internet.addHash(md5: md5, game: 1103, platform: 19) }
        try j.journal.addPlatform(id: 19, name: "SNES")
    }

    var covers: Covers { h.covers(j.journal) }

    func firstImport() async throws -> GameID {
        let run = FirstImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, draftFolder: h.directory.appending(path: "draft"),
            libretro: h.libretro)
        try await run.commit(try await run.start(library: oe.folder) { _, _ in })
        return try #require(try j.journal.library(LibraryFilter(), sort: .name, ascending: true).first?.id)
    }

    @Test func libretroBoxArtComesFirst() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan, USA) (En)"])
        try oe.addROM("Super Metroid (USA)", md5: "aa", boxArt: testImage(width: 20, height: 28))
        let game = try await firstImport()

        let cover = try await covers.cover(for: game)

        let path = "Nintendo - Super Nintendo Entertainment System/Named_Boxarts/Super Metroid (Japan, USA) (En).png"
        guard case .libretro(let file, path) = cover else {
            Issue.record("expected libretro's Box art, got \(cover)")
            return
        }
        #expect(try Data(contentsOf: file) == FakeInternet.boxartPNG)
    }

    @Test func withoutLibretroOpenEmusBoxArtComesFromTheCache() async throws {
        let art = testImage(width: 20, height: 28)
        let pk = try oe.addROM("Super Metroid (USA)", md5: "aa", boxArt: art)
        let game = try await firstImport()
        try FileManager.default.removeItem(at: oe.folder.appending(path: "Artwork/ART-\(pk)"))  // the cache has its own copy

        guard case .openEmu(let file, "ART-\(pk)") = try await covers.cover(for: game) else {
            Issue.record("expected OpenEmu's Box art")
            return
        }
        #expect(try Data(contentsOf: file) == art)
    }

    @Test func withNoBoxArtIGDBsCoverArtShows() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        let game = try await firstImport()

        guard case .igdb(let file, "co1") = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's Cover art")
            return
        }
        #expect(file.lastPathComponent == "co1.jpg")
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

    @Test func anUploadWinsOnAnyGameAndRemovingItFallsBack() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        let game = try await firstImport()

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
        try oe.addROM("Super Metroid (Japan)", md5: "aa", fileName: nil)
        try oe.addROM("Super Metroid (Europe)", md5: "a2")
        let game = try await firstImport()

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path.hasSuffix("Super Metroid (Europe).png"))
    }

    @Test func withNothingPresentTheMostRecentlyAddedMissingROMsBoxArtShows() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (Japan)", "Super Metroid (Europe)"])
        try oe.addROM("Super Metroid (Japan)", md5: "aa", fileName: nil)
        try oe.addROM("Super Metroid (Europe)", md5: "a2", fileName: nil)
        let game = try await firstImport()

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path.hasSuffix("Super Metroid (Europe).png"))
    }

    @Test func aMultiDiscGameShowsItsDisclessBoxArt() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)", "Super Metroid (USA) (Disc 2)"])
        try oe.addROM("Super Metroid (USA) (Disc 2)", md5: "a2", fileName: "Super Metroid (USA) (Disc 2).cue")
        try oe.addROM("Super Metroid (USA) (Disc 1)", md5: "aa", fileName: "Super Metroid (USA) (Disc 1).cue")
        let game = try await firstImport()

        guard case .libretro(_, let path) = try await covers.cover(for: game) else {
            Issue.record("expected libretro's Box art")
            return
        }
        #expect(path.hasSuffix("/Super Metroid (USA).png"))
    }

    @Test func aFailedDownloadThrowsRatherThanFallingBack() async throws {
        h.internet.addLibretro(Self.snes, ["Super Metroid (USA)"])
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        let game = try await firstImport()
        h.internet.setDown(FakeInternet.Hosts.libretro, true)

        await #expect(throws: (any Error).self) { try await covers.cover(for: game) }
    }

    @Test func aCoverGoesWithItsGame() async throws {
        let game = try j.journal.addGameByHand(name: "Hermano", platformId: 19)
        try covers.upload(testImage(width: 60, height: 80), for: game)

        try j.journal.deleteGame(game)

        #expect(try j.journal.uploadedCover(game) == nil)
    }
}
