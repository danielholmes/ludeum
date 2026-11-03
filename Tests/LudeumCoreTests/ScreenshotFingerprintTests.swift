import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LudeumCore

/// A made-up screenshot: blocks of grey and colour placed by `seed`, drawn at `width` × `height`, so the same seed at
/// another size or in another format is the same picture.
func screenshotImage(seed: UInt64, width: Int, height: Int, type: UTType = .png, quality: Double = 0.9) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
    context.setFillColor(red: next(), green: next(), blue: next(), alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for _ in 0..<24 {
        context.setFillColor(red: next(), green: next(), blue: next(), alpha: 1)
        let w = next() * 0.4
        let h = next() * 0.4
        context.fill(
            CGRect(
                x: next() * Double(width), y: next() * Double(height), width: w * Double(width), height: h * Double(height)))
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(
        destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
}

@Suite struct ScreenshotFingerprintTests {
    @Test func theSameScreenshotAtAnotherSizeAndInAnotherFormatIsTheSame() throws {
        let launchBox = try #require(ScreenshotFingerprint(screenshotImage(seed: 1, width: 320, height: 240)))
        let igdb = try #require(ScreenshotFingerprint(screenshotImage(seed: 1, width: 1024, height: 768, type: .jpeg, quality: 0.6)))

        #expect(launchBox.isSameScreenshot(as: igdb))
    }

    @Test func aDifferentScreenshotIsnt() throws {
        let one = try #require(ScreenshotFingerprint(screenshotImage(seed: 1, width: 320, height: 240)))
        for seed in UInt64(2)...30 {
            let other = try #require(ScreenshotFingerprint(screenshotImage(seed: seed, width: 320, height: 240)))
            #expect(!one.isSameScreenshot(as: other), "seed \(seed)")
        }
    }

    /// A blank or nearly blank screen (a black one between scenes) has nothing to tell it apart by.
    @Test func aBlankScreenIsntTheSameAsAnything() throws {
        #expect(ScreenshotFingerprint(testImage(width: 160, height: 144)) == nil)
    }

    @Test func whatIsntAnImageHasNoFingerprint() {
        #expect(ScreenshotFingerprint(Data("not an image".utf8)) == nil)
    }

    @Test func screenshotsAmongOthersAreLeftOutKeepingTheRestInOrder() throws {
        let igdb = [1, 2].map { ScreenshotFingerprint(screenshotImage(seed: $0, width: 640, height: 480, type: .jpeg)) }
        let launchBox: [(String, ScreenshotFingerprint?)] = [
            ("title.png", ScreenshotFingerprint(screenshotImage(seed: 3, width: 320, height: 240))),
            ("dupe.png", ScreenshotFingerprint(screenshotImage(seed: 2, width: 320, height: 240))),
            ("unreadable.png", nil),
            ("new.png", ScreenshotFingerprint(screenshotImage(seed: 4, width: 320, height: 240))),
        ]

        #expect(ScreenshotFingerprint.unmatched(launchBox, by: igdb.compactMap { $0 }) == ["title.png", "unreadable.png", "new.png"])
    }
}
