import SwiftUI
import ZuneKit

/// Artists → Albums → Songs, side by side, like iTunes' column browser.
struct ColumnBrowserView: View {
    @Bindable var store: ZuneStore
    /// Asks to delete (after confirmation) or save what was picked. Disabled while busy.
    var onDelete: (Selection) -> Void = { _ in }
    var onSave: (Selection) -> Void = { _ in }

    /// The "All" rows. List selection can't use nil for a row, so these stand in for it.
    private static let allArtists = "\u{0}all"
    private static let allAlbums = AlbumKey(name: "\u{0}all", albumArtist: "")

    var body: some View {
        let index = store.index
        let query = store.searchText
        let artists = index?.artists(matching: query) ?? []
        let albums = index?.albums(artist: store.selectedArtist, matching: query) ?? []
        let songRows = index.map {
            SongRow.rows(index: $0, artist: store.selectedArtist, album: store.selectedAlbum, matching: query)
        } ?? []

        HSplitView {
            List(selection: artistSelection) {
                Text("All (\(artists.count) Artists)").tag(Self.allArtists)
                ForEach(artists, id: \.self) { Text($0).tag($0) }
            }
            .contextMenu(forSelectionType: String.self) { names in
                if let name = names.first(where: { $0 != Self.allArtists }) { actions(.artist(name)) }
            }
            .onDeleteCommand { if let artist = store.selectedArtist { request(.artist(artist)) } }
            .frame(minWidth: 180, idealWidth: 220)

            List(selection: albumSelection) {
                Text("All (\(albums.count) Albums)").tag(Self.allAlbums)
                ForEach(albums) { album in
                    HStack(spacing: 8) {
                        AlbumArtThumbnail(store: store, albumObjectID: album.albumObjectID)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(album.id.name).lineLimit(1)
                            Text(album.id.albumArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(album.id)
                }
            }
            .contextMenu(forSelectionType: AlbumKey.self) { keys in
                if let key = keys.first(where: { $0 != Self.allAlbums }) { actions(.album(key)) }
            }
            .onDeleteCommand { if let album = store.selectedAlbum { request(.album(album)) } }
            .frame(minWidth: 220, idealWidth: 260)

            // One flat ForEach (headings are rows): nested Sections that change shape crashed
            // SwiftUI's macOS List.
            List(selection: $store.selectedItemIDs) {
                ForEach(songRows) { row in
                    switch row {
                    case .artistHeading(let artist):
                        Text(artist)
                            .font(.headline)
                            .padding(.top, 6)
                    case .albumHeading(let album, _):
                        Text(album.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    case .song(let song, let showTrack):
                        songRow(song, showTrack: showTrack)
                    }
                }
            }
            .contextMenu(forSelectionType: UInt32.self) { ids in
                if !ids.isEmpty { actions(.items(Self.inRowOrder(ids, songRows))) }
            }
            .onDeleteCommand {
                if !store.selectedItemIDs.isEmpty { request(.items(Self.inRowOrder(store.selectedItemIDs, songRows))) }
            }
            .frame(minWidth: 280, idealWidth: 360)
        }
    }

    @ViewBuilder
    private func actions(_ selection: Selection) -> some View {
        Button("Save to Mac…") { onSave(selection) }
        Button("Delete from Zune…", role: .destructive) { onDelete(selection) }
    }

    private func request(_ selection: Selection) {
        guard store.activity == nil else { return }
        onDelete(selection)
    }

    /// The selected songs in the order they're shown.
    static func inRowOrder(_ ids: Set<UInt32>, _ rows: [SongRow]) -> [UInt32] {
        rows.compactMap { row in
            if case .song(let song, _) = row, ids.contains(song.id) { song.id } else { nil }
        }
    }

    private func songRow(_ song: MediaItem, showTrack: Bool) -> some View {
        HStack {
            if showTrack {
                Text(song.trackNumber > 0 ? "\(song.trackNumber)." : "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            Text(song.title).lineLimit(1)
            Spacer()
            Text(Self.duration(song.durationMs))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .tag(song.id)
    }

    private var artistSelection: Binding<String?> {
        Binding(
            get: { store.selectedArtist ?? Self.allArtists },
            set: { value in
                let artist = value == Self.allArtists ? nil : value
                guard artist != store.selectedArtist else { return }
                store.selectedArtist = artist
                store.selectedAlbum = nil
                store.selectedItemIDs = []
            })
    }

    private var albumSelection: Binding<AlbumKey?> {
        Binding(
            get: { store.selectedAlbum ?? Self.allAlbums },
            set: { value in
                let album = value == Self.allAlbums ? nil : value
                guard album != store.selectedAlbum else { return }
                store.selectedAlbum = album
                store.selectedItemIDs = []
            })
    }

    static func duration(_ ms: Int) -> String {
        let seconds = ms / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
