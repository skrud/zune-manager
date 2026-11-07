import SwiftUI

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
