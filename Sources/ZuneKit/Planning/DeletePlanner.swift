import Foundation

public struct DeletePlan: Hashable, Sendable {
    public var itemIDs: [UInt32]
    /// Album objects left with no songs once the items are gone.
    public var albumObjectsToDelete: [UInt32]
    public var totalBytes: UInt64
    public var confirmationText: String
}

public enum DeletePlanner {
    public static func plan(_ selection: Selection, index: LibraryIndex, albums: [AlbumObject]) -> DeletePlan {
        let items = index.resolve(selection)
        let deleted = Set(items.map(\.id))
        let emptied = albums.filter { album in
            let present = album.itemIDs.filter { index.item($0) != nil }
            return !present.isEmpty && present.allSatisfy(deleted.contains)
        }.map(\.id)
        let bytes = items.reduce(UInt64(0)) { $0 + $1.fileSize }

        let count = "\(items.count) \(items.count == 1 ? "song" : "songs")"
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let what: String
        switch selection {
        case .album(let key):
            what = "'\(key.name)' by \(key.albumArtist) (\(count), \(size))"
        case .artist(let name):
            what = "all songs by \(name) (\(count), \(size))"
        case .items:
            if items.count == 1, let item = items.first {
                what = "'\(item.title)' by \(item.artist) (\(count), \(size))"
            } else {
                what = "\(count) (\(size))"
            }
        }
        return DeletePlan(itemIDs: items.map(\.id), albumObjectsToDelete: emptied, totalBytes: bytes,
                          confirmationText: "Delete \(what) from your Zune? This can't be undone.")
    }
}
