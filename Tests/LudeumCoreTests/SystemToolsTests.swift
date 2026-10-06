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
        #expect(!SystemTool.missing().contains(.sevenZip))
    }
}
