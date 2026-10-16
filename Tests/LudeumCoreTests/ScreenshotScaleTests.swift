import Testing

@testable import LudeumCore

@Suite struct ScreenshotScaleTests {
    @Test func aScreenshotAtLeast200PixelsEachWayIsntScaled() {
        #expect(screenshotScale(pixelWidth: 800, pixelHeight: 600) == 1)
        #expect(screenshotScale(pixelWidth: 200, pixelHeight: 200) == 1)
    }

    @Test func aSmallerOneIsScaledByTheLeastWholeAmountThatTakesItsShorterSideTo200() {
        // Game Boy: 144 high needs ×2.
        #expect(screenshotScale(pixelWidth: 160, pixelHeight: 144) == 2)
        // 100 exactly needs only ×2.
        #expect(screenshotScale(pixelWidth: 100, pixelHeight: 100) == 2)
        #expect(screenshotScale(pixelWidth: 256, pixelHeight: 66) == 4)
        #expect(screenshotScale(pixelWidth: 1, pixelHeight: 1) == 200)
    }

    @Test func anImageWithNoPixelsIsntScaled() {
        #expect(screenshotScale(pixelWidth: 0, pixelHeight: 0) == 1)
    }
}
