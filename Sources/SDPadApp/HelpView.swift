import SwiftUI

private struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let paragraphs: [String]
}

private let helpTopics: [HelpTopic] = [
    HelpTopic(id: "start", title: "Getting started", symbol: "sparkles", paragraphs: [
        "Plug in a pad. It appears in the main window: keys on the left, dials on the right.",
        "Click a key, a dial, or an arrow under a dial. Edit it in the panel on the right.",
        "Changes are saved on the pad. It then works on any computer, with or without this app.",
        "With two pads connected, switch between them at the top-left.",
    ]),
    HelpTopic(id: "keys", title: "Keys and shortcuts", symbol: "keyboard", paragraphs: [
        "Keystroke: choose modifiers and a key, or press Record shortcut and type it. For system shortcuts such as ⌘Tab and ⌘Space, use the controls.",
        "F13 to F24 are free in every app. Assign one here, then set it as a shortcut in the app you want to control.",
        "Media key: volume, play/pause, track skip, display brightness, launcher keys.",
        "Mouse: clicks, back and forward, or scrolling by a set number of steps.",
        "System: sleep, power or wake.",
        "Nothing: the control is off.",
    ]),
    HelpTopic(id: "dials", title: "Dials", symbol: "dial.medium", paragraphs: [
        "Each dial has three actions: press, clockwise, anticlockwise. Select the dial for the press, or the arrows beneath it for each direction.",
        "A dial sends its action once per click. Volume, scrolling, undo/redo and zoom all work well.",
    ]),
    HelpTopic(id: "light", title: "Lighting", symbol: "lightbulb", paragraphs: [
        "Choose an effect under the pad. Solid, Breathing and Light on press run the built-in rainbow or one colour. Tide runs its own rainbow.",
        "Per-key colours: select a key and set Key light on the right. Choose the Per-key effect to show them.",
        "The picture of the pad lights up to match.",
        "Lighting is stored in the pad’s memory. Avoid dragging sliders back and forth for long.",
    ]),
    HelpTopic(id: "profiles", title: "Profiles", symbol: "square.stack.3d.up", paragraphs: [
        "A pad holds six profiles, each with its own assignments. Switch with the numbered buttons at the top.",
        "On a profile change the pad blinks key 1 white: once for profile 1, twice for profile 2, and so on.",
        "Macros are shared by all profiles.",
    ]),
    HelpTopic(id: "macros", title: "Macros", symbol: "text.cursor", paragraphs: [
        "A macro is a stored sequence of key presses: a line of text, or several shortcuts. The pad holds 16.",
        "Set a control’s action to Macro, choose one, then press Edit macros. Add text or shortcuts, then Save to pad.",
        "A macro can play a set number of times, repeat while held, repeat until any key, or repeat until pressed again.",
        "Text is stored as US key positions. On other layouts, check symbols such as @ and #.",
    ]),
    HelpTopic(id: "tools", title: "Tools", symbol: "wrench.and.screwdriver", paragraphs: [
        "Open Tools from the toolbar or the Pad menu.",
        "Diagnostics: everything read from the connected pads, as text you can copy.",
        "Key Test: each key press as it arrives, and which control sends it.",
        "Console: send one raw command. See the technical reference.",
        "Firmware: back up and update. See the next topic.",
    ]),
    HelpTopic(id: "firmware", title: "Updating firmware", symbol: "cpu", paragraphs: [
        "Pads often ship with older firmware. The app tells you, and version 105 unlocks remapping, lighting and macros.",
        "1. Unplug the pad. Hold the top-left and top-right keys, plug it in, let go. Lights stay off: bootloader mode.",
        "2. In Tools ▸ Firmware, press Back Up Firmware. Keep the file.",
        "3. Press Flash Firmware and choose the image for that exact model, such as 6key_v105.bin. The app checks it against the pad and asks you to confirm if they differ.",
        "4. Once written and verified, replug the pad without holding keys.",
        "If the pad stays dark, repeat step 1 and flash a known-good image. The bootloader is never overwritten. Keep one pad in bootloader mode at a time.",
    ]),
    HelpTopic(id: "trouble", title: "Troubleshooting", symbol: "questionmark.circle", paragraphs: [
        "Pad missing: try another cable or port, then Pad ▸ Reload from Pad. A pad on old firmware shows an update notice.",
        "“A pad is in bootloader mode”: replug it without holding keys.",
        "Unexpected key: check the selected profile, then Tools ▸ Key Test to see what the pad sends.",
        "Key light off after a profile switch: choose the lighting effect again.",
        "Connection error: replug the pad and press Reload.",
    ]),
]

struct HelpView: View {
    @State private var selection: HelpTopic.ID? = helpTopics[0].id

    var body: some View {
        NavigationSplitView {
            List(helpTopics, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            if let topic = helpTopics.first(where: { $0.id == selection }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        ForEach(topic.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
