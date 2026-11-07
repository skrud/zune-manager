import AVFoundation
import Foundation

/// Reads an MP3's ID3 tags with AVFoundation.
public enum TagReader {
    public static func read(_ url: URL) async throws -> LocalSong {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let metadata = try await asset.loadMetadata(for: .id3Metadata)

        var text: [String: String] = [:]
        var artwork: Data?
        for item in metadata {
            guard let id = item.identifier?.rawValue else { continue }
            if id == AVMetadataIdentifier.id3MetadataAttachedPicture.rawValue {
                if artwork == nil { artwork = try await item.load(.dataValue) }
            } else if text[id] == nil, let value = try await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { text[id] = precomposed(trimmed) }
            }
        }
        func tag(_ identifier: AVMetadataIdentifier) -> String? { text[identifier.rawValue] }

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let yearText = tag(.id3MetadataYear) ?? tag(.id3MetadataRecordingTime)
        return LocalSong(
            url: url,
            title: tag(.id3MetadataTitleDescription) ?? precomposed(url.deletingPathExtension().lastPathComponent),
            artist: tag(.id3MetadataLeadPerformer) ?? LibraryIndex.unknownArtist,
            album: tag(.id3MetadataAlbumTitle) ?? LibraryIndex.unknownAlbum,
            albumArtist: tag(.id3MetadataBand),
            trackNumber: tag(.id3MetadataTrackNumber).flatMap(leadingNumber) ?? 0,
            year: yearText.flatMap { Int($0.prefix(4)) },
            genre: tag(.id3MetadataContentType) ?? "",
            durationMs: duration.isNumeric ? Int((duration.seconds * 1000).rounded()) : 0,
            fileSize: UInt64(size),
            embeddedArtwork: artwork
        )
    }

    /// The Zune can't draw combining accents (macOS file names come decomposed: "e" + U+0308),
    /// so text is sent in its composed form ("ë").
    private static func precomposed(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
    }

    /// "3/12" → 3, "07" → 7.
    private static func leadingNumber(_ s: String) -> Int? {
        Int(s.prefix { $0.isNumber })
    }
}
