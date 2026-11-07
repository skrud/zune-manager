import Foundation

public struct TransferProgress: Hashable, Sendable {
    public var sent: UInt64
    public var total: UInt64

    public init(sent: UInt64, total: UInt64) {
        self.sent = sent
        self.total = total
    }
}

/// Everything the app asks of the Zune. `LiveZuneDevice` talks to the real one; tests use a fake.
public protocol ZuneDeviceClient: Sendable {
    func connect() async throws -> DeviceSnapshot
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
