import Foundation
import Testing

@testable import LudeumCore

/// Where an Xbox disc image has its game partition's media header: 64 KiB into an XISO, and 64 KiB into the game
/// partition, 387 MiB in, in a full Redump image.
enum XboxHeader {
    static let xiso: UInt64 = 0x10000
    static let redump: UInt64 = 0x1831_0000

    /// Writes `text` (the media header unless said otherwise) `at` its offset into `file`, made sparse up to it.
    @discardableResult
    static func write(into file: URL, at offset: UInt64, _ text: String = "MICROSOFT*XBOX*MEDIA") throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: Data(text.utf8))
        return file
    }
}

@Suite struct XboxDiscTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "xbox disc \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func anXISOHasTheGamePartitionAtTheStart() throws {
        let file = try XboxHeader.write(into: directory.appending(path: "Halo.iso"), at: XboxHeader.xiso)

        #expect(XboxDisc.kind(of: file) == .xiso)
    }

    @Test func aFullRedumpImageHasItAfterTheVideoPartition() throws {
        let file = try XboxHeader.write(into: directory.appending(path: "Halo.iso"), at: XboxHeader.redump)

        #expect(XboxDisc.kind(of: file) == .redump)
    }

    @Test func anythingElseIsUnknown() throws {
        let file = try XboxHeader.write(into: directory.appending(path: "Halo.iso"), at: XboxHeader.xiso, "NOT*THE*XBOX*HEADER*")

        #expect(XboxDisc.kind(of: file) == .unknown)
        #expect(XboxDisc.kind(of: directory.appending(path: "Nowhere.iso")) == .unknown)
    }
}
