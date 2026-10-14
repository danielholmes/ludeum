import Foundation
import Testing

@testable import LudeumCore

@Suite struct SystemToolsTests {
    @Test func nothingMissingHasNoWarning() {
        #expect(SystemTool.warning(missing: []) == nil)
    }

    @Test func aMissingToolSaysWhatItsForAndHowToInstallIt() throws {
        let warning = try #require(SystemTool.warning(missing: [.sevenZip]))
        #expect(warning.title == "7-Zip isn't installed")
        #expect(warning.message.contains("Archive, Unarchive and Compact"))
        #expect(warning.message.contains("`brew install sevenzip`"))
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func anInstalledToolIsntMissing() {
        #expect(!SystemTool.missing(emulatorInstalled: { _ in false }).contains(.sevenZip))
    }

    @Test func xdvdfsIsLookedForOnlyWhenXemuIsInstalled() {
        func missing(xemu: Bool) -> [SystemTool] {
            SystemTool.missing(installed: { _ in false }, emulatorInstalled: { $0 == .xemu && xemu })
        }

        #expect(missing(xemu: false) == [.sevenZip])
        #expect(missing(xemu: true) == [.sevenZip, .xdvdfs])
    }

    @Test func xdvdfsSaysItMakesXISOsForXemuAndHowToInstallIt() throws {
        let warning = try #require(SystemTool.warning(missing: [.xdvdfs]))
        #expect(warning.title == "xdvdfs isn't installed")
        #expect(warning.message.contains("XISO"))
        #expect(warning.message.contains("`cargo install xdvdfs-cli`"))
    }

    @Test func xdvdfsIsFoundWhereCargoInstallsIt() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "xdvdfs home \(UUID().uuidString)", directoryHint: .isDirectory)
        let bin = home.appending(path: ".cargo/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appending(path: "xdvdfs")
        FileManager.default.createFile(
            atPath: executable.path(percentEncoded: false), contents: Data(), attributes: [.posixPermissions: 0o755])

        #expect(XDVDFS.find(home: home)?.path(percentEncoded: false) == executable.path(percentEncoded: false))
    }
}
