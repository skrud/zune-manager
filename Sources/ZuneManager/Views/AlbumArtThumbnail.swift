import AppKit
import SwiftUI
import ZuneKit

/// A small album cover, read from the Zune when the row appears (cached by the store).
struct AlbumArtThumbnail: View {
    let store: ZuneStore
    let albumObjectID: UInt32?
    var size: CGFloat = 32

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: albumObjectID) {
            image = nil
            guard let albumObjectID, let data = await store.albumArt(albumObjectID: albumObjectID) else { return }
            image = NSImage(data: data)
        }
    }
}
