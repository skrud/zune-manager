import Foundation
@testable import ZuneKit

/// Small builders shared by the planning and store tests.
enum TestData {
    static func item(_ id: UInt32, _ title: String, artist: String = "Rush", album: String = "2112",
                     track: Int = 0, size: UInt64 = 1_000_000, format: MediaFormat = .mp3,
                     fileName: String? = nil) -> MediaItem {
        MediaItem(id: id, kind: .audio, title: title, artist: artist, album: album, genre: "Rock",
                  trackNumber: track, durationMs: 180_000, fileSize: size,
                  fileName: fileName ?? "\(title).\(format.rawValue)", format: format)
    }

    static func song(_ title: String, artist: String = "Rush", album: String = "2112",
                     albumArtist: String? = nil, track: Int = 0, size: UInt64 = 1_000_000,
                     path: String? = nil) -> LocalSong {
        LocalSong(url: URL(fileURLWithPath: path ?? "/music/\(artist)/\(album)/\(title).mp3"),
                  title: title, artist: artist, album: album, albumArtist: albumArtist,
                  trackNumber: track, year: nil, genre: "Rock", durationMs: 180_000, fileSize: size,
                  embeddedArtwork: nil)
    }

    static func snapshot(_ items: [MediaItem], albums: [AlbumObject] = [],
                         free: UInt64 = 1_000_000_000) -> DeviceSnapshot {
        DeviceSnapshot(deviceName: "Skrud's Zune", items: items, albums: albums,
                       storage: StorageInfo(capacityBytes: 29_814_980_608, freeBytes: free))
    }
}

/// A value shared between test closures on different threads (Mutex needs macOS 15).
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    @discardableResult
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
