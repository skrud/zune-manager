import Foundation

/// Where a song saved from the Zune goes: `<Artist>/<Album>/<NN> <Title>.<ext>`.
public enum ExportNaming {
    public static func relativePath(for item: MediaItem) -> String {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        let name = item.trackNumber > 0
            ? String(format: "%02d %@", item.trackNumber, component(item.title))
            : component(item.title)
        return [component(item.artist), component(item.album),
                "\(name).\(ext.isEmpty ? item.format.rawValue : ext)"].joined(separator: "/")
    }

    private static func component(_ s: String) -> String {
        var cleaned = s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Unknown" : cleaned
    }
}
