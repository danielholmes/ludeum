import Foundation
import Testing

@testable import LudeumCore

/// The screenshot in a MesenCE save state, drawn as MesenCE draws each console's (ADR 0027).
@Suite struct MesenScreenshotTests {
    /// A state's header as MesenCE 2.2.1 writes it, with `frame` zlib-compressed, and some state after it.
    func state(console: UInt32, width: Int, height: Int, frame: [UInt16], name: String, format: UInt32 = 4) -> Data {
        var data = Data("MSS".utf8)
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let raw = frame.withUnsafeBytes { Data($0) }
        let deflated = try! (raw as NSData).compressed(using: .zlib) as Data
        var (a, b): (UInt32, UInt32) = (1, 0)
        for byte in raw { (a, b) = ((a + UInt32(byte)) % 65521, (b + (a + UInt32(byte)) % 65521) % 65521) }
        var packed = Data([0x78, 0x9C]) + deflated
        withUnsafeBytes(of: (b << 16 | a).bigEndian) { packed.append(contentsOf: $0) }
        u32(0x2_0201)
        u32(format)
        if format == 3 { data.append(Data(repeating: 0x61, count: 40)) }
        u32(console)
        u32(UInt32(raw.count))
        u32(UInt32(width))
        u32(UInt32(height))
        u32(100)
        u32(UInt32(packed.count))
        data.append(packed)
        u32(UInt32(name.utf8.count))
        data.append(Data(name.utf8))
        data.append(Data(repeating: 0xEE, count: 64))
        return data
    }

    /// A frame `width` × `height` of `fill`, with `pixels` set at their `x`, `y`.
    func frame(_ width: Int, _ height: Int, fill: UInt16 = 0, _ pixels: [(x: Int, y: Int, value: UInt16)]) -> [UInt16] {
        var frame = [UInt16](repeating: fill, count: width * height)
        for pixel in pixels { frame[pixel.y * width + pixel.x] = pixel.value }
        return frame
    }

    func rgb(_ shot: SaveStateScreenshot, _ x: Int, _ y: Int) -> [UInt8] {
        let at = (y * shot.width + x) * 4
        #expect(shot.rgba[at + 3] == 255)
        return [shot.rgba[at], shot.rgba[at + 1], shot.rgba[at + 2]]
    }

    @Test func anNESStateIsItsPaletteIndicesThroughMesenCEsPaletteWithEmphasis() throws {
        let pixels = frame(
            256, 240, fill: 0x0F,
            [(0, 0, 0x30), (1, 0, 0x16), (2, 0, 0x16 | 0x40), (3, 0, 0x16 | 0x1C0), (4, 0, 0x2E | 0x40), (255, 239, 0x21)])
        let url = FileManager.default.temporaryDirectory.appending(path: "mesen \(UUID().uuidString).mss")
        try state(console: 2, width: 256, height: 240, frame: pixels, name: "Castlevania (USA).nes").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let shot = try #require(MesenScreenshot.of(url))
        #expect((shot.width, shot.height) == (256, 240))
        #expect(shot.rgba.count == 256 * 240 * 4)
        #expect(rgb(shot, 0, 0) == [0xFF, 0xFE, 0xFF])
        #expect(rgb(shot, 1, 0) == [0xB5, 0x31, 0x20])
        // Red emphasised: green and blue darkened.
        #expect(rgb(shot, 2, 0) == [0xB5, 41, 26])
        // All three: each darkened twice.
        #expect(rgb(shot, 3, 0) == [127, 34, 22])
        // $xE isn't emphasised.
        #expect(rgb(shot, 4, 0) == [0, 0, 0])
        #expect(rgb(shot, 255, 239) == [0x64, 0xB0, 0xFF])
        #expect(rgb(shot, 100, 100) == [0, 0, 0])
    }

    @Test func anSNESStateIsCroppedAsMesenCECropsItsOverscan() throws {
        let pixels = frame(256, 239, [(0, 7, 0x001F), (255, 230, 0x7C00), (10, 6, 0x7FFF), (10, 231, 0x7FFF), (5, 100, 0x0200)])
        let shot = try #require(MesenScreenshot.decode(state(console: 0, width: 256, height: 239, frame: pixels, name: "Game.sfc")))
        #expect((shot.width, shot.height) == (256, 224))
        #expect(rgb(shot, 0, 0) == [255, 0, 0])
        #expect(rgb(shot, 255, 223) == [0, 0, 255])
        #expect(rgb(shot, 10, 0) == [0, 0, 0])
        #expect(rgb(shot, 10, 223) == [0, 0, 0])
        #expect(rgb(shot, 5, 93) == [0, 132, 0])

        let high = frame(512, 478, [(0, 14, 0x03E0), (511, 461, 0x7FFF)])
        let hires = try #require(MesenScreenshot.decode(state(console: 0, width: 512, height: 478, frame: high, name: "Game.sfc")))
        #expect((hires.width, hires.height) == (512, 448))
        #expect(rgb(hires, 0, 0) == [0, 255, 0])
        #expect(rgb(hires, 511, 447) == [255, 255, 255])
    }

    @Test func aGameBoyStatesColoursAreAdjustedAsAGameBoyColorsAre() throws {
        let pixels = frame(160, 144, [(0, 0, 0x7FFF), (1, 0, 0x001F), (159, 143, 0x7C00)])
        let shot = try #require(
            MesenScreenshot.decode(state(console: 1, width: 160, height: 144, frame: pixels, name: "DuckTales (USA).gb")))
        #expect((shot.width, shot.height) == (160, 144))
        #expect(rgb(shot, 0, 0) == [240, 240, 240])
        #expect(rgb(shot, 1, 0) == [201, 0, 46])
        #expect(rgb(shot, 159, 143) == [15, 62, 170])
        #expect(rgb(shot, 50, 50) == [0, 0, 0])
    }

    @Test func aGameBoyAdvanceStatesColoursAreAdjustedToItsScreen() throws {
        let pixels = frame(240, 160, [(0, 0, 0x7FFF), (1, 0, 0x8000), (239, 159, 0x001F)])
        let shot = try #require(MesenScreenshot.decode(state(console: 5, width: 240, height: 160, frame: pixels, name: "Game.gba")))
        #expect((shot.width, shot.height) == (240, 160))
        #expect(rgb(shot, 0, 0) == [248, 240, 244])
        // The top bit isn't colour.
        #expect(rgb(shot, 1, 0) == [0, 0, 0])
        #expect(rgb(shot, 239, 159) == [227, 53, 111])
    }

    /// A PC Engine frame: rows 682 wide, and a last row of each row's clock divider.
    func pcEngineFrame(dividers: (Int) -> UInt16, _ pixels: [(x: Int, y: Int, value: UInt16)]) -> [UInt16] {
        var frame = frame(682, 243, pixels)
        for row in 0..<242 { frame[682 * 242 + row] = dividers(row) }
        return frame
    }

    @Test func aPCEngineStateIsCroppedToItsPictureAtItsResolution() throws {
        let low = pcEngineFrame(
            dividers: { _ in 4 }, [(48, 3, 0x1FF), (49, 3, 0x038), (50, 3, 0x200 | 0x038), (303, 241, 0x1C0), (48, 2, 0x1FF)])
        let shot = try #require(MesenScreenshot.decode(state(console: 3, width: 1168, height: 968, frame: low, name: "Game.pce")))
        #expect((shot.width, shot.height) == (256, 239))
        #expect(rgb(shot, 0, 0) == [255, 255, 255])
        #expect(rgb(shot, 1, 0) == [0xC9, 0x11, 0x23])
        // Gray.
        #expect(rgb(shot, 2, 0) == [74, 74, 74])
        #expect(rgb(shot, 255, 238) == [0x25, 0xE3, 0x1F])

        let high = pcEngineFrame(dividers: { _ in 2 }, [(120, 3, 0x1FF), (631, 241, 0x007)])
        let hires = try #require(MesenScreenshot.decode(state(console: 3, width: 1168, height: 968, frame: high, name: "Game.cue")))
        #expect((hires.width, hires.height) == (512, 239))
        #expect(rgb(hires, 0, 0) == [255, 255, 255])
        #expect(rgb(hires, 511, 238) == [0x09, 0x03, 0xB5])
    }

    @Test func aPCEngineStateMixingResolutionsIsStretchedTo256Wide() throws {
        let mixed = pcEngineFrame(dividers: { $0 == 3 ? 2 : 4 }, [(120, 3, 0x1FF), (122, 3, 0x038), (48, 4, 0x038), (49, 4, 0x1FF)])
        let shot = try #require(MesenScreenshot.decode(state(console: 3, width: 1168, height: 968, frame: mixed, name: "Game.pce")))
        #expect((shot.width, shot.height) == (256, 239))
        #expect(rgb(shot, 0, 0) == [255, 255, 255])
        #expect(rgb(shot, 1, 0) == [0xC9, 0x11, 0x23])
        #expect(rgb(shot, 0, 1) == [0xC9, 0x11, 0x23])
        #expect(rgb(shot, 1, 1) == [255, 255, 255])
    }

    @Test func aMasterSystemStateIsItsFirst192RowsAndAGameGearsTheMiddle() throws {
        let pixels = frame(256, 240, [(0, 0, 0x03E0), (255, 191, 0x7FFF), (48, 24, 0x001F), (207, 167, 0x7C00)])
        let sms = try #require(MesenScreenshot.decode(state(console: 4, width: 256, height: 240, frame: pixels, name: "Game.sms")))
        #expect((sms.width, sms.height) == (256, 192))
        #expect(rgb(sms, 0, 0) == [0, 255, 0])
        #expect(rgb(sms, 255, 191) == [255, 255, 255])

        let gg = try #require(MesenScreenshot.decode(state(console: 4, width: 256, height: 240, frame: pixels, name: "Game.GG")))
        #expect((gg.width, gg.height) == (160, 144))
        #expect(rgb(gg, 0, 0) == [255, 0, 0])
        #expect(rgb(gg, 159, 143) == [0, 0, 255])
    }

    @Test func aFormat3StateSkipsItsSHA1() throws {
        let pixels = frame(160, 144, [(0, 0, 0x7FFF)])
        let shot = try #require(
            MesenScreenshot.decode(state(console: 1, width: 160, height: 144, frame: pixels, name: "Game.gb", format: 3)))
        #expect(rgb(shot, 0, 0) == [240, 240, 240])
    }

    @Test func aStateThatCantBeDecodedHasNone() {
        let good = state(console: 2, width: 256, height: 240, frame: frame(256, 240, []), name: "Game.nes")
        #expect(MesenScreenshot.decode(good) != nil)
        // WonderSwan.
        #expect(MesenScreenshot.decode(state(console: 6, width: 224, height: 144, frame: frame(224, 144, []), name: "Game.ws")) == nil)
        #expect(MesenScreenshot.decode(state(console: 9, width: 256, height: 240, frame: frame(256, 240, []), name: "Game.nes")) == nil)
        #expect(
            MesenScreenshot.decode(state(console: 2, width: 256, height: 240, frame: frame(256, 240, []), name: "Game.nes", format: 2))
                == nil)
        // A frame smaller than its console's.
        #expect(MesenScreenshot.decode(state(console: 2, width: 256, height: 240, frame: frame(256, 100, []), name: "Game.nes")) == nil)
        #expect(MesenScreenshot.decode(state(console: 3, width: 1168, height: 968, frame: frame(682, 200, []), name: "Game.pce")) == nil)
        #expect(MesenScreenshot.decode(good.prefix(60)) == nil)
        #expect(MesenScreenshot.decode(Data("MSS".utf8)) == nil)
        #expect(MesenScreenshot.decode(Data("not a save state at all, just some text".utf8)) == nil)
        var corrupt = good
        corrupt.replaceSubrange(40..<80, with: Data(repeating: 0xFF, count: 40))
        #expect(MesenScreenshot.decode(corrupt) == nil)
        #expect(MesenScreenshot.of(URL(filePath: "/nonexistent/Game_1.mss")) == nil)
    }
}
