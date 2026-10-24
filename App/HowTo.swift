import SwiftUI

/// Animated how-to: a small iPhone on screen walks through the taps, one short caption per step.
/// Built for people who would rather watch than read, so the words stay to a few per step.
/// It plays by itself, can be paused, and can be stepped by hand.

struct HowToStep {
    let caption: String
    let screen: MockScreen
}

/// What the little phone shows. A fixed set, so each step is one line to write.
enum MockScreen: Equatable {
    /// Home screen with the Settings icon.
    case settingsApp
    /// A Settings-style list; `tap` is the row the finger is on.
    case list(title: String, rows: [String], tap: Int, checked: Bool = false)
    /// A note with a text box the finger is tapping.
    case textBox
    /// Our keyboard. `highlight` is the key to light up; `overlay` is any panel over it.
    case keyboard(highlight: String? = nil, overlay: KeyboardOverlay = .none, finger: KeyboardSpot = .none)
}

enum KeyboardOverlay: Equatable { case none, globeMenu, settingsMenu }
enum KeyboardSpot: Equatable { case none, globe, gear, key, menuRow }

enum HowTo {
    /// Turning the keyboard on in Settings.
    static let enableKeyboard: [HowToStep] = [
        .init(caption: "Open Settings", screen: .settingsApp),
        .init(caption: "Tap General", screen: .list(title: "Settings", rows: ["General", "Accessibility", "Privacy"], tap: 0)),
        .init(caption: "Tap Keyboard", screen: .list(title: "General", rows: ["About", "Keyboard", "Language"], tap: 1)),
        .init(caption: "Tap Keyboards", screen: .list(title: "Keyboard", rows: ["Keyboards", "Text Replacement"], tap: 0)),
        .init(caption: "Tap Add New Keyboard", screen: .list(title: "Keyboards", rows: ["English", "Emoji", "Add New Keyboard…"], tap: 2)),
        .init(caption: "Choose \(appName)", screen: .list(title: "Add Keyboard", rows: [appName, "Other keyboards"], tap: 0, checked: true)),
        .init(caption: "Done. Leave Full Access off.", screen: .list(title: "Keyboards", rows: ["English", "Emoji", appName], tap: 2, checked: true)),
    ]

    /// Teaching it your touch, from inside any app.
    static let calibrate: [HowToStep] = [
        .init(caption: "Tap a text box", screen: .textBox),
        .init(caption: "Hold the globe key", screen: .keyboard(overlay: .none, finger: .globe)),
        .init(caption: "Choose \(appName)", screen: .keyboard(overlay: .globeMenu, finger: .menuRow)),
        .init(caption: "Tap the gear", screen: .keyboard(finger: .gear)),
        .init(caption: "Choose Calibrate", screen: .keyboard(overlay: .settingsMenu, finger: .menuRow)),
        .init(caption: "Tap each blue key", screen: .keyboard(highlight: "S", finger: .key)),
        .init(caption: "Keep going — it learns you", screen: .keyboard(highlight: "L", finger: .key)),
        .init(caption: "Three short sets, with breaks", screen: .keyboard(highlight: "E", finger: .key)),
    ]
}

// MARK: - Player

struct HowToView: View {
    let steps: [HowToStep]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var playing = true
    // Ticks often; a step changes every `dwell` ticks so pausing is instant.
    private let tick = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            PhoneScreen(screen: steps[index].screen)
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .clipped()
                .accessibilityElement()
                .accessibilityLabel("Step \(index + 1) of \(steps.count). \(steps[index].caption)")

            Text(steps[index].caption)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            controls
        }
        .padding(.vertical, 8)
        .onAppear { playing = !reduceMotion }
        .onReceive(tick) { _ in if playing { advance(1) } }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            step(back: true)
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 60, height: 44)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")
            step(back: false)
            dots
        }
    }

    private func step(back: Bool) -> some View {
        Button {
            playing = false
            advance(back ? -1 : 1)
        } label: {
            Image(systemName: back ? "chevron.left" : "chevron.right")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(back ? "Previous step" : "Next step")
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? Palette.accent : Color(.tertiaryLabel))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func advance(_ by: Int) {
        let next = (index + by + steps.count) % steps.count
        if reduceMotion { index = next } else { withAnimation(.easeInOut(duration: 0.35)) { index = next } }
    }
}

// MARK: - The little phone

private enum M {
    static let width: CGFloat = 206, height: CGFloat = 368
    static let rowH: CGFloat = 40, headerH: CGFloat = 32
}

struct PhoneScreen: View {
    let screen: MockScreen

    var body: some View {
        content
            .frame(width: M.width, height: M.height)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 3))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .settingsApp: SettingsAppScreen()
        case let .list(title, rows, tap, checked): ListScreen(title: title, rows: rows, tap: tap, checked: checked)
        case .textBox: TextBoxScreen()
        case let .keyboard(highlight, overlay, finger): KeyboardScreen(highlight: highlight, overlay: overlay, finger: finger)
        }
    }
}

/// Pulsing ring that marks where to tap.
struct FingerDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Palette.accent.opacity(0.22))
            .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2.5))
            .frame(width: 36, height: 36)
            .scaleEffect(pulse ? 0.78 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

private struct SettingsAppScreen: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(LinearGradient(colors: [Color(.systemGray2), Color(.systemGray)],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                FingerDot().offset(x: 18, y: 20)
            }
            Text("Settings").font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ListScreen: View {
    let title: String
    let rows: [String]
    let tap: Int
    let checked: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: M.headerH)
                .background(Color(.secondarySystemBackground))
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Text(rows[i]).font(.subheadline).lineLimit(1)
                    Spacer()
                    Image(systemName: checked && i == tap ? "checkmark" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(checked && i == tap ? Palette.accent : Color(.tertiaryLabel))
                }
                .padding(.horizontal, 14)
                .frame(height: M.rowH)
                .background(i == tap ? Palette.accent.opacity(0.1) : .clear)
                Divider().padding(.leading, 14)
            }
            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            FingerDot().offset(x: -30, y: M.headerH + M.rowH * CGFloat(tap) + M.rowH / 2 - 18)
        }
    }
}

private struct TextBoxScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Notes")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: M.headerH)
                .background(Color(.secondarySystemBackground))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .frame(height: 76)
                Text("Tap here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                FingerDot().offset(x: 54, y: 26)
            }
            .padding(14)
            Spacer()
        }
    }
}

private struct KeyboardScreen: View {
    let highlight: String?
    let overlay: KeyboardOverlay
    let finger: KeyboardSpot

    private let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

    var body: some View {
        VStack(spacing: 0) {
            Text("Notes")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: M.headerH)
                .background(Color(.secondarySystemBackground))
            // A line of typed text, so the little phone reads as a real app.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0 ..< 2, id: \.self) { i in
                    Capsule().fill(Color(.quaternaryLabel))
                        .frame(width: i == 0 ? 120 : 76, height: 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            Spacer(minLength: 0)
            if overlay == .globeMenu { menu(rows: [appName, "English"], highlightFirst: true) }
            if overlay == .settingsMenu { menu(rows: ["Calibrate", "Typing comparison"], highlightFirst: true) }
            keyboard
        }
    }

    private func menu(rows: [String], highlightFirst: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                Text(rows[i])
                    .font(.subheadline.weight(i == 0 && highlightFirst ? .semibold : .regular))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(i == 0 && highlightFirst ? Palette.accent.opacity(0.14) : .clear)
                if i < rows.count - 1 { Divider() }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .top) { if finger == .menuRow { FingerDot().offset(y: 2) } }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var keyboard: some View {
        VStack(spacing: 5) {
            // Our toolbar: gear on the left.
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "gearshape")
                        .font(.footnote)
                        .frame(width: 26, height: 22)
                        .background(finger == .gear ? Palette.accent.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    if finger == .gear { FingerDot().scaleEffect(0.8) }
                }
                Spacer()
                Image(systemName: "arrow.uturn.backward").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)

            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(Array(rows[r]), id: \.self) { ch in
                        let on = highlight == String(ch)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(on ? Palette.accent : Color(.secondarySystemBackground))
                                .frame(width: 16, height: 24)
                            Text(String(ch))
                                .font(.system(size: 9, weight: on ? .bold : .regular))
                                .foregroundStyle(on ? .white : .primary)
                            if on, finger == .key { FingerDot().scaleEffect(0.72) }
                        }
                    }
                }
            }

            // Bottom row with the globe.
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemBackground)).frame(width: 24, height: 24)
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(finger == .globe ? Palette.accent.opacity(0.25) : Color(.secondarySystemBackground))
                        .frame(width: 22, height: 24)
                    Image(systemName: "globe").font(.system(size: 10))
                    if finger == .globe { FingerDot().scaleEffect(0.72) }
                }
                RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemBackground)).frame(height: 24)
                RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemBackground)).frame(width: 32, height: 24)
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
    }
}

#Preview("Enable") { HowToView(steps: HowTo.enableKeyboard).padding() }
#Preview("Calibrate") { HowToView(steps: HowTo.calibrate).padding() }
