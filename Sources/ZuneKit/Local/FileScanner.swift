import Foundation

/// Finds MP3s in the files and folders the user picked.
public enum FileScanner {
    public struct Result: Sendable {
        public var mp3s: [URL]
        /// Files that aren't MP3s (hidden files are ignored entirely).
        public var skipped: [URL]
    }

    public static func scan(_ urls: [URL]) -> Result {
        var mp3s: [URL] = []
        var skipped: [URL] = []
        func consider(_ file: URL) {
            if file.pathExtension.lowercased() == "mp3" { mp3s.append(file) } else { skipped.append(file) }
        }
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                consider(url)
                continue
            }
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let file = enumerator?.nextObject() as? URL {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    consider(file)
                }
            }
        }
        let byPath: (URL, URL) -> Bool = { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return Result(mp3s: mp3s.sorted(by: byPath), skipped: skipped.sorted(by: byPath))
    }

    /// `cover.jpg`, else `folder.jpg`, in the song's folder (any capitalisation).
    public static func coverImage(forSongAt url: URL) -> URL? {
        let folder = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for wanted in ["cover.jpg", "folder.jpg"] {
            if let match = names.first(where: { $0.lowercased() == wanted }) {
                return folder.appendingPathComponent(match)
            }
        }
        return nil
    }
}
