import SwiftUI
import ZuneKit

/// A centred message for the states where there's no library to show.
struct StatusView<Actions: View>: View {
    let symbol: String?
    let title: String
    let detail: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .textSelection(.enabled)
            actions()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension StatusView where Actions == EmptyView {
    init(symbol: String?, title: String, detail: String) {
        self.init(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }
}

/// The loading screen while the Zune is read: a bar, and what it's doing right now.
struct ConnectingView: View {
    let status: ZuneStore.ConnectStatus?

    var body: some View {
        VStack(spacing: 14) {
            Text("Reading your Zune")
                .font(.title2.weight(.semibold))
            ProgressView(value: status?.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 340)
            Text(status?.label ?? "Connecting…")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("This takes about a minute.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
