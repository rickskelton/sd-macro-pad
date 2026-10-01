import SwiftUI
import SDPadKit

/// Edits the pad's 16 stored macros. Nothing reaches the pad until Save.
struct MacroEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State var macros: [[MacroAction]]
    @State var selected: Int
    @State private var text = ""
    @State private var delay = 10

    private var stepCount: Int { macros.reduce(0) { $0 + $1.count } }
    /// 4096-byte table minus the 64-byte index, four bytes per step.
    private let capacity = (Macro.tableSize - 64) / 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: Binding(get: { Optional(selected) }, set: { selected = $0 ?? selected })) {
                    ForEach(0..<Macro.slotCount, id: \.self) { i in
                        HStack {
                            Text("Macro \(i + 1)")
                            Spacer()
                            Text(macros[i].isEmpty ? "empty" : "\(macros[i].count)").foregroundStyle(.secondary)
                        }
                        .tag(i)
                    }
                }
                .frame(width: 170)
                Divider()
                steps
            }
            Divider()
            HStack {
                Text("\(stepCount) of \(capacity) steps used").foregroundStyle(stepCount > capacity ? .red : .secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save to pad") {
                    model.saveMacros(macros)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(stepCount > capacity)
            }
            .padding(12)
        }
        .frame(width: 640, height: 480)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            if macros[selected].isEmpty {
                Text("Add text or a shortcut below to build Macro \(selected + 1).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(macros[selected].enumerated()), id: \.element.id) { i, action in
                        HStack {
                            Text(action.summary)
                            Spacer()
                            Text("after \(action.delay) ms").foregroundStyle(.secondary).font(.callout)
                            Button { macros[selected].remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove this step")
                        }
                    }
                }
            }
            HStack {
                TextField("Text to type", text: $text)
                    .onSubmit(addText)
                Button("Add text", action: addText).disabled(text.isEmpty)
            }
            HStack {
                ShortcutRecorder(title: "Add shortcut…") { entry in
                    macros[selected] += Macro.shortcut(entry, delay: UInt16(delay))
                }
                Stepper("Delay between steps: \(delay) ms", value: $delay, in: 1...1000, step: 5)
                Spacer()
                Button("Clear macro") { macros[selected] = [] }.disabled(macros[selected].isEmpty)
            }
            Text("Text is stored as US-layout key positions. With another layout on the Mac, check symbols such as @ and # after saving.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func addText() {
        macros[selected] += Macro.typing(text, delay: UInt16(delay))
        text = ""
    }
}
