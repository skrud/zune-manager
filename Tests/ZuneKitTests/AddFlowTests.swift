import Foundation
import Testing
import ZuneTestSupport
@testable import ZuneKit

@MainActor @Suite struct AddFlowTests {
    let dir: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AddFlowTests-\(UUID())")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try! MP3Fixture.write(to: url.appendingPathComponent("05 Tears.mp3"), title: "Tears", artist: "Rush",
                              album: "2112", track: "5")
        return url
    }()

    func flow(_ fake: FakeZuneDevice) async -> (AddFlow, ZuneStore) {
        let store = ZuneStore(makeClient: { fake })
        await store.deviceAttached()
        return (AddFlow(store: store), store)
    }

    @Test func noDuplicatesAddsStraightAway() async {
        let fake = FakeZuneDevice(TestData.snapshot([]))
        let (flow, store) = await flow(fake)
        await flow.start([dir])
        #expect(flow.step == nil)
        #expect(store.lastSummary?.succeeded == ["Tears"])
    }

    @Test func duplicatesWaitForAChoice() async throws {
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(5, "Tears")]))
        let (flow, _) = await flow(fake)
        await flow.start([dir])
        guard case .duplicates(let prep)? = flow.step else {
            Issue.record("expected duplicates step, got \(String(describing: flow.step))")
            return
        }
        #expect(prep.duplicates.map(\.existing.id) == [5])
        #expect(await !fake.calls.contains { $0.hasPrefix("send") })

        await flow.resolveDuplicates(prep, choices: [prep.duplicates[0].id: .overwrite])
        #expect(flow.step == nil)
        #expect(await fake.calls.contains("send Tears"))
        #expect(await fake.calls.contains("delete 5"))
    }

    @Test func tightSpaceAsksBeforeDeletingFirst() async throws {
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(5, "Tears", size: 1_000_000)],
                                                    free: AddPlanner.spaceMarginBytes + 1_000))
        let (flow, _) = await flow(fake)
        await flow.start([dir])
        guard case .duplicates(let prep)? = flow.step else { Issue.record("no duplicates step"); return }
        await flow.resolveDuplicates(prep, choices: [prep.duplicates[0].id: .overwrite])
        guard case .confirmDeleteFirst(_, let plan, let message)? = flow.step else {
            Issue.record("expected confirmDeleteFirst, got \(String(describing: flow.step))")
            return
        }
        #expect(plan.overwriteMode == .deleteThenUpload)
        #expect(message == "There isn't enough free space to copy the new versions first. Zune Manager will delete the existing copies of 1 song before copying the new ones. If a copy fails, those songs will be missing from your Zune.")
        #expect(await !fake.calls.contains { $0.hasPrefix("delete") })

        await flow.confirmDeleteFirst()
        #expect(flow.step == nil)
        #expect(await fake.calls.contains("delete 5"))
    }

    @Test func notEnoughSpaceIsExplained() async {
        let fake = FakeZuneDevice(TestData.snapshot([], free: 1_000))
        let (flow, _) = await flow(fake)
        await flow.start([dir])
        guard case .error(let message)? = flow.step else {
            Issue.record("expected error, got \(String(describing: flow.step))")
            return
        }
        #expect(message.hasPrefix("Not enough space on your Zune: needs "))
        #expect(message.hasSuffix(", 1 KB free."))
        #expect(await !fake.calls.contains { $0.hasPrefix("send") })
    }

    @Test func cancelDropsTheFlow() async {
        let fake = FakeZuneDevice(TestData.snapshot([TestData.item(5, "Tears")]))
        let (flow, _) = await flow(fake)
        await flow.start([dir])
        flow.cancel()
        #expect(flow.step == nil)
        #expect(await !fake.calls.contains { $0.hasPrefix("send") })
    }
}
