import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import LudeumCore

/// Installing the PCSX2 Ludeum keeps (ADR 0032).
@Suite struct PCSX2InstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "pcsx2 install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var installed: URL { ludeum.pcsx2App }
    var ini: URL { ludeum.pcsx2Folder.appending(path: "inis/PCSX2.ini") }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// A fake `PCSX2-v<version>.app` in a `.tar.xz` as GitHub serves it, printing `prints` for `-version`, and the release
    /// that names it.
    func release(version: String = PCSX2Release.pinned.version, prints: String? = nil, sha256: String? = nil) throws
        -> (tar: Data, release: PCSX2Release)
    {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let app = staging.appending(path: "PCSX2-v\(version).app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "v\(version)", "CFBundleExecutable": "PCSX2"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: app.appending(path: "Contents/Info.plist"))
        let executable = macOS.appending(path: "PCSX2")
        try "#!/bin/sh\necho '\(prints ?? "PCSX2 v\(version)")' >&2\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
        try "SLUS-20062:\n  name: \"Okami\"\n".write(
            to: app.appending(path: "Contents/Resources/GameIndex.yaml"), atomically: true, encoding: .utf8)
        let tarFile = staging.appending(path: "pcsx2-v\(version)-macos-Qt.tar.xz")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.currentDirectoryURL = staging
        tar.arguments = ["-cJf", tarFile.path(percentEncoded: false), app.lastPathComponent]
        try tar.run()
        tar.waitUntilExit()
        let data = try Data(contentsOf: tarFile)
        let digest = sha256 ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (data, PCSX2Release(version: version, sha256: digest))
    }

    func installer(_ release: PCSX2Release, tars: [URL: Data]) -> (PCSX2Installer, FakeReleases) {
        let github = FakeReleases(tars)
        return (PCSX2Installer(ludeum: ludeum, release: release, transport: github), github)
    }

    @Test func installPutsThePinnedReleaseInTheLudeumFolderPortableWithItsStandingSettings() async throws {
        let (tar, release) = try self.release()
        let (installer, github) = installer(release, tars: [release.url: tar])
        let seen = Mutex<[Double]>([])

        try await installer.install { value in seen.withLock { $0.append(value) } }

        let progress = seen.withLock { $0 }
        #expect(github.requested.withLock { $0 } == [release.url])
        #expect(FileManager.default.isExecutableFile(atPath: installed.appending(path: "Contents/MacOS/PCSX2").path(percentEncoded: false)))
        #expect(PCSX2Settings(ludeum: ludeum).isPortable)
        #expect(try Data(contentsOf: ludeum.pcsx2Folder.appending(path: "portable.txt")).isEmpty)
        let settings = try String(contentsOf: ini, encoding: .utf8)
        #expect(
            Ini.value("Savestates", in: "Folders", of: settings) == "\(ludeum.data.path(percentEncoded: false))Emulators/PCSX2/Save States")
        #expect(Ini.value("CheckAtStartup", in: "AutoUpdater", of: settings) == "false")
        #expect(progress.last == 1)
        #expect(!FileManager.default.fileExists(atPath: installer.work.path(percentEncoded: false)))
    }

    @Test func aDownloadThatIsntTheReleaseIsRefused() async throws {
        let (tar, right) = try self.release()
        let wrong = PCSX2Release(version: right.version, sha256: String(repeating: "0", count: 64))
        let (installer, _) = installer(wrong, tars: [wrong.url: tar])

        await #expect(throws: PCSX2InstallError.badChecksum(expected: wrong.sha256, found: right.sha256)) { try await installer.install() }
        #expect(!FileManager.default.fileExists(atPath: installed.path(percentEncoded: false)))
    }

    @Test func aReleaseThatIsntOnGitHubIsRefused() async throws {
        let release = PCSX2Release.pinned
        let (installer, _) = installer(release, tars: [:])

        await #expect(throws: PCSX2InstallError.notFound(version: release.version, status: 404)) { try await installer.install() }
    }

    @Test func anAppThatIsntThePinnedVersionIsRefused() async throws {
        let (tar, release) = try self.release(prints: "PCSX2 v2.9.103")
        let (installer, _) = installer(release, tars: [release.url: tar])

        await #expect(throws: PCSX2InstallError.wrongBuild(found: "2.9.103")) { try await installer.install() }
        #expect(!FileManager.default.fileExists(atPath: installed.path(percentEncoded: false)))
    }

    @Test func aReinstallReplacesTheAppAndKeepsWhatPCSX2KeptBesideIt() async throws {
        let (first, release) = try self.release()
        let (installer, _) = installer(release, tars: [release.url: first])
        try await installer.install()
        let settings = try String(contentsOf: ini, encoding: .utf8)
        try Ini.setting("Cross", to: "SDL-0/A", in: "Pad1", of: settings).write(to: ini, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: ludeum.pcsx2Folder.appending(path: "cache"), withIntermediateDirectories: true)
        try "cache".write(to: ludeum.pcsx2Folder.appending(path: "cache/gamelist.cache"), atomically: true, encoding: .utf8)
        try "mine".write(to: installed.appending(path: "Contents/Resources/mine.txt"), atomically: true, encoding: .utf8)
        let (second, again) = try self.release()
        let (reinstaller, _) = self.installer(again, tars: [again.url: second])

        try await reinstaller.install()

        #expect(FileManager.default.isExecutableFile(atPath: installed.appending(path: "Contents/MacOS/PCSX2").path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(atPath: installed.appending(path: "Contents/Resources/mine.txt").path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(atPath: ludeum.pcsx2Folder.appending(path: "PCSX2 (replaced).app").path(percentEncoded: false)))
        #expect(Ini.value("Cross", in: "Pad1", of: try String(contentsOf: ini, encoding: .utf8)) == "SDL-0/A")
        #expect(try String(contentsOf: ludeum.pcsx2Folder.appending(path: "cache/gamelist.cache"), encoding: .utf8) == "cache")
    }
}
