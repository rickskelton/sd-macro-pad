import SwiftUI

private struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let paragraphs: [String]
}

private let helpTopics: [HelpTopic] = [
    HelpTopic(id: "start", title: "Getting started", symbol: "sparkles", paragraphs: [
        "Plug in a pad and it appears in the main window, drawn as it sits on the desk: keys on the left, dials on the right.",
        "Click a key, a dial, or one of the two arrows under a dial. The panel on the right shows what that control does and lets you change it.",
        "Every change is saved on the pad itself within a moment. The pad then works on any computer, with or without this app running.",
        "If two pads are connected, switch between them at the top-left.",
    ]),
    HelpTopic(id: "keys", title: "Keys and shortcuts", symbol: "keyboard", paragraphs: [
        "Keystroke: choose modifiers and a key, or press Record shortcut and type the combination. For system shortcuts such as ⌘Tab and ⌘Space, set the modifiers and key with the controls.",
        "F13 to F24 are ideal for buttons that should trigger something in another app, because they are free everywhere. Assign the same key as a shortcut in that app.",
        "Media key: volume, play/pause, track skip, display brightness and a few launcher keys.",
        "Mouse: a click, the back and forward buttons, or scrolling by a set number of steps.",
        "System: sleep, power or wake.",
        "Nothing: the control is switched off.",
    ]),
    HelpTopic(id: "dials", title: "Dials", symbol: "dial.medium", paragraphs: [
        "Each dial has three actions: pressing it, turning it clockwise and turning it anticlockwise. Select the dial itself for the press, or the arrows beneath it for the two directions.",
        "A dial sends its action once per click of rotation. Volume up and down, scrolling, undo and redo, or zoom in and out all work well.",
    ]),
    HelpTopic(id: "light", title: "Lighting", symbol: "lightbulb", paragraphs: [
        "Choose an effect under the pad. Solid, Breathing and Light on press can run the pad’s built-in rainbow or one colour of your choice. Tide always runs its own rainbow.",
        "Per-key colours lets every key have its own colour: select a key and set Key light in the right-hand panel. Choose the Per-key effect to show them.",
        "The picture of the pad lights up to match, so you can see an effect as you choose it.",
        "Lighting changes are stored in the pad’s memory, so avoid dragging sliders back and forth for long periods.",
    ]),
    HelpTopic(id: "profiles", title: "Profiles", symbol: "square.stack.3d.up", paragraphs: [
        "A pad holds six profiles, each with its own key and dial assignments. Switch with the numbered buttons at the top.",
        "When the profile changes, the pad blinks its first key white: once for profile 1, twice for profile 2, and so on. That is the pad’s own behaviour.",
        "Macros are shared by all profiles.",
    ]),
    HelpTopic(id: "macros", title: "Macros", symbol: "text.cursor", paragraphs: [
        "A macro is a stored sequence of key presses, such as a line of text or several shortcuts in a row. The pad holds 16.",
        "Set a control’s action to Macro, choose which one, then press Edit macros. Add text or shortcuts, then Save to pad.",
        "A macro can play a set number of times, repeat while the key is held, repeat until any key is pressed, or repeat until the same key is pressed again.",
        "Text is stored as key positions on a US keyboard. With another layout on the Mac, check symbols such as @ and # after saving.",
    ]),
    HelpTopic(id: "tools", title: "Tools", symbol: "wrench.and.screwdriver", paragraphs: [
        "Open Tools from the toolbar or the Pad menu.",
        "Diagnostics reads everything from the connected pads and shows it as text you can copy when asking for help.",
        "Key Test shows each key press as it arrives and which control on the pad is set to send it.",
        "Console sends a single raw command to the pad. It is for people following the technical reference.",
        "Firmware backs up and updates the pad’s firmware. See the next topic.",
    ]),
    HelpTopic(id: "firmware", title: "Updating firmware", symbol: "cpu", paragraphs: [
        "Pads are often sold with an older firmware. The app tells you when it sees one, and updating to version 105 unlocks remapping, lighting and macros.",
        "1. Unplug the pad. Hold its top-left and top-right keys, plug it in, then let go. The lights stay off: the pad is in bootloader mode.",
        "2. In Tools ▸ Firmware, press Back Up Firmware and keep the file.",
        "3. Press Flash Firmware and choose the image for that exact model, for example 6key_v105.bin for the 6-key pad. The app checks the image against the pad and asks you to confirm if the two differ.",
        "4. When it says the image is written and verified, unplug the pad and plug it back in without holding keys.",
        "If the pad stays dark afterwards, repeat step 1 and flash a known-good image. The bootloader is never overwritten, so the pad can always be flashed again. Put only one pad in bootloader mode at a time.",
    ]),
    HelpTopic(id: "trouble", title: "Troubleshooting", symbol: "questionmark.circle", paragraphs: [
        "To make a pad appear: try another cable or port, then Pad ▸ Reload from Pad. A pad on the old firmware shows an update notice.",
        "“A pad is in bootloader mode”: unplug it and plug it back in without holding any keys.",
        "A key does something unexpected: check which profile is selected, and use Tools ▸ Key Test to see what the pad actually sends.",
        "A key’s light is off after switching profile: choose the lighting effect again, or press Reload.",
        "After a connection error: unplug the pad, plug it back in and press Reload.",
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
