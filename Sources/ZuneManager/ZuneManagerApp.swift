import AppKit
import SwiftUI
import ZuneKit

@main
struct ZuneManagerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Zune Manager") {
            ContentView(store: delegate.store)
                .frame(minWidth: 820, minHeight: 480)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ZuneStore(makeClient: { LiveZuneDevice() })
    private var watcher: USBWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run with `swift run` (outside an app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        watcher = USBWatcher(
            onAttach: { [store] in
                Task {
                    // The Zune needs a moment after it's plugged in before it answers.
                    try? await Task.sleep(for: .seconds(2))
                    await store.deviceAttached()
                }
            },
            onDetach: { [store] in store.deviceDetached() })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Closes the Zune's session before quitting (bounded, in case the Zune doesn't answer).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.phase != .stuck else { return .terminateNow }
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.store.prepareToQuit() }
                group.addTask { try? await Task.sleep(for: .seconds(5)) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
