import Foundation

/// Writes small but valid MP3 files with ID3v2.3 tags, for tests and device checks.
public enum MP3Fixture {
    /// Writes `seconds` of silent MPEG-1 Layer III audio (128 kbps, 44.1 kHz) to `url`,
    /// preceded by an ID3v2.3 tag holding the given fields. With no fields and no artwork,
    /// the file has no tag at all.
    public static func write(to url: URL, title: String?, artist: String?, album: String?,
                             albumArtist: String? = nil, track: String? = nil, year: String? = nil,
                             genre: String? = nil, artworkJPEG: Data? = nil,
                             seconds: Double = 2) throws {
        var frames = Data()
        let textFrames: [(String, String?)] = [
            ("TIT2", title), ("TPE1", artist), ("TALB", album), ("TPE2", albumArtist),
            ("TRCK", track), ("TYER", year), ("TCON", genre),
        ]
        for (id, value) in textFrames {
            guard let value else { continue }
            frames.append(frame(id, Data([0x03]) + Data(value.utf8)))
        }
        if let artworkJPEG {
            // Encoding ISO-8859-1, MIME type, picture type 3 (front cover), empty description.
            var body = Data([0x00]) + Data("image/jpeg".utf8) + Data([0x00, 0x03, 0x00])
            body.append(artworkJPEG)
            frames.append(frame("APIC", body))
        }

        var file = Data()
        if !frames.isEmpty {
            file.append(Data("ID3".utf8) + Data([0x03, 0x00, 0x00]))
            file.append(syncsafe(frames.count))
            file.append(frames)
        }
        // 128 kbps / 44.1 kHz frames are 417 bytes and hold 1152 samples each.
        let header = Data([0xFF, 0xFB, 0x90, 0x64])
        let audioFrame = header + Data(count: 413)
        for _ in 0..<Int(seconds * 44100 / 1152) { file.append(audioFrame) }
        try file.write(to: url)
    }

    private static func frame(_ id: String, _ body: Data) -> Data {
        var size = UInt32(body.count).bigEndian
        return Data(id.utf8) + Data(bytes: &size, count: 4) + Data([0x00, 0x00]) + body
    }

    private static func syncsafe(_ n: Int) -> Data {
        Data([UInt8((n >> 21) & 0x7F), UInt8((n >> 14) & 0x7F), UInt8((n >> 7) & 0x7F), UInt8(n & 0x7F)])
    }
}
