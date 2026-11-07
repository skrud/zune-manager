import Testing
@testable import ZuneKit

@Suite struct DuplicatesTests {
    @Test func duplicateIgnoresCaseFormatAndSpaces() {
        let existing = TestData.item(5, "Tears", artist: "Rush", album: "2112", format: .m4a)
        let incoming = TestData.song("tears", artist: "RUSH", album: "2112 ")
        let dupes = Duplicates.find(incoming: [incoming], existing: [existing])
        #expect(dupes.count == 1)
        #expect(dupes.first?.existing.id == 5)
        #expect(dupes.first?.id == incoming.url)
    }

    @Test func differentAlbumIsNotDuplicate() {
        let existing = TestData.item(5, "Tears", album: "2112")
        let incoming = TestData.song("Tears", album: "Live")
        #expect(Duplicates.find(incoming: [incoming], existing: [existing]).isEmpty)
    }
}
