import SwiftUI

/// The display name comes from project.yml (APP_DISPLAY_NAME) so renaming happens in one place.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SteadyTap"

@main
struct SteadyTapApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A keyboard that learns how **you** touch the screen.")
                        .font(.title3)
                    Text("If you often hit the key next to the one you meant, \(appName) can learn your personal touch pattern from a short tapping exercise and use it to read your taps more accurately — in Notes, Messages and most other apps.")
                    Text("No diagnosis needed. No account. Nothing you type leaves your phone.")
                        .foregroundStyle(.secondary)
                }
                Section("Get started") {
                    NavigationLink("1. Turn on the keyboard") { SetupView() }
                    NavigationLink("2. Calibrate and try it") { PracticeView() }
                    NavigationLink("Optional: compare keyboards") { ComparisonInfoView() }
                }
                Section("Learn more") {
                    NavigationLink("How it decides which key you meant") { HowItWorksView() }
                    NavigationLink("Privacy and what is stored") { PrivacyView() }
                }
            }
            .navigationTitle(appName)
        }
    }
}

struct SetupView: View {
    var body: some View {
        List {
            Section("Add the keyboard") {
                Step(n: 1, "Open the **Settings** app.")
                Step(n: 2, "Go to **General → Keyboard → Keyboards**.")
                Step(n: 3, "Tap **Add New Keyboard…** and choose **\(appName)**.")
                Step(n: 4, "Leave **Allow Full Access** off. \(appName) does not need it.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text("This opens \(appName)’s page in Settings. If you see **Keyboards** there, you can turn it on directly.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Switch to it while typing") {
                Text("In any text field, tap or hold the 🌐 globe key and pick \(appName). Tap 🌐 on \(appName) to switch back.")
            }
            Section("Where it can’t be used") {
                Text("For your security, iPhone always switches to Apple’s keyboard in password fields and phone-number pads. Some apps (often banking apps) also block other keyboards.")
            }
        }
        .navigationTitle("Turn on the keyboard")
    }
}

struct Step: View {
    let n: Int
    let text: LocalizedStringKey
    init(n: Int, _ text: LocalizedStringKey) {
        self.n = n
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 28, height: 28).background(Circle().fill(.tint.opacity(0.2)))
            Text(text)
        }
    }
}

struct PracticeView: View {
    @State private var text = "" // memory only; cleared when you leave this screen

    var body: some View {
        Form {
            Section("Calibrate") {
                Text("Tap the field below, switch to \(appName) with the 🌐 key, then tap the ⚙︎ gear on the keyboard and choose **Calibrate**. You’ll tap highlighted keys in three short sets, with breaks whenever you like.")
            }
            Section("Practice here (not saved)") {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .accessibilityLabel("Practice text")
                Button("Clear") { text = "" }
            }
            Section {
                Text("Tip: turn on **Show my touches** in the keyboard’s ⚙︎ menu to see where each tap landed and which key was chosen.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Calibrate and try it")
        .onDisappear { text = "" }
    }
}

struct ComparisonInfoView: View {
    var body: some View {
        List {
            Text("The keyboard includes an optional test that compares three ways of reading your taps:")
            Label("Standard keys", systemImage: "keyboard")
            Label("Larger keys", systemImage: "rectangle.expand.vertical")
            Label("Adapted to you", systemImage: "hand.point.up.left")
            Text("To start it, calibrate first, then open the keyboard’s ⚙︎ menu and choose **Typing comparison**. You type 6 short phrases; the order of the three modes changes each time. Results show time, accuracy, corrections and choices.")
            Text("It’s your own test on your own phone — not a medical or clinical result. Scores are kept only if you choose to keep them, and you can type a summary into any text field to share it yourself.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Compare keyboards")
    }
}

struct HowItWorksView: View {
    var body: some View {
        List {
            Section("1. Calibration") {
                Text("You tap keys we highlight. For each tap we record which key we asked for, where your finger first touched, how it moved, and where it lifted.")
            }
            Section("2. Learning your pattern") {
                Text("We measure how far, and in which direction, your touches land from the keys you meant, separately for different parts of the keyboard. Keys with only a few taps borrow from nearby keys so a single unusual tap can’t mislead it.")
                Text("We also test which point — first contact, lift-off, the path’s average, or where your finger rested longest — best predicts your intended key, and use that one.")
            }
            Section("3. Reading new taps") {
                Text("Each new tap is scored against every nearby key using your learned pattern. A tiny hint from common letter pairs can break near-ties, but never overrules a clear tap.")
                Text("If two keys are close in score, the keyboard types the more likely one and shows both, so you can switch with one tap. Undo reverses the last action.")
            }
            Section("Limitations") {
                Text("It learns from your calibration only, not from what you type. If your movements change during the day, recalibrate. It hasn’t been tested in a clinical study, and it may not help everyone.")
            }
        }
        .navigationTitle("How it works")
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Stored on this iPhone, inside the keyboard") {
                Text("• Your calibration taps (the key we asked for and where you touched)\n• The touch pattern learned from them\n• Keyboard settings\n• Comparison scores, only if you choose to keep them")
            }
            Section("Never stored or sent") {
                Text("What you type, a history of your keystrokes, or anything about your health. The keyboard has no internet access and does not request “Allow Full Access”. There is no account and no analytics.")
            }
            Section("Deleting your data") {
                Text("In the keyboard, open ⚙︎ and tap **Delete my calibration and settings**. Deleting this app also removes everything.")
            }
        }
        .navigationTitle("Privacy")
    }
}
