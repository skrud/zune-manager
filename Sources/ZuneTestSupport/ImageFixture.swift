import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Solid-colour images for tests and device checks.
public enum ImageFixture {
    public static func jpeg(width: Int, height: Int) -> Data {
        encode(width: width, height: height, type: .jpeg)
    }

    public static func png(width: Int, height: Int) -> Data {
        encode(width: width, height: height, type: .png)
    }

    private static func encode(width: Int, height: Int, type: UTType) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.91, green: 0.51, blue: 0.23, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
