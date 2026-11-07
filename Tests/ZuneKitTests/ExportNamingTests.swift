import Testing
@testable import ZuneKit

@Suite struct ExportNamingTests {
    @Test func exportPathFormat() {
        let item = TestData.item(1, "A Passage to Bangkok", artist: "Rush", album: "2112", track: 2,
                                 fileName: "02 A Passage to Bangkok.MP3")
        #expect(ExportNaming.relativePath(for: item) == "Rush/2112/02 A Passage to Bangkok.mp3")
    }

    @Test func exportPathSanitizesSlashesAndColons() {
        let item = TestData.item(1, "Re: Stacks", artist: "AC/DC", album: "Back in Black", track: 0,
                                 format: .m4a, fileName: "noext")
        #expect(ExportNaming.relativePath(for: item) == "AC_DC/Back in Black/Re_ Stacks.m4a")
    }

    @Test func exportPathFillsEmptyAndDotComponents() {
        let item = TestData.item(1, "...", artist: " ", album: ".hidden", track: 12)
        #expect(ExportNaming.relativePath(for: item) == "Unknown/hidden/12 Unknown.mp3")
    }
}
