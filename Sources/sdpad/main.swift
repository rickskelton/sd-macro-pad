import Foundation
import SDPadKit

let usage = """
sdpad: configure SDINNOVATION "SIDE-KEYBOARD" macro pads (firmware v105)

  sdpad list                              connected pads
  sdpad info                              firmware, profile, lighting
  sdpad keys                              what every key and dial does
  sdpad set <slot> <action>               remap one control
  sdpad light [effect] [options]          lighting
  sdpad colour <key|all> <#rrggbb>        per-key colour (shown by the perkey effect)
  sdpad profile [1-6]                     show or switch the active profile
  sdpad macro <1-16> show|clear|text "…"|keys "cmd+c, cmd+v"
  sdpad raw "05"                          send 06 + these hex bytes, print the answer
  sdpad listen [seconds]                  print what the pads send when used
  sdpad firmware dump <out.bin>           back up a pad that is in bootloader mode
  sdpad firmware flash <image.bin> [--force]
  sdpad firmware id <image.bin>

Options:  --pad 6|16    choose a pad when more than one is connected

Slots:    1–16 (keys, row by row from the top-left), d1 d1cw d1ccw (dial press, clockwise,
          anticlockwise; d2…, d3… on the 16-key)
Actions:  cmd+shift+4 · f13 · ctrl+a · media:playpause|next|prev|mute|volup|voldown|…
          mouse:left|right|middle|back|forward · scroll:up|down[:steps]
          macro:<1-16>[:repeats] · system:sleep|power|wake · none · raw:20,01,04,00
Light:    effect = off|solid|breathing|press|tide|perkey
          --colour #rrggbb|rainbow   --brightness 0-4   --speed 0-4
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func column(_ text: String, _ width: Int) -> String { text.padding(toLength: max(width, text.count + 1), withPad: " ", startingAt: 0) }

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

var args = Array(CommandLine.arguments.dropFirst())
var padChoice: Int?
if let i = args.firstIndex(of: "--pad"), i + 1 < args.count {
    padChoice = Int(args[i + 1])
    args.removeSubrange(i...i + 1)
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...i + 1)
    return value
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

func connectedPad() -> Pad {
    let snapshot = PadMonitor().settle()
    var pads = snapshot.pads
    if let choice = padChoice { pads = pads.filter { $0.model.keyCount == choice } }
    if pads.count == 1 { return pads[0] }
    if pads.isEmpty {
        if !snapshot.legacyPads.isEmpty {
            fail("Found \(snapshot.legacyPads.joined(separator: ", ")) on the factory firmware, which has no configuration interface. See docs/TECHNICAL_REFERENCE.md, \"Updating the firmware\".")
        }
        fail(snapshot.bootloaderPresent ? "The pad is in bootloader mode. Replug it without holding keys." : "No pad found.")
    }
    fail("More than one pad is connected. Add --pad 6 or --pad 16.")
}

func parseSlot(_ text: String, _ model: PadModel) -> Int {
    let t = text.lowercased()
    if let n = Int(t), n >= 1, n <= model.keyCount { return n - 1 }
    if t.hasPrefix("i"), let n = Int(t.dropFirst()) { return n }
    if t.hasPrefix("d"), let knob = Int(t.dropFirst().prefix(1)), knob >= 1, knob <= model.knobCount {
        switch String(t.dropFirst(2)) {
        case "": return model.knobIndex(knob - 1, .press)
        case "cw": return model.knobIndex(knob - 1, .clockwise)
        case "ccw": return model.knobIndex(knob - 1, .counterClockwise)
        default: break
        }
    }
    fail("Unknown slot \"\(text)\". Use 1–\(model.keyCount), or d1, d1cw, d1ccw.")
}

func parseAction(_ text: String) -> KeyEntry {
    let parts = text.split(separator: ":").map(String.init)
    switch parts[0].lowercased() {
    case "none", "off", "disabled":
        return .disabled
    case "media":
        guard parts.count == 2, let u = ConsumerKeys.usage(token: parts[1]) else {
            fail("Unknown media key. Known: " + ConsumerKeys.all.map { $0.token }.joined(separator: ", ") + ", or 0x<usage>.")
        }
        return .consumer(u)
    case "mouse":
        let buttons: [String: UInt8] = ["left": 1, "right": 2, "middle": 4, "back": 8, "forward": 16]
        guard parts.count == 2, let b = buttons[parts[1].lowercased()] else { fail("mouse:left|right|middle|back|forward") }
        return .mouse(buttons: b)
    case "scroll":
        guard parts.count >= 2 else { fail("scroll:up|down[:steps]") }
        let steps = parts.count > 2 ? (Int(parts[2]) ?? 1) : 1
        return .mouse(wheel: Int8(parts[1].lowercased() == "up" ? steps : -steps))
    case "macro":
        guard parts.count >= 2, let n = Int(parts[1]), n >= 1, n <= Macro.slotCount else { fail("macro:<1-16>[:repeats]") }
        return .macro(n - 1, count: parts.count > 2 ? (Int(parts[2]) ?? 1) : 1)
    case "system":
        let values: [String: UInt8] = ["power": 1, "sleep": 2, "wake": 4]
        guard parts.count == 2, let v = values[parts[1].lowercased()] else { fail("system:power|sleep|wake") }
        return KeyEntry(type: KeyEntry.Kind.system.rawValue, code1: v)
    case "raw":
        let bytes = (parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 4 else { fail("raw:<type>,<c1>,<c2>,<c3> in hex") }
        return KeyEntry(bytes: bytes)
    default:
        guard let entry = KeyNames.parseShortcut(text) else { fail("Cannot read \"\(text)\" as a shortcut. Example: cmd+shift+4") }
        return entry
    }
}

func slotName(_ index: Int, _ model: PadModel) -> String {
    if index < PadModel.firstKnobIndex { return "key \(index + 1)" }
    let knob = (index - PadModel.firstKnobIndex) / 3 + 1
    return "d\(knob)" + ["", "cw", "ccw"][(index - PadModel.firstKnobIndex) % 3]
}

func describe(_ light: LightConfig) -> String {
    var s = light.effect?.title ?? "mode \(light.mode)"
    if light.effect?.hasColour == true { s += light.singleColour ? ", \(light.colour.hex)" : ", rainbow" }
    s += ", brightness \(light.brightness)"
    if light.effect?.hasSpeed == true { s += ", speed \(light.speed)" }
    return s
}

do {
    switch command {
    case "help", "-h", "--help":
        print(usage)

    case "list":
        let snapshot = PadMonitor().settle()
        for pad in snapshot.pads {
            let info = try pad.info()
            print(String(format: "%@  %04X:%04X  firmware v%d  profile %d/%d", pad.model.name, pad.vendorID, pad.productID,
                         info.firmware, info.profile + 1, info.profileCount))
        }
        for name in snapshot.legacyPads { print("\(name)  factory firmware, not configurable until updated") }
        if snapshot.bootloaderPresent { print("A pad is in bootloader mode") }
        if snapshot.pads.isEmpty && snapshot.legacyPads.isEmpty && !snapshot.bootloaderPresent { print("No pad found.") }

    case "info":
        let pad = connectedPad()
        let info = try pad.info()
        print("\(pad.model.name)  (\(pad.productName), \(String(format: "%04X:%04X", pad.vendorID, pad.productID)))")
        print("Firmware v\(info.firmware), protocol \(info.protocolVersion)")
        print("Profile \(info.profile + 1) of \(info.profileCount)")
        print("Lighting: " + describe(try pad.readLight()))

    case "keys":
        let pad = connectedPad()
        let entries = try pad.readKeys()
        let colours = try pad.readKeyColours()
        for index in 0..<pad.model.keyCount {
            print(column(slotName(index, pad.model), 8) + column(entries[index].summary, 24) + colours[index].hex + "   [" + hex(entries[index].bytes) + "]")
        }
        for index in PadModel.firstKnobIndex..<pad.model.entryCount {
            print(column(slotName(index, pad.model), 8) + column(entries[index].summary, 24) + "          [" + hex(entries[index].bytes) + "]")
        }

    case "set":
        guard args.count == 2 else { fail("sdpad set <slot> <action>") }
        let pad = connectedPad()
        let index = parseSlot(args[0], pad.model)
        let entry = parseAction(args[1])
        try pad.writeKey(index, entry)
        let stored = try pad.readKeys()[index]
        guard stored == entry else { fail("The pad stored \(hex(stored.bytes)) instead of \(hex(entry.bytes))") }
        print("\(slotName(index, pad.model)) → \(entry.summary)")

    case "light":
        let pad = connectedPad()
        var light = try pad.readLight()
        let colour = option("--colour") ?? option("--color")
        let brightness = option("--brightness")
        let speed = option("--speed")
        if let name = args.first {
            let effects: [String: LightEffect] = ["off": .off, "solid": .solid, "breathing": .breathing, "press": .lightOnPress, "tide": .tide, "perkey": .perKey]
            guard let effect = effects[name.lowercased()] else { fail("Effects: off, solid, breathing, press, tide, perkey") }
            light.mode = effect.rawValue
        }
        if let colour {
            if colour.lowercased() == "rainbow" { light.singleColour = false }
            else if let rgb = RGB(hex: colour) { light.singleColour = true; light.colour = rgb }
            else { fail("--colour takes #rrggbb or rainbow") }
        }
        if let brightness { light.brightness = UInt8(min(4, max(0, Int(brightness) ?? 4))) }
        if let speed { light.speed = UInt8(min(4, max(0, Int(speed) ?? 2))) }
        if args.first != nil || colour != nil || brightness != nil || speed != nil { try pad.writeLight(light) }
        print(describe(try pad.readLight()))

    case "colour", "color":
        guard args.count == 2, let rgb = RGB(hex: args[1]) else { fail("sdpad colour <key|all> <#rrggbb>") }
        let pad = connectedPad()
        let keys = args[0].lowercased() == "all" ? Array(0..<pad.model.keyCount) : [parseSlot(args[0], pad.model)]
        for key in keys where key < pad.model.keyCount { try pad.writeKeyColour(key, rgb) }
        print("Set \(keys.count) key colour\(keys.count == 1 ? "" : "s") to \(rgb.hex). They show with: sdpad light perkey")

    case "profile":
        let pad = connectedPad()
        if let text = args.first {
            let count = try pad.info().profileCount
            guard let n = Int(text), n >= 1, n <= count else { fail("Profiles are 1–\(count)") }
            try pad.selectProfile(n - 1)
        }
        let info = try pad.info()
        print("Profile \(info.profile + 1) of \(info.profileCount)")

    case "macro":
        guard args.count >= 2, let n = Int(args[0]), n >= 1, n <= Macro.slotCount else { fail("sdpad macro <1-16> show|clear|text \"…\"|keys \"cmd+c, cmd+v\"") }
        let pad = connectedPad()
        var macros = try pad.readMacros()
        switch args[1] {
        case "show":
            if macros[n - 1].isEmpty { print("Macro \(n) is empty") }
            for action in macros[n - 1] { print(String(format: "%5d ms  %@", action.delay, action.summary)) }
        case "clear":
            macros[n - 1] = []
            try pad.writeMacros(macros)
            print("Macro \(n) cleared")
        case "text":
            guard args.count == 3 else { fail("sdpad macro \(n) text \"hello\"") }
            macros[n - 1] = Macro.typing(args[2])
            try pad.writeMacros(macros)
            print("Macro \(n): \(macros[n - 1].count) steps. Assign it with: sdpad set <slot> macro:\(n)")
        case "keys":
            guard args.count == 3 else { fail("sdpad macro \(n) keys \"cmd+c, cmd+v\"") }
            macros[n - 1] = args[2].split(separator: ",").flatMap { part -> [MacroAction] in
                guard let entry = KeyNames.parseShortcut(String(part)) else { fail("Cannot read \"\(part)\" as a shortcut") }
                return Macro.shortcut(entry)
            }
            try pad.writeMacros(macros)
            print("Macro \(n): \(macros[n - 1].count) steps. Assign it with: sdpad set <slot> macro:\(n)")
        default:
            fail("sdpad macro <1-16> show|clear|text \"…\"|keys \"cmd+c, cmd+v\"")
        }

    case "raw":
        guard let text = args.first else { fail("sdpad raw \"05\"") }
        let bytes = text.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { fail("Give the payload as hex bytes, without the leading 06") }
        print(hex(try connectedPad().request(bytes)))

    case "listen":
        let seconds = Double(args.first ?? "30") ?? 30
        print("Listening for \(Int(seconds)) s. Press keys and turn dials.")
        PadListener().run(for: seconds) { product, page, report in
            print(String(format: "%04X %@  %@", product, page == 0xFF00 ? "cfg" : "in ", hex(report)))
        }

    case "firmware":
        guard let sub = args.first else { fail("sdpad firmware dump|flash|id …") }
        args.removeFirst()
        switch sub {
        case "id":
            guard let path = args.first, let data = FileManager.default.contents(atPath: path) else { fail("sdpad firmware id <image.bin>") }
            guard let id = Bootloader.deviceID(inImage: [UInt8](data)) else { fail("No USB device descriptor found in the application area") }
            print(String(format: "%04X:%04X  %@", id.vendorID, id.productID, PadModel.lookup(vendorID: id.vendorID, productID: id.productID)?.name ?? "unknown model"))
        case "dump":
            guard let path = args.first else { fail("sdpad firmware dump <out.bin>") }
            let flash = try Bootloader().read()
            try Data(flash).write(to: URL(fileURLWithPath: path))
            let id = Bootloader.deviceID(inImage: flash)
            print("Wrote \(flash.count) bytes to \(path)" + (id.map { String(format: " (application is %04X:%04X)", $0.vendorID, $0.productID) } ?? ""))
        case "flash":
            let force = flag("--force")
            guard let path = args.first, let data = FileManager.default.contents(atPath: path) else { fail("sdpad firmware flash <image.bin> [--force]") }
            let image = [UInt8](data)
            guard image.count == Bootloader.flashSize else { fail("A firmware image is exactly \(Bootloader.flashSize) bytes; this file is \(image.count).") }
            let bootloader = try Bootloader()
            let current = try bootloader.read()
            let backup = FileManager.default.temporaryDirectory.appendingPathComponent("sdpad-backup-\(Int(Date().timeIntervalSince1970)).bin")
            try Data(current).write(to: backup)
            print("Backed up the pad's current flash to \(backup.path)")
            let have = Bootloader.deviceID(inImage: current), want = Bootloader.deviceID(inImage: image)
            if !force {
                guard let want else { fail("This image has no USB device descriptor where one is expected. It may be misaligned. Use --force to flash it anyway.") }
                guard let have else { fail("Cannot tell which model this pad is from its current flash. Check the image is for this pad, then use --force.") }
                guard have == want else {
                    fail(String(format: "The pad is %04X:%04X but the image is for %04X:%04X. Use --force only if you are sure.", have.vendorID, have.productID, want.vendorID, want.productID))
                }
            }
            try bootloader.writeApplication(image: image) { fraction in
                print(String(format: "\rWriting %3d%%", Int(fraction * 100)), terminator: "")
                fflush(stdout)
            }
            print("\nVerified. Unplug the pad and plug it back in without holding any keys.")
        default:
            fail("sdpad firmware dump|flash|id …")
        }

    default:
        fail("Unknown command \"\(command)\".\n\n" + usage)
    }
} catch {
    fail("\(error)")
}
