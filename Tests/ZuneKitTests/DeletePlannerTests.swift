import Testing
@testable import ZuneKit

@Suite struct DeletePlannerTests {
    @Test func deleteAlbumConfirmationText() {
        let items = (1...6).map { TestData.item(UInt32($0), "Song \($0)", track: $0, size: 52_000_000 / 6) }
            + [TestData.item(7, "Tom Sawyer", album: "Moving Pictures")]
        let album = AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1, 2, 3, 4, 5, 6])
        let snapshot = TestData.snapshot(items, albums: [album])
        let plan = DeletePlanner.plan(.album(AlbumKey(name: "2112", albumArtist: "Rush")),
                                      index: LibraryIndex(snapshot: snapshot), albums: [album])
        #expect(plan.itemIDs == [1, 2, 3, 4, 5, 6])
        #expect(plan.albumObjectsToDelete == [100])
        #expect(plan.totalBytes == 51_999_996)
        #expect(plan.confirmationText == "Delete '2112' by Rush (6 songs, 52 MB) from your Zune? This can't be undone.")
    }

    @Test func deletePartOfAlbumKeepsAlbumObject() {
        let album = AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1, 2])
        let snapshot = TestData.snapshot([TestData.item(1, "A"), TestData.item(2, "B")], albums: [album])
        let plan = DeletePlanner.plan(.items([1]), index: LibraryIndex(snapshot: snapshot), albums: [album])
        #expect(plan.itemIDs == [1])
        #expect(plan.albumObjectsToDelete == [])
    }

    @Test func deleteIgnoresAlbumReferencesToMissingItems() {
        // Album object also lists 99, which isn't on the device any more.
        let album = AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1, 99])
        let snapshot = TestData.snapshot([TestData.item(1, "A")], albums: [album])
        let plan = DeletePlanner.plan(.items([1]), index: LibraryIndex(snapshot: snapshot), albums: [album])
        #expect(plan.albumObjectsToDelete == [100])
    }

    @Test func deleteArtistOnCompilationKeepsOthers() {
        let hits = AlbumObject(id: 100, name: "Hits", artist: "Various Artists", itemIDs: [1, 2])
        let snapshot = TestData.snapshot([TestData.item(1, "One", artist: "A", album: "Hits"),
                                          TestData.item(2, "Two", artist: "B", album: "Hits")], albums: [hits])
        let plan = DeletePlanner.plan(.artist("A"), index: LibraryIndex(snapshot: snapshot), albums: [hits])
        #expect(plan.itemIDs == [1])
        #expect(plan.albumObjectsToDelete == [])
        #expect(plan.confirmationText.hasPrefix("Delete all songs by A (1 song, "))
    }

    @Test func deleteSingleSongTextUsesSingular() {
        let snapshot = TestData.snapshot([TestData.item(1, "Tears", size: 9_377_054)])
        let plan = DeletePlanner.plan(.items([1]), index: LibraryIndex(snapshot: snapshot), albums: [])
        #expect(plan.confirmationText == "Delete 'Tears' by Rush (1 song, 9.4 MB) from your Zune? This can't be undone.")
    }

    @Test func deleteSeveralSongsText() {
        let snapshot = TestData.snapshot([TestData.item(1, "A", size: 2_000_000), TestData.item(2, "B", size: 3_000_000)])
        let plan = DeletePlanner.plan(.items([1, 2]), index: LibraryIndex(snapshot: snapshot), albums: [])
        #expect(plan.confirmationText == "Delete 2 songs (5 MB) from your Zune? This can't be undone.")
    }
}
