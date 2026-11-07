import Foundation

public struct TransferProgress: Hashable, Sendable {
    public var sent: UInt64
    public var total: UInt64

    public init(sent: UInt64, total: UInt64) {
        self.sent = sent
        self.total = total
    }
}

/// How far connecting has got. Connecting reads every object on the Zune one by one
/// (`readingObjects`), then the details of every song (`readingSongs`), then the album list
/// (`readingAlbums`, which reports no progress of its own).
public struct ConnectProgress: Hashable, Sendable {
    public enum Stage: Hashable, Sendable {
        case readingObjects, readingSongs, readingAlbums
    }

    public var stage: Stage
    public var done: Int
    /// 0 when the Zune couldn't say how many there are.
    public var total: Int

    public init(stage: Stage, done: Int, total: Int) {
        self.stage = stage
        self.done = done
        self.total = total
    }
}

/// Everything the app asks of the Zune. `LiveZuneDevice` talks to the real one; tests use a fake.
public protocol ZuneDeviceClient: Sendable {
    func connect(progress: @escaping @Sendable (ConnectProgress) -> Void) async throws -> DeviceSnapshot
    func refreshStorage() async throws -> StorageInfo
    /// Asks the device itself (not a cache) whether the object exists.
    func objectExists(_ id: UInt32) async throws -> Bool
    func download(_ id: UInt32, to url: URL, progress: @escaping @Sendable (TransferProgress) -> Void) async throws
    func albumArt(albumID: UInt32) async throws -> Data?
    func sendSong(_ song: LocalSong, progress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MediaItem
    func createAlbum(name: String, artist: String, itemIDs: [UInt32]) async throws -> AlbumObject
    func updateAlbum(_ album: AlbumObject) async throws
    func setAlbumArt(albumID: UInt32, art: AlbumArt) async throws
    func delete(_ id: UInt32) async throws
    func disconnect() async
}
