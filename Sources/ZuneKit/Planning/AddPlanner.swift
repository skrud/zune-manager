import Foundation

/// When overwriting, which happens first. Uploading first never loses a song if the copy
/// fails; deleting first is only used when there isn't room for both copies.
public enum OverwriteMode: Hashable, Sendable {
    case uploadThenDelete, deleteThenUpload
}

public struct AddStep: Hashable, Sendable {
    public var song: LocalSong
    /// The copy already on the Zune that this song replaces, when overwriting.
    public var replacing: MediaItem?

    public init(song: LocalSong, replacing: MediaItem?) {
        self.song = song
        self.replacing = replacing
    }
}

public struct AddPlan: Hashable, Sendable {
    public var steps: [AddStep]
    public var skippedDuplicates: [LocalSong]
    /// Songs that appear more than once in what the user picked; only the first is added.
    public var skippedInBatch: [LocalSong]
    public var overwriteMode: OverwriteMode
    public var incomingBytes: UInt64
}

public enum AddPlanError: Error, Equatable, Sendable {
    case notEnoughSpace(neededBytes: UInt64, availableBytes: UInt64)
}

public enum AlbumTarget: Hashable, Sendable {
    case existing(AlbumObject)
    case create(name: String, artist: String)
}

public enum AddPlanner {
    /// Room kept free on the Zune beyond what the songs need.
    public static let spaceMarginBytes: UInt64 = 10 * 1024 * 1024

    public static func plan(songs: [LocalSong], duplicates: [Duplicate], choices: [URL: DuplicateChoice],
                            freeBytes: UInt64) throws -> AddPlan {
        let existingByURL = Dictionary(duplicates.map { ($0.incoming.url, $0.existing) },
                                       uniquingKeysWith: { first, _ in first })
        var seen = Set<DuplicateKey>()
        var steps: [AddStep] = []
        var skippedDuplicates: [LocalSong] = []
        var skippedInBatch: [LocalSong] = []

        for song in songs {
            guard seen.insert(DuplicateKey(artist: song.artist, album: song.album, title: song.title)).inserted
            else {
                skippedInBatch.append(song)
                continue
            }
            if let existing = existingByURL[song.url] {
                if choices[song.url] == .overwrite {
                    steps.append(AddStep(song: song, replacing: existing))
                } else {
                    skippedDuplicates.append(song)
                }
            } else {
                steps.append(AddStep(song: song, replacing: nil))
            }
        }

        let incoming = steps.reduce(UInt64(0)) { $0 + $1.song.fileSize }
        let replaced = steps.reduce(UInt64(0)) { $0 + ($1.replacing?.fileSize ?? 0) }
        let needed = incoming + spaceMarginBytes
        let mode: OverwriteMode
        if freeBytes >= needed {
            mode = .uploadThenDelete
        } else if freeBytes + replaced >= needed {
            mode = .deleteThenUpload
        } else {
            throw AddPlanError.notEnoughSpace(neededBytes: needed, availableBytes: freeBytes)
        }
        return AddPlan(steps: steps, skippedDuplicates: skippedDuplicates, skippedInBatch: skippedInBatch,
                       overwriteMode: mode, incomingBytes: incoming)
    }

    /// The album object a new song should join, matched on album name and album artist.
    public static func albumTarget(for song: LocalSong, albums: [AlbumObject]) -> AlbumTarget {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .caseInsensitive, locale: nil)
        }
        let name = norm(song.album)
        let artist = norm(song.effectiveAlbumArtist)
        if let match = albums.first(where: { norm($0.name) == name && norm($0.artist) == artist }) {
            return .existing(match)
        }
        return .create(name: song.album.trimmingCharacters(in: .whitespacesAndNewlines),
                       artist: song.effectiveAlbumArtist.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
