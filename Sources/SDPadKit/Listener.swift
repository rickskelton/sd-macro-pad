import Foundation
import IOKit.hid

/// Prints or delivers every input report a pad sends: key presses, dial turns, media keys.
/// Opening a pad's keyboard interface needs the Input Monitoring permission on macOS.
public final class PadListener {
    private let devices: OpenedDevices
    private var stopped = false

    public init() {
        devices = OpenedDevices(matching: PadMonitor.vendorIDs.map { [kIOHIDVendorIDKey: $0] })
    }

    /// Blocks for `seconds`, calling `handler` with (productID, usagePage, report bytes).
    public func run(for seconds: TimeInterval, handler: (Int, Int, [UInt8]) -> Void) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            for device in devices.devices {
                guard let inbox = devices.inbox(for: device) else { continue }
                while let report = inbox.next(before: Date()) {
                    handler(hidProperty(device, kIOHIDProductIDKey), hidProperty(device, kIOHIDPrimaryUsagePageKey), report)
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
