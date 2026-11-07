import SwiftUI
import UIKit

// Shared health surfaces: mineral whites, near-black green and a quiet green tint.
// Cards use static layers; the floating navigation retains the live glass effect.

enum Obs {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1)
        })
    }

    // Paper / ink — same values as thomas.md.
    static let paper = adaptive(light: 0xf4f6f3, dark: 0x000000)
    static let surface = adaptive(light: 0xffffff, dark: 0x0c0e0c)
    static let ink = adaptive(light: 0x1d3430, dark: 0xeff6f2)
    static let ink2 = adaptive(light: 0x526963, dark: 0xb4c4ba)
    static let muted = adaptive(light: 0x657972, dark: 0x92a69a)
    static let link = adaptive(light: 0x237344, dark: 0x63ca78)
    static let accent = adaptive(light: 0x237344, dark: 0x63ca78)
    static let homeAccent = adaptive(light: 0xbc303e, dark: 0xef5c63)
    static let settingsAccent = adaptive(light: 0x916852, dark: 0xd9b49c)
    static let homeSurface = adaptive(light: 0xfff8f8, dark: 0x130b0e)
    static let homeHero = adaptive(light: 0xffeeee, dark: 0x1c090e)
    static var brandBlend: LinearGradient {
        LinearGradient(colors: [homeAccent, settingsAccent, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let brandRed = Color(red: 0.94, green: 0.23, blue: 0.27)
    static let rule = adaptive(light: 0xd8e3dd, dark: 0x203127)

    // Diagrams sit in the same ink family. Status uses the investing-post green/orange.
    static let chart = adaptive(light: 0x3d7e70, dark: 0x63ca78)
    static let good = adaptive(light: 0x1baf7a, dark: 0x2ec48c)
    static let bad = adaptive(light: 0xeb6834, dark: 0xe07a4a)
    static let alert = adaptive(light: 0xc4472c, dark: 0xe06a4f)

    // Back-compat names. `teal` is the quiet chart color; `yellow` is a problem.
    static var teal: Color { chart }
    static var yellow: Color { bad }
    static var warn: Color { bad }
    static var black: Color { paper }
    static var base: Color { paper }
    static var baseLow: Color { paper }
    static var trace: Color { rule }

    static var canvas: some View { HealthCanvas() }

    // Sleep stages keep distinct hues (deep / light / REM / wake). Other charts
    // stay gray unless a value is actually good or a problem.
    static let deep = adaptive(light: 0x104281, dark: 0x5598e7)
    static let light = adaptive(light: 0x6da7ec, dark: 0x9ec5f4)
    static let rem = adaptive(light: 0x1baf7a, dark: 0x2ec48c)
    static let wake = adaptive(light: 0xeda100, dark: 0xeda100)
    static func stage(_ s: Int) -> Color {
        switch s { case 1: return deep; case 2: return light; case 3: return rem; default: return wake }
    }

    /// Color a delta only when it is large enough to be worth noticing.
    static func tone(delta: Double?, goodWhenPositive: Bool = true, threshold: Double = 8) -> Color {
        guard let d = delta else { return chart }
        let isGood = d >= 0 ? goodWhenPositive : !goodWhenPositive
        if abs(d) < threshold { return chart }
        return isGood ? good : bad
    }

    static func debt(_ state: String) -> Color {
        switch state {
        case "none": return good
        case "low": return chart
        case "moderate": return bad
        case "high": return alert
        default: return chart
        }
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func prose(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

struct ObsTag: View {
    let text: String
    var icon: String? = nil
    init(_ text: String, icon: String? = nil) { self.text = text; self.icon = icon }
    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Obs.muted)
            }
            Text(text.uppercased())
                .font(Obs.mono(11, .medium))
                .tracking(1.6)
                .foregroundStyle(Obs.muted)
        }
    }
}

struct ObsCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 18
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Obs.surface)
                } else {
                    ZStack {
                        // Content cards do not need a live backdrop blur. Keep
                        // that compositing work confined to the floating bar.
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Obs.surface)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.025 : 0.50), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.11 : 0.85), Obs.rule.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.035), radius: 4, y: 3)
    }
}

extension View {
    func obsCard(padding: CGFloat = 18, radius: CGFloat = 24) -> some View {
        modifier(ObsCard(padding: padding, radius: radius))
    }
}

struct HealthCanvas: View {
    var body: some View {
        Obs.paper.ignoresSafeArea().accessibilityHidden(true)
    }
}

/// Small controls use static surfaces; native Liquid Glass lives on the bottom bar.
struct HealthGlassControl: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Obs.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Obs.rule.opacity(0.7), lineWidth: 0.8))
    }
}

struct ObsStat: View {
    let label: String
    let value: String
    var accent: Color = Obs.ink
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Obs.mono(13)).foregroundStyle(Obs.ink2)
            Spacer(minLength: 16)
            Text(value).font(Obs.mono(15, .medium)).foregroundStyle(accent)
                .monospacedDigit()
        }
    }
}
