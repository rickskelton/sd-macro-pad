import SwiftUI
import SDPadKit

final class AppModel: ObservableObject {
    @Published var pads: [Pad] = []
    @Published var legacyPads: [String] = []
    @Published var bootloaderPresent = false
    @Published var padID: Int?
    @Published var info: PadInfo?
    @Published var entries: [KeyEntry] = []
    @Published var colours: [RGB] = []
    @Published var light = LightConfig()
    @Published var macros = [[MacroAction]](repeating: [], count: Macro.slotCount)
    @Published var selection: Slot = .key(0)
    @Published var message: String?
    @Published var loading = false
    @Published var revision = 0
    @Published var editingMacros = false

    private let monitor = PadMonitor()
    private let io = DispatchQueue(label: "SDPadApp.io")
    private var pending: [String: DispatchWorkItem] = [:]

    var pad: Pad? { pads.first { $0.locationID == padID } }

    init() {
        monitor.onChange = { [weak self] snapshot in
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
        apply(monitor.snapshot())
    }

    private func apply(_ snapshot: PadMonitor.Snapshot) {
        let previous = pad
        pads = snapshot.pads
        legacyPads = snapshot.legacyPads
        bootloaderPresent = snapshot.bootloaderPresent
        if pad == nil { padID = pads.first?.locationID }
        if pad !== previous { reload() }
    }

    func select(_ pad: Pad) {
        guard pad !== self.pad else { return }
        padID = pad.locationID
        reload()
    }

    func reload() {
        guard let pad else {
            info = nil; entries = []; colours = []
            return
        }
        loading = true
        io.async {
            do {
                let info = try pad.info()
                let entries = try pad.readKeys()
                let colours = try pad.readKeyColours()
                let light = try pad.readLight()
                let macros = try pad.readMacros()
                DispatchQueue.main.async {
                    guard self.pad === pad else { return }
                    self.info = info
                    self.entries = entries
                    self.colours = colours
                    self.light = light
                    self.macros = macros
                    self.loading = false
                    self.revision += 1
                    if self.selection.index(in: pad.model) >= pad.model.entryCount { self.selection = .key(0) }
                    if case .key(let i) = self.selection, i >= pad.model.keyCount { self.selection = .key(0) }
                }
            } catch {
                self.report(error)
            }
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async {
            self.loading = false
            self.message = "\(error)"
        }
    }

    // debounce: one flash write per drag instead of dozens
    private func write(_ key: String, _ work: @escaping () throws -> Void) {
        pending[key]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.io.async {
                do { try work() } catch { self?.report(error) }
            }
        }
        pending[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    func entry(for slot: Slot) -> KeyEntry {
        guard let pad else { return .disabled }
        let index = slot.index(in: pad.model)
        return index < entries.count ? entries[index] : .disabled
    }

    func setEntry(_ entry: KeyEntry, for slot: Slot) {
        guard let pad else { return }
        let index = slot.index(in: pad.model)
        guard index < entries.count, entries[index] != entry else { return }
        entries[index] = entry
        write("key\(index)") { try pad.writeKey(index, entry) }
    }

    func setColour(_ colour: RGB, forKey index: Int) {
        guard let pad, index < colours.count, colours[index] != colour else { return }
        colours[index] = colour
        write("colour\(index)") { try pad.writeKeyColour(index, colour) }
    }

    func setLight(_ light: LightConfig) {
        guard let pad, light != self.light else { return }
        self.light = light
        write("light") { try pad.writeLight(light) }
    }

    func selectProfile(_ profile: Int) {
        guard let pad, info?.profile != profile else { return }
        info?.profile = profile
        let light = self.light
        io.async {
            do {
                try pad.selectProfile(profile)
                // pad blinks key 1 for the profile number and can leave it dark, so resend lighting after
                Thread.sleep(forTimeInterval: 0.6 + 0.5 * Double(profile + 1))
                try pad.writeLight(light)
            } catch { self.report(error) }
            DispatchQueue.main.async { self.reload() }
        }
    }

    func saveMacros(_ macros: [[MacroAction]]) {
        guard let pad else { return }
        self.macros = macros
        io.async {
            do { try pad.writeMacros(macros) } catch { self.report(error) }
        }
    }
}

// holds its own colour while editing; binding straight to the 8-bit values makes the picker jump
struct PadColourPicker: View {
    let title: String
    var showsLabel = true
    let onChange: (RGB) -> Void
    @State private var colour: Color

    init(_ title: String, colour: RGB, showsLabel: Bool = true, onChange: @escaping (RGB) -> Void) {
        self.title = title
        self.showsLabel = showsLabel
        self.onChange = onChange
        _colour = State(initialValue: colour.color)
    }

    var body: some View {
        let picker = ColorPicker(title, selection: $colour, supportsOpacity: false)
            .onChange(of: colour) { onChange(RGB($0)) }
        if showsLabel { picker } else { picker.labelsHidden() }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: UInt8((c.redComponent * 255).rounded()), g: UInt8((c.greenComponent * 255).rounded()),
                  b: UInt8((c.blueComponent * 255).rounded()))
    }
}
