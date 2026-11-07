import Foundation
import Testing
@testable import ZuneKit

@MainActor @Suite struct ZuneStoreTests {
    let album2112 = AlbumKey(name: "2112", albumArtist: "Rush")

    func makeStore(_ fake: FakeZuneDevice) -> ZuneStore {
        ZuneStore(makeClient: { fake })
    }

    /// Rush/2112 with items 1 and 2 (album object 100), plus 5 on Moving Pictures (no album object).
    func rushFake() -> FakeZuneDevice {
        FakeZuneDevice(TestData.snapshot(
            [TestData.item(1, "2112", track: 1, size: 3_000), TestData.item(2, "A Passage to Bangkok", track: 2, size: 4_000),
             TestData.item(5, "Tom Sawyer", album: "Moving Pictures", track: 1, size: 5_000)],
            albums: [AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1, 2])]))
    }

    func connected(_ fake: FakeZuneDevice) async -> ZuneStore {
        let store = makeStore(fake)
        await store.deviceAttached()
        return store
    }

    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ZuneStoreTests-\(UUID())")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func connectPopulatesIndex() async {
        let store = await connected(rushFake())
        #expect(store.phase == .ready)
        #expect(store.index?.artists(matching: "") == ["Rush"])
        #expect(store.snapshot?.deviceName == "Skrud's Zune")
    }

    @Test func connectTimeoutIsStuck() async {
        let fake = rushFake()
        await fake.configure { $0.stuckOn = ["connect"] }
        let store = await connected(fake)
        #expect(store.phase == .stuck)
        #expect(ZuneStore.stuckMessage.hasPrefix("Your Zune stopped responding. Quit Zune Manager, soft-reset the Zune"))
    }

    @Test func connectErrorIsFailed() async {
        let fake = rushFake()
        await fake.configure { $0.connectError = .libmtp(operation: "connect", message: "Could not open the Zune.") }
        let store = await connected(fake)
        guard case .failed(let message) = store.phase else {
            Issue.record("expected .failed, got \(store.phase)")
            return
        }
        #expect(message.contains("Could not open the Zune."))
    }

    @Test func reconnectAfterFailure() async {
        let fake = rushFake()
        await fake.configure { $0.connectError = .noDevice }
        let store = await connected(fake)
        await fake.configure { $0.connectError = nil }
        await store.reconnect()
        #expect(store.phase == .ready)
    }

    @Test func deleteAlbumDeletesTracksThenAlbum() async throws {
        let fake = rushFake()
        let store = await connected(fake)
        let plan = try #require(store.deletePlan(for: .album(album2112)))
        await store.delete(plan)
        #expect(await fake.calls == ["connect", "delete 1", "exists 1", "delete 2", "exists 2",
                                     "delete 100", "exists 100", "storage"])
        #expect(store.index?.item(1) == nil)
        #expect(store.index?.item(2) == nil)
        #expect(store.snapshot?.albums.isEmpty == true)
        #expect(store.lastSummary?.succeeded == ["2112", "A Passage to Bangkok"])
        #expect(store.activity == nil)
    }

    @Test func deleteSongRemovesItFromItsAlbumObject() async throws {
        let store = await connected(rushFake())
        await store.delete(try #require(store.deletePlan(for: .items([1]))))
        #expect(store.snapshot?.albums.first?.itemIDs == [2])
    }

    @Test func deleteVerificationFailureIsReported() async throws {
        let fake = rushFake()
        await fake.configure { $0.existsAfterDelete = true }
        let store = await connected(fake)
        await store.delete(try #require(store.deletePlan(for: .items([5]))))
        #expect(store.lastSummary?.failed["Tom Sawyer"] == "Still on the Zune after deleting.")
        #expect(store.lastSummary?.succeeded == [])
        #expect(store.index?.item(5) != nil)
    }

    @Test func detachDuringDeleteStopsAndReports() async throws {
        let fake = rushFake()
        let store = await connected(fake)
        await fake.configure { $0.onDelete = { _ in await MainActor.run { store.deviceDetached() } } }
        await store.delete(try #require(store.deletePlan(for: .album(album2112))))
        #expect(store.phase == .waitingForDevice)
        #expect(store.snapshot == nil)
        #expect(store.lastSummary?.failed["2112"] == "The Zune was unplugged before this could be confirmed.")
        #expect(store.lastSummary?.notDone == ["A Passage to Bangkok"])
        #expect(await !fake.calls.contains("delete 2"))
    }

    @Test func stuckDuringDeleteGoesStuck() async throws {
        let fake = rushFake()
        await fake.configure { $0.stuckOn = ["delete"] }
        let store = await connected(fake)
        await store.delete(try #require(store.deletePlan(for: .album(album2112))))
        #expect(store.phase == .stuck)
        #expect(store.lastSummary?.notDone == ["2112", "A Passage to Bangkok"])
    }

    @Test func exportWritesNamedFilesAndSkipsExisting() async throws {
        let fake = rushFake()
        let store = await connected(fake)
        let dir = tempDir()
        let existing = dir.appendingPathComponent("Rush/2112/02 A Passage to Bangkok.mp3")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: existing)
        await store.export(.album(album2112), to: dir)
        let written = dir.appendingPathComponent("Rush/2112/01 2112.mp3")
        #expect(try Data(contentsOf: written).count == 3_000)
        #expect(try Data(contentsOf: existing) == Data([1]))
        #expect(store.lastSummary?.succeeded == ["2112"])
        #expect(store.lastSummary?.skipped == ["A Passage to Bangkok (already on the Mac)"])
        #expect(await !fake.calls.contains("download 2"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: written.deletingLastPathComponent().path)
        #expect(leftovers.sorted() == ["01 2112.mp3", "02 A Passage to Bangkok.mp3"])
    }

    @Test func exportSizeMismatchFails() async throws {
        let fake = rushFake()
        await fake.configure { $0.downloadShortBy = 10 }
        let store = await connected(fake)
        let dir = tempDir()
        await store.export(.items([5]), to: dir)
        #expect(store.lastSummary?.failed["Tom Sawyer"] == "The copy was incomplete.")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Rush/Moving Pictures/01 Tom Sawyer.mp3").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Rush/Moving Pictures").path).isEmpty)
    }

    @Test func cancelStopsBetweenFiles() async throws {
        let fake = rushFake()
        let store = await connected(fake)
        await fake.configure { $0.onDownload = { _ in await MainActor.run { store.cancelAfterCurrentFile() } } }
        await store.export(.artist("Rush"), to: tempDir())
        #expect(store.lastSummary?.succeeded.count == 1)
        #expect(store.lastSummary?.notDone.count == 2)
        #expect(await fake.calls.filter { $0.hasPrefix("download") }.count == 1)
    }

    @Test func secondOperationIgnoredWhileBusy() async throws {
        let fake = rushFake()
        let store = await connected(fake)
        await fake.configure { $0.onDownload = { _ in try? await Task.sleep(for: .milliseconds(200)) } }
        let plan = try #require(store.deletePlan(for: .items([5])))
        let export = Task { await store.export(.items([1]), to: tempDir()) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.activity != nil)
        await store.delete(plan)
        await export.value
        #expect(await !fake.calls.contains { $0.hasPrefix("delete") })
    }

    @Test func albumArtIsCached() async {
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(1, "2112")],
                                                    albums: [AlbumObject(id: 100, name: "2112", artist: "Rush", itemIDs: [1])]),
                                  art: [100: Data([0xFF, 0xD8])])
        let store = await connected(fake)
        #expect(await store.albumArt(albumObjectID: 100) == Data([0xFF, 0xD8]))
        #expect(await store.albumArt(albumObjectID: 100) == Data([0xFF, 0xD8]))
        #expect(await store.albumArt(albumObjectID: 999) == nil)
        #expect(await store.albumArt(albumObjectID: 999) == nil)
        #expect(await fake.calls.filter { $0.hasPrefix("art") } == ["art 100", "art 999"])
    }

    @Test func connectProgressFillsTheBarInStages() {
        func f(_ stage: ConnectProgress.Stage, _ done: Int, _ total: Int) -> Double {
            ZuneStore.connectFraction(ConnectProgress(stage: stage, done: done, total: total))
        }
        #expect(f(.readingObjects, 0, 3886) == 0)
        #expect(abs(f(.readingObjects, 3886, 3886) - 0.47) < 1e-9)
        #expect(abs(f(.readingSongs, 1942, 3884) - 0.66) < 1e-9)
        #expect(abs(f(.readingAlbums, 0, 0) - 0.85) < 1e-9)
        // Unknown totals hold the stage's starting point instead of dividing by zero.
        #expect(f(.readingObjects, 500, 0) == 0)
        #expect(abs(f(.readingSongs, 10, 0) - 0.47) < 1e-9)
        // Never past the stage's end, even if libmtp counts more than it said.
        #expect(abs(f(.readingObjects, 4000, 3886) - 0.47) < 1e-9)
    }

    @Test func connectProgressShownWhileConnectingAndClearedAfter() async {
        let fake = rushFake()
        let store = makeStore(fake)
        let seen = Locked<[ZuneStore.ConnectStatus]>([])
        await fake.configure {
            $0.connectProgress = [ConnectProgress(stage: .readingObjects, done: 50, total: 100),
                                  ConnectProgress(stage: .readingAlbums, done: 0, total: 0)]
            $0.onConnect = {
                // Progress reaches the store via the main actor; let those updates land first.
                for _ in 0..<5 { await MainActor.run {} }
                await MainActor.run { if let s = store.connectStatus { seen.withLock { $0.append(s) } } }
            }
        }
        await store.deviceAttached()
        #expect(seen.withLock { $0 }.last == ZuneStore.ConnectStatus(fraction: 0.85, label: "Reading albums…"))
        #expect(store.connectStatus == nil)
    }

    @Test func prepareToQuitReleasesTheZune() async {
        let fake = rushFake()
        let store = await connected(fake)
        await store.prepareToQuit()
        #expect(await fake.calls.last == "disconnect")
    }

    @Test func prepareToQuitWhenStuckDoesNotWaitOnTheDevice() async {
        let fake = rushFake()
        await fake.configure { $0.stuckOn = ["connect"] }
        let store = await connected(fake)
        await store.prepareToQuit()
        #expect(await !fake.calls.contains("disconnect"))
    }

    @Test func detachClearsAndReattachReconnects() async {
        let fake = rushFake()
        let store = await connected(fake)
        store.deviceDetached()
        #expect(store.phase == .waitingForDevice)
        #expect(store.index == nil)
        await store.deviceAttached()
        #expect(store.phase == .ready)
    }
}
