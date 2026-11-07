import Foundation

/// What the user picked to add, read and checked against the Zune, before anything is copied.
public struct AddPreparation: Hashable, Sendable {
    public var songs: [LocalSong]
    public var duplicates: [Duplicate]
    public var nonMP3: [URL]
    /// File → why its tags couldn't be read.
    public var unreadable: [URL: String]
}

extension ZuneStore {
    public func prepareAdd(_ urls: [URL]) async -> AddPreparation {
        let scan = FileScanner.scan(urls)
        var songs: [LocalSong] = []
        var unreadable: [URL: String] = [:]
        for url in scan.mp3s {
            do {
                songs.append(try await TagReader.read(url))
            } catch {
                unreadable[url] = error.localizedDescription
            }
        }
        return AddPreparation(songs: songs,
                              duplicates: Duplicates.find(incoming: songs, existing: snapshot?.items ?? []),
                              nonMP3: scan.skipped, unreadable: unreadable)
    }

    public func planAdd(_ preparation: AddPreparation, choices: [URL: DuplicateChoice]) throws -> AddPlan {
        try AddPlanner.plan(songs: preparation.songs, duplicates: preparation.duplicates, choices: choices,
                            freeBytes: snapshot?.storage.freeBytes ?? 0)
    }

    public func add(_ plan: AddPlan, preparation: AddPreparation) async {
        guard let client else { return }
        var artFailures: [String: String] = [:]

        guard let run = await perform("Add to Zune", plan.steps, name: \.song.title, { step in
            let song = step.song
            if plan.overwriteMode == .deleteThenUpload, let old = step.replacing {
                guard try await self.removeOldCopy(old, client: client) else {
                    return .failed("Couldn't remove the copy already on the Zune, so this wasn't copied.")
                }
            }

            let item = try await client.sendSong(song) { p in Task { @MainActor in self.report(p) } }
            guard try await client.objectExists(item.id) else { return .failed("The Zune didn't confirm the copy.") }
            self.addItem(item)

            do {
                switch AddPlanner.albumTarget(for: song, albums: self.snapshot?.albums ?? []) {
                case .existing(var album):
                    album.itemIDs.append(item.id)
                    try await client.updateAlbum(album)
                    self.storeAlbum(album)
                case .create(let name, let artist):
                    let album = try await client.createAlbum(name: name, artist: artist, itemIDs: [item.id])
                    self.storeAlbum(album)
                    if let art = Self.albumArt(for: song) {
                        do {
                            try await client.setAlbumArt(albumID: album.id, art: art)
                        } catch {
                            if Self.isStuck(error) { throw error }
                            artFailures["\(name) (art)"] = Self.message(error)
                        }
                    }
                }
            } catch {
                if Self.isStuck(error) { throw error }
                return .failed("Copied, but couldn't add it to its album: \(Self.message(error))")
            }

            if plan.overwriteMode == .uploadThenDelete, let old = step.replacing {
                guard try await self.removeOldCopy(old, client: client) else {
                    return .failed("Copied, but the old copy couldn't be removed.")
                }
            }
            return .succeeded
        }) else { return }

        var summary = run.summary
        summary.skipped = plan.skippedDuplicates.map { "\($0.title) (already on the Zune)" }
            + plan.skippedInBatch.map { "\($0.title) (picked twice)" }
            + preparation.nonMP3.map { "\($0.lastPathComponent) (not an MP3)" }
            + preparation.unreadable.keys.sorted { $0.path < $1.path }.map {
                "\($0.lastPathComponent) (couldn't read it: \(preparation.unreadable[$0]!))"
            }
            + summary.skipped
        summary.failed.merge(artFailures) { first, _ in first }
        await finish(summary, generation: run.generation, refreshStorage: true)
    }

    /// Deletes an existing copy and confirms it's gone. Returns false if the Zune still has it.
    private func removeOldCopy(_ old: MediaItem, client: any ZuneDeviceClient) async throws -> Bool {
        try await client.delete(old.id)
        guard try await !client.objectExists(old.id) else { return false }
        removeItem(old.id)
        return true
    }

    /// The song's embedded cover, else cover.jpg / folder.jpg next to it, ready for the Zune.
    static func albumArt(for song: LocalSong) -> AlbumArt? {
        let data = song.embeddedArtwork
            ?? FileScanner.coverImage(forSongAt: song.url).flatMap { try? Data(contentsOf: $0) }
        return data.flatMap(Artwork.zuneAlbumArt(from:))
    }
}
