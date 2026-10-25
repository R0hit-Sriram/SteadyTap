import SwiftUI
import TouchEngine

typealias Gesture = TouchEngine.Gesture   // SwiftUI also has a Gesture type

/// Sends text to whatever app the keyboard is typing into.
final class ProxyTarget: TextTarget {
    weak var viewController: UIInputViewController?
    var textBeforeCursor: String? { viewController?.textDocumentProxy.documentContextBeforeInput }
    func insert(_ text: String) { viewController?.textDocumentProxy.insertText(text) }
    func deleteBackward() { viewController?.textDocumentProxy.deleteBackward() }
}

enum Screen: Equatable {
    case typing, emoji, menu, learned, calibrating, calibrationDone, comparisonIntro, comparing, comparisonDone
}

/// One touch kept on screen for the "show my touches" view. Memory only.
struct TrailMark: Identifiable {
    let id = UUID()
    let path: [Vec2]
    let usedPoint: Vec2
    let chosenCenter: Vec2?
    let correctedByAdaptation: Bool
}

/// The typing comparison: three keyboard modes × two phrases each, typed into a private buffer
/// (never into the app underneath). Keeps measurements only.
final class ComparisonRun {
    let order: [ComparisonMode]
    private(set) var trialIndex = 0
    private(set) var results: [TrialResult] = []
    private(set) var buffer = BufferTarget()
    private(set) var session: TypingSession
    private var startTime: Double?
    private let model: TouchModel
    private let settings: KeyboardSettings

    init(run: Int, model: TouchModel, settings: KeyboardSettings) {
        order = ComparisonPlan.modeOrder(run: run)
        self.model = model
        self.settings = settings
        session = TypingSession(target: nil)
        startTrial()
    }

    var totalTrials: Int { order.count * ComparisonPlan.phrasesPerMode }
    var isDone: Bool { trialIndex >= totalTrials }
    var currentMode: ComparisonMode { order[min(trialIndex, totalTrials - 1) / ComparisonPlan.phrasesPerMode] }
    var currentPhrase: String {
        let i = min(trialIndex, totalTrials - 1)
        return ComparisonPlan.phraseSets[i / ComparisonPlan.phrasesPerMode][i % ComparisonPlan.phrasesPerMode]
    }

    @discardableResult
    func handle(_ gesture: Gesture, layout: KeyboardLayout) -> Decision {
        if startTime == nil { startTime = gesture.down.t }
        return session.handle(gesture, layout: layout)
    }

    func finishPhrase(now: Double) {
        let seconds = startTime.map { max(0, now - $0) } ?? 0
        results.append(TrialResult(mode: currentMode, seconds: seconds,
                                   accuracy: TextMetrics.accuracy(typed: buffer.text, target: currentPhrase),
                                   characters: buffer.text.count, stats: session.stats))
        trialIndex += 1
        if !isDone { startTrial() }
    }

    private func startTrial() {
        buffer = BufferTarget()
        session = TypingSession(target: buffer)
        session.autoCapitalize = false
        session.askThreshold = settings.askLevel.threshold
        let personalized = currentMode == .personalized
        session.model = personalized ? model : nil
        session.context = personalized && settings.useLetterPatterns ? .english : nil
        startTime = nil
    }

    func summary() -> String { ComparisonStats.report(results) }
}

@MainActor
final class KeyboardController: ObservableObject {
    static let baseRowHeight = 54.0

    let store = ProfileStore(directory: ProfileStore.defaultDirectory())
    let proxyTarget: ProxyTarget
    let session: TypingSession

    @Published var settings = KeyboardSettings() {
        didSet {
            if !suppressSave { try? store.save(settings) }
            applySettings()
            reportHeight()
        }
    }
    @Published private(set) var profile: CalibrationProfile?
    @Published var screen: Screen = .typing { didSet { measuredBarHeight = 0; heightCap = nil; reportHeight() } }
    /// Measured height of the bar above the keys. Wrapped text or big Dynamic Type grows the bar,
    /// and the keys must move down rather than sit under it.
    @Published var measuredBarHeight: Double = 0 {
        didSet { if abs(measuredBarHeight - oldValue) > 0.5 { reportHeight() } }
    }
    /// The most height iOS will give the keyboard, once it has given us less than we asked for.
    /// The key rows shrink to fit it, so nothing (Done, the space bar) is cut off.
    @Published private(set) var heightCap: Double?
    @Published private(set) var width: Double = 375
    @Published private(set) var showGlobe = true
    @Published private(set) var flashKeyID: String?
    @Published private(set) var trail: [TrailMark] = []
    @Published private(set) var lastDecision: Decision?
    @Published private(set) var calibration: CalibrationSession?
    @Published private(set) var comparison: ComparisonRun?
    @Published var keepComparisonResults = false
    /// True while the touch model is being fitted after calibration (done off the main thread).
    @Published private(set) var isFitting = false
    /// Bumped after every tap so SwiftUI redraws state held in non-observable engine objects.
    @Published private(set) var revision = 0

    var onGlobe: ((UIView, UIEvent) -> Void)?
    var onHeightChange: ((Double) -> Void)?
    var insertIntoHost: ((String) -> Void)?
    private var suppressSave = false

    init() {
        let target = ProxyTarget()
        proxyTarget = target
        session = TypingSession(target: target)
        settings = store.loadSettings()
        profile = store.loadProfile()
        applySettings()
        session.onLabeledTouch = { [weak self] label in self?.learn(from: label) }
    }

    // MARK: Layout

    /// The session whose state (shift, choice bar…) is currently on screen.
    var activeSession: TypingSession { screen == .comparing ? (comparison?.session ?? session) : session }

    var layout: KeyboardLayout {
        let multiplier: Double
        if screen == .comparing {
            multiplier = comparison?.currentMode == .larger ? KeySize.large.rowHeightMultiplier : 1
        } else {
            multiplier = settings.keySize.rowHeightMultiplier
        }
        let page = screen == .calibrating ? .letters : activeSession.page
        var rowHeight = Self.baseRowHeight * multiplier
        if let heightCap { rowHeight = min(rowHeight, max(36, (heightCap - toolbarHeight) / 4)) }
        return KeyboardLayout.make(page: page, width: width, rowHeight: rowHeight, showNextKeyboard: showGlobe)
    }

    var toolbarHeight: Double { max(minimumBarHeight, measuredBarHeight) }

    private var minimumBarHeight: Double {
        switch screen {
        case .typing: return settings.showTouches ? 84 : 52
        default: return 52
        }
    }

    var totalHeight: Double { toolbarHeight + layout.height }

    func update(width: Double, showGlobe: Bool) {
        guard width > 0, abs(width - self.width) > 0.5 || showGlobe != self.showGlobe else { return }
        self.width = width
        self.showGlobe = showGlobe
        reportHeight()
    }

    private func reportHeight() { onHeightChange?(totalHeight) }

    /// The height iOS actually laid the keyboard out at. Less than we asked for means iOS won't go taller.
    /// (Below the normal typing height it's a passing layout, not a limit, so it's ignored.)
    func viewHeightChanged(_ height: Double) {
        guard height >= 260, height + 1 < totalHeight else { return }
        heightCap = height
        reportHeight()
    }

    // MARK: Typing

    func applySettings() {
        session.model = settings.adaptationOn ? profile?.model : nil
        session.context = settings.useLetterPatterns ? .english : nil
        // Suggestions always show; Auto-Correction only decides whether space changes the word.
        session.autocorrects = settings.fixWords
        if session.words == nil {
            // Reading 40,000 words takes a moment: do it off the main thread so the keyboard opens instantly.
            Task { [weak self] in
                let words = await Task.detached(priority: .userInitiated) { WordList.english }.value
                self?.session.words = words
                self?.revision += 1
            }
        }
        session.askThreshold = settings.askLevel.threshold
        session.recordsDemoLine = settings.showTouches
        session.autoCapitalize = hostAutoCapitalizes && settings.capitalizeSentences
        if !settings.showTouches { trail = [] }
    }

    /// Whether the text field we're typing into wants sentence capitals.
    private var hostAutoCapitalizes = true

    func hostTextChanged(autoCapitalize: Bool) {
        hostAutoCapitalizes = autoCapitalize
        session.autoCapitalize = autoCapitalize && settings.capitalizeSentences
        session.hostTextChanged()
        revision += 1
    }

    func handle(_ gesture: Gesture) {
        let layout = self.layout
        switch screen {
        case .typing:
            show(session.handle(gesture, layout: layout), gesture: gesture, layout: layout)
        case .comparing:
            guard let run = comparison else { return }
            show(run.handle(gesture, layout: layout), gesture: gesture, layout: layout)
        case .calibrating:
            guard let cal = calibration else { return }
            let requested = cal.currentTarget
            let outcome = cal.record(gesture, layout: layout)
            if outcome != .extraTap { flash(requested) } // acknowledge the tap, wherever it landed
            if outcome == .finished { finishCalibration() }
        default:
            break
        }
        revision += 1
    }

    private func show(_ decision: Decision, gesture: Gesture, layout: KeyboardLayout) {
        lastDecision = decision
        flash(decision.keyID)
        guard settings.showTouches, screen == .typing else { return }
        let mark = TrailMark(path: gesture.samples.map(\.p), usedPoint: decision.point,
                             chosenCenter: layout.key(id: decision.keyID)?.frame.center,
                             correctedByAdaptation: decision.adaptationChangedIt)
        trail = Array((trail + [mark]).suffix(8))
    }

    private func flash(_ keyID: String?) {
        flashKeyID = keyID
        guard keyID != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if self?.flashKeyID == keyID { self?.flashKeyID = nil }
        }
    }

    func chooseAlternative() { activeSession.chooseAlternative(); revision += 1 }
    func acceptChoice() { activeSession.acceptChoice(); revision += 1 }
    func keepExtra() { activeSession.keepExtra(); revision += 1 }
    func acceptSuggestion(_ word: String) { session.acceptSuggestion(word); revision += 1 }
    func revertWordFix() { session.revertWordFix(); revision += 1 }
    func undo() { activeSession.undoLast(); revision += 1 }
    func insertEmoji(_ emoji: String) { session.insertText(emoji); revision += 1 }

    func repeatBackspace() {
        guard screen == .typing || screen == .comparing || screen == .emoji else { return }
        activeSession.repeatBackspace()
        revision += 1
    }

    /// Online learning while typing (see OnlineLearner). Only per-key running totals are stored.
    /// Not during calibration or the comparison test, so those stay fair.
    private func learn(from label: LabeledTouch) {
        guard settings.keepAdapting, settings.adaptationOn, screen == .typing, var updated = profile else { return }
        let startedFast = updated.learn(label, layout: layout)
        profile = updated
        applySettings()
        // Save every 10 updates (and right away when a change is detected) instead of on every letter.
        if startedFast || (updated.adaptive?.updates ?? 0) % 10 == 0 { persist() }
    }

    /// Write the profile to disk (also called when the keyboard closes).
    func persist() {
        if let profile { try? store.save(profile) }
        // Keyboard closed on the results screen: keep the scores if asked, instead of losing them.
        if screen == .comparisonDone { closeComparison() }
    }

    /// Forget what was learned while typing; keep the calibration.
    func resetAdaptation() {
        guard var updated = profile else { return }
        updated.resetAdaptation()
        profile = updated
        persist()
        applySettings()
    }

    // MARK: Calibration

    func startCalibration() {
        session.page = .letters
        screen = .calibrating
        calibration = CalibrationSession(sets: CalibrationSession.standardSets(layout: layout))
    }

    func continueCalibration() {
        calibration?.continueAfterBreak()
        revision += 1
    }

    /// Saves whatever has been collected (the model handles partial calibration).
    func finishCalibration() {
        guard let cal = calibration, !cal.samples.isEmpty else { return cancelCalibration() }
        let fitLayout = KeyboardLayout.make(page: .letters, width: width,
                                            rowHeight: Self.baseRowHeight * settings.keySize.rowHeightMultiplier,
                                            showNextKeyboard: showGlobe)
        let samples = cal.samples
        let filter = RepeatFilter.learn(extraTapGaps: cal.extraTapGaps, intentionalRepeatGaps: cal.intentionalRepeatGaps,
                                        keyWidth: fitLayout.keyWidth)
        isFitting = true
        screen = .calibrationDone
        // Fitting tests every tap against a model that never saw it: lots of math, so keep the screen responsive.
        Task { [weak self] in
            let model = await Task.detached(priority: .userInitiated) {
                ModelFitter.fit(samples, layout: fitLayout, repeatFilter: filter)
            }.value
            guard let self else { return }
            let newProfile = CalibrationProfile(createdAt: Date(), samples: samples, model: model)
            try? self.store.save(newProfile)
            self.profile = newProfile
            self.applySettings()
            self.isFitting = false
        }
    }

    func cancelCalibration() {
        calibration = nil
        screen = .menu
    }

    // MARK: Comparison

    func startComparison() {
        guard let model = profile?.model else { return }
        comparison = ComparisonRun(run: settings.comparisonRuns, model: model, settings: settings)
        keepComparisonResults = false
        screen = .comparing
    }

    func finishPhrase() {
        guard let run = comparison else { return }
        run.finishPhrase(now: ProcessInfo.processInfo.systemUptime)
        if run.isDone {
            settings.comparisonRuns += 1
            screen = .comparisonDone
        }
        heightCap = nil // "larger keys" trials are taller: ask for the full height again
        reportHeight()
        revision += 1
    }

    /// Scores from earlier runs the person chose to keep, plus this run.
    var allKeptResults: [TrialResult] { store.loadResults() + (comparison?.results ?? []) }

    func closeComparison() {
        if keepComparisonResults, let run = comparison {
            try? store.save(store.loadResults() + run.results)
        }
        comparison = nil
        screen = .typing
    }

    // MARK: Privacy

    func deleteAllData() {
        try? store.deleteAll()
        profile = nil
        calibration = nil
        comparison = nil
        trail = []
        suppressSave = true
        settings = KeyboardSettings()
        suppressSave = false
    }
}
