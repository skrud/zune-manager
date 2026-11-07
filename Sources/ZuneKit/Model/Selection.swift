/// An album as shown in the browser: its name and album artist, as displayed.
public struct AlbumKey: Hashable, Sendable {
    public let name: String
    public let albumArtist: String

    public init(name: String, albumArtist: String) {
        self.name = name
        self.albumArtist = albumArtist
    }
}

/// A row in the Albums column.
public struct AlbumEntry: Identifiable, Hashable, Sendable {
    public var id: AlbumKey
    /// The Zune's album object for this album, if it has one.
    public var albumObjectID: UInt32?
    public var itemIDs: [UInt32]

    public init(id: AlbumKey, albumObjectID: UInt32?, itemIDs: [UInt32]) {
        self.id = id
        self.albumObjectID = albumObjectID
        self.itemIDs = itemIDs
    }
}

/// What the user picked to delete or save.
public enum Selection: Hashable, Sendable {
    case items([UInt32])
    case album(AlbumKey)
    case artist(String)
}
