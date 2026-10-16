import Foundation

/// A game in the fake LaunchBox Games Database's dump, written out as its `Metadata.xml` would have it.
struct LaunchBoxGame {
    var id: Int
    var name: String
    var platform: String
    var released: String? = nil
    var alternateNames: [String] = []
    /// Box - Front scans, (region or nil, file name).
    var boxes: [(region: String?, file: String)] = []
    /// Other images, (type, file name).
    var otherImages: [(type: String, file: String)] = []

    /// `Metadata.xml` as LaunchBox writes it: every game, then every alternate name, then every image.
    static func xml(_ games: [LaunchBoxGame]) -> String {
        func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        var xml = "<?xml version=\"1.0\" standalone=\"yes\"?>\n<LaunchBox>\n"
        for g in games {
            xml += "  <Game>\n    <Name>\(escaped(g.name))</Name>\n"
            if let released = g.released { xml += "    <ReleaseDate>\(released)</ReleaseDate>\n" }
            xml += "    <Overview>A game &amp; its overview.</Overview>\n    <DatabaseID>\(g.id)</DatabaseID>\n"
            xml += "    <Platform>\(escaped(g.platform))</Platform>\n    <Genres />\n  </Game>\n"
        }
        for g in games {
            for name in g.alternateNames {
                xml += "  <GameAlternateName>\n    <AlternateName>\(escaped(name))</AlternateName>\n"
                xml += "    <DatabaseID>\(g.id)</DatabaseID>\n    <Region>Japan</Region>\n  </GameAlternateName>\n"
            }
        }
        for g in games {
            let images = g.boxes.map { ("Box - Front", $0.file, $0.region) } + g.otherImages.map { ($0.type, $0.file, nil) }
            for (type, file, region) in images {
                xml += "  <GameImage>\n    <DatabaseID>\(g.id)</DatabaseID>\n    <FileName>\(file)</FileName>\n"
                xml += "    <Type>\(type)</Type>\n"
                if let region { xml += "    <Region>\(region)</Region>\n" }
                xml += "    <CRC32>1</CRC32>\n  </GameImage>\n"
            }
        }
        return xml + "</LaunchBox>\n"
    }

    /// `Metadata.zip`, made with the system's `zip`.
    static func zip(_ games: [LaunchBoxGame]) -> Data {
        let folder = FileManager.default.temporaryDirectory.appending(path: "launchbox-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try! Data(xml(games).utf8).write(to: folder.appending(path: "Metadata.xml"))
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = folder
        zip.arguments = ["-q", "Metadata.zip", "Metadata.xml"]
        try! zip.run()
        zip.waitUntilExit()
        return try! Data(contentsOf: folder.appending(path: "Metadata.zip"))
    }
}
