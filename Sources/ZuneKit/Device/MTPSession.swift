import CLibMTP
import Foundation

/// A thin wrapper over one open libmtp device. Not thread-safe: only `DeviceWorker`
/// bodies touch it, one call at a time.
final class MTPSession {
    private let device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>

    private static let initialized: Bool = {
        LIBMTP_Init()
        return true
    }()

    private init(device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) {
        self.device = device
    }

    /// Opens the first attached device. Cached open: libmtp enumerates every object here
    /// (one by one, thanks to the fork's Zune flag), which takes about a minute.
    static func open() throws -> MTPSession {
        _ = initialized
        var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var count: Int32 = 0
        let status = LIBMTP_Detect_Raw_Devices(&raw, &count)
        defer { free(raw) }
        guard status == LIBMTP_ERROR_NONE, count > 0, let raw else { throw ZuneError.noDevice }
        guard let device = LIBMTP_Open_Raw_Device(raw) else {
            throw ZuneError.libmtp(operation: "connect", message: "Could not open the Zune.")
        }
        return MTPSession(device: device)
    }

    func close() {
        LIBMTP_Release_Device(device)
    }

    func deviceName() -> String {
        guard let name = LIBMTP_Get_Friendlyname(device) else { return "Zune" }
        defer { free(name) }
        return String(cString: name)
    }

    func storage() throws -> StorageInfo {
        guard LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) == 0 else {
            throw error("read storage")
        }
        var info = StorageInfo(capacityBytes: 0, freeBytes: 0)
        var node = device.pointee.storage
        while let s = node {
            info.capacityBytes += s.pointee.MaxCapacity
            info.freeBytes += s.pointee.FreeSpaceInBytes
            node = s.pointee.next
        }
        return info
    }

    func listItems() throws -> [MediaItem] {
        var items: [MediaItem] = []
        var node = LIBMTP_Get_Tracklisting_With_Callback(device, nil, nil)
        while let track = node {
            items.append(Self.mediaItem(track.pointee))
            node = track.pointee.next
            LIBMTP_destroy_track_t(track)
        }
        clearErrors()
        return items
    }

    func listAlbums() throws -> [AlbumObject] {
        var albums: [AlbumObject] = []
        var node = LIBMTP_Get_Album_List(device)
        while let album = node {
            let a = album.pointee
            let ids = a.tracks.map { Array(UnsafeBufferPointer(start: $0, count: Int(a.no_tracks))) } ?? []
            albums.append(AlbumObject(id: a.album_id, name: Self.string(a.name), artist: Self.string(a.artist),
                                      itemIDs: ids))
            node = a.next
            LIBMTP_destroy_album_t(album)
        }
        clearErrors()
        return albums
    }

    func objectExists(_ id: UInt32) throws -> Bool {
        switch LIBMTP_Object_Exists_On_Device(device, id) {
        case 1: return true
        case 0: return false
        default: throw error("check object \(id)")
        }
    }

    func download(_ id: UInt32, to path: String, progress: @escaping (UInt64, UInt64) -> Void) throws {
        let box = Unmanaged.passRetained(ProgressBox(progress))
        defer { box.release() }
        guard LIBMTP_Get_Track_To_File(device, id, path, ProgressBox.callback, box.toOpaque()) == 0 else {
            throw error("copy \(id) to the Mac")
        }
    }

    /// The album object's cover as stored on the Zune, or nil when it has none.
    func albumArt(_ albumID: UInt32) throws -> Data? {
        guard let sample = LIBMTP_new_filesampledata_t() else { return nil }
        defer { LIBMTP_destroy_filesampledata_t(sample) }
        guard LIBMTP_Get_Representative_Sample(device, albumID, sample) == 0 else {
            clearErrors()
            return nil
        }
        guard sample.pointee.size > 0, let data = sample.pointee.data else { return nil }
        return Data(bytes: data, count: Int(sample.pointee.size))
    }

    // MARK: - Writing

    /// Copies an MP3 to the Zune's music folder with the song's tags as its metadata.
    func sendTrack(_ song: LocalSong, progress: @escaping (UInt64, UInt64) -> Void) throws -> MediaItem {
        guard let track = LIBMTP_new_track_t() else { throw error("copy to Zune") }
        defer { LIBMTP_destroy_track_t(track) }
        // libmtp frees these strings with the track, so they must come from strdup.
        track.pointee.title = strdup(song.title)
        track.pointee.artist = strdup(song.artist)
        track.pointee.album = strdup(song.album)
        track.pointee.genre = strdup(song.genre)
        if let year = song.year { track.pointee.date = strdup(String(format: "%04d0101T000000.0", year)) }
        track.pointee.filename = strdup(song.url.lastPathComponent)
        track.pointee.tracknumber = UInt16(clamping: song.trackNumber)
        track.pointee.duration = UInt32(clamping: song.durationMs)
        track.pointee.filesize = song.fileSize
        track.pointee.filetype = LIBMTP_FILETYPE_MP3
        track.pointee.parent_id = device.pointee.default_music_folder
        track.pointee.storage_id = 0

        let box = Unmanaged.passRetained(ProgressBox(progress))
        defer { box.release() }
        guard LIBMTP_Send_Track_From_File(device, song.url.path, track, ProgressBox.callback, box.toOpaque()) == 0
        else { throw error("copy '\(song.title)' to the Zune") }
        return Self.mediaItem(track.pointee)
    }

    func createAlbum(name: String, artist: String, itemIDs: [UInt32]) throws -> AlbumObject {
        let album = try newAlbum(name: name, artist: artist, itemIDs: itemIDs)
        defer { LIBMTP_destroy_album_t(album) }
        guard LIBMTP_Create_New_Album(device, album) == 0 else { throw error("create album '\(name)'") }
        return AlbumObject(id: album.pointee.album_id, name: name, artist: artist, itemIDs: itemIDs)
    }

    func updateAlbum(_ object: AlbumObject) throws {
        let album = try newAlbum(name: object.name, artist: object.artist, itemIDs: object.itemIDs)
        defer { LIBMTP_destroy_album_t(album) }
        album.pointee.album_id = object.id
        guard LIBMTP_Update_Album(device, album) == 0 else { throw error("update album '\(object.name)'") }
    }

    func setAlbumArt(_ albumID: UInt32, art: AlbumArt) throws {
        guard let sample = LIBMTP_new_filesampledata_t() else { throw error("set album art") }
        defer { LIBMTP_destroy_filesampledata_t(sample) }
        let bytes = malloc(art.jpeg.count)!.assumingMemoryBound(to: CChar.self)
        art.jpeg.copyBytes(to: UnsafeMutableRawBufferPointer(start: bytes, count: art.jpeg.count))
        sample.pointee.data = bytes
        sample.pointee.size = UInt64(art.jpeg.count)
        sample.pointee.width = UInt32(art.width)
        sample.pointee.height = UInt32(art.height)
        sample.pointee.filetype = LIBMTP_FILETYPE_JPEG
        guard LIBMTP_Send_Representative_Sample(device, albumID, sample) == 0 else {
            throw error("set album art")
        }
    }

    func deleteObject(_ id: UInt32) throws {
        guard LIBMTP_Delete_Object(device, id) == 0 else { throw error("delete \(id)") }
    }

    private func newAlbum(name: String, artist: String,
                          itemIDs: [UInt32]) throws -> UnsafeMutablePointer<LIBMTP_album_t> {
        guard let album = LIBMTP_new_album_t() else { throw error("album") }
        album.pointee.name = strdup(name)
        album.pointee.artist = strdup(artist)
        if !itemIDs.isEmpty {
            let tracks = malloc(itemIDs.count * MemoryLayout<UInt32>.stride)!.assumingMemoryBound(to: UInt32.self)
            tracks.initialize(from: itemIDs, count: itemIDs.count)
            album.pointee.tracks = tracks
        }
        album.pointee.no_tracks = UInt32(itemIDs.count)
        album.pointee.parent_id = 0
        album.pointee.storage_id = 0
        return album
    }

    // MARK: - Helpers

    /// Carries a Swift progress closure through libmtp's `void *` callback data.
    final class ProgressBox {
        let report: (UInt64, UInt64) -> Void
        init(_ report: @escaping (UInt64, UInt64) -> Void) { self.report = report }

        /// Never cancels: stopping mid-file leaves the Zune stuck.
        static let callback: LIBMTP_progressfunc_t = { sent, total, data in
            if let data {
                Unmanaged<ProgressBox>.fromOpaque(data).takeUnretainedValue().report(sent, total)
            }
            return 0
        }
    }

    static func string(_ p: UnsafeMutablePointer<CChar>?) -> String {
        p.map { String(cString: $0) } ?? ""
    }

    static func mediaItem(_ t: LIBMTP_track_t) -> MediaItem {
        MediaItem(id: t.item_id, kind: .audio, title: string(t.title), artist: string(t.artist),
                  album: string(t.album), genre: string(t.genre), trackNumber: Int(t.tracknumber),
                  durationMs: Int(t.duration), fileSize: t.filesize, fileName: string(t.filename),
                  format: format(t.filetype))
    }

    static func format(_ type: LIBMTP_filetype_t) -> MediaFormat {
        switch type {
        case LIBMTP_FILETYPE_MP3: .mp3
        case LIBMTP_FILETYPE_M4A, LIBMTP_FILETYPE_MP4: .m4a
        case LIBMTP_FILETYPE_WMA: .wma
        default: .other
        }
    }

    /// Turns libmtp's error stack into a ZuneError and clears it.
    func error(_ operation: String) -> ZuneError {
        var messages: [String] = []
        var node = LIBMTP_Get_Errorstack(device)
        while let e = node {
            if let text = e.pointee.error_text { messages.append(String(cString: text)) }
            node = e.pointee.next
        }
        LIBMTP_Clear_Errorstack(device)
        return .libmtp(operation: operation,
                       message: messages.isEmpty ? "The Zune reported an error." : messages.joined(separator: "\n"))
    }

    func clearErrors() {
        LIBMTP_Clear_Errorstack(device)
    }
}
