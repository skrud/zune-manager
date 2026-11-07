import SwiftUI
import ZuneKit

/// "3,097 songs   [■■■■■■■■■□]   1.2 GB free of 29.8 GB"
struct FooterView: View {
    let store: ZuneStore

    var body: some View {
        let visible = store.index?.items(artist: store.selectedArtist, album: store.selectedAlbum,
                                         matching: store.searchText).count ?? 0
        let storage = store.snapshot?.storage ?? StorageInfo(capacityBytes: 0, freeBytes: 0)
        HStack(spacing: 12) {
            Text("\(visible.formatted()) \(visible == 1 ? "song" : "songs")")
            ProgressView(value: Double(storage.capacityBytes - min(storage.freeBytes, storage.capacityBytes)),
                         total: Double(max(storage.capacityBytes, 1)))
                .progressViewStyle(.linear)
            Text("\(Self.bytes(storage.freeBytes)) free of \(Self.bytes(storage.capacityBytes))")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
