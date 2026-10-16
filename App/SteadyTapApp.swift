import SwiftUI

/// The display name comes from project.yml (APP_DISPLAY_NAME) so renaming happens in one place.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SteadyTap"

@main
struct SteadyTapApp: App {
    var body: some Scene {
        WindowGroup { HomeView().tint(Palette.accent) }
    }
}

enum Route: Hashable { case setup, practice, howItWorks, comparison, privacy }

// MARK: - Home

struct HomeView: View {
    // The app can't see inside the keyboard (no Full Access, no shared storage), so people tick steps off themselves.
    @AppStorage("step.added") private var added = false
    @AppStorage("step.calibrated") private var calibrated = false
    @AppStorage("step.typed") private var typed = false
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(appName)
                        .font(.brand)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, -12)
                    hero
                    steps
                    learnMore
                    Label("No account and no internet access. What you type is never stored.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(appName)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .setup: SetupView()
                case .practice: PracticeView()
                case .howItWorks: ArticleView(title: "How it works", sections: Copy.howItWorks)
                case .comparison: ArticleView(title: "Compare keyboards", sections: Copy.comparison)
                case .privacy: ArticleView(title: "Privacy", sections: Copy.privacy)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            TouchMap()
                .frame(maxWidth: 340)
                .padding(24)
                .frame(maxWidth: .infinity)
                .card()
            Text("A keyboard that learns how you touch.")
                .font(.hero)
                .foregroundStyle(Palette.ink)
            Text("If you often hit the key next to the one you meant, \(appName) learns your own touch pattern from a short tapping exercise, then uses it to read your taps in Notes, Messages and most other apps.")
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Build your keyboard").font(.heading).foregroundStyle(Palette.ink)
                Spacer()
                Text("\([added, calibrated, typed].filter { $0 }.count) of 3")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.inkSoft)
            }
            Text("Tap a number to tick off a step.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)

            StepCard(number: 1, title: "Add it to your iPhone", done: $added,
                     detail: Text("Turn on \(appName) in Settings. It never asks for Full Access.")) {
                Button("Show me how") { path.append(.setup) }.buttonStyle(QuietButtonStyle())
            }
            StepCard(number: 2, title: "Teach it your touch", done: $calibrated,
                     detail: Text("Tap 63 highlighted keys in three short sets. Take a break whenever you like.")) {
                Button("Open the practice pad") { path.append(.practice) }.buttonStyle(QuietButtonStyle())
            }
            StepCard(number: 3, title: "Type anywhere", done: $typed,
                     detail: Text("In any app, hold \(Image(systemName: "globe")) and choose \(appName). When a tap is close to two keys, both letters appear so one tap can switch.")) {
                EmptyView()
            }
        }
    }

    private var learnMore: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good to know").font(.heading).foregroundStyle(Palette.ink)
            VStack(spacing: 0) {
                LinkRow(title: "How it decides which key you meant", icon: "scope", route: .howItWorks)
                Divider().overlay(Palette.line).padding(.leading, 56)
                LinkRow(title: "Compare keyboards on yourself", icon: "chart.bar", route: .comparison)
                Divider().overlay(Palette.line).padding(.leading, 56)
                LinkRow(title: "Privacy and what is stored", icon: "lock", route: .privacy)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .card()
        }
    }
}

struct StepCard<Action: View>: View {
    let number: Int
    let title: String
    @Binding var done: Bool
    let detail: Text
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { done.toggle() } label: {
                ZStack {
                    Circle().fill(done ? Palette.done : .clear)
                    Circle().strokeBorder(done ? Palette.done : Palette.line, lineWidth: 1.5)
                    if done {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Palette.card)
                    } else {
                        Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    }
                }
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Step \(number), \(title)")
            .accessibilityValue(done ? "Done" : "Not done")
            .accessibilityHint(done ? "Marks this step as not done" : "Marks this step as done")

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                detail.font(.subheadline).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                action.padding(.top, 6)
            }
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding([.trailing, .bottom], 16)
        .padding(.top, 6)
        .card()
        .animation(.easeOut(duration: 0.2), value: done)
    }
}

struct LinkRow: View {
    let title: String
    let icon: String
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 26).accessibilityHidden(true)
                Text(title).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkSoft)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

// MARK: - Shared page shell

struct Page<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(title)
    }
}

struct NumberedStep: View {
    let n: Int
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Palette.accent)
                .frame(minWidth: 16, alignment: .leading)
            text.foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Note: View {
    let heading: String
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline).foregroundStyle(Palette.ink)
            text.foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Setup

struct SetupView: View {
    var body: some View {
        Page(title: "Add the keyboard") {
            VStack(alignment: .leading, spacing: 16) {
                NumberedStep(n: 1, text: Text("Open the **Settings** app."))
                NumberedStep(n: 2, text: Text("Go to **General → Keyboard → Keyboards**."))
                NumberedStep(n: 3, text: Text("Tap **Add New Keyboard…** and choose **\(appName)**."))
                NumberedStep(n: 4, text: Text("Leave **Allow Full Access** off. \(appName) doesn’t need it."))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Text("This opens \(appName)’s page in Settings. If you see **Keyboards** there, you can turn it on directly.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .padding(.bottom, 8)

            Note(heading: "Switching to it while typing",
                 text: Text("In any text field, tap or hold \(Image(systemName: "globe")) and pick \(appName). Tap \(Image(systemName: "globe")) on \(appName) to switch back."))
            Note(heading: "Where it can’t be used",
                 text: Text("For your security, iPhone always switches to Apple’s keyboard in password fields and phone-number pads. Some apps, often banking apps, also block other keyboards."))
        }
    }
}

// MARK: - Practice

struct PracticeView: View {
    @State private var text = "" // memory only; cleared when you leave this screen

    var body: some View {
        Page(title: "Practice pad") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calibrate here").font(.headline).foregroundStyle(Palette.ink)
                NumberedStep(n: 1, text: Text("Tap the box below."))
                NumberedStep(n: 2, text: Text("Switch to \(appName) with \(Image(systemName: "globe"))."))
                NumberedStep(n: 3, text: Text("Tap \(Image(systemName: "gearshape")) on the keyboard and choose **Calibrate**. You’ll tap highlighted keys in three short sets."))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Type anything. Nothing here is saved.")
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Practice text")
                    .accessibilityHint("Nothing typed here is saved")
            }
            .padding(14)
            .card()

            HStack {
                Text("Cleared when you leave this screen.").font(.footnote).foregroundStyle(Palette.inkSoft)
                Spacer()
                Button("Clear") { text = "" }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(text.isEmpty)
                    .opacity(text.isEmpty ? 0.4 : 1)
            }

            Note(heading: "See what it sees",
                 text: Text("Turn on **Show my touches** in the keyboard’s \(Image(systemName: "gearshape")) menu. Each tap shows where it landed and which key was chosen."))
        }
        .onDisappear { text = "" }
    }
}

// MARK: - Articles

struct ArticleView: View {
    let title: String
    let sections: [(heading: String, body: [LocalizedStringKey])]

    var body: some View {
        Page(title: title) {
            ForEach(sections.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    Text(sections[i].heading).font(.headline).foregroundStyle(Palette.ink)
                    ForEach(sections[i].body.indices, id: \.self) { j in
                        Text(sections[i].body[j]).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
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
        ("Limitations", [
            "It learns from your calibration only, not from what you type. If your movements change during the day, recalibrate. It hasn’t been tested in a clinical study, and it may not help everyone.",
        ]),
    ]

    static let comparison: [(heading: String, body: [LocalizedStringKey])] = [
        ("Three ways of reading your taps", [
            "**Standard keys.** What a normal keyboard types: the key under your finger.",
            "**Larger keys.** The same keyboard with bigger targets.",
            "**Adapted to you.** Your learned touch pattern.",
        ]),
        ("Running the test", [
            "Calibrate first, then open the keyboard’s settings and choose **Typing comparison**. You type 6 short phrases, and the order of the three modes changes each time. Results show time, accuracy, corrections and choices.",
        ]),
        ("What the result means", [
            "It’s your own test on your own phone, not a medical or clinical result. Scores are kept only if you choose to keep them, and you can type a summary into any text field to share it yourself.",
        ]),
    ]

    static let privacy: [(heading: String, body: [LocalizedStringKey])] = [
        ("Stored on this iPhone, inside the keyboard", [
            "Your calibration taps: the key we asked for and where you touched.",
            "The touch pattern learned from them, and your keyboard settings.",
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
#Preview("Privacy") { NavigationStack { ArticleView(title: "Privacy", sections: Copy.privacy) }.tint(Palette.accent) }
