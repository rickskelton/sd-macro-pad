import Foundation
import IOKit.hid

/// The pads' firmware bootloader (USB 5566:0009, "ZXWMicroChip Bootloader").
///
/// A pad enters it when the top-left and top-right keys are held while it is plugged in, and
/// leaves it when it is replugged without keys held. The bootloader occupies flash 0x0000–0x0FFF
/// and is never written by this code; the application lives at 0x1000–0x7FFF.
public final class Bootloader {
    public static let vendorID = 0x5566
    public static let productID = 0x0009
    public static let flashSize = 0x8000
    public static let applicationStart = 0x1000
    public static var applicationSize: Int { flashSize - applicationStart }

    private let devices: OpenedDevices
    private var device: IOHIDDevice!
    private var inbox: ReportInbox!

    /// Fails unless exactly one pad is in bootloader mode.
    public init() throws {
        devices = OpenedDevices(matching: [[kIOHIDVendorIDKey: Bootloader.vendorID, kIOHIDProductIDKey: Bootloader.productID]])
        Thread.sleep(forTimeInterval: 0.4)
        let found = devices.devices
        guard found.count == 1, let inbox = devices.inbox(for: found[0]) else {
            throw PadError.notFound(found.isEmpty
                ? "No pad is in bootloader mode. Hold the top-left and top-right keys while plugging it in."
                : "More than one pad is in bootloader mode. Leave only one connected.")
        }
        device = found[0]
        self.inbox = inbox
        let hello = try command([0x55, 0xFF, 0x01, 0x00])
        guard hello.count >= 3, hello[2] == 0x01 else { throw PadError.badReply("bootloader connect") }
    }

    private func command(_ frame: [UInt8], timeout: TimeInterval = 2) throws -> [UInt8] {
        inbox.drain()
        try sendOutputReport(device, frame)
        guard let reply = inbox.next(before: Date().addingTimeInterval(timeout)) else {
            throw PadError.timeout("bootloader command \(frame.count > 2 ? frame[2] : 0)")
        }
        guard reply.count >= 3, reply[0] == 0xAA, reply[1] == 0xFF, reply[2] == frame[2] else {
            throw PadError.badReply("bootloader command \(frame[2])")
        }
        return reply
    }

    private func range(_ address: Int, _ length: Int) -> [UInt8] {
        [UInt8(address >> 8), UInt8(address & 0xFF), UInt8(length >> 8), UInt8(length & 0xFF)]
    }

    /// Reads flash. The whole 32 KB, bootloader included, can be read.
    public func read(address: Int = 0, length: Int = Bootloader.flashSize) throws -> [UInt8] {
        _ = try command([0x55, 0xFF, 0x03, 0x04] + range(address, length))
        var data: [UInt8] = []
        while data.count < length {
            guard let packet = inbox.next(before: Date().addingTimeInterval(2)) else {
                throw PadError.timeout("flash read stopped at \(data.count) bytes")
            }
            data += packet
        }
        return Array(data.prefix(length))
    }

    /// Writes the application area from a full 32 KB image and verifies the bootloader's checksum.
    /// The pad stays in the bootloader afterwards and must be replugged.
    public func writeApplication(image: [UInt8], progress: ((Double) -> Void)? = nil) throws {
        guard image.count == Bootloader.flashSize else {
            throw PadError.usage("A firmware image is exactly \(Bootloader.flashSize) bytes, this one is \(image.count)")
        }
        let payload = Array(image[Bootloader.applicationStart...])
        _ = try command([0x55, 0xFF, 0x02, 0x04] + range(Bootloader.applicationStart, payload.count))
        var offset = 0
        while offset < payload.count {
            // Data frames are raw and unacknowledged.
            try sendOutputReport(device, Array(payload[offset..<min(offset + 64, payload.count)]))
            Thread.sleep(forTimeInterval: 0.002)
            offset += 64
            progress?(Double(min(offset, payload.count)) / Double(payload.count))
        }
        Thread.sleep(forTimeInterval: 0.3)
        let check = try command([0x55, 0xFF, 0x04, 0x00])
        let reported = Int(check[4]) << 8 | Int(check[5])
        let expected = payload.reduce(0) { ($0 + Int($1)) & 0xFFFF }
        guard reported == expected else {
            throw PadError.badReply(String(format: "checksum %04X, expected %04X. Do not unplug; flash again.", reported, expected))
        }
        _ = try command([0x55, 0xFF, 0x05, 0x01, 0x01])
    }

    /// USB vendor and product ID found in an application image's device descriptor.
    public static func deviceID(inImage image: [UInt8]) -> (vendorID: Int, productID: Int)? {
        guard image.count >= applicationStart + 18 else { return nil }
        for i in applicationStart..<(image.count - 18)
        where image[i] == 0x12 && image[i + 1] == 0x01 && image[i + 4] == 0 && image[i + 5] == 0 && image[i + 6] == 0
            && (image[i + 7] == 0x20 || image[i + 7] == 0x40) && image[i + 17] == 0x01 {
            return (Int(image[i + 8]) | Int(image[i + 9]) << 8, Int(image[i + 10]) | Int(image[i + 11]) << 8)
        }
        return nil
    }
}
