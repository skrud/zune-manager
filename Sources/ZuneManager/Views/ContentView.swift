import SwiftUI
import ZuneKit

struct ContentView: View {
    @Bindable var store: ZuneStore
    @State private var addFlow: AddFlow
    @State private var pendingDelete: DeletePlan?

    init(store: ZuneStore) {
        self.store = store
        _addFlow = State(initialValue: AddFlow(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch store.phase {
                case .waitingForDevice:
                    StatusView(symbol: "cable.connector", title: "Connect your Zune",
                               detail: "Plug it in with its USB cable. Close Chromium-based browsers (like Helium) first — they can interfere with the Zune.")
                case .connecting:
                    ConnectingView(status: store.connectStatus)
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
                    browser
                }
            }
            .frame(maxHeight: .infinity)
            // Outside the phase switch: an unplug mid-operation still reports what happened.
            if let summary = store.lastSummary {
                Divider()
                SummaryBar(summary: summary) { withAnimation { store.dismissSummary() } }
            }
        }
        .animation(.default, value: store.lastSummary)
    }

    private var busy: Bool { store.activity != nil || addFlow.isPreparing }

    private var browser: some View {
        VStack(spacing: 0) {
            ColumnBrowserView(
                store: store,
                onDelete: { selection in
                    guard !busy else { return }
                    pendingDelete = store.deletePlan(for: selection)
                },
                onSave: { selection in
                    guard !busy, let folder = Pickers.chooseSaveFolder() else { return }
                    Task { await store.export(selection, to: folder) }
                })
            Divider()
            if let activity = store.activity {
                ActivityBar(store: store, activity: activity)
                Divider()
            } else if addFlow.isPreparing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading the files you picked…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
            }
            FooterView(store: store)
        }
        .navigationTitle(store.snapshot?.deviceName ?? "Zune")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add…", systemImage: "plus") {
                    let urls = Pickers.chooseSongs()
                    guard !urls.isEmpty else { return }
                    Task { await addFlow.start(urls) }
                }
                .disabled(busy)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !busy, !urls.isEmpty else { return false }
            Task { await addFlow.start(urls) }
            return true
        }
        .modifier(AddFlowPresenter(flow: addFlow))
        .confirmationDialog("Delete from Zune?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { plan in
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                Task { await store.delete(plan) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { plan in
            Text(plan.confirmationText)
        }
    }
}
