import Foundation

/// A pad model this library knows the physical layout of.
public struct PadModel: Equatable, Hashable {
    public let name: String
    public let vendorID: Int
    public let productID: Int
    public let columns: Int
    public let rows: Int
    public let knobCount: Int

    public var keyCount: Int { columns * rows }
    /// Entries in the key table that matter for this model: 16 button slots, then 3 per knob.
    public var entryCount: Int { PadModel.firstKnobIndex + 3 * knobCount }

    public static let firstKnobIndex = 16

    /// Key table index of the button at a grid position (row-major, top-left is 0).
    public func keyIndex(row: Int, column: Int) -> Int { row * columns + column }

    public func knobIndex(_ knob: Int, _ part: KnobPart) -> Int {
        PadModel.firstKnobIndex + knob * 3 + part.rawValue
    }

    public static let sixKey = PadModel(name: "6-key, 1 dial", vendorID: 0x6D80, productID: 0xDC81,
                                        columns: 3, rows: 2, knobCount: 1)
    public static let sixteenKey = PadModel(name: "16-key, 3 dials", vendorID: 0x6D7D, productID: 0xDCFC,
                                            columns: 4, rows: 4, knobCount: 3)
    public static let known = [sixKey, sixteenKey]

    public static func lookup(vendorID: Int, productID: Int) -> PadModel? {
        known.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// Fallback for an SD pad with a config interface but no known layout: every slot is exposed.
    public static func generic(vendorID: Int, productID: Int) -> PadModel {
        PadModel(name: String(format: "Unknown SD pad %04X:%04X", vendorID, productID),
                 vendorID: vendorID, productID: productID, columns: 4, rows: 4, knobCount: 3)
    }
}

/// The three key table slots a knob owns, in table order.
public enum KnobPart: Int, CaseIterable {
    case press = 0, clockwise = 1, counterClockwise = 2
}

/// A control on the pad, addressed the way people think of it.
public enum Slot: Hashable {
    case key(Int)
    case knob(Int, KnobPart)

    public func index(in model: PadModel) -> Int {
        switch self {
        case .key(let i): return i
        case .knob(let k, let part): return model.knobIndex(k, part)
        }
    }

    public var title: String {
        switch self {
        case .key(let i): return "Key \(i + 1)"
        case .knob(let k, .press): return "Dial \(k + 1) press"
        case .knob(let k, .clockwise): return "Dial \(k + 1) clockwise"
        case .knob(let k, .counterClockwise): return "Dial \(k + 1) anticlockwise"
        }
    }
}

public struct Modifiers: OptionSet, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 0x01)
    public static let shift = Modifiers(rawValue: 0x02)
    public static let option = Modifiers(rawValue: 0x04)
    public static let command = Modifiers(rawValue: 0x08)
    public static let rightControl = Modifiers(rawValue: 0x10)
    public static let rightShift = Modifiers(rawValue: 0x20)
    public static let rightOption = Modifiers(rawValue: 0x40)
    public static let rightCommand = Modifiers(rawValue: 0x80)

    public var symbols: String {
        var s = ""
        if !intersection([.control, .rightControl]).isEmpty { s += "⌃" }
        if !intersection([.option, .rightOption]).isEmpty { s += "⌥" }
        if !intersection([.shift, .rightShift]).isEmpty { s += "⇧" }
        if !intersection([.command, .rightCommand]).isEmpty { s += "⌘" }
        return s
    }
}

/// One 4-byte entry of the key table: `[type, code1, code2, code3]`.
public struct KeyEntry: Equatable, Hashable {
    public var type: UInt8
    public var code1: UInt8
    public var code2: UInt8
    public var code3: UInt8

    public init(type: UInt8, code1: UInt8 = 0, code2: UInt8 = 0, code3: UInt8 = 0) {
        self.type = type; self.code1 = code1; self.code2 = code2; self.code3 = code3
    }

    public init(bytes: [UInt8]) {
        self.init(type: bytes[0], code1: bytes[1], code2: bytes[2], code3: bytes[3])
    }

    public var bytes: [UInt8] { [type, code1, code2, code3] }

    public enum Kind: UInt8 {
        case mouse = 0x10
        case disabled = 0x13
        case padFunction = 0x1F
        case key = 0x20
        case consumer = 0x30
        case system = 0x40
        case macro = 0x60
    }

    public var kind: Kind? { Kind(rawValue: type) }

    public static let disabled = KeyEntry(type: Kind.disabled.rawValue)

    /// A keystroke: HID modifier mask plus one keyboard usage (0 for a bare modifier).
    public static func key(_ usage: UInt8, _ modifiers: Modifiers = []) -> KeyEntry {
        KeyEntry(type: Kind.key.rawValue, code1: modifiers.rawValue, code2: usage)
    }

    /// A consumer-page usage such as volume or play/pause.
    public static func consumer(_ usage: UInt16) -> KeyEntry {
        KeyEntry(type: Kind.consumer.rawValue, code1: UInt8(usage & 0xFF), code2: UInt8(usage >> 8))
    }

    /// Mouse buttons (bit 0 left, 1 right, 2 middle, 3 back, 4 forward) and/or wheel steps.
    public static func mouse(buttons: UInt8 = 0, wheel: Int8 = 0) -> KeyEntry {
        KeyEntry(type: Kind.mouse.rawValue, code1: buttons, code3: UInt8(bitPattern: wheel))
    }

    /// Runs a stored macro. `mode`: 0 play `count` times, 1 loop while held,
    /// 2 loop until any key, 3 loop until this key is pressed again.
    public static func macro(_ index: Int, count: Int = 1, mode: Int = 0) -> KeyEntry {
        KeyEntry(type: Kind.macro.rawValue, code1: UInt8(index), code2: UInt8(count), code3: UInt8(mode))
    }

    public var modifiers: Modifiers { Modifiers(rawValue: code1) }
    public var consumerUsage: UInt16 { UInt16(code1) | UInt16(code2) << 8 }
    public var wheel: Int8 { Int8(bitPattern: code3) }

    /// Short human-readable description, for labels.
    public var summary: String {
        switch kind {
        case .disabled: return "None"
        case .key:
            if code1 == 0 && code2 == 0 { return "None" }
            let name = code2 == 0 ? "" : KeyNames.name(forUsage: code2)
            return modifiers.symbols + name
        case .consumer: return ConsumerKeys.name(for: consumerUsage)
        case .mouse:
            var parts: [String] = []
            if code1 & 1 != 0 { parts.append("Left click") }
            if code1 & 2 != 0 { parts.append("Right click") }
            if code1 & 4 != 0 { parts.append("Middle click") }
            if code1 & 8 != 0 { parts.append("Mouse back") }
            if code1 & 16 != 0 { parts.append("Mouse forward") }
            if wheel != 0 {
                let n = abs(Int(wheel))
                parts.append((wheel > 0 ? "Scroll up" : "Scroll down") + (n > 1 ? " ×\(n)" : ""))
            }
            return parts.isEmpty ? "None" : parts.joined(separator: " + ")
        case .macro: return "Macro \(code1 + 1)"
        case .system:
            switch code1 { case 1: return "Power"; case 2: return "Sleep"; case 4: return "Wake"; default: return "System \(code1)" }
        case .padFunction: return "Pad function \(code1)"
        case nil:
            return type == 0 ? "None" : String(format: "Raw %02X %02X %02X %02X", type, code1, code2, code3)
        }
    }
}

public struct RGB: Equatable, Hashable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8(v >> 16), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// Hue, saturation and value on the pad's 0–255 scale.
    public var hsv: (h: UInt8, s: UInt8, v: UInt8) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == rf { h = ((gf - bf) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == gf { h = (bf - rf) / d + 2 }
            else { h = (rf - gf) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = mx == 0 ? 0 : d / mx
        return (UInt8((h * 255).rounded()), UInt8((s * 255).rounded()), UInt8((mx * 255).rounded()))
    }

    public init(h: UInt8, s: UInt8, v: UInt8) {
        let hf = Double(h) / 255 * 6, sf = Double(s) / 255, vf = Double(v) / 255
        let i = Int(hf) % 6, f = hf - Double(Int(hf))
        let p = vf * (1 - sf), q = vf * (1 - f * sf), t = vf * (1 - (1 - f) * sf)
        let (rf, gf, bf): (Double, Double, Double)
        switch i {
        case 0: (rf, gf, bf) = (vf, t, p)
        case 1: (rf, gf, bf) = (q, vf, p)
        case 2: (rf, gf, bf) = (p, vf, t)
        case 3: (rf, gf, bf) = (p, q, vf)
        case 4: (rf, gf, bf) = (t, p, vf)
        default: (rf, gf, bf) = (vf, p, q)
        }
        self.init(r: UInt8((rf * 255).rounded()), g: UInt8((gf * 255).rounded()), b: UInt8((bf * 255).rounded()))
    }
}

public enum LightEffect: UInt8, CaseIterable, Identifiable {
    case off = 0, solid = 1, breathing = 2, lightOnPress = 3, tide = 4, perKey = 5
    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .solid: return "Solid"
        case .breathing: return "Breathing"
        case .lightOnPress: return "Light on press"
        case .tide: return "Tide"
        case .perKey: return "Per-key colours"
        }
    }

    public var hasSpeed: Bool { self == .breathing || self == .lightOnPress || self == .tide }
    /// Tide always runs the built-in palette and ignores the colour setting.
    public var hasColour: Bool { self == .solid || self == .breathing || self == .lightOnPress }
}

/// The backlight block, as read with `06 0A` and written with `06 0B`.
public struct LightConfig: Equatable {
    public var type: UInt8 = 1
    public var mode: UInt8 = LightEffect.tide.rawValue
    /// 0–4.
    public var brightness: UInt8 = 4
    /// 0–4.
    public var speed: UInt8 = 2
    public var direction: UInt8 = 0
    /// false cycles the built-in palette; true uses `hue`/`saturation`/`value`.
    public var singleColour: Bool = false
    public var hue: UInt8 = 0
    public var saturation: UInt8 = 255
    public var value: UInt8 = 255

    public init() {}

    public var effect: LightEffect? { LightEffect(rawValue: mode) }
    public var colour: RGB {
        get { RGB(h: hue, s: saturation, v: value) }
        set { (hue, saturation, value) = newValue.hsv }
    }
}

public struct PadInfo: Equatable {
    public var protocolVersion: Int
    public var productID: Int
    public var firmware: Int
    public var profileCount: Int
    public var profile: Int
    public var layerCount: Int
}
