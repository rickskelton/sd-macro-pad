import Foundation
import IOKit.hid

public final class PadListener {
    private let devices: OpenedDevices
    private var stopped = false

    public init() {
        devices = OpenedDevices(matching: PadMonitor.vendorIDs.map { [kIOHIDVendorIDKey: $0] })
    }

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
