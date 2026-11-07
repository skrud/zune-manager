import Foundation

/// How the Zune identifies a song: artist, album and title, ignoring case and surrounding spaces.
public struct DuplicateKey: Hashable, Sendable {
    let artist: String
    let album: String
    let title: String

    public init(artist: String, album: String, title: String) {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .caseInsensitive, locale: nil)
        }
        self.artist = norm(artist)
        self.album = norm(album)
        self.title = norm(title)
    }
}

/// A song being added that's already on the Zune (in any format).
public struct Duplicate: Identifiable, Hashable, Sendable {
    public var id: URL { incoming.url }
    public var incoming: LocalSong
    public var existing: MediaItem

    public init(incoming: LocalSong, existing: MediaItem) {
        self.incoming = incoming
        self.existing = existing
    }
}

public enum DuplicateChoice: Hashable, Sendable {
    case overwrite, skip
}

public enum Duplicates {
    public static func find(incoming: [LocalSong], existing: [MediaItem]) -> [Duplicate] {
        var byKey: [DuplicateKey: MediaItem] = [:]
        for item in existing {
            byKey[DuplicateKey(artist: item.artist, album: item.album, title: item.title)] = item
        }
        return incoming.compactMap { song in
            byKey[DuplicateKey(artist: song.artist, album: song.album, title: song.title)]
                .map { Duplicate(incoming: song, existing: $0) }
        }
    }
}
