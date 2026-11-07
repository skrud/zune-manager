import Foundation
import IOKit
import IOKit.usb

/// Tells the app when a Zune is plugged in or unplugged, using IOKit notifications.
/// An already-attached Zune is reported as an attach right away.
@MainActor
final class USBWatcher {
    private let port: IONotificationPortRef
    private var attachIterator: io_iterator_t = 0
    private var detachIterator: io_iterator_t = 0
    private let onAttach: @MainActor () -> Void
    private let onDetach: @MainActor () -> Void

    init(vendorID: Int = 0x045E, productID: Int = 0x0710,
         onAttach: @escaping @MainActor () -> Void, onDetach: @escaping @MainActor () -> Void) {
        self.onAttach = onAttach
        self.onDetach = onDetach
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)

        func matching() -> CFDictionary {
            let dict = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
            dict["idVendor"] = vendorID
            dict["idProduct"] = productID
            // IOServiceAddMatchingNotification consumes one reference.
            return Unmanaged.passRetained(dict as CFDictionary).takeUnretainedValue()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(), { context, iterator in
            MainActor.assumeIsolated {
                Unmanaged<USBWatcher>.fromOpaque(context!).takeUnretainedValue().drain(iterator, attached: true)
            }
        }, context, &attachIterator)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(), { context, iterator in
            MainActor.assumeIsolated {
                Unmanaged<USBWatcher>.fromOpaque(context!).takeUnretainedValue().drain(iterator, attached: false)
            }
        }, context, &detachIterator)

        // Arms the notifications and reports a Zune that's already plugged in.
        drain(attachIterator, attached: true)
        drain(detachIterator, attached: false)
    }

    private func drain(_ iterator: io_iterator_t, attached: Bool) {
        var found = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
            found = true
        }
        guard found else { return }
        attached ? onAttach() : onDetach()
    }
}
