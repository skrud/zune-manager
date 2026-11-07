import Testing
@testable import ZuneKit

@Suite struct OperationSummaryTests {
    @Test func headlineListsOnlyWhatHappened() {
        var s = OperationSummary(title: "Add to Zune")
        s.succeeded = ["A", "B", "C"]
        #expect(s.headline == "3 done")
        s.skipped = ["D (already on the Zune)"]
        #expect(s.headline == "3 done, 1 skipped")
        s.failed = ["E": "device said no"]
        s.notDone = ["F", "G"]
        #expect(s.headline == "3 done, 1 skipped, 1 failed, 2 not done")
    }

    @Test func needsAttentionOnlyWhenSomethingWentWrong() {
        var s = OperationSummary(title: "Delete from Zune")
        s.succeeded = ["A"]
        s.skipped = ["B (already on the Mac)"]
        #expect(!s.needsAttention)
        s.notDone = ["C"]
        #expect(s.needsAttention)
        s.notDone = []
        s.failed = ["D": "x"]
        #expect(s.needsAttention)
    }
}
