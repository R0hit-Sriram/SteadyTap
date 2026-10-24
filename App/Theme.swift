import SwiftUI
import UIKit

/// System colours and SF text styles, so light/dark, Increase Contrast and Dynamic Type come for free.
/// Only the gradients are custom; each one keeps white text ≥4.5:1 across its whole range.
enum Palette {
    static let accent = Color.indigo
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let touch = Color(rgb: 0xE5262B) // fingerprint in the hero illustration
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

/// Half-strength Liquid Glass look: a top sheen and a bright rim over whatever fill is underneath.
/// Drawn by hand rather than with .glassEffect so white text keeps its contrast on the colour below.
struct GlassFinish: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.05), .clear],
                                          startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.28)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Top edge of the scroll content, in the scroll view's own space: 0 at rest, negative once scrolled.
struct ScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

/// Fades and lifts a view in after `delay`; instant with Reduce Motion.
struct Rise: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                if reduceMotion { shown = true } else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(delay)) { shown = true }
                }
            }
            // If the entrance never runs (view built off screen, snapshot during launch), show it anyway.
            .task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                shown = true
            }
    }
}

/// A light band that sweeps across a capsule every few seconds.
struct Shimmer: ViewModifier {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = -0.6

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: x * geo.size.width)
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.4).delay(2).repeatForever(autoreverses: false)) { x = 1.2 }
                }
            }
        }
    }
}

extension View {
    func glassFinish(cornerRadius: CGFloat) -> some View { modifier(GlassFinish(cornerRadius: cornerRadius)) }
    func rise(after delay: Double) -> some View { modifier(Rise(delay: delay)) }

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
