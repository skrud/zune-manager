import Foundation
import Observation

/// The app's state: the connection, what's on the Zune, the browser's selection, and the
/// add / delete / save operations (one at a time).
@MainActor @Observable
public final class ZuneStore {
    public enum Phase: Equatable, Sendable {
        case waitingForDevice
        case connecting
        case ready
        /// A libmtp call never returned; the app has to be quit (see `stuckMessage`).
        case stuck
        case failed(String)
    }

    public static let stuckMessage = "Your Zune stopped responding. Quit Zune Manager, soft-reset the Zune (hold Back + Up until it restarts), then reopen the app. If a Chromium-based browser like Helium is open, close it first — it can interfere with the Zune."

    static let unpluggedMessage = "The Zune was unplugged before this could be confirmed."

    /// The loading bar while connecting.
    public struct ConnectStatus: Equatable, Sendable {
        public var fraction: Double
        public var label: String
    }

    public private(set) var phase: Phase = .waitingForDevice
    public private(set) var connectStatus: ConnectStatus?
    public private(set) var snapshot: DeviceSnapshot?
    public private(set) var index: LibraryIndex?
    public var selectedArtist: String?
    public var selectedAlbum: AlbumKey?
    public var selectedItemIDs: Set<UInt32> = []
    public var searchText = ""
    public private(set) var activity: Activity?
    public private(set) var lastSummary: OperationSummary?

    @ObservationIgnored private let makeClient: @Sendable () -> any ZuneDeviceClient
    @ObservationIgnored var client: (any ZuneDeviceClient)?
    @ObservationIgnored private var artCache: [UInt32: Data?] = [:]
    /// Bumped on every connect and detach, so late results from an old connection are dropped.
    @ObservationIgnored var generation = 0

    public init(makeClient: @escaping @Sendable () -> any ZuneDeviceClient) {
        self.makeClient = makeClient
    }

    // MARK: - Connection

    public func deviceAttached() async {
        switch phase {
        case .waitingForDevice, .failed: await connect()
        default: return
        }
    }

    public func reconnect() async {
        guard phase != .stuck, activity == nil else { return }
        if let client { await client.disconnect() }
        client = nil
        await connect()
    }

    public func deviceDetached() {
        generation += 1
        let old = client
        client = nil
        snapshot = nil
        index = nil
        artCache = [:]
        selectedArtist = nil
        selectedAlbum = nil
        selectedItemIDs = []
        // The running operation (if any) stops at its next step and still reports.
        activity = nil
        if phase != .stuck { phase = .waitingForDevice }
        Task { await old?.disconnect() }
    }

    /// Gets ready to quit without leaving the Zune wedged: a running add, delete or save stops
    /// after its current file, a connect in progress is allowed to finish (both are bounded by
    /// the device layer's time limits), then the MTP session is closed so the Zune leaves its
    /// "syncing" screen. When the Zune is stuck there's nothing to wait for or close.
    public func prepareToQuit() async {
        if activity != nil { cancelAfterCurrentFile() }
        while phase != .stuck, activity != nil || phase == .connecting {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard phase != .stuck, let client else { return }
        self.client = nil
        await client.disconnect()
    }

    private func connect() async {
        generation += 1
        let gen = generation
        phase = .connecting
        let c = makeClient()
        client = c
        do {
            let snap = try await c.connect { progress in
                Task { @MainActor in
                    guard gen == self.generation, self.phase == .connecting else { return }
                    self.connectStatus = ConnectStatus(fraction: Self.connectFraction(progress),
                                                       label: Self.connectLabel(progress))
                }
            }
            guard gen == generation else { return }
            connectStatus = nil
            snapshot = snap
            artCache = [:]
            rebuildIndex()
            phase = .ready
        } catch {
            guard gen == generation else { return }
            connectStatus = nil
            phase = Self.isStuck(error) ? .stuck : .failed(Self.message(error))
        }
    }

    // MARK: - Delete

    public func deletePlan(for selection: Selection) -> DeletePlan? {
        guard let index, let snapshot else { return nil }
        let plan = DeletePlanner.plan(selection, index: index, albums: snapshot.albums)
        return plan.itemIDs.isEmpty ? nil : plan
    }

    public func delete(_ plan: DeletePlan) async {
        guard let index, let client else { return }
        let items = plan.itemIDs.compactMap { index.item($0) }
        guard let run = await perform("Delete from Zune", items, name: \.title, { item in
            try await client.delete(item.id)
            guard try await !client.objectExists(item.id) else { return .failed("Still on the Zune after deleting.") }
            self.removeItem(item.id)
            return .succeeded
        }) else { return }
        var summary = run.summary

        // Also after a cancel: albums whose songs are all gone shouldn't linger (the check
        // below skips any album that still has songs). Not after an unplug or a stuck Zune.
        if run.generation == generation, phase == .ready {
            for albumID in plan.albumObjectsToDelete {
                guard let album = snapshot?.albums.first(where: { $0.id == albumID }),
                      album.itemIDs.allSatisfy({ id in snapshot?.items.contains { $0.id == id } != true })
                else { continue }
                do {
                    try await client.delete(albumID)
                    if try await client.objectExists(albumID) {
                        summary.failed.append(.init(name: "\(album.name) (album)", reason: "Still on the Zune after deleting."))
                    } else {
                        removeAlbum(albumID)
                    }
                } catch {
                    guard run.generation == generation else { break }
                    if Self.isStuck(error) {
                        phase = .stuck
                        break
                    }
                    summary.failed.append(.init(name: "\(album.name) (album)", reason: Self.message(error)))
                }
            }
        }
        await finish(summary, generation: run.generation, refreshStorage: true)
    }

    // MARK: - Save to Mac

    public func export(_ selection: Selection, to folder: URL) async {
        guard let index, let client else { return }
        let items = index.resolve(selection)
        guard let run = await perform("Save to Mac", items, name: \.title, { item in
            let fm = FileManager.default
            let destination = folder.appendingPathComponent(ExportNaming.relativePath(for: item))
            if fm.fileExists(atPath: destination.path) { return .skipped("\(item.title) (already on the Mac)") }
            let directory = destination.deletingLastPathComponent()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let partial = directory.appendingPathComponent(".\(UUID().uuidString).part")
            defer { try? fm.removeItem(at: partial) }
            try await client.download(item.id, to: partial) { p in
                Task { @MainActor in self.report(p) }
            }
            let size = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.uint64Value
            guard size == item.fileSize else { return .failed("The copy was incomplete.") }
            try fm.moveItem(at: partial, to: destination)
            return .succeeded
        }) else { return }
        await finish(run.summary, generation: run.generation, refreshStorage: false)
    }

    // MARK: - Album art, cancel, summary

    public func albumArt(albumObjectID: UInt32) async -> Data? {
        if let cached = artCache[albumObjectID] { return cached }
        guard let client, phase == .ready else { return nil }
        let gen = generation
        do {
            let data = try await client.albumArt(albumID: albumObjectID)
            if gen == generation { artCache[albumObjectID] = .some(data) }
            return data
        } catch {
            guard gen == generation else { return nil }
            if Self.isStuck(error) { phase = .stuck } else { artCache[albumObjectID] = .some(nil) }
            return nil
        }
    }

    public func cancelAfterCurrentFile() {
        activity?.cancelRequested = true
    }

    public func dismissSummary() {
        lastSummary = nil
    }

    // MARK: - Running operations

    enum StepResult {
        case succeeded
        case skipped(String)
        case failed(String)
    }

    struct Run {
        var summary: OperationSummary
        /// Every element was attempted (not cancelled, unplugged or stuck).
        var completed: Bool
        var generation: Int
    }

    /// Runs `step` for each element, one at a time, recording the outcome of each. Stops
    /// early on cancel, unplug or a stuck device. Returns nil when another operation is
    /// running or the Zune isn't ready.
    func perform<Element: Sendable>(_ title: String, _ elements: [Element], name: (Element) -> String,
                          _ step: (Element) async throws -> StepResult) async -> Run? {
        guard activity == nil, phase == .ready else { return nil }
        let gen = generation
        var summary = OperationSummary(title: title)
        activity = Activity(title: title, fileIndex: 0, fileCount: elements.count, fraction: 0,
                            cancelRequested: false)
        let names = elements.map(name)
        for (i, element) in elements.enumerated() {
            if gen != generation || activity?.cancelRequested == true || phase != .ready {
                summary.notDone += names[i...]
                return Run(summary: summary, completed: false, generation: gen)
            }
            activity?.fileIndex = i + 1
            activity?.fraction = 0
            do {
                let result = try await step(element)
                if gen != generation {
                    summary.failed.append(.init(name: names[i], reason: Self.unpluggedMessage))
                    summary.notDone += names[(i + 1)...]
                    return Run(summary: summary, completed: false, generation: gen)
                }
                switch result {
                case .succeeded: summary.succeeded.append(names[i])
                case .skipped(let reason): summary.skipped.append(reason)
                case .failed(let reason): summary.failed.append(.init(name: names[i], reason: reason))
                }
            } catch {
                // A late error from a Zune that's since been unplugged says nothing about the
                // current connection, so check that first.
                if gen != generation {
                    summary.failed.append(.init(name: names[i], reason: Self.unpluggedMessage))
                    summary.notDone += names[(i + 1)...]
                    return Run(summary: summary, completed: false, generation: gen)
                }
                if Self.isStuck(error) {
                    phase = .stuck
                    summary.notDone += names[i...]
                    return Run(summary: summary, completed: false, generation: gen)
                }
                summary.failed.append(.init(name: names[i], reason: Self.message(error)))
            }
        }
        return Run(summary: summary, completed: true, generation: gen)
    }

    /// Publishes the summary, and — if still connected — refreshes free space and the index.
    func finish(_ summary: OperationSummary, generation gen: Int, refreshStorage: Bool) async {
        if gen == generation, phase == .ready, let client {
            if refreshStorage {
                do {
                    let storage = try await client.refreshStorage()
                    if gen == generation { snapshot?.storage = storage }
                } catch {
                    if Self.isStuck(error), gen == generation { phase = .stuck }
                }
            }
            rebuildIndex()
        }
        lastSummary = summary
        // After an unplug the bar was already cleared, and a new connection's operation owns it.
        if gen == generation { activity = nil }
    }

    func report(_ progress: TransferProgress) {
        activity?.fraction = progress.total > 0 ? Double(progress.sent) / Double(progress.total) : 0
    }

    func removeItem(_ id: UInt32) {
        snapshot?.items.removeAll { $0.id == id }
        if let albums = snapshot?.albums {
            snapshot?.albums = albums.map { album in
                var a = album
                a.itemIDs.removeAll { $0 == id }
                return a
            }
        }
    }

    func removeAlbum(_ id: UInt32) {
        snapshot?.albums.removeAll { $0.id == id }
    }

    func addItem(_ item: MediaItem) {
        snapshot?.items.append(item)
    }

    /// Adds the album object, or replaces the one with the same id.
    func storeAlbum(_ album: AlbumObject) {
        if let i = snapshot?.albums.firstIndex(where: { $0.id == album.id }) {
            snapshot?.albums[i] = album
        } else {
            snapshot?.albums.append(album)
        }
    }

    func rebuildIndex() {
        index = snapshot.map(LibraryIndex.init(snapshot:))
    }

    /// Where the loading bar sits. Stages are weighted by how long they took on a Zune 30 with
    /// ~3,900 objects: objects 34 s, song details 28 s, album list 11 s.
    static func connectFraction(_ p: ConnectProgress) -> Double {
        let (start, width): (Double, Double) = switch p.stage {
        case .readingObjects: (0, 0.47)
        case .readingSongs: (0.47, 0.38)
        case .readingAlbums: (0.85, 0)
        }
        guard p.total > 0 else { return start }
        return start + width * min(1, Double(p.done) / Double(p.total))
    }

    static func connectLabel(_ p: ConnectProgress) -> String {
        switch p.stage {
        case .readingObjects:
            p.total > 0 ? "Reading your Zune… (\(p.done.formatted()) of \(p.total.formatted()) items)" : "Reading your Zune…"
        case .readingSongs: "Reading song details…"
        case .readingAlbums: "Reading albums…"
        }
    }

    static func isStuck(_ error: Error) -> Bool {
        if case ZuneError.deviceNotResponding = error { return true }
        return false
    }

    static func message(_ error: Error) -> String {
        switch error {
        case ZuneError.noDevice: "No Zune is connected."
        case ZuneError.libmtp(_, let message): message
        case ZuneError.verificationFailed: "The Zune didn't confirm the change."
        case ZuneError.deviceNotResponding: stuckMessage
        default: error.localizedDescription
        }
    }
}
