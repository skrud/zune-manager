import Foundation
import Testing
import ZuneTestSupport
@testable import ZuneKit

@MainActor @Suite struct ZuneStoreAddTests {
    let dir: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ZuneStoreAddTests-\(UUID())")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Writes "Tears" (track 5, with cover art) and "Lessons" (track 4, no art) by Rush on 2112.
    @discardableResult
    func writeSongs(artOnFirst: Bool = true) throws -> [URL] {
        let tears = dir.appendingPathComponent("05 Tears.mp3")
        let lessons = dir.appendingPathComponent("06 Lessons.mp3")
        try MP3Fixture.write(to: tears, title: "Tears", artist: "Rush", album: "2112", track: "5",
                             artworkJPEG: artOnFirst ? ImageFixture.jpeg(width: 300, height: 300) : nil)
        try MP3Fixture.write(to: lessons, title: "Lessons", artist: "Rush", album: "2112", track: "4")
        return [tears, lessons]
    }

    func connected(_ fake: FakeZuneDevice) async -> ZuneStore {
        let store = ZuneStore(makeClient: { fake })
        await store.deviceAttached()
        return store
    }

    /// Adds everything in `dir`. Choices are keyed by the duplicates' own ids, as the app does.
    func addAll(_ store: ZuneStore, overwrite: Bool = false) async throws -> AddPlan {
        let prep = await store.prepareAdd([dir])
        let choices = Dictionary(uniqueKeysWithValues: prep.duplicates.map {
            ($0.id, overwrite ? DuplicateChoice.overwrite : .skip)
        })
        let plan = try store.planAdd(prep, choices: choices)
        await store.add(plan, preparation: prep)
        return plan
    }

    @Test func addCreatesAlbumWithArtThenReusesIt() async throws {
        try writeSongs()
        let fake = FakeZuneDevice(TestData.snapshot([]))
        let store = await connected(fake)
        _ = try await addAll(store)
        #expect(await fake.calls == ["connect", "send Tears", "exists 11", "createAlbum 2112", "setArt 101",
                                     "send Lessons", "exists 12", "updateAlbum 101", "storage"])
        #expect(await fake.updatedAlbums.last?.itemIDs == [11, 12])
        #expect(store.lastSummary?.succeeded == ["Tears", "Lessons"])
        #expect(store.index?.albums(artist: "Rush", matching: "").first?.albumObjectID == 101)
        #expect(store.index?.items(artist: "Rush", album: nil, matching: "").map(\.title) == ["Lessons", "Tears"])
        #expect(store.activity == nil)
    }

    @Test func addAppendsToExistingAlbumObject() async throws {
        try writeSongs()
        try FileManager.default.removeItem(at: dir.appendingPathComponent("05 Tears.mp3"))
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(1, "2112"), TestData.item(2, "Overture")],
                                                    albums: [AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1, 2])]))
        let store = await connected(fake)
        _ = try await addAll(store)
        #expect(await fake.updatedAlbums.last == AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1, 2, 11]))
        #expect(await !fake.calls.contains { $0.hasPrefix("createAlbum") })
    }

    @Test func addUsesCoverJpgWhenNoEmbeddedArt() async throws {
        try writeSongs(artOnFirst: false)
        try ImageFixture.jpeg(width: 500, height: 500).write(to: dir.appendingPathComponent("cover.jpg"))
        let fake = FakeZuneDevice(TestData.snapshot([]))
        let store = await connected(fake)
        _ = try await addAll(store)
        #expect(await fake.calls.contains("setArt 101"))
        let art = try #require(await fake.art[101])
        #expect(art.starts(with: [0xFF, 0xD8]))
    }

    @Test func duplicateSkippedByDefault() async throws {
        try writeSongs()
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(5, "Tears")]))
        let store = await connected(fake)
        let prep = await store.prepareAdd([dir])
        #expect(prep.duplicates.map(\.existing.id) == [5])
        let plan = try store.planAdd(prep, choices: [:])
        await store.add(plan, preparation: prep)
        #expect(await !fake.calls.contains("send Tears"))
        #expect(store.lastSummary?.skipped == ["Tears (already on the Zune)"])
        #expect(store.lastSummary?.succeeded == ["Lessons"])
    }

    @Test func overwriteUploadsBeforeDeleting() async throws {
        try writeSongs()
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(5, "Tears")]))
        let store = await connected(fake)
        let plan = try await addAll(store, overwrite: true)
        #expect(plan.overwriteMode == .uploadThenDelete)
        let calls = await fake.calls
        let send = try #require(calls.firstIndex(of: "send Tears"))
        let delete = try #require(calls.firstIndex(of: "delete 5"))
        #expect(send < delete)
        #expect(calls[delete + 1] == "exists 5")
        #expect(store.index?.item(5) == nil)
        #expect(store.lastSummary?.succeeded == ["Tears", "Lessons"])
    }

    @Test func overwriteRemovesAnAlbumEntryLeftEmpty() async throws {
        try writeSongs()
        // The old "Tears" sits alone in an album entry under a different album artist, so the
        // new copy joins a new entry and the old one would be left empty.
        let fake = FakeZuneDevice(TestData.snapshot(
            [TestData.item(5, "Tears")],
            albums: [AlbumObject(id: 100, name: "2112", artist: "Rush (Remastered)", itemIDs: [5])]))
        let store = await connected(fake)
        _ = try await addAll(store, overwrite: true)
        let calls = await fake.calls
        #expect(calls.contains("delete 100"))
        #expect(await fake.albums[100] == nil)
        #expect(store.snapshot?.albums.contains { $0.id == 100 } == false)
        #expect(store.lastSummary?.failed.isEmpty == true)
    }

    @Test func overwriteDeletesFirstWhenTight() async throws {
        try writeSongs()
        // Room for the margin but not for both songs; deleting the 1 MB old copy makes room.
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(5, "Tears", size: 1_000_000)],
                                                    free: AddPlanner.spaceMarginBytes + 10_000))
        let store = await connected(fake)
        let plan = try await addAll(store, overwrite: true)
        #expect(plan.overwriteMode == .deleteThenUpload)
        let calls = await fake.calls
        #expect(try #require(calls.firstIndex(of: "delete 5")) < (try #require(calls.firstIndex(of: "send Tears"))))
    }

    @Test func addRefusesBeforeSendingWhenNoSpace() async throws {
        try writeSongs()
        let fake = FakeZuneDevice(TestData.snapshot([], free: 1_000))
        let store = await connected(fake)
        let prep = await store.prepareAdd([dir])
        #expect(throws: AddPlanError.self) { try store.planAdd(prep, choices: [:]) }
        #expect(await !fake.calls.contains { $0.hasPrefix("send") })
    }

    @Test func failedSendContinuesWithNext() async throws {
        try writeSongs()
        let fake = FakeZuneDevice(TestData.snapshot([]))
        await fake.configure { $0.failSendFor = ["Tears"] }
        let store = await connected(fake)
        _ = try await addAll(store)
        #expect(store.lastSummary?.reason(for: "Tears") == "device said no")
        #expect(store.lastSummary?.succeeded == ["Lessons"])
        #expect(await fake.calls.contains("send Lessons"))
    }

    @Test func failuresWithTheSameTitleAreAllReported() async throws {
        for album in ["2112", "Moving Pictures"] {
            try MP3Fixture.write(to: dir.appendingPathComponent("Intro \(album).mp3"), title: "Intro",
                                 artist: "Rush", album: album)
        }
        let fake = FakeZuneDevice(TestData.snapshot([]))
        await fake.configure { $0.failSendFor = ["Intro"] }
        let store = await connected(fake)
        _ = try await addAll(store)
        #expect(store.lastSummary?.failed.count == 2)
        #expect(store.lastSummary?.headline.contains("2 failed") == true)
    }

    @Test func nonMP3FilesReportedAsSkipped() async throws {
        try writeSongs()
        try Data("hi".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let store = await connected(FakeZuneDevice(TestData.snapshot([])))
        _ = try await addAll(store)
        #expect(store.lastSummary?.skipped == ["notes.txt (not an MP3)"])
    }

    @Test func sameSongTwiceInBatchReported() async throws {
        try writeSongs()
        let sub = dir.appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: dir.appendingPathComponent("06 Lessons.mp3"),
                                         to: sub.appendingPathComponent("06 Lessons.mp3"))
        let fake = FakeZuneDevice(TestData.snapshot([]))
        let store = await connected(fake)
        _ = try await addAll(store)
        #expect(await fake.calls.filter { $0 == "send Lessons" }.count == 1)
        #expect(store.lastSummary?.skipped == ["Lessons (picked twice)"])
    }
}
