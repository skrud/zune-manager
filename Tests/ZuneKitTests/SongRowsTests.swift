import Testing
@testable import ZuneKit

@Suite struct SongRowsTests {
    let index = LibraryIndex(snapshot: TestData.snapshot([
        TestData.item(1, "Tears", artist: "Rush", album: "2112", track: 5),
        TestData.item(2, "4000 Torches", artist: "3 Inches of Blood", album: "LLHM", track: 7),
        TestData.item(3, "Tom Sawyer", artist: "Rush", album: "Moving Pictures", track: 1),
        TestData.item(4, "Lessons", artist: "Rush", album: "2112", track: 4),
    ]))

    private func describe(_ rows: [SongRow]) -> [String] {
        rows.map {
            switch $0 {
            case .artistHeading(let a): "# \(a)"
            case .albumHeading(let k, _): "## \(k.name)"
            case .song(let s, let showTrack): showTrack ? "\(s.trackNumber). \(s.title)" : s.title
            }
        }
    }

    @Test func everythingHasArtistAndAlbumHeadingsAndTrackNumbers() {
        #expect(describe(SongRow.rows(index: index, artist: nil, album: nil, matching: "")) == [
            "# 3 Inches of Blood", "## LLHM", "7. 4000 Torches",
            "# Rush", "## 2112", "4. Lessons", "5. Tears", "## Moving Pictures", "1. Tom Sawyer",
        ])
    }

    @Test func artistHasAlbumHeadingsAndTrackNumbers() {
        #expect(describe(SongRow.rows(index: index, artist: "Rush", album: nil, matching: "")) == [
            "## 2112", "4. Lessons", "5. Tears", "## Moving Pictures", "1. Tom Sawyer",
        ])
    }

    @Test func albumHasJustSongsWithTrackNumbers() {
        let album = AlbumKey(name: "2112", albumArtist: "Rush")
        #expect(describe(SongRow.rows(index: index, artist: nil, album: album, matching: "")) == [
            "4. Lessons", "5. Tears",
        ])
    }

    @Test func compilationRowIDsAreUnique() {
        // One album object, songs by two track artists: in "All" its heading appears under both.
        let index = LibraryIndex(snapshot: TestData.snapshot(
            [TestData.item(1, "One", artist: "A", album: "Hits", track: 1),
             TestData.item(2, "Two", artist: "B", album: "Hits", track: 2)],
            albums: [AlbumObject(id: 100, name: "Hits", artist: "Various Artists", itemIDs: [1, 2])]))
        let rows = SongRow.rows(index: index, artist: nil, album: nil, matching: "")
        #expect(describe(rows) == ["# A", "## Hits", "1. One", "# B", "## Hits", "2. Two"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func rowIDsAreUniqueAndStable() {
        let rows = SongRow.rows(index: index, artist: nil, album: nil, matching: "")
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == SongRow.rows(index: index, artist: nil, album: nil, matching: "").map(\.id))
    }
}
