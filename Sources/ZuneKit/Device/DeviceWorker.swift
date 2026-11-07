import Foundation

/// Runs libmtp calls one at a time on a dedicated serial queue, each with a time limit.
///
/// A libmtp call that doesn't return can't be cancelled. When one overruns, the worker
/// becomes stuck: that call and every call waiting behind it fail with
/// `.deviceNotResponding`, and so does every later call.
public final class DeviceWorker: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var stuck = false
    private var pending: [UUID: Waiter] = [:]

    /// Resumes its continuation exactly once.
    private final class Waiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<any Sendable, Error>?

        init(_ continuation: CheckedContinuation<any Sendable, Error>) { self.continuation = continuation }

        @discardableResult
        func resume(with result: Result<any Sendable, Error>) -> Bool {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(with: result)
            return c != nil
        }
    }

    public init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    public var isStuck: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stuck
    }

    public func run<T: Sendable>(_ operation: String, timeout: Duration,
                                 _ body: @escaping @Sendable () throws -> T) async throws -> T {
        let notResponding = ZuneError.deviceNotResponding(operation: operation)
        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<any Sendable, Error>) in
            let id = UUID()
            let waiter = Waiter(continuation)
            lock.lock()
            if stuck {
                lock.unlock()
                waiter.resume(with: .failure(notResponding))
                return
            }
            pending[id] = waiter
            lock.unlock()

            queue.async { [self] in
                guard !isStuck else {
                    finish(id, .failure(notResponding))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) { [self] in
                    if finish(id, .failure(notResponding)) { becomeStuck() }
                }
                finish(id, Result { try body() as any Sendable })
            }
        }
        return value as! T
    }

    @discardableResult
    private func finish(_ id: UUID, _ result: Result<any Sendable, Error>) -> Bool {
        lock.lock()
        let waiter = pending.removeValue(forKey: id)
        lock.unlock()
        return waiter?.resume(with: result) ?? false
    }

    private func becomeStuck() {
        lock.lock()
        stuck = true
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        for (_, waiter) in waiting {
            waiter.resume(with: .failure(ZuneError.deviceNotResponding(operation: "queued")))
        }
    }
}

private extension Duration {
    var timeInterval: DispatchTimeInterval {
        let (seconds, attoseconds) = components
        return .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000))
    }
}
