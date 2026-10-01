import SwiftUI
import SDPadKit

/// A button that captures the next key press, with its modifiers, as a keystroke entry.
struct ShortcutRecorder: View {
    var title = "Record shortcut"
    var onRecord: (KeyEntry) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press the keys… (click to cancel)" : title) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let usage = KeyNames.usageForMacKeyCode[event.keyCode] else { return nil }
            var modifiers: Modifiers = []
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            onRecord(.key(usage, modifiers))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
