import Testing

@testable import LudeumCore

@Suite struct ScreenshotGridTests {
    @Test func nintendoDSScreenshotsAreFourPortraitOnesInOneRow() {
        let grid = ScreenshotGrid.of(platformId: 20)  // Nintendo DS
        #expect(grid.columns == 4)
        #expect(grid.rows == 1)
        #expect(grid.limit == 4)
        #expect(grid.portrait)
        #expect(grid.aspectRatio == 2.0 / 3)
    }

    @Test func everyOtherPlatformsScreenshotsAreSixLandscapeOnesInTwoRowsOfThree() {
        // PlayStation, SNES, PlayStation Portable, and none known.
        for platformId: Int64? in [7, 19, 38, nil] {
            let grid = ScreenshotGrid.of(platformId: platformId)
            #expect(grid.columns == 3)
            #expect(grid.rows == 2)
            #expect(grid.limit == 6)
            #expect(!grid.portrait)
            #expect(grid.aspectRatio == 16.0 / 9)
        }
    }
}
