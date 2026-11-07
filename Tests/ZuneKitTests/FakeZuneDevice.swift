import Foundation
@testable import ZuneKit

/// An in-memory Zune. Records every call in `calls` using these exact strings:
/// `connect`, `storage`, `exists <id>`, `download <id>`, `art <albumID>`, `send <title>`,
/// `createAlbum <name>`, `updateAlbum <albumID>`, `setArt <albumID>`, `delete <id>`, `disconnect`.
/// New items get ids from 11, new albums from 101.
actor FakeZuneDevice: ZuneDeviceClient {
    private(set) var calls: [String] = []
    private(set) var items: [UInt32: MediaItem]
    private(set) var albums: [UInt32: AlbumObject]
    private(set) var art: [UInt32: Data]
    private(set) var updatedAlbums: [AlbumObject] = []
    private var storage: StorageInfo
    private let deviceName: String
    private var nextItemID: UInt32 = 11
    private var nextAlbumID: UInt32 = 101

    // Failure injection.
    var connectError: ZuneError?
    var stuckOn: Set<String> = []
    var failSendFor: Set<String> = []
    var existsAfterDelete = false
    var downloadShortBy = 0
    var onDownload: (@Sendable (UInt32) async -> Void)?
    var onDelete: (@Sendable (UInt32) async -> Void)?
    /// Thrown by delete after `onDelete` runs (e.g. a late error from an unplugged Zune).
    var deleteError: ZuneError?
    /// Reported in order during connect, then `onConnect` runs before connect returns.
    var connectProgress: [ConnectProgress] = []
    var onConnect: (@Sendable () async -> Void)?
    var onDisconnect: (@Sendable () async -> Void)?

    init(_ snapshot: DeviceSnapshot, art: [UInt32: Data] = [:]) {
        items = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        albums = Dictionary(uniqueKeysWithValues: snapshot.albums.map { ($0.id, $0) })
        storage = snapshot.storage
        deviceName = snapshot.deviceName
        self.art = art
    }

    func configure(_ change: @Sendable (isolated FakeZuneDevice) -> Void) {
        change(self)
    }

    private func record(_ call: String, op: String) throws {
        calls.append(call)
        if stuckOn.contains(op) { throw ZuneError.deviceNotResponding(operation: op) }
    }

    func connect(progress: @escaping @Sendable (ConnectProgress) -> Void) async throws -> DeviceSnapshot {
        try record("connect", op: "connect")
        if let connectError { throw connectError }
        for p in connectProgress { progress(p) }
        await onConnect?()
        return DeviceSnapshot(deviceName: deviceName, items: items.values.sorted { $0.id < $1.id },
                              albums: albums.values.sorted { $0.id < $1.id }, storage: storage)
    }

    func refreshStorage() async throws -> StorageInfo {
        try record("storage", op: "storage")
        return storage
    }

    func objectExists(_ id: UInt32) async throws -> Bool {
        try record("exists \(id)", op: "exists")
        return items[id] != nil || albums[id] != nil
    }

    func download(_ id: UInt32, to url: URL, progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        try record("download \(id)", op: "download")
        await onDownload?(id)
        guard let item = items[id] else { throw ZuneError.libmtp(operation: "download", message: "no such item") }
        let size = Int(item.fileSize) - downloadShortBy
        try Data(repeating: 7, count: max(0, size)).write(to: url)
        progress(TransferProgress(sent: UInt64(size), total: item.fileSize))
    }

    func albumArt(albumID: UInt32) async throws -> Data? {
        try record("art \(albumID)", op: "art")
        return art[albumID]
    }

    func sendSong(_ song: LocalSong, progress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MediaItem {
        try record("send \(song.title)", op: "send")
        if failSendFor.contains(song.title) {
            throw ZuneError.libmtp(operation: "copy to Zune", message: "device said no")
        }
        let item = MediaItem(id: nextItemID, kind: .audio, title: song.title, artist: song.artist,
                             album: song.album, genre: song.genre, trackNumber: song.trackNumber,
                             durationMs: song.durationMs, fileSize: song.fileSize,
                             fileName: song.url.lastPathComponent, format: .mp3)
        nextItemID += 1
        items[item.id] = item
        storage.freeBytes -= min(storage.freeBytes, song.fileSize)
        progress(TransferProgress(sent: song.fileSize, total: song.fileSize))
        return item
    }

    func createAlbum(name: String, artist: String, itemIDs: [UInt32]) async throws -> AlbumObject {
        try record("createAlbum \(name)", op: "createAlbum")
        let album = AlbumObject(id: nextAlbumID, name: name, artist: artist, itemIDs: itemIDs)
        nextAlbumID += 1
        albums[album.id] = album
        return album
    }

    func updateAlbum(_ album: AlbumObject) async throws {
        try record("updateAlbum \(album.id)", op: "updateAlbum")
        albums[album.id] = album
        updatedAlbums.append(album)
    }

    func setAlbumArt(albumID: UInt32, art: AlbumArt) async throws {
        try record("setArt \(albumID)", op: "setArt")
        self.art[albumID] = art.jpeg
    }

    func delete(_ id: UInt32) async throws {
        try record("delete \(id)", op: "delete")
        await onDelete?(id)
        if let deleteError { throw deleteError }
        guard !existsAfterDelete else { return }
        if let item = items.removeValue(forKey: id) { storage.freeBytes += item.fileSize }
        albums.removeValue(forKey: id)
    }

    func disconnect() async {
        calls.append("disconnect")
        await onDisconnect?()
    }
}
