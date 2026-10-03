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

@Suite struct IGDBAlwaysWinsTests {
    let h: Harness
    let j: JournalHarness

    init() throws {
        h = try Harness()
        j = try JournalHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
    }

    var covers: Covers { Covers(journal: j.journal, igdb: h.igdb) }
    var upload: Data { testImage(width: 600, height: 800) }

    @Test func aHandMadeGameCanUploadReplaceAndRemoveACover() async throws {
        let game = try j.journal.addGameByHand(name: "Hermano", platformId: 19)

        try await covers.upload(upload, for: game)
        #expect(try j.journal.journalCover(game)?.origin == .uploaded)
        try await covers.upload(testImage(width: 100, height: 100), for: game)
        #expect(try j.journal.journalCover(game)?.width == 100)
        guard case .journal = try await covers.cover(for: game) else {
            Issue.record("expected the uploaded cover")
            return
        }

        try await covers.remove(for: game)
        #expect(try await covers.cover(for: game) == .placeholder)
    }

    @Test func aLinkedGameWithAnIGDBCoverShowsItAndRefusesUploads() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["cover": ["image_id": "co1"]])
        let game = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")

        guard case .igdb(let file) = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's cover")
            return
        }
        #expect(file.lastPathComponent == "co1.jpg")
        #expect(try await !covers.canUpload(for: game))
        await #expect(throws: CoverError.igdbHasACover) { try await covers.upload(upload, for: game) }
    }

    @Test func aLinkedGameWithoutAnIGDBCoverCanUpload() async throws {
        h.internet.addGame(5, "Obscure Homebrew")
        let game = try j.journal.addGame(platformId: 19, name: "Obscure Homebrew", igdbGameId: 5, igdbName: "Obscure Homebrew")

        #expect(try await covers.canUpload(for: game))
        try await covers.upload(upload, for: game)
        guard case .journal = try await covers.cover(for: game) else {
            Issue.record("expected the uploaded cover")
            return
        }
    }

    @Test func gainingALinkWithACoverDeletesTheJournalCover() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["cover": ["image_id": "co1"]])
        let game = try j.journal.addGameByHand(name: "Metroid 3", platformId: 19)
        try await covers.upload(upload, for: game)
        try j.journal.link(game, igdbGameId: 1103, igdbName: "Super Metroid")

        try await covers.reconcile(game)

        #expect(try j.journal.journalCover(game) == nil)
        guard case .igdb = try await covers.cover(for: game) else {
            Issue.record("expected IGDB's cover")
            return
        }
    }

    @Test func showingACoverAlsoReconciles() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["cover": ["image_id": "co1"]])
        let game = try j.journal.addGameByHand(name: "Metroid 3", platformId: 19)
        try await covers.upload(upload, for: game)
        try j.journal.link(game, igdbGameId: 1103, igdbName: "Super Metroid")

        _ = try await covers.cover(for: game)

        #expect(try j.journal.journalCover(game) == nil)
    }

    @Test func withoutIGDBALinkedGameCantUpload() async throws {
        let game = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        let hand = try j.journal.addGameByHand(name: "Hermano", platformId: 19)
        let offline = Covers(journal: j.journal, igdb: nil)

        #expect(try await !offline.canUpload(for: game))
        #expect(try await offline.canUpload(for: hand))
    }

    @Test func aFailedDownloadKeepsTheJournalCover() async throws {
        h.internet.addGame(5, "Obscure Homebrew")
        let game = try j.journal.addGame(platformId: 19, name: "Obscure Homebrew", igdbGameId: 5, igdbName: "Obscure Homebrew")
        try await covers.upload(upload, for: game)
        h.internet.addGame(5, "Obscure Homebrew", fields: ["cover": ["image_id": "co5"]])
        try h.cache.store(["igdb:game:5": Data(#"{"id":5,"name":"Obscure Homebrew","cover":{"image_id":"co5"}}"#.utf8)])
        h.internet.setDown(FakeInternet.Hosts.igdbImages, true)

        await #expect(throws: (any Error).self) { try await covers.cover(for: game) }

        #expect(try j.journal.journalCover(game) != nil)
    }

    @Test func aCoverGoesWithItsGame() async throws {
        let game = try j.journal.addGameByHand(name: "Hermano", platformId: 19)
        try await covers.upload(upload, for: game)

        try j.journal.deleteGame(game)

        #expect(try j.journal.journalCover(game) == nil)
    }
}
