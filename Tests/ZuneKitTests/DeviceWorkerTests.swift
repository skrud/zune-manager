import Foundation
import Testing
@testable import ZuneKit

@Suite struct DeviceWorkerTests {
    let worker = DeviceWorker(label: "test")

    @Test func returnsValue() async throws {
        #expect(try await worker.run("x", timeout: .seconds(1)) { 42 } == 42)
    }

    @Test func propagatesError() async {
        await #expect(throws: ZuneError.libmtp(operation: "x", message: "m")) {
            try await worker.run("x", timeout: .seconds(1)) { () throws -> Int in
                throw ZuneError.libmtp(operation: "x", message: "m")
            }
        }
        #expect(!worker.isStuck)
    }

    @Test func timesOutAndBecomesStuck() async {
        await #expect(throws: ZuneError.deviceNotResponding(operation: "slow")) {
            try await worker.run("slow", timeout: .milliseconds(100)) {
                Thread.sleep(forTimeInterval: 1)
                return 0
            }
        }
        #expect(worker.isStuck)
    }

    @Test func stuckWorkerRefusesWithoutRunning() async {
        _ = try? await worker.run("slow", timeout: .milliseconds(50)) { Thread.sleep(forTimeInterval: 1) }
        let ran = Locked(false)
        await #expect(throws: ZuneError.deviceNotResponding(operation: "next")) {
            try await worker.run("next", timeout: .seconds(1)) { ran.withLock { $0 = true } }
        }
        #expect(!ran.withLock { $0 })
    }

    @Test func queuedCallsFailWhenStuck() async {
        // The second call is waiting behind the hung one; it must fail too, not wait forever.
        let worker = self.worker
        let first = Task { try await worker.run("slow", timeout: .milliseconds(100)) { Thread.sleep(forTimeInterval: 2) } }
        try? await Task.sleep(for: .milliseconds(20))
        let second = Task { try await worker.run("queued", timeout: .seconds(5)) { 1 } }
        await #expect(throws: ZuneError.deviceNotResponding(operation: "slow")) { try await first.value }
        await #expect(throws: ZuneError.deviceNotResponding(operation: "queued")) { try await second.value }
    }

    @Test func runsOneAtATime() async throws {
        let inside = Locked(0)
        let maxInside = Locked(0)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await worker.run("op", timeout: .seconds(5)) {
                        let now = inside.withLock { $0 += 1; return $0 }
                        maxInside.withLock { $0 = max($0, now) }
                        Thread.sleep(forTimeInterval: 0.01)
                        inside.withLock { $0 -= 1 }
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(maxInside.withLock { $0 } == 1)
    }
}
