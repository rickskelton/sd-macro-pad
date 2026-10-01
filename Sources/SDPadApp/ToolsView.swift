import SwiftUI
import UniformTypeIdentifiers
import SDPadKit

/// Diagnostics, key test, raw console and firmware tools, in their own window.
struct ToolsView: View {
    var body: some View {
        TabView {
            DiagnosticsTab().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            KeyTestTab().tabItem { Label("Key Test", systemImage: "keyboard") }
            ConsoleTab().tabItem { Label("Console", systemImage: "terminal") }
            FirmwareTab().tabItem { Label("Firmware", systemImage: "cpu") }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 480)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

// MARK: - Diagnostics

private struct DiagnosticsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var report = "Reading…"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(report)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Button("Refresh", action: refresh)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                Spacer()
                Text("Reads only; nothing is changed on the pad.").foregroundStyle(.secondary).font(.callout)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model.padID) { _ in refresh() }
    }

    private func refresh() {
        report = "Reading…"
        model.diagnostics { report = $0 }
    }
}

extension AppModel {
    /// A plain-text dump of everything the app can read, for troubleshooting.
    func diagnostics(_ completion: @escaping (String) -> Void) {
        let pads = self.pads, legacy = legacyPads, bootloader = bootloaderPresent
        DispatchQueue.global(qos: .userInitiated).async {
            var lines: [String] = []
            if pads.isEmpty { lines.append("No configurable pad connected.") }
            for pad in pads {
                lines.append("\(pad.model.name)  \"\(pad.productName)\"  " + String(format: "%04X:%04X  location 0x%08X", pad.vendorID, pad.productID, pad.locationID))
                if !pad.isKnownModel { lines.append("  Layout unknown: shown as 16 keys and 3 dials.") }
                do {
                    let info = try pad.info()
                    lines.append("  Firmware v\(info.firmware), protocol \(info.protocolVersion), profile \(info.profile + 1) of \(info.profileCount), layers \(info.layerCount)")
                    lines.append("  Info      " + hex(Array(try pad.request([0x05]).prefix(24))))
                    lines.append("  Lighting  " + hex(Array(try pad.request([0x0A]).prefix(16))))
                    let entries = try pad.readKeys(), colours = try pad.readKeyColours()
                    for index in 0..<pad.model.entryCount {
                        let slot = index < PadModel.firstKnobIndex ? "key \(index + 1)" : "dial slot \(index)"
                        if index >= pad.model.keyCount && index < PadModel.firstKnobIndex { continue }
                        let colour = index < colours.count ? "  \(colours[index].hex)" : ""
                        lines.append("  " + slot.padding(toLength: 13, withPad: " ", startingAt: 0) + hex(entries[index].bytes) + "  " + entries[index].summary + colour)
                    }
                    let macros = try pad.readMacros()
                    let used = macros.enumerated().filter { !$0.element.isEmpty }.map { "\($0.offset + 1) (\($0.element.count) steps)" }
                    lines.append("  Macros    " + (used.isEmpty ? "none stored" : used.joined(separator: ", ")))
                } catch {
                    lines.append("  Error: \(error)")
                }
                lines.append("")
            }
            for name in legacy { lines.append("\(name): factory firmware, no configuration interface. Update it from the Firmware tab.") }
            if bootloader { lines.append("A pad is in bootloader mode (USB 5566:0009).") }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async { completion(text) }
        }
    }
}

// MARK: - Key test

private struct KeyTestTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var events: [String] = []
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Press keys and turn dials while this window is in front. Each event is matched against what the selected pad is set to send. Mouse and macro actions are not listed.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            List(Array(events.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.body, design: .monospaced))
            }
            HStack {
                Button("Clear") { events.removeAll() }
                Spacer()
                Text("Volume and other media keys still act on the Mac while testing.").foregroundStyle(.secondary).font(.callout)
            }
        }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { event in
            if event.type == .keyDown {
                guard !event.isARepeat, let usage = KeyNames.usageForMacKeyCode[event.keyCode] else { return nil }
                var modifiers: Modifiers = []
                if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
                if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
                if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
                if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
                log(KeyEntry.key(usage, modifiers))
                return nil
            }
            // Media keys arrive as system-defined events, subtype 8; 0x0A in the flags byte is key down.
            if event.subtype.rawValue == 8, (event.data1 & 0xFF00) >> 8 == 0x0A {
                let usages: [Int: UInt16] = [0: 0xE9, 1: 0xEA, 7: 0xE2, 16: 0xCD, 17: 0xB5, 18: 0xB6, 19: 0xB5, 20: 0xB6]
                if let usage = usages[(event.data1 & 0xFFFF0000) >> 16] { log(.consumer(usage)) }
            }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func log(_ entry: KeyEntry) {
        var matches: [String] = []
        if let pad = model.pad {
            for index in 0..<min(model.entries.count, pad.model.entryCount) where normalised(model.entries[index]) == entry {
                if index < pad.model.keyCount { matches.append("Key \(index + 1)") }
                else if index >= PadModel.firstKnobIndex {
                    let knob = (index - PadModel.firstKnobIndex) / 3
                    matches.append(Slot.knob(knob, KnobPart(rawValue: (index - PadModel.firstKnobIndex) % 3)!).title)
                }
            }
        }
        let source = matches.isEmpty ? "no control on this pad is set to it" : matches.joined(separator: " or ")
        events.insert(entry.summary.padding(toLength: 18, withPad: " ", startingAt: 0) + "← " + source, at: 0)
        if events.count > 200 { events.removeLast() }
    }

    /// Folds right-hand modifiers onto the left ones, as key events do not tell them apart here.
    private func normalised(_ entry: KeyEntry) -> KeyEntry {
        guard entry.kind == .key else { return entry }
        var modifiers: Modifiers = []
        if !entry.modifiers.intersection([.control, .rightControl]).isEmpty { modifiers.insert(.control) }
        if !entry.modifiers.intersection([.shift, .rightShift]).isEmpty { modifiers.insert(.shift) }
        if !entry.modifiers.intersection([.option, .rightOption]).isEmpty { modifiers.insert(.option) }
        if !entry.modifiers.intersection([.command, .rightCommand]).isEmpty { modifiers.insert(.command) }
        return .key(entry.code2, modifiers)
    }
}

// MARK: - Console

private struct ConsoleTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var input = "05"
    @State private var log: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sends one configuration frame to the selected pad: 06 followed by the hex bytes below. The command list is in docs/TECHNICAL_REFERENCE.md. Erase and factory-reset commands (0F) are blocked here.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            HStack {
                Text("06").font(.system(.body, design: .monospaced))
                TextField("hex bytes, for example 0A", text: $input)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(send)
                Button("Send", action: send).disabled(model.pad == nil)
            }
            ScrollView {
                Text(log.joined(separator: "\n"))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Button("Clear") { log.removeAll() }
                Spacer()
                Button("Reload app from pad") { model.reload() }
                    .help("Use after changing settings from the console")
            }
        }
    }

    private func send() {
        guard let pad = model.pad else { return }
        let parts = input.split(whereSeparator: { $0 == " " || $0 == "," })
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty, bytes.count == parts.count, bytes.count <= 63 else {
            log.insert("?  Enter up to 63 hex bytes separated by spaces", at: 0)
            return
        }
        guard bytes[0] != 0x0F else {
            log.insert("✕  0F commands erase settings and are blocked", at: 0)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let line: String
            do { line = "←  " + hex(try pad.request(bytes)) } catch { line = "✕  \(error)" }
            DispatchQueue.main.async {
                log.insert(line, at: 0)
                log.insert("→  06 " + hex(bytes), at: 0)
            }
        }
    }
}

// MARK: - Firmware

/// Runs bootloader operations off the main thread and publishes their progress.
final class FirmwareModel: ObservableObject {
    @Published var status = ""
    @Published var progress: Double?
    @Published var busy = false
    @Published var confirmation: String?

    private let queue = DispatchQueue(label: "SDPadApp.firmware")
    private var pending: (bootloader: Bootloader, image: [UInt8])?

    private func publish(_ status: String, busy: Bool, progress: Double? = nil) {
        DispatchQueue.main.async {
            self.status = status
            self.busy = busy
            self.progress = progress
        }
    }

    func backUp(to url: URL) {
        publish("Reading the pad’s flash…", busy: true)
        queue.async {
            do {
                let flash = try Bootloader().read()
                try Data(flash).write(to: url)
                let id = Bootloader.deviceID(inImage: flash).map { String(format: " It holds firmware for %04X:%04X.", $0.vendorID, $0.productID) } ?? ""
                self.publish("Saved \(flash.count) bytes to \(url.lastPathComponent).\(id)", busy: false)
            } catch {
                self.publish("Backup failed: \(error)", busy: false)
            }
        }
    }

    func flash(from url: URL) {
        publish("Checking the image and the pad…", busy: true)
        queue.async {
            do {
                let image = [UInt8](try Data(contentsOf: url))
                guard image.count == Bootloader.flashSize else {
                    throw PadError.usage("A firmware image is exactly \(Bootloader.flashSize) bytes; this file is \(image.count).")
                }
                let bootloader = try Bootloader()
                let current = try bootloader.read()
                let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SD Macro Pad/Firmware backups")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                try Data(current).write(to: folder.appendingPathComponent("backup-\(stamp).bin"))

                let have = Bootloader.deviceID(inImage: current), want = Bootloader.deviceID(inImage: image)
                var concern: String?
                if want == nil {
                    concern = "This file has no USB device descriptor where firmware for these pads has one. It may not be a firmware image for them, and flashing it will probably leave the pad dark until a good image is flashed."
                } else if have == nil {
                    concern = "The pad’s current firmware cannot be identified, so the app cannot check this image is for the same model."
                } else if let have, let want, have != want {
                    concern = String(format: "The pad currently runs firmware for %04X:%04X, but this image is for %04X:%04X (%@). Firmware for another model will not drive this pad’s keys and lights correctly.",
                                     have.vendorID, have.productID, want.vendorID, want.productID,
                                     PadModel.lookup(vendorID: want.vendorID, productID: want.productID)?.name ?? "unknown model")
                }
                if let concern {
                    self.pending = (bootloader, image)
                    DispatchQueue.main.async {
                        self.status = "Waiting for confirmation."
                        self.busy = false
                        self.confirmation = concern
                    }
                    return
                }
                try self.write(bootloader, image)
            } catch {
                self.publish("Not flashed: \(error)", busy: false)
            }
        }
    }

    func confirmPending(_ proceed: Bool) {
        guard let pending else { return }
        self.pending = nil
        guard proceed else {
            publish("Cancelled. Nothing was written.", busy: false)
            return
        }
        publish("Writing…", busy: true, progress: 0)
        queue.async {
            do { try self.write(pending.bootloader, pending.image) } catch {
                self.publish("Flash failed: \(error)", busy: false)
            }
        }
    }

    private func write(_ bootloader: Bootloader, _ image: [UInt8]) throws {
        try bootloader.writeApplication(image: image) { fraction in
            self.publish("Writing…", busy: true, progress: fraction)
        }
        publish("Written and verified. Unplug the pad and plug it back in without holding any keys.", busy: false)
    }
}

private struct FirmwareTab: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var firmware = FirmwareModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Connected") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.pads, id: \.locationID) { pad in
                        Text("\(pad.model.name): running normally" + (pad === model.pad && model.info != nil ? ", firmware v\(model.info!.firmware)" : ""))
                    }
                    ForEach(model.legacyPads, id: \.self) { Text("\($0): factory firmware, needs v105 to be configurable") }
                    if model.bootloaderPresent {
                        Label("A pad is in bootloader mode and ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("No pad is in bootloader mode.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            GroupBox("How to") {
                Text("1. Unplug the pad. Hold its top-left and top-right keys, plug it in, then let go. Its lights stay off.\n2. Back up what is on it.\n3. Flash an image made for that model: 32 KB .bin files such as 6key_v105.bin or 16key_v105.bin.\n4. Unplug it and plug it back in without holding keys.\n\nThe bootloader itself is never overwritten, so a pad that stays dark after a flash can be put back into bootloader mode and flashed again. Keep only one pad in bootloader mode at a time.")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            HStack {
                Button("Back Up Firmware…", action: backUp)
                Button("Flash Firmware…", action: flash)
            }
            .disabled(!model.bootloaderPresent || firmware.busy)
            if let progress = firmware.progress { ProgressView(value: progress) }
            Text(firmware.status).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .alert("Flash this image anyway?", isPresented: Binding(get: { firmware.confirmation != nil }, set: { if !$0 { firmware.confirmation = nil } })) {
            Button("Flash Anyway", role: .destructive) { firmware.confirmPending(true) }
            Button("Cancel", role: .cancel) { firmware.confirmPending(false) }
        } message: {
            Text(firmware.confirmation ?? "")
        }
    }

    private func backUp() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pad-firmware-backup.bin"
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { firmware.backUp(to: url) }
    }

    private func flash() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.message = "Choose a 32 KB firmware image for the pad that is in bootloader mode"
        if panel.runModal() == .OK, let url = panel.url { firmware.flash(from: url) }
    }
}
