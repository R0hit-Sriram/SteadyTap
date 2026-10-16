import SwiftUI
import UIKit

/// System colours and SF text styles, so light/dark, Increase Contrast and Dynamic Type come for free.
/// Only the gradients are custom; each one keeps white text ≥4.5:1 across its whole range.
enum Palette {
    static let accent = Color.indigo
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let touch = Color(rgb: 0xFCD34D) // tap marks in the hero illustration
}

/// Shortcuts-style tile gradients: lighter top-left, deeper bottom-right.
enum Hue {
    case hero, indigo, teal, orange, purple, blue, slate

    private var stops: (UInt32, UInt32) {
        switch self {
        case .hero: (0x2B4FD8, 0x1A1F6B)
        case .indigo: (0x4F46E5, 0x3730A3)
        case .teal: (0x0F766E, 0x115E59)
        case .orange: (0xC2410C, 0x9A3412)
        case .purple: (0x9333EA, 0x6B21A8)
        case .blue: (0x2563EB, 0x1E40AF)
        case .slate: (0x475569, 0x334155)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(rgb: stops.0), Color(rgb: stops.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// Rounded-square icon on a gradient, like Settings and Shortcuts.
struct IconTile: View {
    let symbol: String
    let hue: Hue
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(hue.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Gentle press: scales the drawing only, so nothing around it moves.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// Inset-grouped container, matching List's insetGrouped look on any iOS version.
    func grouped() -> some View {
        background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Liquid Glass prominent button on iOS 26+, filled button before that.
    @ViewBuilder func prominentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).controlSize(.large)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    @ViewBuilder func successHaptic(_ trigger: Bool) -> some View {
        if #available(iOS 17, *) {
            sensoryFeedback(.success, trigger: trigger) { _, isOn in isOn }
        } else {
            self
        }
    }
}
