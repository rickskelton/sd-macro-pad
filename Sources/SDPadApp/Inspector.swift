import SwiftUI
import SDPadKit

private enum ActionKind: String, CaseIterable, Identifiable {
    case keystroke = "Keystroke"
    case media = "Media key"
    case mouse = "Mouse"
    case macro = "Macro"
    case system = "System"
    case nothing = "Nothing"

    var id: String { rawValue }

    init(_ entry: KeyEntry) {
        switch entry.kind {
        case .key: self = (entry.code1 == 0 && entry.code2 == 0) ? .nothing : .keystroke
        case .consumer: self = .media
        case .mouse: self = .mouse
        case .macro: self = .macro
        case .system: self = .system
        default: self = .nothing
        }
    }

    var defaultEntry: KeyEntry {
        switch self {
        case .keystroke: return .key(0x68)
        case .media: return .consumer(0xCD)
        case .mouse: return .mouse(buttons: 1)
        case .macro: return .macro(0)
        case .system: return KeyEntry(type: KeyEntry.Kind.system.rawValue, code1: 2)
        case .nothing: return .disabled
        }
    }
}

struct Inspector: View {
    @EnvironmentObject private var model: AppModel

    private var slot: Slot { model.selection }
    private var headline: String {
        if case .key = slot { return "Key" }
        return "Dial"
    }
    private var entry: KeyEntry { model.entry(for: slot) }
    private func set(_ entry: KeyEntry) { model.setEntry(entry, for: slot) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(headline)
                    Text(slot.title).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(entry.summary).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent)
                }

                SectionLabel("Action")
                Picker("Action", selection: Binding(get: { ActionKind(entry) }, set: { kind in
                    if kind != ActionKind(entry) { set(kind.defaultEntry) }
                })) {
                    ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()

                switch ActionKind(entry) {
                case .keystroke: keystroke
                case .media: media
                case .mouse: mouse
                case .macro: macro
                case .system: system
                case .nothing:
                    Text("Switched off.").foregroundStyle(.secondary)
                }

                if entry.kind == nil && entry.type != 0 || entry.kind == .padFunction {
                    Text("Custom action on the pad: \(entry.summary). Choose an action above to replace it.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                if case .key(let index) = slot, index < model.colours.count {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    SectionLabel("Key light")
                    PadColourPicker("Key colour", colour: model.colours[index]) { model.setColour($0, forKey: index) }
                        .id("key-\(index)-\(model.revision)")
                    if model.light.effect == .perKey {
                        Text("Showing now.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Shown with the Per-key colours effect.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Switch to Per-key colours") {
                            var light = model.light
                            light.mode = LightEffect.perKey.rawValue
                            model.setLight(light)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $model.editingMacros) {
            MacroEditor(macros: model.macros, selected: Int(entry.kind == .macro ? entry.code1 : 0))
        }
    }

    // MARK: Keystroke

    private func modifier(_ left: Modifiers, _ right: Modifiers) -> Binding<Bool> {
        Binding(get: { !entry.modifiers.intersection([left, right]).isEmpty }, set: { on in
            var mods = entry.modifiers
            mods.subtract([left, right])
            if on { mods.insert(left) }
            set(.key(entry.code2, mods))
        })
    }

    @ViewBuilder private var keystroke: some View {
        HStack(spacing: 6) {
            ModifierChip(symbol: "⌃", name: "Control", isOn: modifier(.control, .rightControl))
            ModifierChip(symbol: "⌥", name: "Option", isOn: modifier(.option, .rightOption))
            ModifierChip(symbol: "⇧", name: "Shift", isOn: modifier(.shift, .rightShift))
            ModifierChip(symbol: "⌘", name: "Command", isOn: modifier(.command, .rightCommand))
        }
        Picker("Key", selection: Binding(get: { entry.code2 }, set: { set(.key($0, entry.modifiers)) })) {
            Text("None (modifiers only)").tag(UInt8(0))
            ForEach(KeyNames.all, id: \.usage) { Text($0.name).tag($0.usage) }
            if entry.code2 != 0 && !KeyNames.all.contains(where: { $0.usage == entry.code2 }) {
                Text(KeyNames.name(forUsage: entry.code2)).tag(entry.code2)
            }
        }
        ShortcutRecorder { set($0) }
        Text("F13–F24 are free in every app. For system shortcuts such as ⌘Tab, use the controls above.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Media, mouse, system

    private var media: some View {
        Picker("Media key", selection: Binding(get: { entry.consumerUsage }, set: { set(.consumer($0)) })) {
            ForEach(ConsumerKeys.all, id: \.usage) { Text($0.name).tag($0.usage) }
            if !ConsumerKeys.all.contains(where: { $0.usage == entry.consumerUsage }) {
                Text(ConsumerKeys.name(for: entry.consumerUsage)).tag(entry.consumerUsage)
            }
        }
    }

    private enum MouseAction: String, CaseIterable, Identifiable {
        case left = "Left click", right = "Right click", middle = "Middle click"
        case back = "Back button", forward = "Forward button"
        case scrollUp = "Scroll up", scrollDown = "Scroll down"
        var id: String { rawValue }
    }

    private var mouseAction: MouseAction {
        if entry.wheel > 0 { return .scrollUp }
        if entry.wheel < 0 { return .scrollDown }
        switch entry.code1 {
        case 2: return .right
        case 4: return .middle
        case 8: return .back
        case 16: return .forward
        default: return .left
        }
    }

    private func mouseEntry(_ action: MouseAction, steps: Int) -> KeyEntry {
        switch action {
        case .left: return .mouse(buttons: 1)
        case .right: return .mouse(buttons: 2)
        case .middle: return .mouse(buttons: 4)
        case .back: return .mouse(buttons: 8)
        case .forward: return .mouse(buttons: 16)
        case .scrollUp: return .mouse(wheel: Int8(steps))
        case .scrollDown: return .mouse(wheel: Int8(-steps))
        }
    }

    @ViewBuilder private var mouse: some View {
        let steps = max(1, abs(Int(entry.wheel)))
        Picker("Mouse", selection: Binding(get: { mouseAction }, set: { set(mouseEntry($0, steps: steps)) })) {
            ForEach(MouseAction.allCases) { Text($0.rawValue).tag($0) }
        }
        if entry.wheel != 0 {
            Stepper("Steps per press: \(steps)", value: Binding(get: { steps }, set: { set(mouseEntry(mouseAction, steps: $0)) }), in: 1...10)
        }
    }

    private var system: some View {
        Picker("System", selection: Binding(get: { entry.code1 }, set: { set(KeyEntry(type: KeyEntry.Kind.system.rawValue, code1: $0)) })) {
            Text("Sleep").tag(UInt8(2))
            Text("Power").tag(UInt8(1))
            Text("Wake").tag(UInt8(4))
        }
    }

    // MARK: Macro

    @ViewBuilder private var macro: some View {
        let index = Int(entry.code1)
        Picker("Macro", selection: Binding(get: { index }, set: { set(.macro($0, count: Int(max(entry.code2, 1)), mode: Int(entry.code3))) })) {
            ForEach(0..<Macro.slotCount, id: \.self) { i in
                Text("Macro \(i + 1)" + (model.macros[i].isEmpty ? " (empty)" : " · \(model.macros[i].count) steps")).tag(i)
            }
        }
        Picker("Play", selection: Binding(get: { Int(entry.code3) }, set: { set(.macro(index, count: Int(max(entry.code2, 1)), mode: $0)) })) {
            Text("A set number of times").tag(0)
            Text("Repeat while held").tag(1)
            Text("Repeat until any key").tag(2)
            Text("Repeat until pressed again").tag(3)
        }
        if entry.code3 == 0 {
            let count = Int(max(entry.code2, 1))
            Stepper("Times: \(count)", value: Binding(get: { count }, set: { set(.macro(index, count: $0, mode: 0)) }), in: 1...255)
        }
        Button("Edit macros…") { model.editingMacros = true }
        if index < model.macros.count && model.macros[index].isEmpty {
            Text("Add steps with Edit macros.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModifierChip: View {
    let symbol: String
    let name: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 2) {
                Text(symbol).font(.system(size: 17, weight: .medium))
                Text(name).font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.06))))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(isOn ? 0.3 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
