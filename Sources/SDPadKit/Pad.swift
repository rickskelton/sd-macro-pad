import Foundation
import IOKit.hid

/// A connected pad's configuration interface (vendor usage page FF00, usage 2, 64-byte reports).
///
/// Every frame starts with `06` and a sub-command; the pad answers each one with `AA` and the
/// same sub-command. A frame must not be sent before the previous answer has been read.
/// Methods block, so call them off the main thread in a UI.
public final class Pad {
    public let vendorID: Int
    public let productID: Int
    public let productName: String
    public let locationID: Int
    public let model: PadModel
    public let isKnownModel: Bool

    private let device: IOHIDDevice
    private let inbox: ReportInbox
    private let lock = NSLock()
    /// The manager that holds the device open; a pad keeps working after its monitor is gone.
    private let owner: OpenedDevices

    init(device: IOHIDDevice, inbox: ReportInbox, owner: OpenedDevices) {
        self.device = device
        self.inbox = inbox
        self.owner = owner
        vendorID = hidProperty(device, kIOHIDVendorIDKey)
        productID = hidProperty(device, kIOHIDProductIDKey)
        productName = hidString(device, kIOHIDProductKey)
        locationID = hidProperty(device, kIOHIDLocationIDKey)
        let known = PadModel.lookup(vendorID: vendorID, productID: productID)
        isKnownModel = known != nil
        model = known ?? .generic(vendorID: vendorID, productID: productID)
    }

    // MARK: Transport

    /// Sends `06 <payload…>` and returns the pad's 64-byte answer.
    @discardableResult
    public func request(_ payload: [UInt8], timeout: TimeInterval = 1.5) throws -> [UInt8] {
        try exchange([0x06] + payload, expecting: payload[0] == 0x08 ? 0x07 : payload[0], timeout: timeout)
    }

    /// Sends a raw frame and waits for an `AA <expecting>` answer.
    public func exchange(_ frame: [UInt8], expecting: UInt8, timeout: TimeInterval = 1.5) throws -> [UInt8] {
        // 5A and 55 FF are the firmware-update entry points; they are never sent from here.
        guard frame.first != 0x5A, frame.first != 0x55 else { throw PadError.usage("Refusing to send a firmware-update frame") }
        lock.lock(); defer { lock.unlock() }
        inbox.drain()
        try sendOutputReport(device, frame)
        let deadline = Date().addingTimeInterval(timeout)
        while let reply = inbox.next(before: deadline) {
            if reply.count >= 2, reply[0] == 0xAA, reply[1] == expecting { return reply }
        }
        throw PadError.timeout(String(format: "command %02X", frame.count > 1 ? frame[1] : 0))
    }

    private func offsetBytes(_ offset: Int) -> [UInt8] { [UInt8(offset & 0xFF), UInt8(offset >> 8)] }

    // MARK: Device

    public func info() throws -> PadInfo {
        let r = try request([0x05])
        guard r.count >= 19 else { throw PadError.badReply("device info too short") }
        let d = Array(r[5...])
        return PadInfo(protocolVersion: Int(d[0]) | Int(d[1]) << 8, productID: Int(d[2]) | Int(d[3]) << 8,
                       firmware: Int(d[4]) | Int(d[5]) << 8, profileCount: Int(d[10]), profile: Int(d[11]),
                       layerCount: Int(d[12]))
    }

    /// Makes one of the stored profiles (0-based) the active one. Each profile has its own key table.
    public func selectProfile(_ profile: Int) throws {
        try request([0xFB, UInt8(profile)])
    }

    // MARK: Keys

    /// Reads the active profile's key table: one entry per slot up to the model's `entryCount`.
    public func readKeys(layer: UInt8 = 0) throws -> [KeyEntry] {
        let wanted = model.entryCount * 4
        var bytes: [UInt8] = []
        var offset = 0
        while bytes.count < wanted {
            let r = try request([0x08, 0x3A] + offsetBytes(offset) + [0x00, layer])
            bytes += r[8..<64]
            offset += 56
        }
        return stride(from: 0, to: wanted, by: 4).map { KeyEntry(bytes: Array(bytes[$0..<$0 + 4])) }
    }

    public func writeKey(_ index: Int, _ entry: KeyEntry, layer: UInt8 = 0) throws {
        try request([0x10, 0x07] + offsetBytes(index * 4) + [0x00, layer, 0x00] + entry.bytes)
    }

    public func writeKey(_ slot: Slot, _ entry: KeyEntry) throws {
        try writeKey(slot.index(in: model), entry)
    }

    // MARK: Lighting

    public func readLight() throws -> LightConfig {
        let r = try request([0x0A])
        var c = LightConfig()
        c.type = r[5]; c.mode = r[7]; c.brightness = r[8]; c.speed = r[9]; c.direction = r[10]
        c.singleColour = r[11] != 0
        c.hue = r[13]; c.saturation = r[14]; c.value = r[15]
        return c
    }

    public func writeLight(_ c: LightConfig) throws {
        let colourFlag: UInt8 = c.singleColour && c.mode != 0 ? 1 : 0
        try request([0x0B, 0x0B, 0x00, 0x00, c.type, 0x00, c.mode, c.brightness, c.speed, c.direction,
                     colourFlag, 0x00, c.hue, c.saturation, c.value])
    }

    /// Per-key colours, shown by the "per-key" effect (mode 5). Index matches the key table.
    public func readKeyColours() throws -> [RGB] {
        let wanted = model.keyCount * 3
        var bytes: [UInt8] = []
        var offset = 0
        while bytes.count < wanted {
            let r = try request([0x13, 0x3A] + offsetBytes(offset))
            bytes += r[8..<64]
            offset += 56
        }
        return stride(from: 0, to: wanted, by: 3).map { RGB(r: bytes[$0], g: bytes[$0 + 1], b: bytes[$0 + 2]) }
    }

    public func writeKeyColour(_ index: Int, _ colour: RGB) throws {
        try request([0x14, 0x03] + offsetBytes(index * 3) + [0x00, 0x00, 0x00, colour.r, colour.g, colour.b])
    }

    // MARK: Macros

    public func readMacroTable() throws -> [UInt8] {
        var table: [UInt8] = []
        while table.count < Macro.tableSize {
            let count = min(56, Macro.tableSize - table.count)
            let r = try request([0x0C, UInt8(count)] + offsetBytes(table.count))
            table += r[8..<8 + count]
        }
        return table
    }

    /// Writes the bytes of `table` up to the end of the last stored macro, in 56-byte frames.
    public func writeMacroTable(_ table: [UInt8]) throws {
        guard table.count == Macro.tableSize else { throw PadError.usage("A macro table is \(Macro.tableSize) bytes") }
        let used = max(64, (table.lastIndex { $0 != 0 } ?? 0) + 1)
        var offset = 0
        while offset < used {
            let chunk = Array(table[offset..<min(offset + 56, Macro.tableSize)])
            try request([0x0D, UInt8(chunk.count)] + offsetBytes(offset) + chunk)
            offset += chunk.count
        }
    }

    /// Reads only as much of the macro table as the stored macros occupy.
    public func readMacros() throws -> [[MacroAction]] {
        var table: [UInt8] = []
        func readFrame() throws {
            let count = min(56, Macro.tableSize - table.count)
            let r = try request([0x0C, UInt8(count)] + offsetBytes(table.count))
            table += r[8..<8 + count]
        }
        while table.count < 64 { try readFrame() }
        let starts = (0..<Macro.slotCount).map { Int(table[2 * $0]) | Int(table[2 * $0 + 1]) << 8 }.filter { $0 >= 64 && $0 < Macro.tableSize }
        for start in starts {
            var offset = start
            while true {
                while table.count < offset + 4 && table.count < Macro.tableSize { try readFrame() }
                guard offset + 4 <= table.count, table[offset + 2] & 0x80 == 0 else { break }
                offset += 4
            }
        }
        return Macro.decode(table)
    }

    public func writeMacros(_ macros: [[MacroAction]]) throws { try writeMacroTable(try Macro.encode(macros)) }
}

/// Watches USB for pads and reports what is connected.
public final class PadMonitor {
    public struct Snapshot {
        /// Pads whose configuration interface is available.
        public var pads: [Pad] = []
        /// SD pads that are connected but run the factory firmware without a configuration interface.
        public var legacyPads: [String] = []
        /// A pad is sitting in its firmware bootloader.
        public var bootloaderPresent = false
    }

    /// Called on a background thread whenever a pad is plugged in or removed.
    public var onChange: ((Snapshot) -> Void)?

    static let vendorIDs = [0x6D7B, 0x6D7C, 0x6D7D, 0x6D7E, 0x6D7F, 0x6D80, 0x6D81, 0x6D82, 0x6D83]

    private let config: OpenedDevices
    private let presence: IOHIDManager
    private var pads: [ObjectIdentifier: Pad] = [:]
    private let lock = NSLock()

    public init() {
        config = OpenedDevices(matching: PadMonitor.vendorIDs.map {
            [kIOHIDVendorIDKey: $0, kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 2]
        })
        // Never opened: it only tells us which pads exist, so no keyboard interface is touched.
        presence = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matching: [[String: Any]] = PadMonitor.vendorIDs.map { [kIOHIDVendorIDKey: $0] }
        matching.append([kIOHIDVendorIDKey: Bootloader.vendorID, kIOHIDProductIDKey: Bootloader.productID])
        IOHIDManagerSetDeviceMatchingMultiple(presence, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(presence, { context, _, _, _ in
            Unmanaged<PadMonitor>.fromOpaque(context!).takeUnretainedValue().changed()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(presence, { context, _, _, _ in
            Unmanaged<PadMonitor>.fromOpaque(context!).takeUnretainedValue().changed()
        }, context)
        config.onChange = { [weak self] in self?.changed() }
        HIDThread.shared.sync { HIDThread.shared.schedule(self.presence) }
    }

    deinit {
        let presence = self.presence
        config.onChange = nil
        HIDThread.shared.sync {
            IOHIDManagerRegisterDeviceMatchingCallback(presence, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(presence, nil, nil)
            HIDThread.shared.unschedule(presence)
        }
    }

    private func changed() { onChange?(snapshot()) }

    public func snapshot() -> Snapshot {
        var snap = Snapshot()
        lock.lock()
        var current: [ObjectIdentifier: Pad] = [:]
        for device in config.devices {
            let id = ObjectIdentifier(device)
            if let pad = pads[id] { current[id] = pad }
            else if let inbox = config.inbox(for: device) { current[id] = Pad(device: device, inbox: inbox, owner: config) }
        }
        pads = current
        lock.unlock()
        snap.pads = current.values.sorted { ($0.model.keyCount, $0.locationID) < ($1.model.keyCount, $1.locationID) }

        let seen = (IOHIDManagerCopyDevices(presence) as? Set<IOHIDDevice>) ?? []
        var configurable = Set<Int>()
        var names: [Int: String] = [:]
        for device in seen {
            let vendor = hidProperty(device, kIOHIDVendorIDKey)
            if vendor == Bootloader.vendorID { snap.bootloaderPresent = true; continue }
            let location = hidProperty(device, kIOHIDLocationIDKey)
            let product = hidProperty(device, kIOHIDProductIDKey)
            names[location] = PadModel.lookup(vendorID: vendor, productID: product)?.name
                ?? String(format: "SD pad %04X:%04X", vendor, product)
            if hidProperty(device, kIOHIDPrimaryUsagePageKey) == 0xFF00, hidProperty(device, kIOHIDPrimaryUsageKey) == 2 {
                configurable.insert(location)
            }
        }
        snap.legacyPads = names.filter { !configurable.contains($0.key) }.map { $0.value }.sorted()
        return snap
    }

    /// Waits briefly for USB enumeration, then returns what is connected. For command-line use.
    public func settle(_ seconds: TimeInterval = 0.4) -> Snapshot {
        Thread.sleep(forTimeInterval: seconds)
        return snapshot()
    }
}
