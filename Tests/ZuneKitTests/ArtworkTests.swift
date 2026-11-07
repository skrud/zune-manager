import Foundation
import ImageIO
import Testing
import ZuneTestSupport
@testable import ZuneKit

@Suite struct ArtworkTests {
    private func pixelSize(_ jpeg: Data) -> (Int, Int) {
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
    }

    @Test func artworkFitsWithin240KeepingAspect() throws {
        let art = try #require(Artwork.zuneAlbumArt(from: ImageFixture.png(width: 600, height: 300)))
        #expect(art.width == 240)
        #expect(art.height == 120)
        #expect(art.jpeg.starts(with: [0xFF, 0xD8]))
        #expect(pixelSize(art.jpeg) == (240, 120))
    }

    @Test func artworkDoesNotUpscale() throws {
        let art = try #require(Artwork.zuneAlbumArt(from: ImageFixture.jpeg(width: 100, height: 100)))
        #expect(art.width == 100 && art.height == 100)
        #expect(pixelSize(art.jpeg) == (100, 100))
    }

    @Test func artworkRejectsGarbage() {
        #expect(Artwork.zuneAlbumArt(from: Data("nope".utf8)) == nil)
    }
}
