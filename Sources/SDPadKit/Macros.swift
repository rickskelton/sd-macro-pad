import Foundation

public struct MacroAction: Equatable, Hashable, Identifiable {
    public enum Kind: UInt8 {
        case mouseButton = 3, key = 2, scrollVertical = 4, scrollHorizontal = 5
    }

    public let id = UUID()
    public var kind: Kind
    public var down: Bool
    public var code: UInt8
    public var delay: UInt16

    public init(kind: Kind = .key, down: Bool, code: UInt8, delay: UInt16 = 10) {
        self.kind = kind; self.down = down; self.code = code; self.delay = delay
    }

    public static func == (a: MacroAction, b: MacroAction) -> Bool {
        a.kind == b.kind && a.down == b.down && a.code == b.code && a.delay == b.delay
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind); hasher.combine(down); hasher.combine(code); hasher.combine(delay)
    }

    public var summary: String {
        switch kind {
        case .key: return (down ? "Press " : "Release ") + Macro.keyName(code)
        case .mouseButton: return (down ? "Mouse down " : "Mouse up ") + String(code)
        case .scrollVertical: return code == 1 ? "Scroll up" : "Scroll down"
        case .scrollHorizontal: return code == 1 ? "Scroll right" : "Scroll left"
        }
    }
}

// Macro table, 4096 bytes, shared by all profiles.
// 0-63: little-endian start offset per macro, FF FF = empty.
// From 64: 4 bytes per action = delay lo, delay hi, flags, code.
// flags: bits 0-2 kind, 0x40 press, 0x80 last action.
public enum Macro {
    public static let tableSize = 4096
    public static let slotCount = 16
    private static let headerSize = 64

    public static func decode(_ table: [UInt8]) -> [[MacroAction]] {
        var result = [[MacroAction]](repeating: [], count: slotCount)
        guard table.count >= headerSize else { return result }
        for slot in 0..<slotCount {
            var offset = Int(table[2 * slot]) | Int(table[2 * slot + 1]) << 8
            guard offset >= headerSize, offset != 0xFFFF else { continue }
            while offset + 4 <= table.count {
                let flags = table[offset + 2]
                guard let kind = MacroAction.Kind(rawValue: flags & 0x07) else { break }
                result[slot].append(MacroAction(kind: kind, down: flags & 0x40 != 0, code: table[offset + 3],
                                                delay: UInt16(table[offset]) | UInt16(table[offset + 1]) << 8))
                if flags & 0x80 != 0 { break }
                offset += 4
            }
        }
        return result
    }

    public static func encode(_ macros: [[MacroAction]]) throws -> [UInt8] {
        var table = [UInt8](repeating: 0xFF, count: headerSize) + [UInt8](repeating: 0, count: tableSize - headerSize)
        var offset = headerSize
        for (slot, actions) in macros.prefix(slotCount).enumerated() where !actions.isEmpty {
            guard offset + 4 * actions.count <= tableSize else { throw PadError.usage("Macros need more than the pad's 4096 bytes") }
            table[2 * slot] = UInt8(offset & 0xFF)
            table[2 * slot + 1] = UInt8(offset >> 8)
            for (i, action) in actions.enumerated() {
                var flags = action.kind.rawValue
                if action.down { flags |= 0x40 }
                if i == actions.count - 1 { flags |= 0x80 }
                table[offset] = UInt8(action.delay & 0xFF)
                table[offset + 1] = UInt8(action.delay >> 8)
                table[offset + 2] = flags
                table[offset + 3] = action.code
                offset += 4
            }
        }
        return table
    }

    public static func typing(_ text: String, delay: UInt16 = 10) -> [MacroAction] {
        var actions: [MacroAction] = []
        for character in text {
            guard let stroke = KeyNames.stroke(for: character) else { continue }
            if stroke.shift { actions.append(MacroAction(down: true, code: 0xE1, delay: delay)) }
            actions.append(MacroAction(down: true, code: stroke.usage, delay: delay))
            actions.append(MacroAction(down: false, code: stroke.usage, delay: delay))
            if stroke.shift { actions.append(MacroAction(down: false, code: 0xE1, delay: delay)) }
        }
        return actions
    }

    public static func shortcut(_ entry: KeyEntry, delay: UInt16 = 10) -> [MacroAction] {
        let modifierUsages: [(Modifiers, UInt8)] = [(.control, 0xE0), (.shift, 0xE1), (.option, 0xE2), (.command, 0xE3),
                                                    (.rightControl, 0xE4), (.rightShift, 0xE5), (.rightOption, 0xE6), (.rightCommand, 0xE7)]
        let held = modifierUsages.filter { entry.modifiers.contains($0.0) }.map { $0.1 }
        var actions = held.map { MacroAction(down: true, code: $0, delay: delay) }
        if entry.code2 != 0 {
            actions.append(MacroAction(down: true, code: entry.code2, delay: delay))
            actions.append(MacroAction(down: false, code: entry.code2, delay: delay))
        }
        actions += held.reversed().map { MacroAction(down: false, code: $0, delay: delay) }
        return actions
    }

    static func keyName(_ usage: UInt8) -> String {
        switch usage {
        case 0xE0: return "⌃ Control"
        case 0xE1: return "⇧ Shift"
        case 0xE2: return "⌥ Option"
        case 0xE3: return "⌘ Command"
        case 0xE4: return "Right ⌃"
        case 0xE5: return "Right ⇧"
        case 0xE6: return "Right ⌥"
        case 0xE7: return "Right ⌘"
        default: return KeyNames.name(forUsage: usage)
        }
    }
}
