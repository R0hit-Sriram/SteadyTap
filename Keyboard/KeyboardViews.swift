import SwiftUI
import TouchEngine

struct KeyboardRootView: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        Group {
            switch c.screen {
            case .typing, .calibrating, .comparing:
                VStack(spacing: 0) {
                    ToolbarView(c: c).frame(height: c.toolbarHeight)
                    SurfaceView(c: c).frame(height: c.layout.height)
                }
            case .menu:
                MenuView(c: c)
            case .calibrationDone:
                CalibrationDoneView(c: c)
            case .comparisonIntro:
                ComparisonIntroView(c: c)
            case .comparisonDone:
                ComparisonDoneView(c: c)
            }
        }
        .frame(height: c.totalHeight)
    }
}

// MARK: - Key surface

struct SurfaceView: UIViewRepresentable {
    @ObservedObject var c: KeyboardController

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        let controller = c
        view.onGesture = { [weak controller] g in controller?.handle(g) }
        view.onGlobe = { [weak controller] v, e in controller?.onGlobe?(v, e) }
        view.onBackspaceRepeat = { [weak controller] in controller?.repeatBackspace() }
        return view
    }

    func updateUIView(_ v: TouchSurfaceView, context: Context) {
        v.layout = c.layout
        v.shift = c.activeSession.shift
        v.holdToDelete = c.settings.holdToDelete && c.screen != .calibrating
        v.targetKeyID = c.screen == .calibrating ? c.calibration?.currentTarget : nil
        v.flashKeyID = c.flashKeyID
        v.showTouches = c.settings.showTouches && c.screen == .typing
        v.trail = c.trail
        v.model = c.session.model
        v.candidates = c.lastDecision?.candidates ?? []
        v.setNeedsDisplay()
    }
}

// MARK: - Toolbar

struct BarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 52, height: 44)
        }
        .accessibilityLabel(title)
    }
}

struct ToolbarView: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        switch c.screen {
        case .calibrating: CalibrationBar(c: c)
        case .comparing: ComparisonBar(c: c)
        default: TypingBar(c: c)
        }
    }
}

/// Choice between two letters, or "keep the extra tap" — shared by typing and comparison.
struct ChoiceStrip: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        let s = c.activeSession
        if let choice = s.pendingChoice {
            HStack(spacing: 8) {
                Button { c.acceptChoice() } label: {
                    Text(choice.inserted).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Keep \(choice.inserted)")
                Button { c.chooseAlternative() } label: {
                    Text(choice.alternative).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Change to \(choice.alternative)")
            }
        } else if let extra = s.pendingExtra {
            Button { c.keepExtra() } label: {
                Text("Quick extra tap ignored — add “\(extra)”").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct TypingBar: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        let s = c.session
        HStack(spacing: 4) {
            BarButton(title: "Settings", systemImage: "gearshape") { c.screen = .menu }
            Group {
                if s.pendingChoice != nil || s.pendingExtra != nil {
                    ChoiceStrip(c: c)
                } else if c.settings.showTouches {
                    DemoReadout(c: c)
                } else if c.profile == nil && c.settings.adaptationOn {
                    Text("Not calibrated yet — tap ⚙︎ to start").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            BarButton(title: "Undo", systemImage: "arrow.uturn.backward") { c.undo() }
                .disabled(!s.canUndo)
        }
        .padding(.horizontal, 4)
    }
}

/// Live explanation of the last decision for the demo view.
struct DemoReadout: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let d = c.lastDecision, !d.candidates.isEmpty {
                Text(d.candidates.prefix(3).map { "\($0.keyID) \(Int(($0.probability * 100).rounded()))%" }.joined(separator: " · "))
                    .font(.footnote.monospaced().bold())
            } else {
                Text(c.session.model == nil ? "Adaptation off: fixed keyboard" : "Tap a key to see its scores")
                    .font(.footnote)
            }
            Text("Fixed keyboard: \(c.session.demoFixed)").font(.footnote.monospaced()).foregroundStyle(.orange)
            Text("Adapted:        \(c.session.demoAdapted)").font(.footnote.monospaced())
        }
        .lineLimit(1)
        .truncationMode(.head)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalibrationBar: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        if let cal = c.calibration {
            HStack {
                if cal.isOnBreak {
                    Text("Set \(cal.setIndex) of \(cal.sets.count) done. Rest as long as you like.")
                        .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Save & stop") { c.finishCalibration() }
                    Button("Continue") { c.continueCalibration() }.buttonStyle(.borderedProminent)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tap the blue key. No need to hurry.").font(.callout.bold())
                        ProgressView(value: Double(cal.completedTargets), total: Double(cal.totalTargets))
                    }
                    Button(cal.setIndex == 0 ? "Cancel" : "Save & stop") {
                        cal.setIndex == 0 ? c.cancelCalibration() : c.finishCalibration()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct ComparisonBar: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        if let run = c.comparison {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Test \(run.trialIndex + 1) of \(run.totalTrials) · \(run.currentMode.title)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { c.undo() }.disabled(!run.session.canUndo)
                    Button("Done") { c.finishPhrase() }.buttonStyle(.borderedProminent)
                }
                Text(run.currentPhrase).font(.title3.bold())
                if run.session.pendingChoice != nil || run.session.pendingExtra != nil {
                    ChoiceStrip(c: c)
                } else {
                    Text(run.buffer.text + "▏").font(.title3.monospaced()).lineLimit(1).truncationMode(.head)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Panels

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.headline)
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct MenuView: View {
    @ObservedObject var c: KeyboardController
    @State private var confirmDelete = false

    var body: some View {
        Panel(title: "Keyboard settings") {
            Button("Back to typing") { c.screen = .typing }.buttonStyle(.borderedProminent)

            Button(c.profile == nil ? "Calibrate (about 2 minutes)" : "Recalibrate") { c.startCalibration() }
                .buttonStyle(.bordered)
            if let p = c.profile {
                Text("Learned from \(p.samples.count) calibration taps on \(p.createdAt.formatted(date: .abbreviated, time: .omitted))"
                     + (p.confirmedCount > 0 ? ", plus \(p.confirmedCount) of your choices." : "."))
                    .font(.footnote).foregroundStyle(.secondary)
                if !p.model.evaluation.isEmpty {
                    NavigationLinkLike(title: "What each part of the model adds") { c.screen = .calibrationDone }
                }
            }
            Button("Typing comparison") { c.screen = .comparisonIntro }
                .buttonStyle(.bordered)
                .disabled(c.profile == nil)

            Toggle("Adapt to my touch", isOn: $c.settings.adaptationOn)
            VStack(alignment: .leading) {
                Text("Key height")
                Picker("Key height", selection: $c.settings.keySize) {
                    Text("Standard").tag(KeySize.standard)
                    Text("Large").tag(KeySize.large)
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading) {
                Text("Offer two choices when unsure")
                Picker("Offer two choices when unsure", selection: $c.settings.askLevel) {
                    Text("Often").tag(AskLevel.often)
                    Text("Sometimes").tag(AskLevel.sometimes)
                    Text("Rarely").tag(AskLevel.rarely)
                }
                .pickerStyle(.segmented)
            }
            Toggle("Use common letter pairs as a small hint", isOn: $c.settings.useLetterPatterns)
            Toggle("Show my touches (explains each decision)", isOn: $c.settings.showTouches)
            Toggle("Hold backspace to keep deleting", isOn: $c.settings.holdToDelete)
            Toggle("Keep learning from letters I pick", isOn: $c.settings.learnFromChoices)
            Text("When two letters are offered and you tap one, that tells us what that touch meant. If this is on, we add it to your touch pattern as a running total for that key — never the text or the order of letters. Newer choices count more than old ones.")
                .font(.footnote).foregroundStyle(.secondary)

            Text("What this keyboard stores")
                .font(.subheadline.bold())
            Text("Only your calibration taps (the key we asked for and where your finger touched), the touch pattern learned from them, per-key totals from letters you picked (if you turned that on), these settings, and comparison scores if you choose to keep them. It never stores what you type, has no internet access, and does not need “Allow Full Access”. Password fields always use Apple’s keyboard.")
                .font(.footnote)

            Button(role: .destructive) {
                if confirmDelete {
                    c.deleteAllData()
                    confirmDelete = false
                } else {
                    confirmDelete = true
                }
            } label: {
                Text(confirmDelete ? "Tap again to delete everything" : "Delete my calibration and settings")
            }
            .buttonStyle(.bordered)
        }
    }
}

struct CalibrationDoneView: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        Panel(title: "Your touch pattern") {
            if let m = c.profile?.model, !m.evaluation.isEmpty {
                Text("Each of your \(c.profile?.samples.count ?? 0) calibration taps was predicted by a model that had **not** seen that tap. Share read correctly:")
                    .font(.callout)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(m.evaluation.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label)
                                .font(row.isComparison ? Font.footnote.italic() : Font.footnote)
                                .foregroundStyle(row.isComparison ? Color.secondary : Color.primary)
                            AccuracyBar(value: row.accuracy)
                        }
                    }
                }
                Text("Your \(m.pointKind.plainName) predicted your intended key best.").font(.callout)
                if m.repeatFilter.enabled {
                    Text("We noticed a few quick extra touches. A very fast second touch in the same spot will now ask before typing.")
                        .font(.callout)
                }
                Text("Checked on taps from this one calibration session, so everyday typing may score lower. These numbers are not a medical measurement.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Start typing") { c.screen = .typing }.buttonStyle(.borderedProminent)
        }
    }
}

struct AccuracyBar: View {
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(Color.accentColor).frame(width: g.size.width * max(0, min(1, value)))
                }
            }
            .frame(width: 70, height: 10)
            Text("\(Int((value * 100).rounded()))%").font(.footnote.monospacedDigit().bold())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((value * 100).rounded())) percent")
    }
}

/// A plain row button that looks like a navigation link (the keyboard has no navigation stack).
struct NavigationLinkLike: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
    }
}

struct ComparisonIntroView: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        Panel(title: "Typing comparison (optional)") {
            Text("Type 9 short phrases: 3 with standard keys, 3 with larger keys, and 3 with the keyboard adapted to you. The order changes each time. Nothing you type here goes into the app underneath.")
                .font(.callout)
            Text("We measure time, accuracy, corrections and choices. This is your own test, not a medical or clinical result.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Not now") { c.screen = .menu }.buttonStyle(.bordered)
                Button("Start") { c.startComparison() }.buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ComparisonDoneView: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        Panel(title: "Your results") {
            if let run = c.comparison {
                Text(run.summary()).font(.footnote)
                let earlier = c.allKeptResults.count - run.results.count
                if earlier > 0 {
                    Text("Including your \(earlier) earlier saved phrases:").font(.footnote.bold())
                    Text(ComparisonStats.report(c.allKeptResults)).font(.footnote)
                }
                Toggle("Keep these scores on this iPhone", isOn: $c.keepComparisonResults)
                Button("Type this summary into the current text field") { c.insertIntoHost?(run.summary()) }
                    .buttonStyle(.bordered)
            }
            Button("Done") { c.closeComparison() }.buttonStyle(.borderedProminent)
        }
    }
}
