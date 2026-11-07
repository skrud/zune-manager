import SwiftUI
import ZuneKit

/// What happened: done, skipped, failed (with reasons) and not done.
struct SummarySheet: View {
    let summary: OperationSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.title).font(.headline)
            Text(headline).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    section("Done", summary.succeeded)
                    section("Skipped", summary.skipped)
                    section("Failed", summary.failed.keys.sorted().map { "\($0) — \(summary.failed[$0]!)" })
                    section("Not done", summary.notDone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("OK", action: onDismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
    }

    private var headline: String {
        var parts = ["\(summary.succeeded.count) done"]
        if !summary.skipped.isEmpty { parts.append("\(summary.skipped.count) skipped") }
        if !summary.failed.isEmpty { parts.append("\(summary.failed.count) failed") }
        if !summary.notDone.isEmpty { parts.append("\(summary.notDone.count) not done") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func section(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            DisclosureGroup("\(title) (\(lines.count))") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
