import SwiftUI
import UIKit

/// Design tokens. Light and dark live side by side so contrast is checked as a pair.
/// Text pairs are ≥4.5:1 on both `paper` and `card`; `touch` is decorative-only (≥3:1).
enum Palette {
    static let paper = Color(dynamic(0xF5F2EC, 0x161513))   // page background
    static let card = Color(dynamic(0xFFFFFF, 0x211F1C))
    static let ink = Color(dynamic(0x1B1A17, 0xF2EFE9))     // primary text
    static let inkSoft = Color(dynamic(0x5C5850, 0xABA59A)) // secondary text
    static let line = Color(dynamic(0xE4DFD5, 0x34312C))
    static let accent = Color(dynamic(0x1E3A8A, 0x9DB4EA))  // actions
    static let onAccent = Color(dynamic(0xFFFFFF, 0x161513))
    static let touch = Color(dynamic(0xA16207, 0xE0A53A))   // tap marks in illustrations
    static let done = Color(dynamic(0x2F6B3F, 0x7CC48F))

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// SF throughout, using Apple’s text styles so everything follows Dynamic Type.
    static let heading = Font.title2.weight(.bold)
    static let brand = Font.largeTitle.weight(.bold)
    static let hero = Font.title.weight(.bold)
}

extension View {
    func card() -> some View {
        background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.82 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
    }
}

/// Full-width row inside a card; highlights on press without moving anything.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Palette.line.opacity(0.6) : .clear)
    }
}
