import SwiftUI
import SDPadKit

enum Theme {
    static let backdrop = Color(red: 0.055, green: 0.06, blue: 0.08)
    static let panel = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.09)
    static let accent = Color(red: 0.38, green: 0.62, blue: 1.0)
    static let accentGradient = LinearGradient(colors: [Color(red: 0.35, green: 0.78, blue: 1.0), Color(red: 0.62, green: 0.45, blue: 1.0)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(1.1)
            .foregroundStyle(.white.opacity(0.45))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
    }
}

// rough on-screen version of what the pad's LEDs are doing
struct LightPreview {
    let light: LightConfig
    let colours: [RGB]
    let columns: Int
    let time: Double

    private var level: Double { 0.35 + 0.65 * Double(min(light.brightness, 4)) / 4 }
    private var rate: Double { 0.25 + 0.25 * Double(min(light.speed, 4)) }

    private var baseColour: Color {
        light.singleColour ? light.colour.color : Color(hue: (time * 0.05).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1)
    }

    func glow(forKey index: Int) -> (colour: Color, strength: Double)? {
        switch light.effect {
        case .off, .lightOnPress, nil:
            return nil
        case .solid:
            return (baseColour, level)
        case .breathing:
            return (baseColour, level * (0.2 + 0.8 * (0.5 + 0.5 * sin(time * rate * 2.2))))
        case .tide:
            let column = Double(index % max(columns, 1))
            let hue = (time * rate * 0.22 + column / (Double(max(columns, 1)) * 1.6)).truncatingRemainder(dividingBy: 1)
            return (Color(hue: hue, saturation: 0.9, brightness: 1), level)
        case .perKey:
            guard index < colours.count else { return nil }
            let c = colours[index]
            if c.r == 0 && c.g == 0 && c.b == 0 { return nil }
            return (c.color, level)
        }
    }

    var ambient: Color {
        switch light.effect {
        case .off, .lightOnPress, nil: return Theme.accent
        case .perKey: return colours.first?.color ?? Theme.accent
        case .tide: return Color(hue: (time * rate * 0.22).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1)
        default: return baseColour
        }
    }
}
