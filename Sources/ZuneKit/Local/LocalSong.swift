import Foundation

/// An MP3 on the Mac, with the tags read from it.
public struct LocalSong: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String?
    /// 0 when unknown.
    public var trackNumber: Int
    public var year: Int?
    public var genre: String
    public var durationMs: Int
    public var fileSize: UInt64
    public var embeddedArtwork: Data?

    /// The artist the song's album belongs to: the album artist tag, else the song's artist.
    public var effectiveAlbumArtist: String { albumArtist ?? artist }

    public init(url: URL, title: String, artist: String, album: String, albumArtist: String?,
                trackNumber: Int, year: Int?, genre: String, durationMs: Int, fileSize: UInt64,
                embeddedArtwork: Data?) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.year = year
        self.genre = genre
        self.durationMs = durationMs
        self.fileSize = fileSize
        self.embeddedArtwork = embeddedArtwork
    }
}
