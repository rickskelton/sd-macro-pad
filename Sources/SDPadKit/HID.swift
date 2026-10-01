import Foundation
import IOKit.hid

public enum PadError: Error, CustomStringConvertible {
    case timeout(String)
    case io(IOReturn)
    case badReply(String)
    case usage(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .timeout(let what): return "The pad did not answer (\(what))"
        case .io(let code): return String(format: "USB error 0x%08X", UInt32(bitPattern: code))
        case .badReply(let what): return "Unexpected reply: \(what)"
        case .usage(let what): return what
        case .notFound(let what): return what
        }
    }
}

/// All IOKit HID callbacks are delivered on this one background thread, so callers on any
/// other thread can block waiting for a reply.
final class HIDThread {
    static let shared = HIDThread()
    private var runLoop: CFRunLoop!

    private init() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            // A run loop with no sources exits at once; this timer keeps it alive.
            let keepAlive = Timer(timeInterval: 3600, repeats: true) { _ in }
            RunLoop.current.add(keepAlive, forMode: .default)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "SDPadKit.HID"
        thread.start()
        ready.wait()
    }

    var isCurrent: Bool { CFRunLoopGetCurrent() === runLoop }

    func sync(_ block: @escaping () -> Void) {
        if isCurrent { block(); return }
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { block(); done.signal() }
        CFRunLoopWakeUp(runLoop)
        done.wait()
    }

    func schedule(_ manager: IOHIDManager) {
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }

    func unschedule(_ manager: IOHIDManager) {
        IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }
}

/// Input reports of one opened HID interface, queued for a blocking reader.
final class ReportInbox {
    private let condition = NSCondition()
    private var reports: [[UInt8]] = []

    func push(_ report: [UInt8]) {
        condition.lock(); reports.append(report); condition.signal(); condition.unlock()
    }

    func drain() {
        condition.lock(); reports.removeAll(); condition.unlock()
    }

    func next(before deadline: Date) -> [UInt8]? {
        condition.lock(); defer { condition.unlock() }
        while reports.isEmpty {
            if !condition.wait(until: deadline) { return nil }
        }
        return reports.removeFirst()
    }
}

/// An IOHIDManager whose matched devices are opened and whose input reports are routed
/// into one inbox per device.
final class OpenedDevices {
    let manager: IOHIDManager
    private let lock = NSLock()
    private var inboxes: [ObjectIdentifier: ReportInbox] = [:]
    private var buffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    var onChange: (() -> Void)?

    init(matching: [[String: Any]]) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<OpenedDevices>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<OpenedDevices>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        HIDThread.shared.sync {
            HIDThread.shared.schedule(self.manager)
            IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    deinit {
        let manager = self.manager
        HIDThread.shared.sync {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            HIDThread.shared.unschedule(manager)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func attach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        let size = max(64, IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        let inbox = ReportInbox()
        lock.lock(); inboxes[id] = inbox; buffers[id] = buffer; lock.unlock()
        // The manager opens devices that exist when it is opened; one that arrives later, or
        // that the manager failed to open, is opened here.
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, _, _, _, _, report, length in
            let inbox = Unmanaged<ReportInbox>.fromOpaque(context!).takeUnretainedValue()
            inbox.push(Array(UnsafeBufferPointer(start: report, count: length)))
        }, Unmanaged.passUnretained(inbox).toOpaque())
        onChange?()
    }

    private func detach(_ device: IOHIDDevice) {
        // The inbox and buffer are left allocated: a late callback must not touch freed memory.
        lock.lock(); inboxes[ObjectIdentifier(device)] = nil; lock.unlock()
        onChange?()
    }

    var devices: [IOHIDDevice] {
        lock.lock(); let ids = Set(inboxes.keys); lock.unlock()
        let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return all.filter { ids.contains(ObjectIdentifier($0)) }
    }

    func inbox(for device: IOHIDDevice) -> ReportInbox? {
        lock.lock(); defer { lock.unlock() }
        return inboxes[ObjectIdentifier(device)]
    }
}

func hidProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
}

func hidString(_ device: IOHIDDevice, _ key: String) -> String {
    IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
}

func sendOutputReport(_ device: IOHIDDevice, _ bytes: [UInt8], length: Int = 64) throws {
    var frame = bytes
    if frame.count < length { frame += [UInt8](repeating: 0, count: length - frame.count) }
    let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, frame, frame.count)
    guard result == kIOReturnSuccess else { throw PadError.io(result) }
}
