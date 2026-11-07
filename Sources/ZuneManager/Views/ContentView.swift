import SwiftUI
import ZuneKit

struct ContentView: View {
    @Bindable var store: ZuneStore

    var body: some View {
        switch store.phase {
        case .waitingForDevice:
            StatusView(symbol: "cable.connector", title: "Connect your Zune",
                       detail: "Plug it in with its USB cable. Close Chromium-based browsers (like Helium) first — they can interfere with the Zune.")
        case .connecting:
            StatusView(symbol: nil, title: "Reading your Zune…",
                       detail: "This takes about a minute.")
        case .stuck:
            StatusView(symbol: "exclamationmark.triangle", title: "Your Zune stopped responding",
                       detail: ZuneStore.stuckMessage) {
                Button("Quit Zune Manager") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            StatusView(symbol: "exclamationmark.triangle", title: "Couldn't read your Zune", detail: message) {
                Button("Reconnect") { Task { await store.reconnect() } }
                    .keyboardShortcut(.defaultAction)
            }
        case .ready:
            VStack(spacing: 0) {
                ColumnBrowserView(store: store)
                Divider()
                FooterView(store: store)
            }
            .navigationTitle(store.snapshot?.deviceName ?? "Zune")
            .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add…", systemImage: "plus") {}
                        .disabled(true)
                }
            }
        }
    }
}
