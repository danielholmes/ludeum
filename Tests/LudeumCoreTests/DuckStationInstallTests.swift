import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import LudeumCore

/// GitHub's release downloads, faked: a zip at each URL that has one.
final class FakeReleases: HTTPTransport, Sendable {
    let zips: [URL: Data]
    let requested = Mutex<[URL]>([])

    init(_ zips: [URL: Data]) { self.zips = zips }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        requested.withLock { $0.append(url) }
        let zip = zips[url]
        return (zip ?? Data(), HTTPURLResponse(url: url, statusCode: zip == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Installing the DuckStation Ludeum keeps (ADR 0024).
@Suite struct DuckStationInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "duckstation install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var installed: URL { ludeum.duckStationApp }
    var dataRoot: URL { installed.appending(path: "Contents/MacOS", directoryHint: .isDirectory) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// A fake DuckStation.app zipped as GitHub serves it, printing `version` for `-version`, and the release that names it.
    func release(
        version: String = "DuckStation Version 0.1-\(DuckStationRelease.pinned.build)-g2781502e0 (dev)",
        build: Int = DuckStationRelease.pinned.build, sha256: String? = nil
    ) throws
        -> (zip: Data, release: DuckStationRelease)
    {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let app = staging.appending(path: "DuckStation.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "0.1", "CFBundleExecutable": "DuckStation"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: app.appending(path: "Contents/Info.plist"))
        let executable = macOS.appending(path: "DuckStation")
        try "#!/bin/sh\necho '\(version)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
        try "SLUS-00551:\n  name: \"Resident Evil\"\n".write(
            to: app.appending(path: "Contents/Resources/discdb.yaml"), atomically: true, encoding: .utf8)
        let zipFile = staging.appending(path: "duckstation-mac-release.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", app.path(percentEncoded: false), zipFile.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        let zip = try Data(contentsOf: zipFile)
        let digest = sha256 ?? SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        return (zip, DuckStationRelease(tag: "v0.1-\(build)", build: build, sha256: digest))
    }

    func installer(_ release: DuckStationRelease, zips: [URL: Data]) -> (DuckStationInstaller, FakeReleases) {
        let github = FakeReleases(zips)
        return (DuckStationInstaller(ludeum: ludeum, release: release, transport: github), github)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    @Test func thePinnedReleaseIsVersionedWithItsZipsDigest() {
        let pinned = DuckStationRelease.pinned
        // The rolling `latest` for now, until a versioned release past 12442 (#90); then `v0.1-<build>` again.
        #expect(pinned.tag == "latest" || pinned.tag == "v0.1-\(pinned.build)")
        #expect(pinned.sha256.count == 64)
        #expect(
            pinned.urls.map(\.absoluteString) == [
                "https://github.com/stenzek/duckstation/releases/download/\(pinned.tag)/duckstation-mac-release.zip",
                "https://github.com/duckstation/old-releases/releases/download/\(pinned.tag)/duckstation-mac-release.zip",
            ])
    }

    @Test func installingPutsAPortableDuckStationInTheLudeumFolderWithItsStandingSettings() async throws {
        let (zip, release) = try release()
        let (installer, github) = installer(release, zips: [release.urls[0]: zip])
        let progress = Mutex<[Double]>([])

        try await installer.install { fraction in progress.withLock { $0.append(fraction) } }

        #expect(DuckStationSettings(ludeum: ludeum).isInstalled)
        #expect(DuckStationSettings(ludeum: ludeum).isPortable)
        #expect(EmulatorVersions.check(.duckStation, app: installed)?.check == .ok)
        let standing = try String(contentsOf: dataRoot.appending(path: "settings.ini"), encoding: .utf8)
        #expect(Ini.value("CheckAtStartup", in: "AutoUpdater", of: standing) == "false")
        #expect(
            Ini.value("SaveStates", in: "Folders", of: standing)
                == String(ludeum.duckStationSaveStates.path(percentEncoded: false).dropLast()))
        #expect(github.requested.withLock { $0 } == [release.urls[0]])
        #expect(progress.withLock { $0 }.last == 1)
        #expect(!exists(ludeum.emulators.appending(path: ".installing")))
    }

    @Test func aReleaseThatHasAgedOffTheMainRepoComesFromOldReleases() async throws {
        let (zip, release) = try release()
        let (installer, github) = installer(release, zips: [release.urls[1]: zip])

        try await installer.install()

        #expect(DuckStationSettings(ludeum: ludeum).isInstalled)
        #expect(github.requested.withLock { $0 } == release.urls)
    }

    @Test func aReleaseNeitherRepoHasIsRefused() async throws {
        let (_, release) = try release()
        let (installer, _) = installer(release, zips: [:])

        await #expect(throws: DuckStationInstallError.notFound(tag: release.tag, status: 404)) { try await installer.install() }
        #expect(!exists(installed))
    }

    @Test func aDownloadThatIsntTheReleaseIsRefused() async throws {
        let (zip, release) = try release(sha256: String(repeating: "0", count: 64))
        let (installer, _) = installer(release, zips: [release.urls[0]: zip])

        let error = await #expect(throws: DuckStationInstallError.self) { try await installer.install() }

        if case .badChecksum(let expected, _) = error {
            #expect(expected == release.sha256)
        } else {
            Issue.record("\(String(describing: error))")
        }
        #expect(!exists(installed))
    }

    /// A build the pin isn't: the one before it.
    var otherBuild: Int { DuckStationRelease.pinned.build - 1 }

    @Test func aDownloadOfAnotherBuildIsRefused() async throws {
        let (zip, release) = try release(version: "DuckStation Version 0.1-\(otherBuild)-gdd4a0eb77 (dev)")
        let (installer, _) = installer(release, zips: [release.urls[0]: zip])

        await #expect(throws: DuckStationInstallError.wrongBuild(found: String(otherBuild))) { try await installer.install() }
        #expect(!exists(installed))
    }

    @Test func installingAgainCarriesAcrossWhatDuckStationKeptInItsDataRoot() async throws {
        let (zip, release) = try release()
        let (installer, _) = installer(release, zips: [release.urls[0]: zip])
        try await installer.install()
        try "[Main]\nRewindEnable = true\n".write(to: dataRoot.appending(path: "settings.ini"), atomically: true, encoding: .utf8)
        try "played".write(to: dataRoot.appending(path: "playtime.dat"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dataRoot.appending(path: "cache"), withIntermediateDirectories: true)
        try "list".write(to: dataRoot.appending(path: "cache/gamelist.cache"), atomically: true, encoding: .utf8)
        // Something written into the bundle outside the data root doesn't come along.
        try "mine".write(to: installed.appending(path: "Contents/Resources/mine.txt"), atomically: true, encoding: .utf8)

        try await installer.install()

        let standing = try String(contentsOf: dataRoot.appending(path: "settings.ini"), encoding: .utf8)
        #expect(Ini.value("RewindEnable", in: "Main", of: standing) == "true")
        #expect(Ini.value("CheckAtStartup", in: "AutoUpdater", of: standing) == "false")
        #expect(try String(contentsOf: dataRoot.appending(path: "playtime.dat"), encoding: .utf8) == "played")
        #expect(try String(contentsOf: dataRoot.appending(path: "cache/gamelist.cache"), encoding: .utf8) == "list")
        #expect(exists(dataRoot.appending(path: "portable.txt")))
        #expect(!exists(installed.appending(path: "Contents/Resources/mine.txt")))
        #expect(DuckStationSettings(ludeum: ludeum).isInstalled)
    }

    @Test func aFailedInstallLeavesTheCopyThatWasThere() async throws {
        let (zip, pinned) = try release()
        try await installer(pinned, zips: [pinned.urls[0]: zip]).0.install()
        let (other, otherRelease) = try release(version: "DuckStation Version 0.1-\(otherBuild)-gdd4a0eb77 (dev)")

        await #expect(throws: DuckStationInstallError.wrongBuild(found: String(otherBuild))) {
            try await installer(otherRelease, zips: [otherRelease.urls[0]: other]).0.install()
        }

        #expect(EmulatorVersions.check(.duckStation, app: installed)?.check == .ok)
    }

    @Test func nothingIsInstalledWhileTheDataFolderIsMissing() async throws {
        let (zip, release) = try release()
        try FileManager.default.removeItem(at: ludeum.data)

        await #expect(throws: DataFolderMissing.self) { try await installer(release, zips: [release.urls[0]: zip]).0.install() }
        #expect(!exists(installed))
    }
}
