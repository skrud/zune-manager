import Foundation
import Testing
@testable import ZuneKit

@Suite struct AddPlannerTests {
    let mb: UInt64 = 1_000_000

    @Test func planSkipsDuplicatesWithinBatch() throws {
        let a = TestData.song("Tears", path: "/m/Tears.mp3")
        let copy = TestData.song("Tears", path: "/m/sub/Tears.mp3")
        let p = try AddPlanner.plan(songs: [a, copy], duplicates: [], choices: [:], freeBytes: .max / 2)
        #expect(p.steps.map(\.song.url) == [a.url])
        #expect(p.skippedInBatch.map(\.url) == [copy.url])
    }

    @Test func planSkipsDuplicateWithoutChoice() throws {
        let song = TestData.song("Tears")
        let dupe = Duplicate(incoming: song, existing: TestData.item(5, "Tears"))
        let p = try AddPlanner.plan(songs: [song], duplicates: [dupe], choices: [:], freeBytes: 100 * mb)
        #expect(p.steps.isEmpty)
        #expect(p.skippedDuplicates == [song])
        #expect(p.incomingBytes == 0)
    }

    @Test func planUploadsFirstWhenSpaceAllows() throws {
        let song = TestData.song("Tears", size: 20 * mb)
        let old = TestData.item(5, "Tears", size: 18 * mb)
        let p = try AddPlanner.plan(songs: [song], duplicates: [Duplicate(incoming: song, existing: old)],
                                    choices: [song.url: .overwrite], freeBytes: 100 * mb)
        #expect(p.steps == [AddStep(song: song, replacing: old)])
        #expect(p.overwriteMode == .uploadThenDelete)
        #expect(p.incomingBytes == 20 * mb)
    }

    @Test func planDeletesFirstWhenTight() throws {
        let song = TestData.song("Tears", size: 20 * mb)
        let old = TestData.item(5, "Tears", size: 18 * mb)
        // 25 MB free: not enough for 20 MB + 10.49 MB margin, enough once the 18 MB copy is gone.
        let p = try AddPlanner.plan(songs: [song], duplicates: [Duplicate(incoming: song, existing: old)],
                                    choices: [song.url: .overwrite], freeBytes: 25 * mb)
        #expect(p.overwriteMode == .deleteThenUpload)
    }

    @Test func planThrowsWhenNotEnoughSpace() {
        let song = TestData.song("Big", size: 20_000_000)
        #expect(throws: AddPlanError.notEnoughSpace(neededBytes: 20_000_000 + 10_485_760,
                                                    availableBytes: 5_000_000)) {
            try AddPlanner.plan(songs: [song], duplicates: [], choices: [:], freeBytes: 5_000_000)
        }
    }

    @Test func albumTargetMatchesAlbumArtistCaseInsensitive() {
        let hits = AlbumObject(id: 100, name: "Hits", artist: "Various Artists", itemIDs: [1])
        let song = TestData.song("One", artist: "A", album: "hits ", albumArtist: "various artists")
        #expect(AddPlanner.albumTarget(for: song, albums: [hits]) == .existing(hits))
    }

    @Test func albumTargetCreatesWhenMissing() {
        let other = AlbumObject(id: 100, name: "2112", artist: "Someone Else", itemIDs: [])
        let song = TestData.song("Tears", artist: "Rush", album: "2112")
        #expect(AddPlanner.albumTarget(for: song, albums: [other]) == .create(name: "2112", artist: "Rush"))
    }
}
