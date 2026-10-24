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
            case .emoji:
                EmojiView(c: c)
            case .menu:
                MenuView(c: c)
            case .learned:
                LearnedView(c: c)
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        // While a word is being typed (or was just autocorrected) the bar is Apple's: three word slots.
        let showsWords = s.pendingChoice == nil && s.pendingExtra == nil && !c.settings.showTouches
            && (s.lastWordFix != nil || !s.suggestions.typed.isEmpty)
        // ⚙︎ and Undo keep their places whatever the middle shows: the suggestion bar must never
        // take over the gear's spot, or the first tap there would pick a word instead of opening settings.
        HStack(spacing: 4) {
            BarButton(title: "Settings", systemImage: "gearshape") { c.screen = .menu }
            if showsWords {
                SuggestionBar(c: c).frame(maxWidth: .infinity)
            } else {
                status.frame(maxWidth: .infinity)
                BarButton(title: "Emoji", systemImage: "face.smiling") { c.screen = .emoji }
            }
            BarButton(title: "Undo", systemImage: "arrow.uturn.backward") { c.undo() }
                .disabled(!s.canUndo)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var status: some View {
        let s = c.session
        Group {
                if s.pendingChoice != nil || s.pendingExtra != nil {
                    ChoiceStrip(c: c)
                } else if c.settings.showTouches {
                    DemoReadout(c: c)
                } else if c.profile == nil && c.settings.adaptationOn {
                    Text("Not calibrated yet — tap ⚙︎ to start").font(.footnote).foregroundStyle(.secondary)
                } else if c.settings.keepAdapting, c.profile?.adaptive?.isAdaptingFast == true {
                    Label("Your taps changed — adapting faster", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Spacer()
                }
        }
    }
}

/// Apple-style suggestion bar: “what you typed” | the word space will put in (highlighted) | the next best word.
/// Right after an autocorrect it offers the typed word back instead.
struct SuggestionBar: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        let s = c.session
        if let fix = s.lastWordFix {
            Button { c.revertWordFix() } label: {
                Label("Change back to “\(fix.typed)”", systemImage: "arrow.uturn.backward")
                    .font(.body).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Undoes the autocorrection")
        } else {
            let w = s.suggestions
            let middle = w.autocorrect ?? w.others.first
            let right = w.autocorrect == nil ? w.others.dropFirst().first : w.others.first
            HStack(spacing: 0) {
                slot("“\(w.typed)”", word: w.typed, hint: "Keeps what you typed")
                divider
                slot(middle, word: middle, highlighted: w.autocorrect != nil,
                     hint: w.autocorrect != nil ? "Space will type this" : nil)
                divider
                slot(right, word: right)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(.separator)).frame(width: 1, height: 24)
    }

    @ViewBuilder
    private func slot(_ title: String?, word: String?, highlighted: Bool = false, hint: String? = nil) -> some View {
        if let title, let word {
            Button { c.acceptSuggestion(word) } label: {
                Text(title)
                    .font(highlighted ? .body.weight(.semibold) : .body)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(highlighted ? Color(.systemGray5) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint ?? "")
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
        }
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
                     + ".")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLinkLike(title: "What it learned about my touch") { c.screen = .learned }
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
            Toggle("Capitalize the first letter of sentences", isOn: $c.settings.capitalizeSentences)
            Toggle("Hold backspace to keep deleting", isOn: $c.settings.holdToDelete)
            Toggle("Auto-Correction", isOn: $c.settings.fixWords)
            Text("Word suggestions show above the keys while you type. With Auto-Correction on, space (or . , ? !) puts in the highlighted word. When you press space, it compares the word you typed with 40,000 common words, using how likely each of your taps was to mean each letter. It can also fix a letter tapped twice, a missed letter, or two swapped letters. It only changes the word if another one is much more likely. Undo puts your word back. Letters you picked in the two-choice bar are never changed.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Keep adapting as I type", isOn: $c.settings.keepAdapting)
            Text("The keyboard keeps learning from letters you pick in the two-choice bar, letters you delete and retype nearby, and letters it was sure about that you kept. Older evidence slowly fades, so it follows how you type now. If you suddenly need to fix more letters than usual, it learns faster for a while. It stores only running totals per key — never your text or the order of letters.")
                .font(.footnote).foregroundStyle(.secondary)
            if let a = c.profile?.adaptive, a.updates > 0 {
                Text("Learned while typing: \(a.count(.picked)) picks, \(a.count(.corrected)) corrections, \(a.count(.confident)) sure taps. Letters needing a fix lately: \(Int((a.recentFixRate * 100).rounded()))% (usual \(Int((a.usualFixRate * 100).rounded()))%).")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Go back to just my calibration") { c.resetAdaptation() }
                    .buttonStyle(.bordered)
            }

            Text("What this keyboard stores")
                .font(.subheadline.bold())
            Text("Only your calibration taps (the key we asked for and where your finger touched), the touch pattern learned from them, running per-key totals learned while you type (if “Keep adapting” is on), these settings, and comparison scores if you choose to keep them. It never stores what you type, has no internet access, and does not need “Allow Full Access”. Password fields always use Apple’s keyboard.")
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
            if c.isFitting {
                ProgressView("Learning your touch pattern…").frame(maxWidth: .infinity)
            } else if let m = c.profile?.model, !m.evaluation.isEmpty {
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
            Button("Start typing") { c.screen = .typing }.buttonStyle(.borderedProminent).disabled(c.isFitting)
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

/// Draws what the model learned: for each letter, where this person's taps for it really land (shaded oval,
/// sized by how spread out they are), compared with right after calibration (dashed).
struct LearnedView: View {
    @ObservedObject var c: KeyboardController

    var body: some View {
        Panel(title: "What it learned about my touch") {
            if let p = c.profile {
                let now = p.model
                let before = p.calibrationModel
                let layout = KeyboardLayout.make(page: .letters, width: c.width, rowHeight: KeyboardController.baseRowHeight,
                                                 showNextKeyboard: false)
                Canvas { ctx, size in
                    let s = size.width / layout.width
                    ctx.scaleBy(x: s, y: s)
                    for key in layout.keys where key.kind == .character && key.id.first?.isLetter == true {
                        let f = key.frame
                        let box = CGRect(x: f.x + 2, y: f.y + 3, width: f.w - 4, height: f.h - 6)
                        ctx.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(.secondary.opacity(0.4)))
                        ctx.draw(Text(key.label).font(.caption).foregroundColor(.secondary),
                                 at: CGPoint(x: f.center.x, y: f.center.y))
                        oval(ctx, key, before, fill: false)
                        oval(ctx, key, now, fill: true)
                        let aim = f.center + now.offset(for: key)
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: f.center.x, y: f.center.y))
                        arrow.addLine(to: CGPoint(x: aim.x, y: aim.y))
                        ctx.stroke(arrow, with: .color(.accentColor), lineWidth: 1.5)
                        ctx.fill(Path(ellipseIn: CGRect(x: aim.x - 2.5, y: aim.y - 2.5, width: 5, height: 5)), with: .color(.accentColor))
                    }
                }
                .aspectRatio(layout.width / (layout.rowHeight * 3), contentMode: .fit)
                .accessibilityLabel(summary(now))
                Text(summary(now)).font(.callout)
                Text("Each arrow goes from the middle of a key to where your taps for that letter usually land. The shaded oval shows how spread out they are: bigger means more spread. The dashed oval is what calibration measured; if they differ, the keyboard has adapted since.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let a = p.adaptive, a.updates > 0 {
                    Text("Updated from \(a.updates) letters you typed since calibration.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Back") { c.screen = .menu }.buttonStyle(.borderedProminent)
        }
    }

    private func oval(_ ctx: GraphicsContext, _ key: Key, _ model: TouchModel, fill: Bool) {
        let center = key.frame.center + model.offset(for: key)
        let e = model.cov(for: key).ellipse
        let shape = Path(ellipseIn: CGRect(x: -e.major, y: -e.minor, width: 2 * e.major, height: 2 * e.minor))
            .applying(CGAffineTransform(rotationAngle: e.angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        if fill {
            ctx.fill(shape, with: .color(.accentColor.opacity(0.2)))
        } else {
            ctx.stroke(shape, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func summary(_ m: TouchModel) -> String {
        let o = m.globalOffset
        func part(_ v: Double, _ pos: String, _ neg: String) -> String? {
            abs(v) < 2 ? nil : "\(Int(abs(v).rounded())) points \(v > 0 ? pos : neg)"
        }
        let parts = [part(o.x, "to the right", "to the left"), part(o.y, "lower", "higher")].compactMap { $0 }
        return parts.isEmpty ? "On average your taps land close to the middle of the key you mean."
            : "Compared with the middle of the key you mean, your taps land on average \(parts.joined(separator: " and "))."
    }
}

// MARK: - Emoji

/// Big, well-spaced emoji buttons (easier to hit than the system emoji keyboard). Emoji are typed as is.
struct EmojiView: View {
    @ObservedObject var c: KeyboardController

    static let emoji = ["😀", "😂", "😊", "😍", "🥰", "😘", "😉", "😎",
                        "🤔", "😮", "😢", "😭", "😡", "😴", "🤒", "🙂",
                        "👍", "👎", "👏", "🙏", "💪", "👋", "🤝", "👌",
                        "❤️", "💙", "💚", "💛", "💜", "🧡", "💯", "🔥",
                        "🎉", "🎂", "🎁", "☀️", "🌧️", "🌸", "⭐️", "✅",
                        "❌", "☕️", "🍕", "🏠", "🚗", "✈️", "📞", "📷"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Self.emoji, id: \.self) { e in
                        Button { c.insertEmoji(e) } label: {
                            Text(e).font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .accessibilityLabel(e)
                    }
                }
                .padding(4)
            }
            HStack(spacing: 8) {
                Button("ABC") { c.screen = .typing }
                    .font(.headline).frame(width: 72, height: 44)
                Button { c.insertEmoji(" ") } label: {
                    Text("space").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                BarButton(title: "Delete", systemImage: "delete.left") { c.repeatBackspace() }
            }
            .padding(.horizontal, 6).padding(.bottom, 4)
        }
    }
}
