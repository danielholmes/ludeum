import Testing

@testable import LudeumCore

@Suite struct ScreenshotShapeTests {
    @Test func eachPlatformsScreenshotsAreItsScreensShape() {
        let shapes: [(Int64?, Double)] = [
            (33, 10.0 / 9),  // Game Boy, 160 × 144
            (22, 10.0 / 9),  // Game Boy Color
            (35, 10.0 / 9),  // Sega Game Gear
            (24, 3.0 / 2),  // Game Boy Advance, 240 × 160
            (18, 16.0 / 15),  // NES, 256 × 240
            (99, 16.0 / 15),  // Family Computer
            (19, 8.0 / 7),  // SNES, 256 × 224
            (58, 8.0 / 7),  // Super Famicom
            (29, 10.0 / 7),  // Mega Drive, 320 × 224
            (78, 10.0 / 7),  // Sega CD
            (13, 16.0 / 10),  // DOS, 320 × 200
            (16, 16.0 / 10),  // Amiga
            (7, 4.0 / 3),  // PlayStation, 640 × 480
            (8, 4.0 / 3),  // PlayStation 2
            (4, 4.0 / 3),  // Nintendo 64
            (21, 4.0 / 3),  // GameCube
            (64, 4.0 / 3),  // Master System, 256 × 192
            (20, 2.0 / 3),  // Nintendo DS, both screens
            (38, 16.0 / 9),  // PlayStation Portable, 480 × 272
            (48, 16.0 / 9),  // PlayStation 4
            (6, 16.0 / 9),  // PC
            (nil, 16.0 / 9),  // none known
        ]
        for (platformId, aspectRatio) in shapes {
            #expect(ScreenshotShape.of(platformId: platformId).aspectRatio == aspectRatio, "Platform \(String(describing: platformId))")
        }
    }

    @Test func onlyNintendoDSScreenshotsHoldTwoScreens() {
        #expect(ScreenshotShape.of(platformId: 20).screens == 2)
        for platformId: Int64? in [33, 7, 48, nil] { #expect(ScreenshotShape.of(platformId: platformId).screens == 1) }
    }

    @Test func onlyWidescreenOnesFitIGDBsThumbnails() {
        #expect(ScreenshotShape.of(platformId: 48).fitsThumbnail)
        #expect(ScreenshotShape.of(platformId: nil).fitsThumbnail)
        for platformId: Int64 in [33, 24, 7, 20] { #expect(!ScreenshotShape.of(platformId: platformId).fitsThumbnail) }
    }

    @Test func widescreenOnesInANarrowPanelAreTwoRowsOfThree() {
        let layout = ScreenshotShape.widescreen.layout(width: ScreenshotShape.narrowPanelWidth, spacing: 12)
        #expect(layout == ScreenshotLayout(columns: 3, rows: 2))
        #expect(layout.limit == 6)
    }

    @Test func aWiderPanelFitsMoreAcrossRatherThanTallerOnes() {
        #expect(ScreenshotShape.widescreen.layout(width: 640, spacing: 12) == ScreenshotLayout(columns: 4, rows: 2))
        #expect(ScreenshotShape.widescreen.layout(width: 840, spacing: 12) == ScreenshotLayout(columns: 5, rows: 2))
    }

    @Test func squarerOnesAreNarrowerSoMoreFitAcross() {
        let gameBoy = ScreenshotShape.of(platformId: 33)
        #expect(gameBoy.layout(width: 400, spacing: 12) == ScreenshotLayout(columns: 3, rows: 2))
        #expect(gameBoy.layout(width: 480, spacing: 12) == ScreenshotLayout(columns: 4, rows: 2))
        #expect(gameBoy.layout(width: 840, spacing: 12) == ScreenshotLayout(columns: 7, rows: 2))
    }

    @Test func nintendoDSOnesAreOneRowAsTwoWouldBeTallerThan300Points() {
        let ds = ScreenshotShape.of(platformId: 20)
        #expect(ds.layout(width: 400, spacing: 12) == ScreenshotLayout(columns: 3, rows: 1))
        #expect(ds.layout(width: 540, spacing: 12) == ScreenshotLayout(columns: 4, rows: 1))
        #expect(ds.layout(width: 840, spacing: 12) == ScreenshotLayout(columns: 6, rows: 1))
    }

    @Test func twoRowsAreAlwaysUnder300PointsTall() {
        for platformId: Int64? in [33, 24, 18, 19, 29, 13, 7, 20, nil] {
            let shape = ScreenshotShape.of(platformId: platformId)
            for width in stride(from: 200.0, through: 1200, by: 10) {
                let layout = shape.layout(width: width, spacing: 12)
                let tileHeight = (width - Double(layout.columns - 1) * 12) / Double(layout.columns) / shape.aspectRatio
                #expect(layout.columns >= 1)
                if layout.rows == 2 { #expect(2 * tileHeight + 12 < 300, "Platform \(String(describing: platformId)) at \(width)") }
            }
        }
    }
}
