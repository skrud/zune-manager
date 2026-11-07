import Foundation
import Testing
import ZuneTestSupport
@testable import ZuneKit

@Suite struct TagReaderTests {
    let dir: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TagReaderTests-\(UUID())")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @Test func readsAllTags() async throws {
        let url = dir.appendingPathComponent("tears.mp3")
        try MP3Fixture.write(to: url, title: "Tears", artist: "Rush", album: "2112", albumArtist: "Rush",
                             track: "5/6", year: "1976", genre: "(17)",
                             artworkJPEG: ImageFixture.jpeg(width: 300, height: 300))
        let s = try await TagReader.read(url)
        #expect(s.url == url)
        #expect(s.title == "Tears")
        #expect(s.artist == "Rush")
        #expect(s.album == "2112")
        #expect(s.albumArtist == "Rush")
        #expect(s.trackNumber == 5)
        #expect(s.year == 1976)
        #expect(s.genre == "Rock")
        #expect(abs(s.durationMs - 2000) < 100)
        #expect(s.fileSize == UInt64(try Data(contentsOf: url).count))
        let art = try #require(s.embeddedArtwork)
        #expect(art.starts(with: [0xFF, 0xD8]))
    }

    @Test func readsUntaggedFileWithFallbacks() async throws {
        let url = dir.appendingPathComponent("07 Some Song.mp3")
        try MP3Fixture.write(to: url, title: nil, artist: nil, album: nil)
        let s = try await TagReader.read(url)
        #expect(s.title == "07 Some Song")
        #expect(s.artist == "Unknown Artist")
        #expect(s.album == "Unknown Album")
        #expect(s.albumArtist == nil)
        #expect(s.trackNumber == 0)
        #expect(s.year == nil)
        #expect(s.genre == "")
        #expect(s.embeddedArtwork == nil)
    }

    @Test func keepsUnicodeTags() async throws {
        let url = dir.appendingPathComponent("u.mp3")
        try MP3Fixture.write(to: url, title: "Tëst Ünicode / Song", artist: "Motörhead", album: "Ace of Spades")
        let s = try await TagReader.read(url)
        #expect(s.title == "Tëst Ünicode / Song")
        #expect(s.artist == "Motörhead")
    }

    /// The Zune can't draw combining accents, and macOS hands back file names decomposed
    /// ("e" + U+0308), so everything read must come out precomposed ("ë" = U+00EB).
    @Test func textIsPrecomposed() async throws {
        let url = dir.appendingPathComponent("Te\u{0308}st.mp3")
        try MP3Fixture.write(to: url, title: nil, artist: "Mo\u{0308}rhead", album: "U\u{0308}ber")
        let s = try await TagReader.read(url)
        #expect(Array(s.title.unicodeScalars) == Array("T\u{00EB}st".unicodeScalars))
        #expect(Array(s.artist.unicodeScalars) == Array("M\u{00F6}rhead".unicodeScalars))
        #expect(Array(s.album.unicodeScalars) == Array("\u{00DC}ber".unicodeScalars))
    }

    @Test func effectiveAlbumArtistFallsBackToArtist() async throws {
        let url = dir.appendingPathComponent("e.mp3")
        try MP3Fixture.write(to: url, title: "T", artist: "Rush", album: "2112")
        #expect(try await TagReader.read(url).effectiveAlbumArtist == "Rush")
    }
}
