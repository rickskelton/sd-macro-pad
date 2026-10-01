import Foundation

/// HID keyboard usage names, and the conversions the app and CLI need.
public enum KeyNames {
    /// Usage → display name, in a sensible picker order.
    public static let all: [(usage: UInt8, name: String)] = {
        var list: [(UInt8, String)] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { list.append((UInt8(0x04 + i), String(c))) }
        for (i, c) in "1234567890".enumerated() { list.append((UInt8(0x1E + i), String(c))) }
        list += [(0x28, "Return"), (0x29, "Esc"), (0x2A, "Delete"), (0x2B, "Tab"), (0x2C, "Space"),
                 (0x2D, "-"), (0x2E, "="), (0x2F, "["), (0x30, "]"), (0x31, "\\"), (0x33, ";"),
                 (0x34, "'"), (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock")]
        for i in 0..<12 { list.append((UInt8(0x3A + i), "F\(i + 1)")) }
        list += [(0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"),
                 (0x4A, "Home"), (0x4B, "Page Up"), (0x4C, "Forward Delete"), (0x4D, "End"),
                 (0x4E, "Page Down"), (0x4F, "→"), (0x50, "←"), (0x51, "↓"), (0x52, "↑"),
                 (0x53, "Num Lock"), (0x54, "Keypad /"), (0x55, "Keypad *"), (0x56, "Keypad -"),
                 (0x57, "Keypad +"), (0x58, "Keypad Enter")]
        for (i, c) in "1234567890".enumerated() { list.append((UInt8(0x59 + i), "Keypad \(c)")) }
        list += [(0x63, "Keypad ."), (0x64, "§"), (0x65, "Menu"), (0x67, "Keypad =")]
        for i in 0..<12 { list.append((UInt8(0x68 + i), "F\(i + 13)")) }
        return list
    }()

    private static let byUsage: [UInt8: String] = Dictionary(uniqueKeysWithValues: all.map { ($0.usage, $0.name) })

    public static func name(forUsage usage: UInt8) -> String {
        byUsage[usage] ?? String(format: "Key 0x%02X", usage)
    }

    /// Parses a name as the CLI accepts it ("a", "f13", "space", "up", "0x68").
    public static func usage(named raw: String) -> UInt8? {
        let s = raw.lowercased()
        if s.hasPrefix("0x"), let v = UInt8(s.dropFirst(2), radix: 16) { return v }
        let aliases: [String: UInt8] = [
            "enter": 0x28, "return": 0x28, "esc": 0x29, "escape": 0x29, "backspace": 0x2A, "delete": 0x2A,
            "tab": 0x2B, "space": 0x2C, "minus": 0x2D, "equals": 0x2E, "capslock": 0x39,
            "home": 0x4A, "pageup": 0x4B, "del": 0x4C, "forwarddelete": 0x4C, "end": 0x4D, "pagedown": 0x4E,
            "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52, "insert": 0x49, "numlock": 0x53,
            "printscreen": 0x46, "menu": 0x65,
        ]
        if let v = aliases[s] { return v }
        return all.first { $0.name.lowercased() == s }?.usage
    }

    /// macOS virtual key code (`NSEvent.keyCode`) → HID usage.
    public static let usageForMacKeyCode: [UInt16: UInt8] = [
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A, 6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19,
        10: 0x64, 11: 0x05, 12: 0x14, 13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C, 17: 0x17,
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22, 24: 0x2E, 25: 0x26, 26: 0x24,
        27: 0x2D, 28: 0x25, 29: 0x27, 30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2F, 34: 0x0C, 35: 0x13,
        36: 0x28, 37: 0x0F, 38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33, 42: 0x31, 43: 0x36, 44: 0x38,
        45: 0x11, 46: 0x10, 47: 0x37, 48: 0x2B, 49: 0x2C, 50: 0x35, 51: 0x2A, 53: 0x29,
        64: 0x6C, 65: 0x63, 67: 0x55, 69: 0x57, 71: 0x53, 75: 0x54, 76: 0x58, 78: 0x56,
        79: 0x6D, 80: 0x6E, 81: 0x67, 82: 0x62, 83: 0x59, 84: 0x5A, 85: 0x5B, 86: 0x5C, 87: 0x5D,
        88: 0x5E, 89: 0x5F, 90: 0x6F, 91: 0x60, 92: 0x61,
        96: 0x3E, 97: 0x3F, 98: 0x40, 99: 0x3C, 100: 0x41, 101: 0x42, 103: 0x44, 105: 0x68,
        106: 0x6B, 107: 0x69, 109: 0x43, 111: 0x45, 113: 0x6A, 114: 0x49, 115: 0x4A, 116: 0x4B,
        117: 0x4C, 118: 0x3D, 119: 0x4D, 120: 0x3B, 121: 0x4E, 122: 0x3A, 123: 0x50, 124: 0x4F,
        125: 0x51, 126: 0x52,
    ]

    /// Character → key position on a US layout, for building text macros.
    /// The host's keyboard layout decides what a position actually types.
    public static func stroke(for character: Character) -> (usage: UInt8, shift: Bool)? {
        let plain = "abcdefghijklmnopqrstuvwxyz"
        if let i = plain.firstIndex(of: character) { return (UInt8(0x04 + plain.distance(from: plain.startIndex, to: i)), false) }
        let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        if let i = upper.firstIndex(of: character) { return (UInt8(0x04 + upper.distance(from: upper.startIndex, to: i)), true) }
        let digits = "1234567890"
        if let i = digits.firstIndex(of: character) { return (UInt8(0x1E + digits.distance(from: digits.startIndex, to: i)), false) }
        let shiftedDigits = "!@#$%^&*()"
        if let i = shiftedDigits.firstIndex(of: character) { return (UInt8(0x1E + shiftedDigits.distance(from: shiftedDigits.startIndex, to: i)), true) }
        let table: [Character: (UInt8, Bool)] = [
            "\n": (0x28, false), "\t": (0x2B, false), " ": (0x2C, false),
            "-": (0x2D, false), "_": (0x2D, true), "=": (0x2E, false), "+": (0x2E, true),
            "[": (0x2F, false), "{": (0x2F, true), "]": (0x30, false), "}": (0x30, true),
            "\\": (0x31, false), "|": (0x31, true), ";": (0x33, false), ":": (0x33, true),
            "'": (0x34, false), "\"": (0x34, true), "`": (0x35, false), "~": (0x35, true),
            ",": (0x36, false), "<": (0x36, true), ".": (0x37, false), ">": (0x37, true),
            "/": (0x38, false), "?": (0x38, true),
        ]
        return table[character].map { (usage: $0.0, shift: $0.1) }
    }

    /// Parses "cmd+shift+4", "ctrl+a", "f13" into a keystroke entry.
    public static func parseShortcut(_ text: String) -> KeyEntry? {
        var mods: Modifiers = []
        var usage: UInt8 = 0
        for part in text.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch part {
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "shift", "⇧": mods.insert(.shift)
            case "alt", "opt", "option", "⌥": mods.insert(.option)
            case "cmd", "command", "win", "gui", "meta", "⌘": mods.insert(.command)
            default:
                guard usage == 0, let u = KeyNames.usage(named: part) else { return nil }
                usage = u
            }
        }
        guard usage != 0 || !mods.isEmpty else { return nil }
        return .key(usage, mods)
    }
}

/// Consumer-page (media) usages worth offering by name.
public enum ConsumerKeys {
    public static let all: [(usage: UInt16, name: String, token: String)] = [
        (0xE9, "Volume up", "volup"), (0xEA, "Volume down", "voldown"), (0xE2, "Mute", "mute"),
        (0xCD, "Play / Pause", "playpause"), (0xB5, "Next track", "next"), (0xB6, "Previous track", "prev"),
        (0xB7, "Stop", "stop"), (0x6F, "Display brighter", "brightnessup"), (0x70, "Display dimmer", "brightnessdown"),
        (0x192, "Calculator", "calculator"), (0x18A, "Mail", "mail"), (0x223, "Browser home", "home"),
        (0x221, "Search", "search"), (0x224, "Browser back", "back"), (0x225, "Browser forward", "forward"),
        (0x227, "Browser refresh", "refresh"),
    ]

    public static func name(for usage: UInt16) -> String {
        all.first { $0.usage == usage }?.name ?? String(format: "Media 0x%04X", usage)
    }

    public static func usage(token: String) -> UInt16? {
        let t = token.lowercased()
        if t.hasPrefix("0x"), let v = UInt16(t.dropFirst(2), radix: 16) { return v }
        return all.first { $0.token == t }?.usage
    }
}
