import SwiftUI
import SDPadKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderBar()
                Rectangle().fill(Theme.hairline).frame(height: 1)
                if model.pad != nil {
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 22) {
                                PadStage()
                                LightingPanel()
                            }
                            .padding(26)
                            .frame(maxWidth: .infinity)
                        }
                        Rectangle().fill(Theme.hairline).frame(width: 1)
                        Inspector()
                            .frame(width: 330)
                            .background(Color.black.opacity(0.22))
                    }
                } else {
                    EmptyState()
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .alert("Pad error", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Reload") { model.reload() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 18) {
            if model.pads.count > 1 {
                Picker("Pad", selection: Binding(get: { model.padID ?? 0 }, set: { id in
                    if let pad = model.pads.first(where: { $0.locationID == id }) { model.select(pad) }
                })) {
                    ForEach(model.pads, id: \.locationID) { Text($0.model.name).tag($0.locationID) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else if let pad = model.pad {
                Text(pad.model.name).font(.system(size: 15, weight: .semibold, design: .rounded))
            } else {
                Text("SD Macro Pad").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            if let info = model.info {
                ProfileChips(count: max(info.profileCount, 1), selected: info.profile)
                Text("v\(info.firmware)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Firmware version on this pad")
            }
            Spacer()
            if model.loading { ProgressView().controlSize(.small) }
            notices
            Button { openWindow(id: "tools") } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .help("Diagnostics, key test, console and firmware")
            Button { model.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                .disabled(model.pad == nil)
                .help("Read the settings from the pad again")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.25))
    }

    @ViewBuilder private var notices: some View {
        if model.bootloaderPresent {
            Label("A pad is in bootloader mode", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Replug it without holding any keys to return to normal")
        }
        if !model.legacyPads.isEmpty {
            Label("\(model.legacyPads.count) pad needs a firmware update", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("\(model.legacyPads.joined(separator: ", ")): update to firmware v105 from Tools ▸ Firmware to unlock every setting.")
        }
    }
}

private struct ProfileChips: View {
    @EnvironmentObject private var model: AppModel
    let count: Int
    let selected: Int

    var body: some View {
        HStack(spacing: 6) {
            SectionLabel("Profile")
            ForEach(0..<count, id: \.self) { index in
                Button { model.selectProfile(index) } label: {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(index == selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08))))
                        .foregroundStyle(index == selected ? Color.white : Color.white.opacity(0.65))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile \(index + 1)")
                .accessibilityAddTraits(index == selected ? .isSelected : [])
            }
        }
        .help("Each profile stores its own key and dial assignments. The pad blinks key 1 to show the profile number.")
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(pulse ? 0.22 : 0.08)).frame(width: 230, height: 230).blur(radius: 50)
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            }
            .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true } }
            if model.bootloaderPresent {
                Text("The pad is in bootloader mode").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Unplug it and plug it back in without holding any keys, or open the firmware tools to back it up or flash it.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Open Firmware Tools") { openWindow(id: "tools") }.controlSize(.large)
            } else if !model.legacyPads.isEmpty {
                Text("Ready for a firmware update").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("\(model.legacyPads.joined(separator: ", ")) is on its factory firmware.\nUpdate it to v105 from Tools ▸ Firmware to unlock remapping, lighting and macros.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Open Firmware Tools") { openWindow(id: "tools") }.controlSize(.large)
            } else {
                Text("Plug in a pad").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Connect a 6-key or 16-key SIDE-KEYBOARD macro pad and it appears here.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pad picture

/// The pad, drawn with its LEDs doing what the lighting settings say.
private struct PadStage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pad = model.pad {
            let animated = !reduceMotion && model.light.effect != .off && model.light.effect != .perKey
                && !(model.light.effect == .solid && model.light.singleColour)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
                let preview = LightPreview(light: model.light, colours: model.colours, columns: pad.model.columns,
                                           time: animated ? context.date.timeIntervalSinceReferenceDate : 0)
                PadBody(padModel: pad.model, preview: preview)
            }
        }
    }
}

private struct PadBody: View {
    let padModel: PadModel
    let preview: LightPreview

    var body: some View {
        let size: CGFloat = padModel.columns > 3 ? 72 : 96
        ZStack {
            Ellipse()
                .fill(preview.ambient.opacity(preview.light.effect == .off ? 0.05 : 0.20))
                .blur(radius: 70)
                .padding(-10)
            HStack(alignment: .center, spacing: 34) {
                VStack(spacing: 12) {
                    ForEach(0..<padModel.rows, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(0..<padModel.columns, id: \.self) { column in
                                let index = padModel.keyIndex(row: row, column: column)
                                KeyCap(index: index, size: size, glow: preview.glow(forKey: index))
                            }
                        }
                    }
                }
                VStack(spacing: 16) {
                    ForEach(0..<padModel.knobCount, id: \.self) { KnobView(knob: $0) }
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.085)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            )
        }
    }
}

private struct KeyCap: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let size: CGFloat
    let glow: (colour: Color, strength: Double)?

    private var selected: Bool { model.selection == .key(index) }

    var body: some View {
        let corner: CGFloat = size * 0.19
        Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { model.selection = .key(index) } } label: {
            ZStack {
                if let glow {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(glow.colour)
                        .opacity(0.55 * glow.strength)
                        .blur(radius: 13)
                    RoundedRectangle(cornerRadius: corner)
                        .strokeBorder(glow.colour.opacity(0.95 * glow.strength), lineWidth: 2.5)
                }
                RoundedRectangle(cornerRadius: corner - 2)
                    .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.13)], startPoint: .top, endPoint: .bottom))
                    .padding(3)
                RoundedRectangle(cornerRadius: corner - 5)
                    .fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.23)], startPoint: .top, endPoint: .bottom))
                    .padding(9)
                VStack(spacing: 0) {
                    Text("\(index + 1)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(model.entry(for: .key(index)).summary)
                        .font(.system(size: size > 80 ? 13 : 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                if selected {
                    RoundedRectangle(cornerRadius: corner + 3)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .padding(-5)
                        .shadow(color: .white.opacity(0.5), radius: 6)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(selected ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Key \(index + 1), \(model.entry(for: .key(index)).summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct KnobView: View {
    @EnvironmentObject private var model: AppModel
    let knob: Int

    /// Alternating light and dark slivers that read as a knurled metal edge.
    private static let knurl: AngularGradient = {
        var stops: [Gradient.Stop] = []
        let count = 48
        for i in 0...count {
            stops.append(.init(color: Color(white: i % 2 == 0 ? 0.42 : 0.16), location: Double(i) / Double(count)))
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
    }()

    var body: some View {
        VStack(spacing: 7) {
            press
            HStack(spacing: 6) {
                turn(.counterClockwise, symbol: "arrow.counterclockwise")
                turn(.clockwise, symbol: "arrow.clockwise")
            }
        }
    }

    private func select(_ slot: Slot) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { model.selection = slot }
    }

    private var press: some View {
        let slot = Slot.knob(knob, .press)
        let selected = model.selection == slot
        return Button { select(slot) } label: {
            ZStack {
                Circle().fill(KnobView.knurl).shadow(color: .black.opacity(0.55), radius: 7, y: 5)
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                    .padding(6)
                Capsule().fill(Color.white.opacity(0.85)).frame(width: 3, height: 9).offset(y: -27)
                VStack(spacing: 1) {
                    Text("DIAL \(knob + 1)").font(.system(size: 8.5, weight: .semibold)).kerning(0.8).foregroundStyle(.white.opacity(0.45))
                    Text(model.entry(for: slot).summary)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.65)
                }
                .padding(.horizontal, 12)
                .offset(y: 4)
                if selected {
                    Circle().strokeBorder(Color.white, lineWidth: 2).padding(-5).shadow(color: .white.opacity(0.5), radius: 6)
                }
            }
            .frame(width: 80, height: 80)
            .scaleEffect(selected ? 1.04 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.title), \(model.entry(for: slot).summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func turn(_ part: KnobPart, symbol: String) -> some View {
        let slot = Slot.knob(knob, part)
        let selected = model.selection == slot
        return Button { select(slot) } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                Text(model.entry(for: slot).summary)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 6)
            .frame(width: 86, height: 46)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selected ? 0.16 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.white : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.title), \(model.entry(for: slot).summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Lighting

private struct LightingPanel: View {
    @EnvironmentObject private var model: AppModel

    private func update(_ change: (inout LightConfig) -> Void) {
        var light = model.light
        change(&light)
        model.setLight(light)
    }

    private func level(_ keyPath: WritableKeyPath<LightConfig, UInt8>) -> Binding<Double> {
        Binding(get: { Double(model.light[keyPath: keyPath]) }, set: { value in
            update { $0[keyPath: keyPath] = UInt8(value.rounded()) }
        })
    }

    private static let icons: [LightEffect: String] = [
        .off: "lightbulb.slash", .solid: "circle.fill", .breathing: "waveform.path",
        .lightOnPress: "hand.tap", .tide: "water.waves", .perKey: "square.grid.3x2.fill",
    ]

    var body: some View {
        let effect = model.light.effect
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Lighting")
                HStack(spacing: 8) {
                    ForEach(LightEffect.allCases) { item in
                        EffectChip(title: item.title, symbol: LightingPanel.icons[item] ?? "circle", selected: effect == item) {
                            update { $0.mode = item.rawValue }
                        }
                    }
                }
                if effect?.hasColour == true {
                    HStack(spacing: 12) {
                        Text("Colour").frame(width: 76, alignment: .leading)
                        Picker("Colour", selection: Binding(get: { model.light.singleColour }, set: { value in update { $0.singleColour = value } })) {
                            Text("Rainbow").tag(false)
                            Text("One colour").tag(true)
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                        if model.light.singleColour {
                            PadColourPicker("Colour", colour: model.light.colour, showsLabel: false) { colour in
                                update { $0.colour = colour }
                            }
                            .id("light-\(model.revision)")
                        }
                    }
                }
                if effect == .tide {
                    Text("Tide always runs its own rainbow.").foregroundStyle(.secondary).font(.callout)
                }
                if effect == .perKey {
                    Text("Select a key above, then set its colour in the panel on the right.").foregroundStyle(.secondary).font(.callout)
                }
                if effect == .lightOnPress {
                    Text("Keys stay dark and light up when pressed.").foregroundStyle(.secondary).font(.callout)
                }
                if effect != .off {
                    HStack(spacing: 12) {
                        Text("Brightness").frame(width: 76, alignment: .leading)
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: level(\.brightness), in: 0...4, step: 1).frame(maxWidth: 260)
                        Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                    }
                }
                if effect?.hasSpeed == true {
                    HStack(spacing: 12) {
                        Text("Speed").frame(width: 76, alignment: .leading)
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: level(\.speed), in: 0...4, step: 1).frame(maxWidth: 260)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct EffectChip: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.06))))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(selected ? 0.3 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
