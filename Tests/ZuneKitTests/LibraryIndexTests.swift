import Testing
@testable import ZuneKit

private func song(_ id: UInt32, _ title: String, artist: String, album: String,
                  track: Int = 0, format: MediaFormat = .mp3) -> MediaItem {
    MediaItem(id: id, kind: .audio, title: title, artist: artist, album: album, genre: "",
              trackNumber: track, durationMs: 1000, fileSize: 1000, fileName: "\(title).mp3",
              format: format)
}

private func index(_ items: [MediaItem], albums: [AlbumObject] = []) -> LibraryIndex {
    LibraryIndex(snapshot: DeviceSnapshot(deviceName: "Zune", items: items, albums: albums,
                                          storage: StorageInfo(capacityBytes: 0, freeBytes: 0)))
}

@Suite struct LibraryIndexTests {
    @Test func artistsAreTrackArtistsSorted() {
        let idx = index([
            song(1, "2112", artist: "Rush", album: "2112"),
            song(2, "4000 Torches", artist: "3 Inches of Blood", album: "Long Live Heavy Metal"),
            song(3, "Tears", artist: "rush ", album: "2112"),
        ])
        #expect(idx.artists(matching: "") == ["3 Inches of Blood", "Rush"])
    }

    @Test func compilationGroupsUnderAlbumArtist() {
        let hits = AlbumKey(name: "Hits", albumArtist: "Various Artists")
        let idx = index(
            [song(1, "One", artist: "A", album: "Hits"), song(2, "Two", artist: "B", album: "Hits")],
            albums: [AlbumObject(id: 100, name: "Hits", artist: "Various Artists", itemIDs: [1, 2])])
        #expect(idx.albums(artist: nil, matching: "").map(\.id) == [hits])
        #expect(idx.albums(artist: nil, matching: "").first?.albumObjectID == 100)
        #expect(idx.albums(artist: "A", matching: "").map(\.id) == [hits])
        #expect(idx.items(artist: "A", album: hits, matching: "").map(\.title) == ["One"])
        #expect(idx.items(artist: nil, album: hits, matching: "").map(\.title) == ["One", "Two"])
    }

    @Test func itemWithoutAlbumObjectUsesTrackArtist() {
        let idx = index([song(7, "Tom Sawyer", artist: "Rush", album: "Moving Pictures", format: .m4a)])
        #expect(idx.albumArtist(of: 7) == "Rush")
        #expect(idx.albums(artist: "Rush", matching: "").map(\.id)
                == [AlbumKey(name: "Moving Pictures", albumArtist: "Rush")])
        #expect(idx.albums(artist: "Rush", matching: "").first?.albumObjectID == nil)
    }

    @Test func albumNamesGroupIgnoringCaseAndSpaces() {
        let idx = index([song(1, "2112", artist: "Rush", album: "2112"),
                         song(2, "Tears", artist: "Rush", album: "2112 ")])
        let albums = idx.albums(artist: nil, matching: "")
        #expect(albums.count == 1)
        #expect(albums.first?.id == AlbumKey(name: "2112", albumArtist: "Rush"))
        #expect(albums.first?.itemIDs.sorted() == [1, 2])
    }

    @Test func albumItemsSortByTrackNumberUnknownLast() {
        let idx = index([song(1, "Second", artist: "Rush", album: "2112", track: 2),
                         song(2, "Bonus", artist: "Rush", album: "2112", track: 0),
                         song(3, "First", artist: "Rush", album: "2112", track: 1)])
        let album = AlbumKey(name: "2112", albumArtist: "Rush")
        #expect(idx.items(artist: nil, album: album, matching: "").map(\.title) == ["First", "Second", "Bonus"])
        #expect(idx.items(artist: "Rush", album: album, matching: "").map(\.title) == ["First", "Second", "Bonus"])
        #expect(idx.resolve(.album(album)).map(\.title) == ["First", "Second", "Bonus"])
    }

    @Test func allItemsSortByArtistThenAlbumThenTrack() {
        let idx = index([song(1, "Tears", artist: "Rush", album: "2112", track: 5),
                         song(2, "4000 Torches", artist: "3 Inches of Blood", album: "LLHM", track: 7),
                         song(3, "Tom Sawyer", artist: "Rush", album: "Moving Pictures", track: 1),
                         song(4, "Lessons", artist: "Rush", album: "2112", track: 4)])
        #expect(idx.items(artist: nil, album: nil, matching: "").map(\.title)
                == ["4000 Torches", "Lessons", "Tears", "Tom Sawyer"])
    }

    @Test func songGroupsNestAlbumsUnderArtists() {
        let idx = index([song(1, "Tears", artist: "Rush", album: "2112", track: 5),
                         song(2, "4000 Torches", artist: "3 Inches of Blood", album: "LLHM", track: 7),
                         song(3, "Tom Sawyer", artist: "Rush", album: "Moving Pictures", track: 1),
                         song(4, "Lessons", artist: "Rush", album: "2112", track: 4)])
        let groups = idx.songGroups(artist: nil, album: nil, matching: "")
        #expect(groups.map(\.artist) == ["3 Inches of Blood", "Rush"])
        #expect(groups[1].albums.map(\.album.name) == ["2112", "Moving Pictures"])
        #expect(groups[1].albums[0].items.map(\.title) == ["Lessons", "Tears"])

        let rush = idx.songGroups(artist: "Rush", album: nil, matching: "")
        #expect(rush.map(\.artist) == ["Rush"])
        #expect(rush[0].albums.map(\.album.name) == ["2112", "Moving Pictures"])

        let one = idx.songGroups(artist: nil, album: AlbumKey(name: "2112", albumArtist: "Rush"), matching: "")
        #expect(one.flatMap(\.albums).map(\.album.name) == ["2112"])
        #expect(one.flatMap(\.albums).flatMap(\.items).map(\.title) == ["Lessons", "Tears"])
    }

    @Test func songGroupsFollowSearch() {
        let idx = index([song(1, "Tears", artist: "Rush", album: "2112"),
                         song(2, "4000 Torches", artist: "3 Inches of Blood", album: "LLHM")])
        #expect(idx.songGroups(artist: nil, album: nil, matching: "tear").map(\.artist) == ["Rush"])
    }

    @Test func artistItemsSortByAlbumThenTrack() {
        let idx = index([song(1, "Tom Sawyer", artist: "Rush", album: "Moving Pictures", track: 1),
                         song(2, "Lessons", artist: "Rush", album: "2112", track: 4),
                         song(3, "Limelight", artist: "Rush", album: "Moving Pictures", track: 3),
                         song(4, "Overture", artist: "Rush", album: "2112", track: 1),
                         song(5, "Red Barchetta", artist: "Rush", album: "Moving Pictures", track: 2)])
        #expect(idx.items(artist: "Rush", album: nil, matching: "").map(\.title)
                == ["Overture", "Lessons", "Tom Sawyer", "Red Barchetta", "Limelight"])
        #expect(idx.resolve(.artist("Rush")).map(\.title)
                == ["Overture", "Lessons", "Tom Sawyer", "Red Barchetta", "Limelight"])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        let idx = index([song(1, "Ace of Spades", artist: "Motörhead", album: "Ace of Spades"),
                         song(2, "Tears", artist: "Rush", album: "2112")])
        #expect(idx.artists(matching: "motorhead") == ["Motörhead"])
        #expect(idx.items(artist: nil, album: nil, matching: "ACE OF").map(\.title) == ["Ace of Spades"])
        #expect(idx.albums(artist: nil, matching: "2112").map(\.id.name) == ["2112"])
    }

    @Test func searchMatchesAlbumArtist() {
        let idx = index([song(1, "One", artist: "A", album: "Hits")],
                        albums: [AlbumObject(id: 100, name: "Hits", artist: "Various Artists", itemIDs: [1])])
        #expect(idx.items(artist: nil, album: nil, matching: "various").map(\.title) == ["One"])
    }

    @Test func indexUsesUnknownForEmptyFields() {
        let idx = index([song(1, "Mystery", artist: "", album: " ")])
        #expect(idx.artists(matching: "") == ["Unknown Artist"])
        #expect(idx.albums(artist: "Unknown Artist", matching: "").map(\.id)
                == [AlbumKey(name: "Unknown Album", albumArtist: "Unknown Artist")])
        #expect(idx.items(artist: "Unknown Artist", album: nil, matching: "").map(\.id) == [1])
    }

    @Test func resolveAlbumAndArtist() {
        let idx = index([song(1, "2112", artist: "Rush", album: "2112", track: 1),
                         song(2, "Tears", artist: "Rush", album: "2112", track: 5),
                         song(3, "Torches", artist: "3 Inches of Blood", album: "LLHM"),
                         song(5, "Tom Sawyer", artist: "Rush", album: "Moving Pictures")])
        #expect(idx.resolve(.album(AlbumKey(name: "2112", albumArtist: "Rush"))).map(\.id) == [1, 2])
        #expect(idx.resolve(.artist("Rush")).map(\.id).sorted() == [1, 2, 5])
        #expect(idx.resolve(.items([3, 99])).map(\.id) == [3])
        #expect(idx.item(5)?.title == "Tom Sawyer")
    }
}
