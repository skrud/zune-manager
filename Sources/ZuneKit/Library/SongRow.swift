/// One row of the Songs column. Headings are rows like any other, so the list is always a
/// single flat run of rows: SwiftUI's macOS List crashed (inside AppKit's outline view) when
/// switching between differently nested Section structures.
public enum SongRow: Identifiable, Hashable, Sendable {
    case artistHeading(String)
    case albumHeading(AlbumKey)
    case song(MediaItem, showTrack: Bool)

    public var id: String {
        switch self {
        case .artistHeading(let artist): "artist\u{1F}\(artist)"
        case .albumHeading(let key): "album\u{1F}\(key.name)\u{1F}\(key.albumArtist)"
        case .song(let item, _): "song\u{1F}\(item.id)"
        }
    }

    /// Everything: artist and album headings. One artist: album headings. One album: just its
    /// songs. Songs always show their track numbers.
    public static func rows(index: LibraryIndex, artist: String?, album: AlbumKey?, matching query: String) -> [SongRow] {
        let groups = index.songGroups(artist: artist, album: album, matching: query)
        if album != nil {
            return groups.flatMap(\.albums).flatMap(\.items).map { .song($0, showTrack: true) }
        }
        var rows: [SongRow] = []
        for group in groups {
            if artist == nil { rows.append(.artistHeading(group.artist)) }
            for albumGroup in group.albums {
                rows.append(.albumHeading(albumGroup.album))
                rows += albumGroup.items.map { .song($0, showTrack: true) }
            }
        }
        return rows
    }
}
