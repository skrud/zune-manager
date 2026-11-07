import Foundation
import Testing
@testable import ZuneKit

@Suite struct FileScannerTests {
    let dir: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FileScannerTests-\(UUID())")
        try! FileManager.default.createDirectory(at: url.appendingPathComponent("sub"),
                                                 withIntermediateDirectories: true)
        return url
    }()

    private func touch(_ path: String) -> URL {
        let url = dir.appendingPathComponent(path)
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        return url
    }

    @Test func scanRecursesAndSkipsNonMP3() {
        _ = touch("a.mp3")
        _ = touch("sub/B.MP3")
        _ = touch("notes.txt")
        _ = touch(".hidden.mp3")
        _ = touch("c.m4a")
        let r = FileScanner.scan([dir])
        #expect(r.mp3s.map(\.lastPathComponent) == ["a.mp3", "B.MP3"])
        #expect(Set(r.skipped.map(\.lastPathComponent)) == ["notes.txt", "c.m4a"])
    }

    @Test func scanAcceptsSingleFile() {
        let a = touch("a.mp3")
        let r = FileScanner.scan([a])
        #expect(r.mp3s.map(\.lastPathComponent) == ["a.mp3"])
        #expect(r.skipped.isEmpty)
    }

    @Test func scanReportsSingleNonMP3File() {
        let t = touch("notes.txt")
        #expect(FileScanner.scan([t]).skipped.map(\.lastPathComponent) == ["notes.txt"])
    }

    @Test func findsCoverJpgCaseInsensitive() {
        let song = touch("sub/B.MP3")
        _ = touch("sub/Folder.JPG")
        #expect(FileScanner.coverImage(forSongAt: song)?.lastPathComponent == "Folder.JPG")
        #expect(FileScanner.coverImage(forSongAt: touch("a.mp3")) == nil)
    }

    @Test func prefersCoverOverFolder() {
        let song = touch("a.mp3")
        _ = touch("folder.jpg")
        _ = touch("cover.jpg")
        #expect(FileScanner.coverImage(forSongAt: song)?.lastPathComponent == "cover.jpg")
    }
}
