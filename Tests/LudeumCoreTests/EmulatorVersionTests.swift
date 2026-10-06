import Foundation
import Testing

@testable import LudeumCore

@Suite struct EmulatorVersionCheckTests {
    @Test func theExpectedVersionOrLaterIsFine() {
        #expect(EmulatorVersions.check(found: "v2.9.103", for: .pcsx2) == .ok)
        #expect(EmulatorVersions.check(found: "PCSX2 v2.10.1\nhttps://pcsx2.net/", for: .pcsx2) == .ok)
        #expect(EmulatorVersions.check(found: "2.9.103", for: .pcsx2) == .ok)
    }

    @Test func anOlderVersionIsTooOld() {
        #expect(EmulatorVersions.check(found: "PCSX2 v2.9.99", for: .pcsx2) == .tooOld(found: "2.9.99"))
        #expect(EmulatorVersions.check(found: "1.20", for: .ppsspp) == .tooOld(found: "1.20"))
    }

    @Test func aNewerMajorVersionIsWarnedAbout() {
        #expect(EmulatorVersions.check(found: "3.0.0", for: .pcsx2) == .newerMajor(found: "3.0.0"))
        #expect(EmulatorVersions.check(found: "2.0", for: .melonDS) == .newerMajor(found: "2.0"))
    }

    @Test func emulatorsWithoutMeaningfulMajorsAreOnlyCheckedForBeingTooOld() {
        #expect(EmulatorVersions.check(found: "2709", for: .dolphin) == .ok)
        #expect(EmulatorVersions.check(found: "2508-3-gabc", for: .dolphin) == .tooOld(found: "2508"))
        #expect(EmulatorVersions.check(found: "ares v200", for: .ares) == .ok)
    }

    @Test func duckStationIsComparedByBuildNumber() {
        #expect(EmulatorVersions.check(found: "DuckStation Version 0.1-12070-g4122fed9a (dev)", for: .duckStation) == .ok)
        #expect(EmulatorVersions.check(found: "0.1-11894-gabc", for: .duckStation) == .tooOld(found: "11894"))
        #expect(EmulatorVersions.check(found: "0.1-99999-gabc", for: .duckStation) == .ok)
    }

    @Test func whatTheInstalledEmulatorsPrintIsUnderstood() {
        // Each Emulator's real `--version` / `-version` output, from the installed apps.
        #expect(EmulatorVersions.check(found: "v148", for: .ares) == .ok)
        #expect(EmulatorVersions.check(found: "v1.20.4", for: .ppsspp) == .ok)
        #expect(EmulatorVersions.check(found: "PCSX2 v2.9.103\nhttps://pcsx2.net/", for: .pcsx2) == .ok)
        #expect(
            EmulatorVersions.check(
                found: "DuckStation Version 0.1-12070-g4122fed9a (dev)\nhttps://github.com/stenzek/duckstation", for: .duckStation) == .ok)
        #expect(EmulatorVersions.check(found: "v147", for: .ares) == .tooOld(found: "147"))
        // App versions: Ymir and melonDS have no version flag (Ymir's `--version` opens its window), and Dolphin's matches its flag.
        #expect(EmulatorVersions.check(found: "0.3.3", for: .ymir) == .ok)
        #expect(EmulatorVersions.check(found: "1.1", for: .melonDS) == .ok)
        #expect(EmulatorVersions.check(found: "2609", for: .dolphin) == .ok)
        #expect(EmulatorVersions.check(found: "Dolphin 2609", for: .dolphin) == .ok)
    }

    @Test func theInstalledVersionIsShownTheWayItsCompared() {
        #expect(EmulatorVersions.shown(found: "PCSX2 v2.9.103\nhttps://pcsx2.net/", for: .pcsx2) == "2.9.103")
        #expect(EmulatorVersions.shown(found: "DuckStation Version 0.1-12070-g4122fed9a (dev)", for: .duckStation) == "12070")
        #expect(EmulatorVersions.shown(found: nil, for: .pcsx2) == nil)
    }

    @Test func aVersionThatCantBeReadSaysSo() {
        #expect(EmulatorVersions.check(found: nil, for: .pcsx2) == .unreadable)
        #expect(EmulatorVersions.check(found: "dev build", for: .pcsx2) == .unreadable)
    }
}

@Suite struct EmulatorVersionReadingTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "versions \(UUID().uuidString)", directoryHint: .isDirectory)

    /// A fake app: an Info.plist, and an executable that's a shell script printing `output`.
    func app(shortVersion: String, executableOutput: String = "") throws -> URL {
        let app = directory.appending(path: "Fake.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": shortVersion, "CFBundleExecutable": "Fake"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        let script = macOS.appending(path: "Fake")
        try "#!/bin/sh\necho '\(executableOutput)'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))
        return app
    }

    @Test func anEmulatorWithAVersionFlagIsAskedOnTheCommandLine() throws {
        let fake = try app(shortVersion: "1.0", executableOutput: "PCSX2 v2.9.103")

        #expect(EmulatorVersions.read(.pcsx2, app: fake) == "PCSX2 v2.9.103")
    }

    @Test func oneWithoutAFlagIsReadFromItsAppVersion() throws {
        let fake = try app(shortVersion: "1.1", executableOutput: "should not run")

        #expect(EmulatorVersions.read(.melonDS, app: fake) == "1.1")
    }

    @Test func mesenCEIsReadFromItsSettings() throws {
        let fake = try app(shortVersion: "1.0")
        let settings = directory.appending(path: "settings.json")
        try #"{ "Version": "2.2.1", "Audio": {} }"#.write(to: settings, atomically: true, encoding: .utf8)

        #expect(EmulatorVersions.read(.mesenCE, app: fake, mesenSettings: settings) == "2.2.1")
        #expect(EmulatorVersions.read(.mesenCE, app: fake, mesenSettings: directory.appending(path: "none.json")) == nil)
    }
}
