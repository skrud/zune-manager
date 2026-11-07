import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Album art ready for the Zune: a JPEG no larger than 240×240.
public struct AlbumArt: Hashable, Sendable {
    public var jpeg: Data
    public var width: Int
    public var height: Int

    public init(jpeg: Data, width: Int, height: Int) {
        self.jpeg = jpeg
        self.width = width
        self.height = height
    }
}

public enum Artwork {
    /// The Zune accepts album art up to 240×240 (from its device report).
    public static let maxPixels = 240

    /// Scales any image ImageIO can read to fit 240×240 (never upscaling) and encodes it as
    /// JPEG. Returns nil when the data isn't an image.
    public static func zuneAlbumArt(from imageData: Data) -> AlbumArt? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels, max(width, height)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return AlbumArt(jpeg: output as Data, width: image.width, height: image.height)
    }
}
