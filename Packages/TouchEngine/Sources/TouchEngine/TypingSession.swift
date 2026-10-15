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
    public init() {}

    public init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backspaces = try c.decodeIfPresent(Int.self, forKey: .backspaces) ?? 0
        undos = try c.decodeIfPresent(Int.self, forKey: .undos) ?? 0
        choicesShown = try c.decodeIfPresent(Int.self, forKey: .choicesShown) ?? 0
        choicesChanged = try c.decodeIfPresent(Int.self, forKey: .choicesChanged) ?? 0
        adaptationChanges = try c.decodeIfPresent(Int.self, forKey: .adaptationChanges) ?? 0
        hintChanges = try c.decodeIfPresent(Int.self, forKey: .hintChanges) ?? 0
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

    public enum Undo: Equatable {
        case inserted(String)
        case deleted(String)
        case replaced(old: String, new: String)
    }

    public weak var target: TextTarget?
    /// nil = fixed keyboard.
    public var model: TouchModel?
    public var context: LetterContext?
    public var askThreshold = 0.7
    public var autoCapitalize = true {
        didSet { if autoCapitalize { refreshAutoShift() } else if shift == .once { shift = .off } }
    }

    /// Called when the person explicitly tells us which key a touch meant (by tapping a letter in
    /// the choice bar). Used only for opt-in learning.
    public var onConfirmedIntent: ((_ keyID: String, _ point: Vec2) -> Void)?

    public var shift: ShiftState = .off
    public var page: KeyboardPage = .letters
    public private(set) var pendingChoice: PendingChoice?
    /// A tap we think was an accidental extra contact; shown with a "keep it" button, not typed.
    public private(set) var pendingExtra: String?
    public private(set) var lastDecision: Decision?
    public private(set) var undo: Undo?
    public private(set) var stats = SessionStats()

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

        switch key.kind {
        case .character, .space:
            let text = cased(key.output ?? "")
            target?.insert(text)
            undo = .inserted(text)
            if decision.adaptationChangedIt { stats.adaptationChanges += 1 }
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
            switch shift {
            case .off: shift = .once
            case .once: shift = t - lastShiftTap < 0.4 ? .locked : .off
            case .locked: shift = .off
            }
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
        for _ in choice.inserted { target.deleteBackward() }
        target.insert(choice.alternative)
        undo = .replaced(old: choice.inserted, new: choice.alternative)
        stats.choicesChanged += 1
        onConfirmedIntent?(choice.alternativeKeyID, choice.point)
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
        onConfirmedIntent?(choice.insertedKeyID, choice.point)
    }

    /// Backspace held down: called repeatedly by the keyboard UI.
    public func repeatBackspace() {
        pendingChoice = nil
        pendingExtra = nil
        deleteOne()
        refreshAutoShift()
    }

    private func deleteOne() {
        if let last = target?.textBeforeCursor?.last { undo = .deleted(String(last)) }
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
    }

    public var canUndo: Bool { undo != nil }

    /// Reverse the single most recent action, if the text around the cursor still matches.
    public func undoLast() {
        guard let action = undo, let target else { return }
        undo = nil
        pendingChoice = nil
        pendingExtra = nil
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
        if before.isEmpty || [". ", "? ", "! ", "\n"].contains(where: before.hasSuffix) { shift = .once }
    }

    private func cased(_ s: String) -> String { shift == .off ? s : s.uppercased() }
}
