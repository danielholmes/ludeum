import CoreGraphics
import Foundation
import ImageIO

/// What a Screenshot looks like, to tell whether two images are the same Screenshot whatever their size or format:
/// IGDB's JPEG, often scaled up, and LaunchBox's PNG at the console's own size. The image is shrunk to 17 × 16 in grey,
/// and each of 256 spots is darker than the spot to its right, lighter, or about the same (a difference hash with a
/// tolerance). Two are compared only where either has an edge, as flat spots (a black screen, a plain background)
/// agree with anything flat.
public struct ScreenshotFingerprint: Sendable, Equatable {
    /// The spots darker than the one to their right, then those lighter, one bit each.
    let darker: [UInt64]
    let lighter: [UInt64]

    static let columns = 16
    static let rows = 16
    /// How much darker or lighter, out of 255, a spot has to be than the next for an edge: less is JPEG's noise.
    static let tolerance = 6
    /// The fewest edges an image has for there to be anything to tell it apart by: a black screen, or one nearly so,
    /// isn't the same as anything.
    static let fewestEdges = 24
    /// The share of the spots where either has an edge that two can disagree on and be the same Screenshot: a different
    /// crop or palette, or JPEG's blur, moves a few; a different picture most.
    static let mostApart = 0.3

    /// The fingerprint of an image file; nil when it isn't one, or it's blank.
    public init?(contentsOf file: URL) {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        self.init(source)
    }

    /// The fingerprint of an image; nil when it isn't one, or it's blank.
    init?(_ data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        self.init(source)
    }

    private init?(_ source: CGImageSource) {
        // Decoded small first: a 1080p JPEG decodes at an eighth of its size.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ]
        let width = Self.columns + 1
        guard CGImageSourceGetCount(source) > 0,
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let context = CGContext(
                data: nil, width: width, height: Self.rows, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
            let pixels = context.data
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: Self.rows))
        let grey = UnsafeBufferPointer(start: pixels.assumingMemoryBound(to: UInt8.self), count: width * Self.rows)
        var darker = [UInt64](repeating: 0, count: Self.columns * Self.rows / 64)
        var lighter = darker
        for row in 0..<Self.rows {
            for column in 0..<Self.columns {
                let step = Int(grey[row * width + column + 1]) - Int(grey[row * width + column])
                let spot = row * Self.columns + column
                if step > Self.tolerance { darker[spot / 64] |= 1 << UInt64(spot % 64) }
                if step < -Self.tolerance { lighter[spot / 64] |= 1 << UInt64(spot % 64) }
            }
        }
        guard zip(darker, lighter).reduce(0, { $0 + ($1.0 | $1.1).nonzeroBitCount }) >= Self.fewestEdges else { return nil }
        self.darker = darker
        self.lighter = lighter
    }

    /// Whether the two are the same Screenshot: they disagree on at most `mostApart` of the spots where either has an
    /// edge.
    public func isSameScreenshot(as other: ScreenshotFingerprint) -> Bool {
        apart(other) <= Self.mostApart
    }

    /// The share of the spots where either has an edge that the two disagree on.
    func apart(_ other: ScreenshotFingerprint) -> Double {
        var edges = 0
        var disagreeing = 0
        for word in darker.indices {
            edges += (darker[word] | lighter[word] | other.darker[word] | other.lighter[word]).nonzeroBitCount
            disagreeing += ((darker[word] ^ other.darker[word]) | (lighter[word] ^ other.lighter[word])).nonzeroBitCount
        }
        return Double(disagreeing) / Double(edges)
    }

    /// Those of `candidates` that aren't the same Screenshot as any of `others`, in their order: one with no fingerprint
    /// (not read, or blank) is kept, as nothing says it's one of them.
    public static func unmatched<ID>(_ candidates: [(ID, ScreenshotFingerprint?)], by others: [ScreenshotFingerprint]) -> [ID] {
        candidates.filter { _, fingerprint in
            guard let fingerprint else { return true }
            return !others.contains { fingerprint.isSameScreenshot(as: $0) }
        }.map(\.0)
    }
}
