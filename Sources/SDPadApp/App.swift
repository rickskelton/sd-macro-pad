import SwiftUI
import SDPadKit

@main
struct SDPadApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("SD Macro Pad", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) { OpenWindowButton(title: "About SD Macro Pad", id: "about") }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .systemServices) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .help) { OpenWindowButton(title: "SD Macro Pad Help", id: "help", shortcut: "?") }
            CommandMenu("Pad") { PadCommands(model: model) }
        }

        Window("Pad Tools", id: "tools") {
            ToolsView().environmentObject(model)
        }

        Window("SD Macro Pad Help", id: "help") {
            HelpView()
        }

        Window("About SD Macro Pad", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct OpenWindowButton: View {
    let title: String
    let id: String
    var shortcut: KeyEquivalent?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let shortcut {
            Button(title) { openWindow(id: id) }.keyboardShortcut(shortcut)
        } else {
            Button(title) { openWindow(id: id) }
        }
    }
}

private struct PadCommands: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Reload from Pad") { model.reload() }
            .keyboardShortcut("r")
            .disabled(model.pad == nil)
        Button("Edit Macros…") { model.editingMacros = true }
            .keyboardShortcut("m")
            .disabled(model.pad == nil)
        Divider()
        Button("Diagnostics and Firmware…") { openWindow(id: "tools") }
            .keyboardShortcut("d")
        Divider()
        Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
            .keyboardShortcut("w")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Menus SwiftUI adds that hold nothing this app uses.
    private static let unwantedMenus: Set<String> = ["File", "View", "Format"]
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary is run outside an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
        pruneMenus()
        // SwiftUI rebuilds the menu bar when scenes change, so prune again whenever it does.
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { [weak self] note in
            if (note.object as? NSMenu) === NSApp.mainMenu { self?.pruneMenus() }
        }
    }

    private func pruneMenus() {
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items where AppDelegate.unwantedMenus.contains(item.title) {
            menu.removeItem(item)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
