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
    case typing, menu, calibrating, calibrationDone, comparisonIntro, comparing, comparisonDone
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
    @Published var screen: Screen = .typing { didSet { reportHeight() } }
    @Published private(set) var width: Double = 375
    @Published private(set) var showGlobe = true
    @Published private(set) var flashKeyID: String?
    @Published private(set) var trail: [TrailMark] = []
    @Published private(set) var lastDecision: Decision?
    @Published private(set) var calibration: CalibrationSession?
    @Published private(set) var comparison: ComparisonRun?
    @Published var keepComparisonResults = false
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
        session.onConfirmedIntent = { [weak self] keyID, point in self?.learnFromChoice(keyID: keyID, point: point) }
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
        return KeyboardLayout.make(page: page, width: width, rowHeight: Self.baseRowHeight * multiplier,
                                   showNextKeyboard: showGlobe)
    }

    var toolbarHeight: Double {
        switch screen {
        case .comparing: return 124
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

    // MARK: Typing

    func applySettings() {
        session.model = settings.adaptationOn ? profile?.model : nil
        session.context = settings.useLetterPatterns ? .english : nil
        session.askThreshold = settings.askLevel.threshold
        session.recordsDemoLine = settings.showTouches
        if !settings.showTouches { trail = [] }
    }

    func hostTextChanged(autoCapitalize: Bool) {
        session.autoCapitalize = autoCapitalize
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
    func undo() { activeSession.undoLast(); revision += 1 }

    func repeatBackspace() {
        guard screen == .typing || screen == .comparing else { return }
        activeSession.repeatBackspace()
        revision += 1
    }

    /// Opt-in: the person explicitly picked a letter in the choice bar, so we know what that touch meant.
    /// Only per-key offset totals are kept (see CalibrationProfile.addConfirmed).
    private func learnFromChoice(keyID: String, point: Vec2) {
        guard settings.learnFromChoices, settings.adaptationOn, screen == .typing,
              var updated = profile, let key = layout.key(id: keyID) else { return }
        updated.addConfirmed(keyID: keyID, region: key.region, offset: point - key.frame.center)
        try? store.save(updated)
        profile = updated
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
        let newProfile = CalibrationProfile(createdAt: Date(), samples: cal.samples, model: cal.makeModel(layout: fitLayout))
        try? store.save(newProfile)
        profile = newProfile
        applySettings()
        screen = .calibrationDone
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
        reportHeight() // "larger keys" trials are taller
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
