import SwiftUI

/// Animated how-to: a small iPhone on screen walks through the taps, one short caption per step.
/// Built for people who would rather watch than read, so the words stay to a few per step.
///
/// The phone is drawn at real iPhone point sizes (393 wide, 44-point rows, 29-point icons, 20-point
/// margins) and then scaled down as a whole, so the proportions match what the person is holding
/// instead of being a loose sketch of a list.

struct HowToStep {
    let caption: String
    let screen: MockScreen
}

enum MockScreen {
    /// Home screen with the Settings icon.
    case homeScreen
    /// A Settings page.
    case settings(SettingsPage)
    /// A note with a text box the finger is tapping.
    case textBox
    /// Our keyboard inside a note.
    case keyboard(highlight: String? = nil, overlay: KeyboardOverlay = .none, finger: KeyboardSpot = .none)
}

enum KeyboardOverlay { case none, globeMenu, settingsMenu }
enum KeyboardSpot { case none, globe, gear, key, menuRow }

// MARK: - A Settings page, as iOS draws it

struct SettingsRow {
    var icon: (symbol: String, color: Color)?
    var title: String
    var value: String?
    var accessory: Accessory = .chevron
    var tint: Color?

    enum Accessory { case chevron, none, toggleOn }
}

struct SettingsGroup {
    var header: String?
    var rows: [SettingsRow]
}

struct SettingsPage {
    var back: String?
    var title: String
    var largeTitle = false
    var search = false
    var trailing: String?
    var groups: [SettingsGroup]
    /// Which row the finger rests on.
    var tap: (group: Int, row: Int)?
}

private enum Pages {
    static let grey = Color(.systemGray)
    static let blue = Color(red: 0, green: 0.48, blue: 1)

    static let root = SettingsPage(
        title: "Settings", largeTitle: true, search: true,
        groups: [SettingsGroup(rows: [
            .init(icon: ("gearshape.fill", grey), title: "General"),
            .init(icon: ("switch.2", grey), title: "Control Center"),
            .init(icon: ("sun.max.fill", blue), title: "Display & Brightness"),
            .init(icon: ("square.grid.2x2.fill", blue), title: "Home Screen & App Library"),
            .init(icon: ("accessibility", blue), title: "Accessibility"),
        ])],
        tap: (0, 0))

    static let general = SettingsPage(
        back: "Settings", title: "General",
        groups: [
            SettingsGroup(rows: [
                .init(title: "About"),
                .init(title: "Software Update"),
            ]),
            SettingsGroup(rows: [
                .init(title: "Date & Time"),
                .init(title: "Keyboard"),
                .init(title: "Fonts"),
                .init(title: "Language & Region"),
                .init(title: "Dictionary"),
            ]),
        ],
        tap: (1, 1))

    static let keyboard = SettingsPage(
        back: "General", title: "Keyboard",
        groups: [
            SettingsGroup(rows: [
                .init(title: "Keyboards", value: "2"),
                .init(title: "Text Replacement"),
                .init(title: "One Handed Keyboard", value: "Off"),
            ]),
            SettingsGroup(header: "ALL KEYBOARDS", rows: [
                .init(title: "Auto-Capitalization", accessory: .toggleOn),
                .init(title: "Auto-Correction", accessory: .toggleOn),
                .init(title: "Check Spelling", accessory: .toggleOn),
            ]),
        ],
        tap: (0, 0))

    static let keyboards = SettingsPage(
        back: "Keyboard", title: "Keyboards", trailing: "Edit",
        groups: [SettingsGroup(rows: [
            .init(title: "English (US)", accessory: .none),
            .init(title: "Emoji", accessory: .none),
            .init(title: "Add New Keyboard…", tint: blue),
        ])],
        tap: (0, 2))

    static let addKeyboard = SettingsPage(
        back: "Keyboards", title: "Add New Keyboard",
        groups: [
            SettingsGroup(header: "THIRD-PARTY KEYBOARDS", rows: [
                .init(title: appName, accessory: .none),
            ]),
            SettingsGroup(header: "OTHER IPHONE KEYBOARDS", rows: [
                .init(title: "Afrikaans", accessory: .none),
                .init(title: "Arabic", accessory: .none),
            ]),
        ],
        tap: (0, 0))

    static let done = SettingsPage(
        back: "Keyboard", title: "Keyboards", trailing: "Edit",
        groups: [SettingsGroup(rows: [
            .init(title: "English (US)", accessory: .none),
            .init(title: "Emoji", accessory: .none),
            .init(title: appName, accessory: .none),
            .init(title: "Add New Keyboard…", tint: blue),
        ])])
}

enum HowTo {
    /// Turning the keyboard on in Settings.
    static let enableKeyboard: [HowToStep] = [
        .init(caption: "Open Settings", screen: .homeScreen),
        .init(caption: "Tap General", screen: .settings(Pages.root)),
        .init(caption: "Tap Keyboard", screen: .settings(Pages.general)),
        .init(caption: "Tap Keyboards", screen: .settings(Pages.keyboard)),
        .init(caption: "Tap Add New Keyboard", screen: .settings(Pages.keyboards)),
        .init(caption: "Choose \(appName)", screen: .settings(Pages.addKeyboard)),
        .init(caption: "Done. Leave Full Access off.", screen: .settings(Pages.done)),
    ]

    /// Teaching it your touch, from inside any app.
    static let calibrate: [HowToStep] = [
        .init(caption: "Tap a text box", screen: .textBox),
        .init(caption: "Hold the globe key", screen: .keyboard(finger: .globe)),
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
    private let tick = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

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

// MARK: - The little phone, drawn at real iPhone sizes and scaled down as a whole

/// Real iPhone metrics, in points.
enum IOS {
    static let width: CGFloat = 393
    static let shown: CGFloat = 700      // how much of the screen's height the card shows
    static let scale: CGFloat = 0.56
    static let statusBar: CGFloat = 54
    static let navBar: CGFloat = 44
    static let largeTitle: CGFloat = 52
    static let search: CGFloat = 52
    static let row: CGFloat = 44
    static let margin: CGFloat = 20
    static let groupGap: CGFloat = 35
    static let headerText: CGFloat = 30
    static let corner: CGFloat = 10
}

struct PhoneScreen: View {
    let screen: MockScreen

    var body: some View {
        content
            .frame(width: IOS.width, height: IOS.shown, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 6))
            .scaleEffect(IOS.scale)
            .frame(width: IOS.width * IOS.scale, height: IOS.shown * IOS.scale)
            .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .homeScreen: HomeScreenView()
        case let .settings(page): SettingsPageView(page: page)
        case .textBox: NoteView(keyboard: nil, finger: .none, highlight: nil, overlay: .none)
        case let .keyboard(highlight, overlay, finger):
            NoteView(keyboard: true, finger: finger, highlight: highlight, overlay: overlay)
        }
    }
}

/// Pulsing ring that marks where to tap. Sized in real iPhone points.
struct FingerDot: View {
    var size: CGFloat = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Palette.accent.opacity(0.22))
            .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 4))
            .frame(width: size, height: size)
            .scaleEffect(pulse ? 0.78 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

private struct StatusBar: View {
    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
            }
            .font(.system(size: 14))
        }
        .padding(.horizontal, 28)
        .frame(height: IOS.statusBar, alignment: .bottom)
        .padding(.bottom, 4)
    }
}

private struct HomeScreenView: View {
    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            Spacer()
            ZStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(LinearGradient(colors: [Color(.systemGray2), Color(.systemGray)],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                FingerDot().offset(x: 26, y: 28)
            }
            Text("Settings").font(.system(size: 14)).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A Settings page: status bar, navigation bar, then inset-grouped rows — iOS metrics throughout.
private struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            navBar
            if page.largeTitle {
                Text(page.title)
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IOS.margin)
                    .frame(height: IOS.largeTitle, alignment: .bottom)
            }
            if page.search { searchField }
            ForEach(page.groups.indices, id: \.self) { g in
                group(page.groups[g], index: g)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topLeading) { finger }
    }

    private var navBar: some View {
        ZStack {
            Text(page.largeTitle ? "" : page.title).font(.system(size: 17, weight: .semibold))
            HStack {
                if let back = page.back {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        Text(back).font(.system(size: 17))
                    }
                    .foregroundStyle(Pages.blue)
                }
                Spacer()
                if let trailing = page.trailing {
                    Text(trailing).font(.system(size: 17)).foregroundStyle(Pages.blue)
                }
            }
            .padding(.horizontal, IOS.margin - 8)
        }
        .frame(height: IOS.navBar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            Text("Search")
            Spacer()
        }
        .font(.system(size: 17))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, IOS.margin)
        .frame(height: IOS.search)
    }

    private func group(_ group: SettingsGroup, index: Int) -> some View {
        VStack(spacing: 0) {
            if let header = group.header {
                Text(header)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IOS.margin + 12)
                    .frame(height: IOS.headerText, alignment: .bottom)
                    .padding(.bottom, 6)
            }
            VStack(spacing: 0) {
                ForEach(group.rows.indices, id: \.self) { r in
                    rowView(group.rows[r])
                    if r < group.rows.count - 1 {
                        Divider().padding(.leading, group.rows[r].icon == nil ? 16 : 57)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: IOS.corner, style: .continuous))
            .padding(.horizontal, IOS.margin)
        }
        .padding(.top, index == 0 ? (page.search ? 10 : IOS.groupGap) : IOS.groupGap - (group.header == nil ? 0 : 10))
    }

    private func rowView(_ row: SettingsRow) -> some View {
        HStack(spacing: 12) {
            if let icon = row.icon {
                Image(systemName: icon.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(icon.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(row.title)
                .font(.system(size: 17))
                .foregroundStyle(row.tint ?? .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let value = row.value {
                Text(value).font(.system(size: 17)).foregroundStyle(.secondary)
            }
            switch row.accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            case .toggleOn:
                Capsule().fill(Color.green).frame(width: 51, height: 31)
                    .overlay(Circle().fill(.white).padding(2), alignment: .trailing)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: IOS.row)
    }

    /// Where the tapped row sits, measured down the page in the same metrics used to lay it out.
    @ViewBuilder private var finger: some View {
        if let tap = page.tap {
            FingerDot()
                .offset(x: IOS.width - 96, y: rowCentre(tap) - 27)
        }
    }

    private func rowCentre(_ tap: (group: Int, row: Int)) -> CGFloat {
        var y = IOS.statusBar + 4 + IOS.navBar
        if page.largeTitle { y += IOS.largeTitle }
        if page.search { y += IOS.search }
        for g in 0 ..< tap.group {
            y += topPad(g) + headerHeight(g) + CGFloat(page.groups[g].rows.count) * IOS.row
        }
        y += topPad(tap.group) + headerHeight(tap.group) + CGFloat(tap.row) * IOS.row + IOS.row / 2
        return y
    }

    private func topPad(_ g: Int) -> CGFloat {
        g == 0 ? (page.search ? 10 : IOS.groupGap) : IOS.groupGap - (page.groups[g].header == nil ? 0 : 10)
    }

    private func headerHeight(_ g: Int) -> CGFloat {
        page.groups[g].header == nil ? 0 : IOS.headerText + 6
    }
}

/// A note with our keyboard at the bottom, at real keyboard proportions.
private struct NoteView: View {
    let keyboard: Bool?
    let finger: KeyboardSpot
    let highlight: String?
    let overlay: KeyboardOverlay

    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            ZStack {
                Text("Notes").font(.system(size: 17, weight: .semibold))
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        Text("Folders").font(.system(size: 17))
                    }
                    .foregroundStyle(Pages.blue)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .frame(height: IOS.navBar)

            if keyboard == nil {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.accent, lineWidth: 3)
                        .frame(height: 120)
                    Text("Tap here to type")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .padding(16)
                    FingerDot().offset(x: 96, y: 36)
                }
                .padding(IOS.margin)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Color(.quaternaryLabel)).frame(width: 210, height: 11)
                    Capsule().fill(Color(.quaternaryLabel)).frame(width: 140, height: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(IOS.margin)
            }
            Spacer(minLength: 0)
            if keyboard != nil { KeyboardMock(highlight: highlight, overlay: overlay, finger: finger) }
        }
    }
}

private struct KeyboardMock: View {
    let highlight: String?
    let overlay: KeyboardOverlay
    let finger: KeyboardSpot

    private let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
    private let keyW: CGFloat = 33, keyH: CGFloat = 42, gap: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            if overlay == .globeMenu { menu(rows: [appName, "English (US)", "Emoji"]) }
            if overlay == .settingsMenu { menu(rows: ["Calibrate", "Typing comparison"]) }
            keyboard
        }
    }

    private func menu(rows: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                Text(rows[i])
                    .font(.system(size: 17, weight: i == 0 ? .semibold : .regular))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(i == 0 ? Palette.accent.opacity(0.15) : .clear)
                if i < rows.count - 1 { Divider() }
            }
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .top) { if finger == .menuRow { FingerDot().offset(y: -5) } }
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }

    private var keyboard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 36)
                        .background(finger == .gear ? Palette.accent.opacity(0.2) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if finger == .gear { FingerDot(size: 44) }
                }
                Spacer()
                Image(systemName: "arrow.uturn.backward").font(.system(size: 20)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .frame(height: 40)

            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(Array(rows[r]), id: \.self) { ch in
                        let on = highlight == String(ch)
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? Palette.accent : Color(.secondarySystemGroupedBackground))
                                .frame(width: keyW, height: keyH)
                            Text(String(ch))
                                .font(.system(size: 20, weight: on ? .bold : .regular))
                                .foregroundStyle(on ? .white : .primary)
                            if on, finger == .key { FingerDot(size: 46) }
                        }
                    }
                }
            }

            HStack(spacing: gap) {
                key(width: 48, label: "123")
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(finger == .globe ? Palette.accent.opacity(0.25) : Color(.secondarySystemGroupedBackground))
                        .frame(width: 42, height: keyH)
                    Image(systemName: "globe").font(.system(size: 18))
                    if finger == .globe { FingerDot(size: 46) }
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: keyH)
                key(width: 62, label: "return")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
    }

    private func key(width: CGFloat, label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: width, height: keyH)
            Text(label).font(.system(size: 14))
        }
    }
}

#Preview("Enable") { HowToView(steps: HowTo.enableKeyboard).padding() }
#Preview("Calibrate") { HowToView(steps: HowTo.calibrate).padding() }
