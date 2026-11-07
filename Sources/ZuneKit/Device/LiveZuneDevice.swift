import Foundation

/// The real Zune, through libmtp. Every call goes through one `DeviceWorker`.
public final class LiveZuneDevice: ZuneDeviceClient, @unchecked Sendable {
    private let worker = DeviceWorker(label: "zune.device")
    /// Only read or written inside worker bodies, which run one at a time.
    private var session: MTPSession?

    private static let connectTimeout: Duration = .seconds(300)
    private static let callTimeout: Duration = .seconds(90)

    public init() {}

    /// 90 seconds plus one second per megabyte.
    static func transferTimeout(bytes: UInt64) -> Duration {
        .seconds(90 + Int(bytes / 1_000_000))
    }

    private func withSession<T: Sendable>(_ operation: String, timeout: Duration = callTimeout,
                                          _ body: @escaping @Sendable (MTPSession) throws -> T) async throws -> T {
        try await worker.run(operation, timeout: timeout) { [self] in
            guard let session else { throw ZuneError.noDevice }
            return try body(session)
        }
    }

    public func connect() async throws -> DeviceSnapshot {
        try await worker.run("connect", timeout: Self.connectTimeout) { [self] in
            session?.close()
            session = nil
            let s = try MTPSession.open()
            session = s
            return DeviceSnapshot(deviceName: s.deviceName(), items: try s.listItems(),
                                  albums: try s.listAlbums(), storage: try s.storage())
        }
    }

    public func refreshStorage() async throws -> StorageInfo {
        try await withSession("read storage") { try $0.storage() }
    }

    public func objectExists(_ id: UInt32) async throws -> Bool {
        try await withSession("check object") { try $0.objectExists(id) }
    }

    public func download(_ id: UInt32, to url: URL,
                         progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        try await withSession("copy to Mac", timeout: .seconds(600)) { s in
            try s.download(id, to: url.path) { progress(TransferProgress(sent: $0, total: $1)) }
        }
    }

    public func albumArt(albumID: UInt32) async throws -> Data? {
        try await withSession("read album art") { try $0.albumArt(albumID) }
    }

    public func sendSong(_ song: LocalSong,
                         progress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MediaItem {
        throw ZuneError.libmtp(operation: "copy to Zune", message: "not implemented")
    }

    public func createAlbum(name: String, artist: String, itemIDs: [UInt32]) async throws -> AlbumObject {
        throw ZuneError.libmtp(operation: "create album", message: "not implemented")
    }

    public func updateAlbum(_ album: AlbumObject) async throws {
        throw ZuneError.libmtp(operation: "update album", message: "not implemented")
    }

    public func setAlbumArt(albumID: UInt32, art: AlbumArt) async throws {
        throw ZuneError.libmtp(operation: "set album art", message: "not implemented")
    }

    public func delete(_ id: UInt32) async throws {
        throw ZuneError.libmtp(operation: "delete", message: "not implemented")
    }

    public func disconnect() async {
        _ = try? await worker.run("disconnect", timeout: .seconds(30)) { [self] in
            session?.close()
            session = nil
        }
    }
}
