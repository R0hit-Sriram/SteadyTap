import SwiftUI

/// The display name comes from project.yml (APP_DISPLAY_NAME) so renaming happens in one place.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SteadyTap"

@main
struct SteadyTapApp: App {
    var body: some Scene {
        WindowGroup { HomeView().tint(Palette.accent) }
    }
}

enum Route: Hashable {
    case setup, practice, howItWorks, comparison, privacy

    var title: String {
        switch self {
        case .setup: "Add the keyboard"
        case .practice: "Practice pad"
        case .howItWorks: "How it works"
        case .comparison: "Compare keyboards"
        case .privacy: "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .setup: "keyboard"
        case .practice: "hand.tap.fill"
        case .howItWorks: "scope"
        case .comparison: "chart.bar.xaxis"
        case .privacy: "hand.raised.fill"
        }
    }

    var hue: Hue {
        switch self {
        case .setup: .indigo
        case .practice: .teal
        case .howItWorks: .purple
        case .comparison: .orange
        case .privacy: .slate
        }
    }

    var blurb: String {
        switch self {
        case .setup: "Turn \(appName) on in Settings. It never asks for Full Access."
        case .practice: "Calibrate and try the keyboard. Nothing you type here is saved."
        case .howItWorks: "How it decides which key you meant, and how it keeps learning."
        case .comparison: "Test the adapted keyboard against a standard one, on yourself."
        case .privacy: "What stays on this iPhone, and what is never stored."
        }
    }
}

// MARK: - Home

struct HomeView: View {
    // The app can't see inside the keyboard (no Full Access, no shared storage), so people tick steps off themselves.
    @AppStorage("step.added") private var added = false
    @AppStorage("step.calibrated") private var calibrated = false
    @AppStorage("step.typed") private var typed = false
    @State private var path: [Route] = []
    /// 0 while the page sits at the top, 1 once the title has finished shrinking into the corner.
    @State private var titleProgress: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Color.clear
                        .frame(height: 0)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: ScrollTopKey.self,
                                                   value: g.frame(in: .named("home")).minY)
                        })
                    HeroCard(action: next.title) { path.append(next.route) }
                    setup
                    explore
                    Label("No account, no internet access. What you type is never stored.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                }
                .coordinateSpace(name: "home")
                .onPreferenceChange(ScrollTopKey.self) { top in
                    // Tracks the finger, so no animation here: the size follows the scroll itself.
                    titleProgress = min(max(-top / 44, 0), 1)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .setup: SetupView()
                case .practice: PracticeView()
                case .howItWorks: ArticleView(route: route, sections: Copy.howItWorks)
                case .comparison: ArticleView(route: route, sections: Copy.comparison)
                case .privacy: ArticleView(route: route, sections: Copy.privacy)
                }
            }
        }
    }

    /// The name, pinned at the top left. It shrinks smoothly into the corner as the page scrolls,
    /// rather than jumping to a small centred title the way a navigation large title does.
    /// Scaling (not a font change) keeps it smooth: the glyphs are drawn once and resized.
    private var header: some View {
        let p = titleProgress
        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text(appName).font(.largeTitle.bold())
            }
                .fixedSize()
                .scaleEffect(1 - 0.5 * p, anchor: .leading)
                .frame(height: 41 - 19 * p, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10 - 4 * p)
        .padding(.bottom, 10 - 5 * p)
        .background(Palette.background)
        .overlay(alignment: .bottom) { Divider().opacity(p) }
    }

    private var doneCount: Int { [added, calibrated, typed].filter { $0 }.count }

    private var next: (title: String, route: Route) {
        if !added { return ("Get started", .setup) }
        if !calibrated { return ("Teach it your touch", .practice) }
        return ("Open the practice pad", .practice)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Get set up").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(doneCount == 3 ? "All done" : "\(doneCount) of 3")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(doneCount), total: 3)
                .tint(.green)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("\(doneCount) of 3 steps done")

            VStack(spacing: 0) {
                StepRow(title: "Add it to your iPhone", detail: Text("Turn it on in Settings."),
                        symbol: "keyboard", hue: .indigo, done: $added) { path.append(.setup) }
                Divider().padding(.leading, 66)
                StepRow(title: "Teach it your touch", detail: Text("Tap 63 highlighted keys in three short sets."),
                        symbol: "hand.tap.fill", hue: .teal, done: $calibrated) { path.append(.practice) }
                Divider().padding(.leading, 66)
                StepRow(title: "Type anywhere",
                        detail: Text("Hold \(Image(systemName: "globe")) in any app and choose \(appName)."),
                        symbol: "globe", hue: .blue, done: $typed, open: nil)
            }
            .grouped()
            .padding(.top, 4)

            Text("Tap a circle to tick off a step.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var explore: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            // One column at accessibility text sizes so titles never truncate.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(Array([Route.practice, .howItWorks, .comparison, .privacy].enumerated()), id: \.element) { i, route in
                    NavigationLink(value: route) { Tile(route: route) }
                        .buttonStyle(PressStyle())
                        .rise(after: 0.35 + Double(i) * 0.07)
                }
            }
        }
    }
}

/// Tips-style feature card: illustration, headline and one clear next action.
/// Everything rises in on a short stagger; the button then breathes a light sweep and nudges its arrow.
struct HeroCard: View {
    let action: String
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADAPTIVE KEYBOARD")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.85))
                .rise(after: 0.05)
            TouchMap()
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .rise(after: 0.12)
            VStack(alignment: .leading, spacing: 8) {
                Text("A keyboard that learns how you touch.")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap a few keys and \(appName) learns where your touches land, then reads them that way in Notes, Messages and most other apps.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .rise(after: 0.22)
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Text(action).contentTransition(.opacity)
                    nudgingArrow
                }
                .font(.headline)
                .foregroundStyle(Color(rgb: 0x1A1F6B))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white, in: Capsule())
                .modifier(Shimmer(color: Color(rgb: 0x2B4FD8).opacity(0.16)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
            .buttonStyle(PressStyle())
            .padding(.top, 4)
            .rise(after: 0.32)
            .animation(.easeInOut(duration: 0.25), value: action)
        }
        .padding(20)
        .background { DriftingGlow(paused: reduceMotion) }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .glassFinish(cornerRadius: 30)
        .shadow(color: Color(rgb: 0x1A1F6B).opacity(0.25), radius: 20, y: 10)
    }

    @ViewBuilder private var nudgingArrow: some View {
        let arrow = Image(systemName: "arrow.right").accessibilityHidden(true)
        if #available(iOS 18, *), !reduceMotion {
            arrow.symbolEffect(.wiggle.forward.byLayer, options: .repeat(.periodic(delay: 2.5)))
        } else {
            arrow
        }
    }
}

/// The hero's gradient, with a soft light that slowly circles the card.
struct DriftingGlow: View {
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { timeline in
            let a = paused ? 0.8 : timeline.date.timeIntervalSinceReferenceDate / 9 * .pi * 2
            ZStack {
                Hue.hero.gradient
                RadialGradient(colors: [.white.opacity(0.2), .clear],
                               center: UnitPoint(x: 0.75 + 0.25 * cos(a), y: 0.2 + 0.15 * sin(a)),
                               startRadius: 0, endRadius: 300)
            }
        }
    }
}

/// Settings-style row: icon tile, title and detail open the step; the circle ticks it off.
struct StepRow: View {
    let title: String
    let detail: Text
    let symbol: String
    let hue: Hue
    @Binding var done: Bool
    let open: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Button { if let open { open() } else { done.toggle() } } label: {
                HStack(spacing: 14) {
                    IconTile(symbol: symbol, hue: hue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        detail.font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint(open == nil ? "Marks this step as done" : "Opens this step")

            Button { done.toggle() } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(done ? "Done" : "Not done")
            .accessibilityHint(done ? "Marks this step as not done" : "Marks this step as done")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: done)
        .successHaptic(done)
    }
}

/// Shortcuts-style tile with a half-strength glass finish.
struct Tile: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: route.symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .accessibilityHidden(true)
            Spacer(minLength: 20)
            Text(route.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background(route.hue.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassFinish(cornerRadius: 24)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

// MARK: - Detail pages

/// Icon, title and one-line summary at the top of each page, as in Settings and Feedback Assistant.
struct PageHeader: View {
    let route: Route

    var body: some View {
        VStack(spacing: 10) {
            IconTile(symbol: route.symbol, hue: route.hue, size: 64)
            Text(route.title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(route.blurb).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    }
}

struct SetupView: View {
    var body: some View {
        List {
            Section { PageHeader(route: .setup) }
            Section {
                HowToView(steps: HowTo.enableKeyboard)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open Settings").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .prominentButton()
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                .listRowBackground(Color.clear)
            }
            Section {
                Text("In password boxes, iPhone always uses Apple’s keyboard.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Route.setup.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PracticeView: View {
    @State private var text = "" // memory only; cleared when you leave this screen

    var body: some View {
        List {
            Section { PageHeader(route: .practice) }
            Section {
                HowToView(steps: HowTo.calibrate)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type anything…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Practice text")
                        .accessibilityHint("Nothing typed here is saved")
                }
            } header: {
                Text("Practice")
            } footer: {
                Text("Nothing here is saved. It’s cleared when you leave this screen.")
            }
            Section {
                Text("To watch it read your taps, turn on **Show my touches** in the keyboard’s \(Image(systemName: "gearshape")) menu.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Route.practice.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { text = "" }.disabled(text.isEmpty)
            }
        }
        .onDisappear { text = "" }
    }
}

struct ArticleView: View {
    let route: Route
    let sections: [(heading: String, body: [LocalizedStringKey])]

    var body: some View {
        List {
            Section { PageHeader(route: route) }
            ForEach(sections.indices, id: \.self) { i in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sections[i].heading).font(.headline)
                        ForEach(sections[i].body.indices, id: \.self) { j in
                            Text(sections[i].body[j])
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum Copy {
    static let howItWorks: [(heading: String, body: [LocalizedStringKey])] = [
        ("1. Calibration", [
            "You tap keys we highlight. For each tap we record which key we asked for, where your finger first touched, how it moved, and where it lifted.",
        ]),
        ("2. Learning your pattern", [
            "We measure how far, and in which direction, your touches land from the keys you meant, separately for different parts of the keyboard. Keys with only a few taps borrow from nearby keys so a single unusual tap can’t mislead it.",
            "We also test which point (first contact, lift-off, the path’s average, or where your finger rested longest) best predicts your intended key, and use that one.",
        ]),
        ("3. Reading new taps", [
            "Each new tap is scored against every nearby key using your learned pattern. A small hint from common letter pairs can break near-ties, but never overrules a clear tap.",
            "If two keys are close in score, the keyboard types the more likely one and shows both, so you can switch with one tap. Undo reverses the last action.",
        ]),
        ("4. Keeps adapting as you type", [
            "Calibration gives it a starting point. After that, it keeps learning from letters you pick when it offers two, letters you delete and retype nearby, and letters it was sure about that you kept.",
            "Older evidence fades, and if you suddenly need more fixes than usual, it learns faster. It keeps only running totals per key, never your text. You can turn this off in the keyboard’s settings.",
            "To see it, open the keyboard’s settings and choose **What it learned about my touch**. Each key shows where your taps for it really land, now and right after calibration.",
        ]),
        ("5. Fixing whole words", [
            "When you press space, the keyboard compares the word you typed with 40,000 common words. For each one it adds up how likely each of your taps was to mean that word’s letters, using your own touch pattern, and how common the word is. It also allows for a letter tapped twice, a missed letter, or two letters swapped.",
            "It only changes the word if another one is much more likely, at least 80%. Undo puts your word back, and letters you picked in the two-choice bar are never changed. The word list is built into the keyboard; nothing is sent anywhere.",
        ]),
        ("Limitations", [
            "Big changes can still take a few dozen letters to catch up with; recalibrating is faster. It hasn’t been tested in a clinical study, and it may not help everyone.",
        ]),
    ]

    static let comparison: [(heading: String, body: [LocalizedStringKey])] = [
        ("Three ways of reading your taps", [
            "**Standard keys.** What a normal keyboard types: the key under your finger.",
            "**Larger keys.** The same keyboard with bigger targets.",
            "**Adapted to you.** Your learned touch pattern.",
        ]),
        ("Running the test", [
            "Calibrate first, then open the keyboard’s settings and choose **Typing comparison**. You type 9 short phrases, and the order of the three modes changes each time. Results show time, accuracy, corrections and choices.",
        ]),
        ("What the result means", [
            "It’s your own test on your own phone, not a medical or clinical result. Scores are kept only if you choose to keep them, and you can type a summary into any text field to share it yourself.",
        ]),
    ]

    static let privacy: [(heading: String, body: [LocalizedStringKey])] = [
        ("Stored on this iPhone, inside the keyboard", [
            "Your calibration taps: the key we asked for and where you touched.",
            "The touch pattern learned from them, kept up to date as you type (running totals per key only), and your keyboard settings.",
            "Comparison scores, only if you choose to keep them.",
        ]),
        ("Never stored or sent", [
            "What you type, a history of your keystrokes, or anything about your health. The keyboard has no internet access and doesn’t request **Allow Full Access**. There is no account and no analytics.",
        ]),
        ("Deleting your data", [
            "In the keyboard, open settings and tap **Delete my calibration and settings**. Deleting this app also removes everything.",
        ]),
    ]
}

// MARK: - Previews

#Preview("Home") { HomeView().tint(Palette.accent) }
#Preview("Home, dark") { HomeView().tint(Palette.accent).preferredColorScheme(.dark) }
#Preview("Home, largest text") { HomeView().tint(Palette.accent).dynamicTypeSize(.accessibility3) }
#Preview("Setup") { NavigationStack { SetupView() }.tint(Palette.accent) }
#Preview("Practice pad") { NavigationStack { PracticeView() }.tint(Palette.accent) }
#Preview("Privacy") { NavigationStack { ArticleView(route: .privacy, sections: Copy.privacy) }.tint(Palette.accent) }
