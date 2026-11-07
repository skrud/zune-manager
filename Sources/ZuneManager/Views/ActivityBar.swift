import SwiftUI
import ZuneKit

/// Progress of the add, delete or save that's running, with Cancel (after the current file).
struct ActivityBar: View {
    let store: ZuneStore
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            Text(activity.title).font(.callout.weight(.semibold))
            Text("file \(max(activity.fileIndex, 1)) of \(activity.fileCount)")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            ProgressView(value: activity.fraction)
                .progressViewStyle(.linear)
            if activity.cancelRequested {
                Text("Stopping after this file…").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Cancel") { store.cancelAfterCurrentFile() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
