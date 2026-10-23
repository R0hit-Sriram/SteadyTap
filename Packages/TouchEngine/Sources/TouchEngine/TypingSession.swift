import Foundation

/// Where typed text goes. On iPhone this wraps `textDocumentProxy`; in the comparison test and in
/// unit tests it is an in-memory buffer.
public protocol TextTarget: AnyObject {
    /// Text just before the cursor. Only the last few characters are ever read.
    var textBeforeCursor: String? { get }
    func insert(_ text: String)
    func deleteBackward()
}

/// In-memory text, used by the typing comparison and tests. Never written to disk.
public final class BufferTarget: TextTarget {
    public private(set) var text = ""
    public init() {}
    public var textBeforeCursor: String? { text }
    public func insert(_ t: String) { text += t }
    public func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

public enum ShiftState: Equatable { case off, once, locked }

/// Counters only — never the text itself.
public struct SessionStats: Codable, Equatable, Sendable {
    public var backspaces = 0
    public var undos = 0
    public var choicesShown = 0
    public var choicesChanged = 0
    public var adaptationChanges = 0
    /// Taps where the letter-pair hint (not touch) decided the key.
    public var hintChanges = 0
    /// Whole words fixed when space was pressed.
    public var wordFixes = 0
    public init() {}

    public init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backspaces = try c.decodeIfPresent(Int.self, forKey: .backspaces) ?? 0
        undos = try c.decodeIfPresent(Int.self, forKey: .undos) ?? 0
        choicesShown = try c.decodeIfPresent(Int.self, forKey: .choicesShown) ?? 0
        choicesChanged = try c.decodeIfPresent(Int.self, forKey: .choicesChanged) ?? 0
        adaptationChanges = try c.decodeIfPresent(Int.self, forKey: .adaptationChanges) ?? 0
        hintChanges = try c.decodeIfPresent(Int.self, forKey: .hintChanges) ?? 0
        wordFixes = try c.decodeIfPresent(Int.self, forKey: .wordFixes) ?? 0
    }
}

/// Turns decided gestures into text edits, with a choice bar for uncertain letters, a one-step undo,
/// and repeated-letter protection. Holds no history beyond the single last action.
public final class TypingSession {
    public struct PendingChoice: Equatable {
        public let inserted: String
        public let alternative: String
        public let insertedKeyID: String
        public let alternativeKeyID: String
        /// The touch point the model used — paired with the person's answer, it's a labeled example.
        public let point: Vec2
    }

    public struct WordFix: Equatable {
        public let typed: String
        public let fixed: String
    }

    public enum Undo: Equatable {
        case inserted(String)
        case deleted(String)
        case replaced(old: String, new: String)
    }

    public weak var target: TextTarget?
    /// nil = fixed keyboard.
    public var model: TouchModel?
    public var context: LetterContext?
    /// nil = don't fix whole words. Only used with an adapted model (it needs per-letter probabilities).
    public var words: WordList?
    public var askThreshold = 0.7
    public var autoCapitalize = true {
        didSet {
            guard autoCapitalize != oldValue else { return }
            if autoCapitalize { refreshAutoShift() } else if autoShifted { shift = .off }
        }
    }

    /// Reports touches whose intended key became known while typing (see LabelKind), for online learning.
    /// Only fires when an adapted model is in use.
    public var onLabeledTouch: ((LabeledTouch) -> Void)?

    /// Letters typed recently whose outcome isn't known yet. MEMORY ONLY, at most `recentLimit`.
    private struct RecentTouch {
        var keyID: String
        var output: String
        let point: Vec2
        let probabilities: [String: Double]
        let topProbability: Double
        let time: Double
        var labeled = false
    }
    private var recent: [RecentTouch] = []
    private var deletedTouch: RecentTouch?
    /// The word being typed: each letter and how likely each a–z was for its tap. MEMORY ONLY; cleared at
    /// the next space or non-letter key.
    private var word: [(output: String, evidence: [Double])] = []
    public static let recentLimit = 3
    public static let confidentThreshold = 0.9
    public static let correctionWindow = 5.0
    /// A retyped key only counts as a correction if the model had given it at least this probability
    /// for the deleted touch. Stops "cat → car" (a changed word, not a misread) from teaching anything.
    public static let plausibleAlternative = 0.02

    public var shift: ShiftState = .off { didSet { autoShifted = false } }
    /// True while `shift` is an automatic sentence capital rather than one the person turned on.
    private var autoShifted = false
    /// Text before the cursor when the person turned an automatic capital off. It isn't turned back on
    /// there, even when the host app reports a change; typing anything moves past it.
    private var autoShiftDismissedAt: String?
    private var lastTapDismissedAuto = false
    public var page: KeyboardPage = .letters
    public private(set) var pendingChoice: PendingChoice?
    /// A tap we think was an accidental extra contact; shown with a "keep it" button, not typed.
    public private(set) var pendingExtra: String?
    public private(set) var lastDecision: Decision?
    public private(set) var undo: Undo?
    public private(set) var stats = SessionStats()
    /// Set when the last space fixed a word; cleared by the next key.
    public private(set) var lastWordFix: WordFix?

    /// Demo-only, memory-only: the last few characters as a fixed keyboard vs. we read them.
    public var recordsDemoLine = false
    public private(set) var demoFixed = ""
    public private(set) var demoAdapted = ""

    private var lastGesture: Gesture?
    private var lastShiftTap: Double = -1

    public init(target: TextTarget?) {
        self.target = target
        refreshAutoShift()
    }

    @discardableResult
    public func handle(_ gesture: Gesture, layout: KeyboardLayout) -> Decision {
        let before = target?.textBeforeCursor
        let decision = Decoder.decode(
            gesture, layout: layout, model: model, context: context, previous: before?.last,
            askThreshold: askThreshold
        )
        lastDecision = decision
        let key = layout.key(id: decision.keyID) ?? layout.key(at: gesture.up.p)

        if key.isDecodable, let filter = model?.repeatFilter, filter.isLikelyBounce(previous: lastGesture, next: gesture) {
            lastGesture = gesture
            pendingExtra = cased(key.output ?? "")
            return decision
        }
        lastGesture = gesture
        pendingChoice = nil
        pendingExtra = nil
        lastWordFix = nil

        switch key.kind {
        case .character, .space:
            if key.kind == .space { fixWord() }
            let text = cased(key.output ?? "")
            target?.insert(text)
            undo = lastWordFix.map { .replaced(old: $0.typed + text, new: $0.fixed + text) } ?? .inserted(text)
            trackWord(key: key, output: text, decision: decision)
            if decision.adaptationChangedIt { stats.adaptationChanges += 1 }
            if model != nil, !decision.candidates.isEmpty {
                noteTyped(keyID: key.id, output: text, decision: decision, time: gesture.up.t)
            }
            if decision.hintChangedIt { stats.hintChanges += 1 }
            if let alt = decision.alternativeKeyID, let altKey = layout.key(id: alt), let altOut = altKey.output {
                pendingChoice = PendingChoice(inserted: text, alternative: cased(altOut), insertedKeyID: key.id,
                                              alternativeKeyID: alt, point: decision.point)
                stats.choicesShown += 1
            }
            if recordsDemoLine {
                demoFixed = String((demoFixed + cased(layout.key(id: decision.fixedKeyID)?.output ?? "·")).suffix(40))
                demoAdapted = String((demoAdapted + text).suffix(40))
            }
            if shift == .once, key.kind == .character { shift = .off }
        case .backspace:
            deleteOne()
        case .returnKey:
            target?.insert("\n")
            undo = .inserted("\n")
        case .shift:
            let t = gesture.up.t
            let wasAuto = autoShifted, quick = t - lastShiftTap < 0.4
            switch shift {
            // A quick second tap after turning an automatic capital off is a double-tap: caps lock, as on iOS.
            case .off: shift = quick && lastTapDismissedAuto ? .locked : .once
            case .once: shift = quick ? .locked : .off
            case .locked: shift = .off
            }
            lastTapDismissedAuto = wasAuto && shift == .off
            if lastTapDismissedAuto { autoShiftDismissedAt = target?.textBeforeCursor ?? "" }
            lastShiftTap = t
        case .pageSwitch:
            page = page == .letters ? .symbols : .letters
        case .nextKeyboard:
            break // the keyboard UI hands this to the system
        }
        refreshAutoShift()
        return decision
    }

    /// The person picked the other letter in the choice bar.
    public func chooseAlternative() {
        guard let choice = pendingChoice else { return }
        pendingChoice = nil
        // Only swap if the cursor is still right after what we typed.
        guard let target, target.textBeforeCursor?.hasSuffix(choice.inserted) == true else { return }
        if let fix = lastWordFix, choice.inserted == " ", target.textBeforeCursor?.hasSuffix(fix.fixed + " ") == true {
            // That space was really a letter, so the word wasn't finished: put back what was typed.
            for _ in fix.fixed + " " { target.deleteBackward() }
            target.insert(fix.typed + choice.alternative)
            undo = .replaced(old: fix.fixed + " ", new: fix.typed + choice.alternative)
            lastWordFix = nil
            stats.wordFixes -= 1
            word = []
        } else {
            for _ in choice.inserted { target.deleteBackward() }
            target.insert(choice.alternative)
            undo = .replaced(old: choice.inserted, new: choice.alternative)
        }
        stats.choicesChanged += 1
        if word.last?.output == choice.inserted, let letter = choice.alternative.lowercased().first,
           choice.alternative.count == 1, LetterContext.index(of: letter) < 26 {
            word[word.count - 1] = (choice.alternative, WordFixer.certain(letter))
        } else {
            word = [] // a space or punctuation picked here ends the word
        }
        labelLast(LabeledTouch(kind: .picked, keyID: choice.alternativeKeyID, point: choice.point, misread: true),
                  newOutput: choice.alternative)
        if recordsDemoLine, !demoAdapted.isEmpty {
            demoAdapted.removeLast()
            demoAdapted += choice.alternative
        }
    }

    /// The person tapped the letter we already typed — an explicit confirmation.
    /// (Simply typing on also accepts it, but that's not counted as a confirmation.)
    public func acceptChoice() {
        guard let choice = pendingChoice else { return }
        pendingChoice = nil
        if word.last?.output == choice.inserted, let letter = choice.inserted.lowercased().first {
            word[word.count - 1].evidence = WordFixer.certain(letter)
        }
        labelLast(LabeledTouch(kind: .picked, keyID: choice.insertedKeyID, point: choice.point, misread: false),
                  newOutput: choice.inserted)
    }

    // MARK: Fixing whole words

    private func trackWord(key: Key, output: String, decision: Decision) {
        let isLetter = key.kind == .character && LetterContext.index(of: key.id.first ?? " ") < 26
        guard isLetter, model != nil, let evidence = WordFixer.letterEvidence(decision.candidates, scale: model?.confidenceScale ?? 1) else {
            word = []
            return
        }
        word.append((output, evidence))
    }

    /// Called just before a space is typed: replace the word if a listed word is clearly more likely.
    private func fixWord() {
        defer { word = [] }
        guard let words, model != nil, let target, let before = target.textBeforeCursor else { return }
        let typed = word.map(\.output).joined()
        // The text must still end with exactly the letters we typed (the cursor didn't move).
        guard !typed.isEmpty, before.hasSuffix(typed), before.dropLast(typed.count).last?.isLetter != true else { return }
        let lower = typed.lowercased()
        let capitalized = typed != lower
        guard !capitalized || typed == lower.prefix(1).uppercased() + lower.dropFirst() else { return } // ALL CAPS etc.
        guard let fix = WordFixer.fix(typed: lower, evidence: word.map(\.evidence), words: words) else { return }
        let fixed = capitalized ? fix.word.prefix(1).uppercased() + fix.word.dropFirst() : fix.word

        for _ in typed { target.deleteBackward() }
        target.insert(fixed)
        lastWordFix = WordFix(typed: typed, fixed: fixed)
        stats.wordFixes += 1
        if recordsDemoLine { demoAdapted = String((demoAdapted.dropLast(typed.count) + fixed).suffix(40)) }
        // Keep the recent-letter buffer matching the text. A word fix is a guess, not a label: don't learn from it.
        let letters = fixed.map(String.init)
        if fixed.count != typed.count { // letters were added or dropped: the touches no longer line up with the text
            recent = recent.map { var r = $0; r.labeled = true; return r }
            return
        }
        for j in 0 ..< min(recent.count, letters.count) {
            let i = recent.count - 1 - j, out = letters[letters.count - 1 - j]
            if recent[i].output != out {
                recent[i].output = out
                recent[i].keyID = out.lowercased()
                recent[i].labeled = true
            }
        }
    }

    // MARK: Turning normal typing into labeled touches

    private func noteTyped(keyID: String, output: String, decision: Decision, time: Double) {
        // A letter typed right after deleting one: was the deleted touch misread as a nearby key?
        if let deleted = deletedTouch {
            deletedTouch = nil
            if time - deleted.time < Self.correctionWindow, keyID != deleted.keyID,
               (deleted.probabilities[keyID] ?? 0) >= Self.plausibleAlternative {
                emit(LabeledTouch(kind: .corrected, keyID: keyID, point: deleted.point, misread: true))
            } else {
                settleDeleted(deleted)
            }
        }
        let probs = Dictionary(decision.candidates.prefix(5).map { ($0.keyID, $0.probability) }, uniquingKeysWith: max)
        recent.append(RecentTouch(keyID: keyID, output: output, point: decision.point, probabilities: probs,
                                  topProbability: decision.candidates[0].probability, time: time))
        if recent.count > Self.recentLimit { settle(recent.removeFirst()) }
    }

    /// A letter that was typed and then left alone long enough: the person kept it.
    private func settle(_ t: RecentTouch) {
        guard !t.labeled else { return }
        let kind: LabelKind = t.topProbability >= Self.confidentThreshold ? .confident : .kept
        emit(LabeledTouch(kind: kind, keyID: t.keyID, point: t.point, misread: false))
    }

    /// Deleted with no matching retype: it needed fixing, but we don't know the intended key.
    private func settleDeleted(_ t: RecentTouch) {
        guard !t.labeled else { return }
        emit(LabeledTouch(kind: .kept, keyID: t.keyID, point: t.point, misread: true))
    }

    private func labelLast(_ label: LabeledTouch, newOutput: String) {
        guard model != nil, !recent.isEmpty else { return }
        recent[recent.count - 1].labeled = true
        recent[recent.count - 1].keyID = label.keyID
        recent[recent.count - 1].output = newOutput
        emit(label)
    }

    private func forgetRecent() {
        recent = []
        deletedTouch = nil
        word = []
    }

    private func emit(_ label: LabeledTouch) { onLabeledTouch?(label) }

    /// Backspace held down: called repeatedly by the keyboard UI.
    public func repeatBackspace() {
        pendingChoice = nil
        pendingExtra = nil
        lastWordFix = nil
        deleteOne()
        refreshAutoShift()
    }

    private func deleteOne() {
        let lastChar = target?.textBeforeCursor?.last
        // Track which recent touch is being deleted, but only if the text still matches what we typed
        // (if the cursor moved, we no longer know which touch this letter came from).
        if let touch = recent.last, let lastChar, String(lastChar) == touch.output {
            if let previous = deletedTouch { settleDeleted(previous) }
            deletedTouch = recent.removeLast()
        } else {
            forgetRecent()
        }
        if let last = lastChar { undo = .deleted(String(last)) }
        if let lastChar, word.last?.output == String(lastChar) { word.removeLast() } else { word = [] }
        target?.deleteBackward()
        stats.backspaces += 1
        if recordsDemoLine {
            if !demoFixed.isEmpty { demoFixed.removeLast() }
            if !demoAdapted.isEmpty { demoAdapted.removeLast() }
        }
    }

    /// Type the extra letter we held back.
    public func keepExtra() {
        guard let extra = pendingExtra else { return }
        pendingExtra = nil
        target?.insert(extra)
        undo = .inserted(extra)
        forgetRecent() // this letter isn't tied to a tracked touch
    }

    /// Text from outside the letter keys (the emoji panel): typed as is, never decoded, fixed or learned from.
    public func insertText(_ text: String) {
        pendingChoice = nil
        pendingExtra = nil
        lastWordFix = nil
        forgetRecent()
        target?.insert(text)
        undo = .inserted(text)
        refreshAutoShift()
    }

    public var canUndo: Bool { undo != nil }

    /// Reverse the single most recent action, if the text around the cursor still matches.
    public func undoLast() {
        guard let action = undo, let target else { return }
        undo = nil
        pendingChoice = nil
        pendingExtra = nil
        forgetRecent() // undo rewrites text in ways we can't attribute to touches
        let before = target.textBeforeCursor ?? ""
        switch action {
        case .inserted(let t):
            guard before.hasSuffix(t) else { return }
            for _ in t { target.deleteBackward() }
        case .deleted(let t):
            target.insert(t)
        case .replaced(let old, let new):
            guard before.hasSuffix(new) else { return }
            for _ in new { target.deleteBackward() }
            target.insert(old)
        }
        stats.undos += 1
        refreshAutoShift()
    }

    /// Call when the host text changed in a way we didn't cause (cursor moved, field changed).
    public func hostTextChanged() {
        lastGesture = nil
        refreshAutoShift()
    }

    public func resetStats() {
        stats = SessionStats()
        demoFixed = ""
        demoAdapted = ""
    }

    func refreshAutoShift() {
        guard autoCapitalize, shift == .off, page == .letters else { return }
        let before = target?.textBeforeCursor ?? ""
        guard before != autoShiftDismissedAt else { return }
        if before.isEmpty || [". ", "? ", "! ", "\n"].contains(where: before.hasSuffix) {
            shift = .once
            autoShifted = true
        }
    }

    private func cased(_ s: String) -> String { shift == .off ? s : s.uppercased() }
}
