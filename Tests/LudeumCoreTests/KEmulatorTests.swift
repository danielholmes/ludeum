import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

private func put(_ text: String, at file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

private func run(_ tool: String, _ arguments: [String], in folder: URL? = nil) throws {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    if let folder { process.currentDirectoryURL = folder }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
}

/// A jar at `file` whose manifest is `manifest`, as a phone game's is.
private func jar(at file: URL, manifest: String) throws {
    let staging = file.deletingLastPathComponent().appending(path: ".jar \(UUID().uuidString)", directoryHint: .isDirectory)
    try put(manifest, at: staging.appending(path: "META-INF/MANIFEST.MF"))
    try put("class", at: staging.appending(path: "Main.class"))
    try run("/usr/bin/ditto", ["-c", "-k", staging.path(percentEncoded: false), file.path(percentEncoded: false)])
    try FileManager.default.removeItem(at: staging)
}

/// How a Java phone game reads in its ROM folder, and is Added (ADR 0044).
@Suite struct MobileROMTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "mobile rom \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func legacyMobileDeviceIsPlayedInKEmulator() throws {
        #expect(Emulator.of(platformId: ROMPlatform.legacyMobile) == .kemulator)
        #expect(Emulator.kemulator.isLudeums)
        #expect(Emulator.all.contains(.kemulator))
        let platform = try #require(ROMPlatform.all[ROMPlatform.legacyMobile])
        #expect(platform.folderName == "Legacy Mobile")
        #expect(platform.compactExtension == nil && platform.archiving == nil)
    }

    @Test func aJarIsAROM() throws {
        let mobile = try FakeROMFolder(in: directory, platform: ROMPlatform.legacyMobile)
        try mobile.add("Resident Evil - Genesis.jar")
        try mobile.add("Resident Evil - Genesis.jad")

        let roms = try mobile.folder.scan()

        #expect(roms.map(\.name) == ["Resident Evil - Genesis"])
        #expect(roms.first?.ready?.lastPathComponent == "Resident Evil - Genesis.jar")
    }

    @Test func aGamesJarsAsDiscsAreOneROMOpeningItsPlaylist() throws {
        let mobile = try FakeROMFolder(in: directory, platform: ROMPlatform.legacyMobile)
        let name = "Resident Evil - Confidential Report"
        for n in 1...2 { try mobile.add("\(name)/\(name) (Disc \(n)).jar") }
        try mobile.add("\(name)/\(name).m3u", "\(name) (Disc 1).jar\n\(name) (Disc 2).jar\n")

        let roms = try mobile.folder.scan()

        #expect(roms.map(\.name) == [name])
        #expect(roms.first?.ready?.lastPathComponent == "\(name).m3u")
        #expect(roms.first?.needsPlaylist == false)
    }

    @Test func aJarIsReadAsLegacyMobileDevicesAlone() async throws {
        let file = directory.appending(path: "Resident Evil - Genesis.jar")
        try put("jar", at: file)

        let source = ROMSource([file])

        #expect(try await source.platforms(sevenZip: nil) == [ROMPlatform.legacyMobile])
    }

    @Test func addingAGamesJarsAsDiscsKeepsThemTogetherWithAPlaylist() async throws {
        let mobile = try FakeROMFolder(in: directory, platform: ROMPlatform.legacyMobile)
        let picked = directory.appending(path: "picked", directoryHint: .isDirectory)
        let files = try (1...2).map { n in
            let file = picked.appending(path: "Resident Evil - Confidential Report (Disc \(n)).jar")
            try put("episode \(n)", at: file)
            return file
        }
        let j = try LudeumHarness()
        let source = ROMSource(files)

        try await AddROM(journal: j.journal, sevenZip: nil, moveToTrash: { _ in })
            .add(source, to: mobile.folder, match: .byHand(name: "Resident Evil: Confidential Report"), keepingOriginals: true)

        let name = "Resident Evil - Confidential Report"
        let playlist = mobile.url.appending(path: "\(name)/\(name).m3u")
        #expect(try String(contentsOf: playlist, encoding: .utf8) == "\(name) (Disc 1).jar\n\(name) (Disc 2).jar\n")
        #expect(try mobile.folder.scan().map(\.name) == [name])
    }
}

/// What a jar's manifest says, and where KEmulator keeps its Game saves (ADR 0044).
@Suite struct MobileGameSaveTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "mobile saves \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }

    @Test func itsSaveFolderIsBase64OfVendorAndNameAsKEmulatorNamesIt() {
        // As KEmulator wrote it for Resident Evil: Genesis, on this Mac.
        let manifest = JarManifest(vendor: "Capcom Interactive, Inc.", name: "Resident Evil")
        #expect(manifest.saveFolderName == "Q2FwY29tIEludGVyYWN0aXZlLCBJbmMuX1Jlc2lkZW50IEV2aWw=")
    }

    @Test func aSlashInItsBase64IsADash() {
        // "a_???" is "YV8/Pz8=" in Base64.
        #expect(JarManifest(vendor: "a", name: "???").saveFolderName == "YV8-Pz8=")
        #expect(JarManifest(vendor: nil, name: "x").saveFolderName == Data("null_x".utf8).base64EncodedString())
    }

    @Test func itsManifestsMainSectionIsRead() {
        let manifest = JarManifest.parse(
            "Manifest-Version: 1.0\r\nMIDlet-Vendor: CAPCOM\r\nMIDlet-Name: Resident Evil Confidential\r\n  Report 1\r\n"
                + "MIDlet-Description:www.example.com\r\n\r\nName: Main.class\r\nMIDlet-Name: Not this\r\n")

        #expect(manifest.vendor == "CAPCOM")
        #expect(manifest.name == "Resident Evil Confidential Report 1")
    }

    @Test func aJarsGameSaveIsFoundFromItsManifest() throws {
        let file = directory.appending(path: "Resident Evil - Genesis.jar")
        try jar(at: file, manifest: "Manifest-Version: 1.0\nMIDlet-Vendor: Capcom Interactive, Inc.\nMIDlet-Name: Resident Evil\n\n")
        #expect(MobileGameSave.of(jar: file, ludeum: ludeum) == nil)

        let folder = ludeum.mobileGameSaves.appending(path: "Q2FwY29tIEludGVyYWN0aXZlLCBJbmMuX1Jlc2lkZW50IEV2aWw=")
        try put("12345", at: folder.appending(path: "b3B0aW9ucy5kYXQ=/1.rms"))
        let save = try #require(MobileGameSave.of(jar: file, ludeum: ludeum))

        #expect(save.midlet == "Resident Evil")
        #expect(save.folder.standardizedFileURL == folder.standardizedFileURL)
        #expect(save.size == 5)
    }

    @Test func aROMOfDiscsHasEachDiscsJarInOrder() throws {
        let mobile = try FakeROMFolder(in: directory, platform: ROMPlatform.legacyMobile)
        let name = "Resident Evil - Confidential Report"
        try mobile.add("\(name)/\(name) (Disc 1).jar")
        try mobile.add("\(name)/\(name) (Disc 2).jar")
        try mobile.add("\(name)/\(name).m3u", "\(name) (Disc 2).jar\n\(name) (Disc 1).jar\n")
        let rom = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.legacyMobile, fileName: "\(name)/\(name).m3u", name: name, version: "",
            disc: nil, missing: false, archived: false)

        let jars = MobileGameSave.jars(of: rom, locator: ROMLocator(romFolders: [mobile.folder]))

        #expect(jars.map(\.lastPathComponent) == ["\(name) (Disc 2).jar", "\(name) (Disc 1).jar"])
    }
}

/// KEmulator's Standing settings and its own settings files (ADR 0044).
@Suite struct KEmulatorSettingsTests {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "kemulator settings \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: KEmulatorSettings { KEmulatorSettings(ludeum: ludeum) }
    var property: URL { ludeum.kEmulatorHome.appending(path: "property.txt") }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    @Test func itsSettingsAreWrittenOverWithTheRestKept() {
        let text = """
            #KEmulator properties
            AutoUpdate=0
            MAP_KEY_LSOFT=F1
            RMSFolder=./rms
            ShowAppSettingsOnStart \\
              true
            Zoom=2

            """

        let written = KEmulatorSettings.writing(
            [("RMSFolder", "file:///a b"), ("AutoUpdate", "1"), ("ShowAppSettingsOnStart", "false")], into: text)

        #expect(
            written == """
                #KEmulator properties
                MAP_KEY_LSOFT=F1
                Zoom=2
                RMSFolder=file\\:///a b
                AutoUpdate=1
                ShowAppSettingsOnStart=false

                """)
    }

    @Test func aValueIsEscapedAsJavaPropertiesReadsIt() {
        #expect(KEmulatorSettings.escaped("file:///Users/me/Ünïcode=\\") == "file\\:///Users/me/\\u00DCn\\u00EFcode\\=\\\\")
        #expect(KEmulatorSettings.escaped(" lead") == "\\ lead")
    }

    @Test func aKeyIsReadUpToItsSeparator() {
        #expect(KEmulatorSettings.key(of: "  RMSFolder = x") == "RMSFolder")
        #expect(KEmulatorSettings.key(of: "a\\:b:c") == "a:b")
        #expect(KEmulatorSettings.key(of: "# RMSFolder=x") == nil)
        #expect(KEmulatorSettings.key(of: "! RMSFolder=x") == nil)
    }

    @Test func aPlayWritesItsStandingSettingsAndOpensTheJar() throws {
        try put("#KEmulator properties\nMAP_KEY_LSOFT=F1\nAutoUpdate=2\n", at: property)
        let jar = directory.appending(path: "Resident Evil - Genesis.jar")

        let arguments = try settings.arguments(jar: jar)

        #expect(arguments == ["-jar", jar.path(percentEncoded: false), "-s"])
        let text = try String(contentsOf: property, encoding: .isoLatin1)
        let saves = KEmulatorSettings.escaped("file://" + ludeum.mobileGameSaves.path(percentEncoded: false))
        #expect(text == "#KEmulator properties\nMAP_KEY_LSOFT=F1\nRMSFolder=\(saves)\nAutoUpdate=1\nShowAppSettingsOnStart=false\n")
        #expect(exists(ludeum.mobileGameSaves))
    }

    @Test func itsOwnSettingsFilesAreCopiedIntoTheDataFolder() throws {
        try put("MAP_KEY_LSOFT=F3\n", at: property)
        try put("[abc:/x.jar]\nScreenWidth=240\n", at: ludeum.kEmulatorHome.appending(path: "midlets.ini"))

        _ = try settings.arguments(jar: directory.appending(path: "x.jar"))

        #expect(try String(contentsOf: ludeum.kEmulatorData.appending(path: "property.txt"), encoding: .utf8) == "MAP_KEY_LSOFT=F3\n")
        #expect(
            try String(contentsOf: ludeum.kEmulatorData.appending(path: "midlets.ini"), encoding: .utf8)
                == "[abc:/x.jar]\nScreenWidth=240\n")
    }

    @Test func theDataFoldersComeBackWhenTheAppsAreMissingOrEmpty() throws {
        try put("MAP_KEY_LSOFT=F3\n", at: ludeum.kEmulatorData.appending(path: "property.txt"))
        try put("[abc:/x.jar]\nScreenWidth=240\n", at: ludeum.kEmulatorData.appending(path: "midlets.ini"))
        // A forced quit's: KEmulator left it empty.
        try put("", at: property)

        _ = try settings.arguments(jar: directory.appending(path: "x.jar"))

        #expect(try String(contentsOf: property, encoding: .isoLatin1).hasPrefix("MAP_KEY_LSOFT=F3\nRMSFolder="))
        #expect(
            try String(contentsOf: ludeum.kEmulatorHome.appending(path: "midlets.ini"), encoding: .utf8)
                == "[abc:/x.jar]\nScreenWidth=240\n")
        // The empty one didn't replace what was kept.
        #expect(try String(contentsOf: ludeum.kEmulatorData.appending(path: "property.txt"), encoding: .utf8) == "MAP_KEY_LSOFT=F3\n")
    }
}

/// Playing a Java phone game in KEmulator (ADR 0044).
@Suite struct KEmulatorPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "kemulator play \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var kEmulator: KEmulatorSettings { KEmulatorSettings(ludeum: ludeum) }
    let name = "Resident Evil - Confidential Report"

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func install() throws {
        for executable in [
            ludeum.kEmulatorApp.appending(path: "Contents/MacOS/KEmulator"), ludeum.kEmulatorJRE.appending(path: "Contents/Home/bin/java"),
        ] {
            try put("", at: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        }
        try put("jar", at: ludeum.kEmulatorHome.appending(path: "KEmulator.jar"))
    }

    func mobile(discs: Int) throws -> FakeROMFolder {
        let mobile = try FakeROMFolder(in: directory, platform: ROMPlatform.legacyMobile)
        if discs == 1 {
            try mobile.add("\(name).jar")
        } else {
            for n in 1...discs { try mobile.add("\(name)/\(name) (Disc \(n)).jar") }
            try mobile.add("\(name)/\(name).m3u", (1...discs).map { "\(name) (Disc \($0)).jar\n" }.joined())
        }
        return mobile
    }

    func play(_ mobile: FakeROMFolder, lastDisc: Int? = nil) throws -> Play {
        let rom = try #require(try mobile.folder.scan().first)
        var journal = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.legacyMobile, fileName: rom.fileName, name: name, version: "", disc: nil,
            missing: false, archived: false)
        journal.lastDisc = lastDisc
        return Play(platformId: ROMPlatform.legacyMobile, platformName: "Legacy Mobile Device", roms: [journal], settings: .init())
    }

    func press(_ play: Play, _ mobile: FakeROMFolder, disc: Int? = nil, running: Bool = false) -> Play.Outcome {
        play.prepare(
            locator: ROMLocator(romFolders: [mobile.folder]), version: .ok, app: { _ in nil }, disc: disc, kEmulator: kEmulator,
            running: { $0 == .kemulator && running })
    }

    func jar(_ mobile: FakeROMFolder, disc: Int) -> String {
        mobile.url.appending(path: "\(name)/\(name) (Disc \(disc)).jar").path(percentEncoded: false)
    }

    @Test func itsRefusedUntilKEmulatorIsInstalled() throws {
        let mobile = try mobile(discs: 1)
        #expect(press(try play(mobile), mobile).refusal == .notInstalled(.kemulator))
    }

    @Test func itsRefusedWhileKEmulatorIsOpen() throws {
        try install()
        let mobile = try mobile(discs: 1)
        #expect(press(try play(mobile), mobile, running: true).refusal == .running(.kemulator))
    }

    @Test func itOpensTheAppWithItsJar() throws {
        try install()
        let mobile = try mobile(discs: 1)

        let outcome = press(try play(mobile), mobile)

        guard case .open(let app, let arguments, _, let startsOn, let environment) = outcome else {
            Issue.record("refused: \(String(describing: outcome.refusal))")
            return
        }
        #expect(app == ludeum.kEmulatorApp)
        #expect(arguments == ["-jar", mobile.url.appending(path: "\(name).jar").path(percentEncoded: false), "-s"])
        #expect(startsOn == nil)
        #expect(environment.isEmpty)
    }

    @Test func aROMOfDiscsOffersEachAndOpensItsJarNotThePlaylist() throws {
        try install()
        let mobile = try mobile(discs: 3)
        let play = try play(mobile)

        let discs = play.discs(locator: ROMLocator(romFolders: [mobile.folder]))
        #expect(discs.map(\.number) == [1, 2, 3])
        #expect(play.starts(discs: discs, resume: nil).map(\.menuTitle) == ["Play Disc 1", "Play Disc 2", "Play Disc 3"])

        let first = press(play, mobile)
        #expect(first.arguments == ["-jar", jar(mobile, disc: 1), "-s"])
        #expect(first.startsOn == Play.DiscStart(rom: 1, disc: 1))

        let chosen = press(play, mobile, disc: 3)
        #expect(chosen.arguments == ["-jar", jar(mobile, disc: 3), "-s"])
        #expect(chosen.startsOn == Play.DiscStart(rom: 1, disc: 3))
    }

    @Test func itStartsOnTheDiscItLastStartedOn() throws {
        try install()
        let mobile = try mobile(discs: 3)

        #expect(press(try play(mobile, lastDisc: 2), mobile).arguments == ["-jar", jar(mobile, disc: 2), "-s"])
    }
}

/// Installing the KEmulator Ludeum makes around KEmulator nnmod and a Java runtime (ADR 0044).
@Suite struct KEmulatorInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "kemulator install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: KEmulatorSettings { KEmulatorSettings(ludeum: ludeum) }
    /// Where the stand-in `java` notes how it was run.
    var ran: URL { root.appending(path: "java ran") }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A zip like the release's: `kemnnx64/` with `KEmulator.jar` in it.
    func zip(jar: String? = "KEmulator.jar") throws -> Data {
        let staging = root.appending(path: "zip \(UUID().uuidString)", directoryHint: .isDirectory)
        try put("kemulator", at: staging.appending(path: "kemnnx64/\(jar ?? "Other.jar")"))
        try put("lib", at: staging.appending(path: "kemnnx64/swt-macosx-aarch64.jar"))
        let file = root.appending(path: "kem \(UUID().uuidString).zip")
        try run("/usr/bin/ditto", ["-c", "-k", staging.path(percentEncoded: false), file.path(percentEncoded: false)])
        return try Data(contentsOf: file)
    }

    /// A tarball like Temurin's: `jdk-…-jre/Contents/Home/bin/java`, here a script that notes its working folder and
    /// arguments, or fails.
    func jre(fails: Bool = false) throws -> Data {
        let staging = root.appending(path: "jre \(UUID().uuidString)", directoryHint: .isDirectory)
        let java = staging.appending(path: "jdk-21.0.13+9-jre/Contents/Home/bin/java")
        let note = ran.path(percentEncoded: false)
        try put(
            fails
                ? "#!/bin/sh\necho broken >&2\nexit 1\n"
                : "#!/bin/sh\npwd > '\(note)'\nfor a in \"$@\"; do echo \"$a\" >> '\(note)'; done\n",
            at: java)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path(percentEncoded: false))
        let file = root.appending(path: "jre \(UUID().uuidString).tar.gz")
        try run("/usr/bin/tar", ["-czf", file.path(percentEncoded: false), "-C", staging.path(percentEncoded: false), "jdk-21.0.13+9-jre"])
        return try Data(contentsOf: file)
    }

    func installer(zip: Data, jre: Data) -> KEmulatorInstaller {
        let release = KEmulatorRelease(version: "2.22", sha256: digest(zip), jreTag: "jdk-21.0.13+9", jreSHA256: digest(jre))
        return KEmulatorInstaller(ludeum: ludeum, release: release, transport: FakeReleases([release.url: zip, release.jreURL: jre]))
    }

    @Test func theReleaseAndRuntimeArePinned() {
        let pinned = KEmulatorRelease.pinned
        #expect(pinned.url.absoluteString == "https://github.com/shinovon/KEmulator/releases/download/v2.22/kemnnx64.v2.22.zip")
        #expect(
            pinned.jreURL.absoluteString
                == "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jre_aarch64_mac_hotspot_21.0.13_9.tar.gz"
        )
        #expect(pinned.sha256.count == 64 && pinned.jreSHA256.count == 64)
        #expect(Emulator.kemulator.expectedVersion == "2.22")
    }

    @Test func installingMakesAnAppThatStartsKEmulatorOnItsRuntime() async throws {
        try await installer(zip: try zip(), jre: try jre()).install()

        #expect(settings.isInstalled)
        let info = try #require(Bundle(url: settings.app)?.infoDictionary)
        #expect(info["CFBundleIdentifier"] as? String == Emulator.kemulator.bundleIdentifier)
        #expect(EmulatorVersions.check(.kemulator, app: settings.app)?.check == .ok)
        #expect(!exists(ludeum.emulators.appending(path: ".installing KEmulator")))

        // Its launcher, as Play opens it.
        try run(settings.app.appending(path: "Contents/MacOS/KEmulator").path(percentEncoded: false), ["-jar", "/games/a b.jar", "-s"])
        let lines = try String(contentsOf: ran, encoding: .utf8).split(separator: "\n").map(String.init)
        let home = ludeum.kEmulatorHome.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        #expect(
            URL(filePath: lines[0]).resolvingSymlinksInPath().path(percentEncoded: false).trimmingSuffix("/") == home.trimmingSuffix("/"))
        #expect(lines.contains("-XstartOnFirstThread"))
        // KEmulator's jar, then what Play gave it, a space in a path kept.
        #expect(lines.suffix(5).first == "-jar" && lines.suffix(4).first?.hasSuffix("/KEmulator/KEmulator.jar") == true)
        #expect(Array(lines.suffix(3)) == ["-jar", "/games/a b.jar", "-s"])
    }

    @Test func reinstallingKeepsItsOwnSettingsFiles() async throws {
        try await installer(zip: try zip(), jre: try jre()).install()
        try put("MAP_KEY_LSOFT=F3\n", at: ludeum.kEmulatorHome.appending(path: "property.txt"))
        try put("[abc:/x.jar]\n", at: ludeum.kEmulatorHome.appending(path: "midlets.ini"))

        try await installer(zip: try zip(), jre: try jre()).install()

        #expect(try String(contentsOf: ludeum.kEmulatorHome.appending(path: "property.txt"), encoding: .utf8) == "MAP_KEY_LSOFT=F3\n")
        #expect(try String(contentsOf: ludeum.kEmulatorHome.appending(path: "midlets.ini"), encoding: .utf8) == "[abc:/x.jar]\n")
    }

    @Test func aRuntimeThatDoesntRunReplacesNothing() async throws {
        try await installer(zip: try zip(), jre: try jre()).install()

        await #expect(throws: KEmulatorInstallError.javaDoesntRun("broken")) {
            try await installer(zip: try zip(), jre: try jre(fails: true)).install()
        }
        #expect(settings.isInstalled)
    }

    @Test func aZipWithNoKEmulatorIsRefused() async throws {
        await #expect(throws: KEmulatorInstallError.missing("KEmulator.jar")) {
            try await installer(zip: try zip(jar: nil), jre: try jre()).install()
        }
        #expect(!exists(settings.app))
    }

    @Test func aDownloadThatIsntThePinnedOneIsRefused() async throws {
        let release = KEmulatorRelease(version: "2.22", sha256: String(repeating: "0", count: 64), jreTag: "jdk-21.0.13+9", jreSHA256: "")
        let zip = try zip()
        await #expect(throws: KEmulatorInstallError.self) {
            try await KEmulatorInstaller(ludeum: ludeum, release: release, transport: FakeReleases([release.url: zip])).install()
        }
        #expect(!exists(settings.app))
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }
}
