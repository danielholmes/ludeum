import Testing

@testable import LudeumCore

@Suite struct ScreenshotFitTests {
    /// The gallery on a 1440 × 900 screen.
    static let stage = (width: 1129.0, height: 635.0)

    func fit(_ width: Int, _ height: Int) -> ScreenshotFit {
        screenshotFit(pixelWidth: width, pixelHeight: height, width: Self.stage.width, height: Self.stage.height)
    }

    @Test func aSmallOneIsTheMostWholeTimesItsSizeThatFitsSharp() {
        // Game Boy: 4 × 144 = 576 fits 635; 5 × 144 doesn't.
        #expect(fit(160, 144) == ScreenshotFit(width: 640, height: 576, sharp: true))
        // PlayStation: 2 × 240 = 480.
        #expect(fit(320, 240) == ScreenshotFit(width: 640, height: 480, sharp: true))
        // Exactly twice fits.
        #expect(fit(564, 317) == ScreenshotFit(width: 1128, height: 634, sharp: true))
    }

    @Test func oneThatWouldntFitTwiceFillsTheSpaceSmoothed() {
        // IGDB's 640 × 480, already scaled up: as tall as the space.
        let scaledUp = fit(640, 480)
        #expect(scaledUp.height == 635)
        #expect(abs(scaledUp.width - 635 * 4 / 3) < 0.001)
        #expect(!scaledUp.sharp)
        // A 1080p one shrinks to fit.
        let big = fit(1920, 1080)
        #expect(abs(big.width - 1128.9) < 0.1)
        #expect(!big.sharp)
    }

    @Test func anImageWithNoPixelsTakesNoSpace() {
        #expect(fit(0, 0) == ScreenshotFit(width: 0, height: 0, sharp: false))
    }
}
