import SwiftUI
import SDPadKit

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.19), Color(red: 0.05, green: 0.05, blue: 0.08)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 112, height: 112)
                    Text("SD Macro Pad").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Version \(version)").font(.callout).foregroundStyle(.white.opacity(0.6))
                    TideStrip()
                }
                .padding(.vertical, 26)
            }
            .frame(height: 290)

            VStack(alignment: .leading, spacing: 12) {
                Text("Remap the keys and dials, set the lighting and store macros on SDINNOVATION “SIDE-KEYBOARD” macro pads. Everything is saved on the pad itself, so it works on any computer afterwards.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Supports the 6-key and 16-key pads on firmware v105.")
                    .foregroundStyle(.secondary)
                Divider()
                Text("Acknowledgements").font(.headline)
                Text("The protocol was worked out from the pads themselves and the vendor’s own configuration tool, with a head start from two open-source projects:")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Link("Knurl", destination: URL(string: "https://github.com/dozzenn/knurl")!)
                    Link("MacroPad", destination: URL(string: "https://github.com/ysalitrynskyi/MacroPad")!)
                }
                Divider()
                Text("Disclaimer").font(.headline)
                Text("This is an independent tool, not made or endorsed by SDINNOVATION, SDCX or Huali. It is provided as is, with no warranty of any kind. Changing a pad’s settings, and especially flashing firmware, is done at your own risk: a wrong or interrupted firmware flash can leave a pad unusable until it is flashed again, and the author accepts no liability for damage to any device or loss of data. Back up a pad’s firmware before flashing it.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                Text("Made by Rick Skelton.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .frame(width: 460)
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}

/// A row of key caps running the pad's "tide" rainbow.
private struct TideStrip: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate / 4
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let hue = (phase + Double(i) / 9).truncatingRemainder(dividingBy: 1)
                    let colour = Color(hue: hue, saturation: 0.85, brightness: 1)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 34, height: 30)
                        .padding(.bottom, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(colour))
                        .shadow(color: colour.opacity(0.8), radius: 9, y: 3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
