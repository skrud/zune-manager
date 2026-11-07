/// What happened during an add, delete or save, shown to the user when it finishes.
public struct OperationSummary: Hashable, Sendable {
    public struct Failure: Hashable, Sendable {
        public var name: String
        public var reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public var title: String
    public var succeeded: [String] = []
    /// Names with the reason in parentheses, e.g. "notes.txt (not an MP3)".
    public var skipped: [String] = []
    /// What failed and why, in the order it happened (names can repeat, e.g. two "Intro"s).
    public var failed: [Failure] = []
    /// Not attempted: cancelled, unplugged or the Zune stopped responding.
    public var notDone: [String] = []

    public init(title: String) {
        self.title = title
    }

    /// "3 done, 1 skipped, 1 failed, 2 not done" — only the parts that happened.
    public var headline: String {
        var parts = ["\(succeeded.count) done"]
        if !skipped.isEmpty { parts.append("\(skipped.count) skipped") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        if !notDone.isEmpty { parts.append("\(notDone.count) not done") }
        return parts.joined(separator: ", ")
    }

    /// The reason the first failure with this name failed.
    public func reason(for name: String) -> String? {
        failed.first { $0.name == name }?.reason
    }

    /// Something failed or was left undone, so the result shouldn't disappear by itself.
    public var needsAttention: Bool {
        !failed.isEmpty || !notDone.isEmpty
    }
}

/// The operation in progress, for the progress bar.
public struct Activity: Hashable, Sendable {
    public var title: String
    /// 1-based index of the file being worked on.
    public var fileIndex: Int
    public var fileCount: Int
    /// Progress of the current file, 0...1.
    public var fraction: Double
    public var cancelRequested: Bool
}
