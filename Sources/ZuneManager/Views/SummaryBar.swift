import SwiftUI
import ZuneKit

/// The result of an add, delete or save, as a slim bar at the bottom of the window:
/// "Add to Zune: 3 done, 1 skipped · Details · ✕". It fades out on its own when everything
/// went fine; when something failed or wasn't done it stays until dismissed.
struct SummaryBar: View {
    let summary: OperationSummary
    let onDismiss: () -> Void

    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(summary.needsAttention ? .orange : .green)
            Text(summary.title).font(.callout.weight(.semibold))
            Text(summary.headline).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Details") { showingDetails.toggle() }
                .buttonStyle(.link)
                .popover(isPresented: $showingDetails, arrowEdge: .top) {
                    SummaryDetails(summary: summary)
                }
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: summary) {
            guard !summary.needsAttention else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, !showingDetails { onDismiss() }
        }
    }
}

/// Done, skipped, failed (with reasons) and not done, in a popover.
struct SummaryDetails: View {
    let summary: OperationSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                section("Done", summary.succeeded)
                section("Skipped", summary.skipped)
                section("Failed", summary.failed.map { "\($0.name) — \($0.reason)" })
                section("Not done", summary.notDone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(width: 420, height: 280)
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
