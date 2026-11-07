import AppKit
import SwiftUI
import ZuneKit

@main
struct ZuneManagerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // One window: a second one would run its own add flow against the same Zune.
        Window("Zune Manager", id: "main") {
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

    /// Never quits in the middle of a libmtp call (that wedges the Zune): finishes the current
    /// file or the connect, then closes the Zune's session. Every step is bounded by the
    /// device layer's time limits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.phase != .stuck else { return .terminateNow }
        Task {
            await store.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
