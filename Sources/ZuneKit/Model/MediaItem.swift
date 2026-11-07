/// What kind of media an item is. Only audio for now; video comes later.
public enum MediaKind: Hashable, Sendable {
    case audio
}

public enum MediaFormat: String, Hashable, Sendable {
    case mp3, m4a, wma, other
}

/// A song (later also a video) stored on the Zune.
public struct MediaItem: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public var kind: MediaKind
    public var title: String
    public var artist: String
    public var album: String
    public var genre: String
    /// 0 when unknown.
    public var trackNumber: Int
    public var durationMs: Int
    public var fileSize: UInt64
    public var fileName: String
    public var format: MediaFormat

    public init(id: UInt32, kind: MediaKind, title: String, artist: String, album: String,
                genre: String, trackNumber: Int, durationMs: Int, fileSize: UInt64,
                fileName: String, format: MediaFormat) {
        self.id = id
        self.kind = kind
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.trackNumber = trackNumber
        self.durationMs = durationMs
        self.fileSize = fileSize
        self.fileName = fileName
        self.format = format
    }
}

/// The Zune's own album entry: groups songs in its menus and carries the cover art.
/// `artist` is the album artist.
public struct AlbumObject: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public var name: String
    public var artist: String
    public var itemIDs: [UInt32]

    public init(id: UInt32, name: String, artist: String, itemIDs: [UInt32]) {
        self.id = id
        self.name = name
        self.artist = artist
        self.itemIDs = itemIDs
    }
}

public struct StorageInfo: Hashable, Sendable {
    public var capacityBytes: UInt64
    public var freeBytes: UInt64

    public init(capacityBytes: UInt64, freeBytes: UInt64) {
        self.capacityBytes = capacityBytes
        self.freeBytes = freeBytes
    }
}

/// Everything read from the Zune when connecting.
public struct DeviceSnapshot: Sendable {
    public var deviceName: String
    public var items: [MediaItem]
    public var albums: [AlbumObject]
    public var storage: StorageInfo

    public init(deviceName: String, items: [MediaItem], albums: [AlbumObject], storage: StorageInfo) {
        self.deviceName = deviceName
        self.items = items
        self.albums = albums
        self.storage = storage
    }
}
