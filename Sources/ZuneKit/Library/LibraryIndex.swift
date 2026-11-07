import Foundation

/// The Artists → Albums → Songs view of a `DeviceSnapshot`, grouped the way the Zune's own
/// menus group them: songs under their own artist, albums under their album artist.
public struct LibraryIndex: Sendable {
    public static let unknownArtist = "Unknown Artist"
    public static let unknownAlbum = "Unknown Album"

    private struct GroupKey: Hashable {
        let name: String
        let artist: String
    }

    private let itemsByID: [UInt32: MediaItem]
    private let displayArtistByID: [UInt32: String]
    private let albumArtistByID: [UInt32: String]
    private let albumKeyByID: [UInt32: AlbumKey]
    private let albumEntries: [AlbumKey: AlbumEntry]
    private let orderedItems: [MediaItem]

    public init(snapshot: DeviceSnapshot) {
        var objectByItem: [UInt32: AlbumObject] = [:]
        for album in snapshot.albums {
            for id in album.itemIDs { objectByItem[id] = album }
        }

        var artistSpelling: [String: String] = [:]
        func display(_ raw: String, fallback: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.isEmpty ? fallback : trimmed
            if let seen = artistSpelling[Self.fold(value)] { return seen }
            artistSpelling[Self.fold(value)] = value
            return value
        }

        var items: [UInt32: MediaItem] = [:]
        var displayArtist: [UInt32: String] = [:]
        var albumArtist: [UInt32: String] = [:]
        var albumKey: [UInt32: AlbumKey] = [:]
        var groups: [GroupKey: (key: AlbumKey, objectID: UInt32?, ids: [UInt32])] = [:]
        var groupOrder: [GroupKey] = []

        for item in snapshot.items {
            items[item.id] = item
            let artist = display(item.artist, fallback: Self.unknownArtist)
            displayArtist[item.id] = artist
            let object = objectByItem[item.id]
            let owner = object.map { display($0.artist, fallback: artist) } ?? artist
            albumArtist[item.id] = owner

            let trimmedAlbum = item.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let albumName = trimmedAlbum.isEmpty ? Self.unknownAlbum : trimmedAlbum
            let group = GroupKey(name: Self.fold(albumName), artist: Self.fold(owner))
            if groups[group] == nil {
                groups[group] = (AlbumKey(name: albumName, albumArtist: owner), object?.id, [])
                groupOrder.append(group)
            }
            groups[group]!.ids.append(item.id)
            if groups[group]!.objectID == nil { groups[group]!.objectID = object?.id }
            albumKey[item.id] = groups[group]!.key
        }

        var entries: [AlbumKey: AlbumEntry] = [:]
        for group in groupOrder {
            let g = groups[group]!
            entries[g.key] = AlbumEntry(id: g.key, albumObjectID: g.objectID, itemIDs: g.ids)
        }

        itemsByID = items
        displayArtistByID = displayArtist
        albumArtistByID = albumArtist
        albumKeyByID = albumKey
        albumEntries = entries
        orderedItems = snapshot.items
    }

    public func artists(matching query: String) -> [String] {
        let names = Set(matchingItems(query).compactMap { displayArtistByID[$0.id] })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func albums(artist: String?, matching query: String) -> [AlbumEntry] {
        var keys = Set<AlbumKey>()
        for item in matchingItems(query) where artist == nil || displayArtistByID[item.id] == artist {
            if let key = albumKeyByID[item.id] { keys.insert(key) }
        }
        return keys.compactMap { albumEntries[$0] }.sorted {
            let byName = $0.id.name.localizedStandardCompare($1.id.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.id.albumArtist.localizedStandardCompare($1.id.albumArtist) == .orderedAscending
        }
    }

    public func items(artist: String?, album: AlbumKey?, matching query: String) -> [MediaItem] {
        let filtered = matchingItems(query).filter { item in
            (artist == nil || displayArtistByID[item.id] == artist)
                && (album == nil || albumKeyByID[item.id] == album)
        }
        return group(filtered, artist: artist, album: album).flatMap(\.albums).flatMap(\.items)
    }

    /// The Songs column's sections: songs under album headings, under artist headings.
    /// With an album selected there's one group, in track order; with an artist selected,
    /// one artist with its albums; otherwise every artist.
    public func songGroups(artist: String?, album: AlbumKey?, matching query: String) -> [SongArtistGroup] {
        let filtered = matchingItems(query).filter { item in
            (artist == nil || displayArtistByID[item.id] == artist)
                && (album == nil || albumKeyByID[item.id] == album)
        }
        return group(filtered, artist: artist, album: album)
    }

    private func group(_ items: [MediaItem], artist: String?, album: AlbumKey?) -> [SongArtistGroup] {
        if let album {
            guard !items.isEmpty else { return [] }
            return [SongArtistGroup(artist: artist ?? album.albumArtist,
                                    albums: [SongAlbumGroup(album: album, items: Self.inTrackOrder(items))])]
        }
        let byArtist = Dictionary(grouping: items) { displayArtistByID[$0.id] ?? Self.unknownArtist }
        return byArtist.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            let byAlbum = Dictionary(grouping: byArtist[name]!) {
                albumKeyByID[$0.id] ?? AlbumKey(name: Self.unknownAlbum, albumArtist: name)
            }
            let keys = byAlbum.keys.sorted { a, b in
                let byName = a.name.localizedStandardCompare(b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return a.albumArtist.localizedStandardCompare(b.albumArtist) == .orderedAscending
            }
            return SongArtistGroup(artist: name, albums: keys.map {
                SongAlbumGroup(album: $0, items: Self.inTrackOrder(byAlbum[$0]!))
            })
        }
    }

    public func item(_ id: UInt32) -> MediaItem? {
        itemsByID[id]
    }

    public func albumArtist(of id: UInt32) -> String {
        albumArtistByID[id] ?? Self.unknownArtist
    }

    public func resolve(_ selection: Selection) -> [MediaItem] {
        switch selection {
        case .items(let ids):
            return ids.compactMap { itemsByID[$0] }
        case .album(let key):
            return Self.inTrackOrder((albumEntries[key]?.itemIDs ?? []).compactMap { itemsByID[$0] })
        case .artist(let name):
            return items(artist: name, album: nil, matching: "")
        }
    }

    private func matchingItems(_ query: String) -> [MediaItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return orderedItems }
        return orderedItems.filter { item in
            [item.title, displayArtistByID[item.id] ?? "", albumKeyByID[item.id]?.name ?? "",
             albumArtistByID[item.id] ?? ""].contains { $0.localizedStandardContains(q) }
        }
    }

    private static func inTrackOrder(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted(by: trackOrder)
    }

    /// Track number (unknown last), then title.
    private static func trackOrder(_ a: MediaItem, _ b: MediaItem) -> Bool {
        let ta = a.trackNumber == 0 ? Int.max : a.trackNumber
        let tb = b.trackNumber == 0 ? Int.max : b.trackNumber
        if ta != tb { return ta < tb }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// An artist heading in the Songs column, with its albums.
public struct SongArtistGroup: Identifiable, Hashable, Sendable {
    public var id: String { artist }
    public var artist: String
    public var albums: [SongAlbumGroup]
}

/// An album heading in the Songs column, with its songs in track order.
public struct SongAlbumGroup: Identifiable, Hashable, Sendable {
    public var id: AlbumKey { album }
    public var album: AlbumKey
    public var items: [MediaItem]
}
