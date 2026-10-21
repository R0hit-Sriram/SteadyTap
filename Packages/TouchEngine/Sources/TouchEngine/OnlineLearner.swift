import Foundation

/// How we came to know which key a touch was meant for, while the person typed normally.
public enum LabelKind: String, Codable, CaseIterable, Sendable {
    /// The person tapped a letter in the two-choice bar.
    case picked
    /// The person deleted the letter and retyped a nearby key the model had considered possible.
    case corrected
    /// The model was very sure and the letter was never deleted. Not verified, so trusted less.
    case confident
    /// The letter was kept but the model wasn't very sure. Counted for the fix rate, not learned from.
    case kept

    /// How much one such touch counts, relative to a calibration tap.
    public var weight: Double {
        switch self {
        case .picked, .corrected: return 1
        case .confident: return 0.3
        case .kept: return 0
        }
    }

    /// Unverified labels come from taps the model already found easy, so they're biased toward the
    /// center. They may move the averages but never shrink the spread (that would feed overconfidence).
    public var updatesSpread: Bool { self != .confident }
}

/// One touch whose intended key we now know (or strongly believe).
public struct LabeledTouch: Equatable, Sendable {
    public var kind: LabelKind
    public var keyID: String
    public var point: Vec2
    /// True when the keyboard's first reading of this touch was wrong (it had to be fixed).
    public var misread: Bool

    public init(kind: LabelKind, keyID: String, point: Vec2, misread: Bool) {
        self.kind = kind
        self.keyID = keyID
        self.point = point
        self.misread = misread
    }
}

/// What the keyboard has learned while typing. Only per-key running totals (with older evidence
/// faded out), a drift score, and counts. No text, no letter order, no times.
public struct AdaptiveState: Codable, Equatable, Sendable {
    public var means: [String: KeyEvidence]
    public var spreads: [String: KeyEvidence]
    /// Share of letters that needed fixing: over roughly the last 10 letters, and over the last ~100.
    public var recentFixRate: Double = 0.1
    public var usualFixRate: Double = 0.1
    /// While `updates < fastUntil`, older evidence fades faster (the person's touch changed).
    public var fastUntil: Int = 0
    public var updates: Int = 0
    public var counts: [String: Int] = [:]

    public var isAdaptingFast: Bool { updates < fastUntil }
    public func count(_ kind: LabelKind) -> Int { counts[kind.rawValue] ?? 0 }
}

/// Online learning: keeps the touch model in step with how the person types *now*.
///
/// For each typed letter whose outcome we know:
/// 1. Track the fix rate on two time scales. If recent letters need fixing much more often than
///    usual, the person's touch has probably changed (tired hand, new grip, different posture),
///    so learning speeds up for a while.
/// 2. Fade all existing evidence a little (calibration included), so old habits gradually count less.
/// 3. Add the touch, weighted by how trustworthy its label is.
/// 4. Refit offsets and spreads with the same shrinkage used for calibration.
public enum OnlineLearner {
    /// Normal fading: evidence halves after ~140 learned touches.
    public static let slowRetention = 0.995
    /// After a change is detected: evidence halves after ~23 learned touches.
    public static let fastRetention = 0.97
    public static let fastPeriod = 60
    public static let recentRate = 0.1
    public static let usualRate = 0.01
    /// Speed up when recent fixes exceed the usual rate by this much (15 percentage points)…
    public static let driftMargin = 0.15
    /// …but only after enough letters to know what "usual" is.
    public static let warmup = 30

    /// Start from the calibration evidence.
    public static func seed(samples: [CalibrationSample], model: TouchModel) -> AdaptiveState {
        let e = ModelFitter.evidence(from: samples, kind: model.pointKind, keyWidth: model.keyWidth)
        return AdaptiveState(means: e, spreads: e)
    }

    /// Learn from one touch. Returns true if this touch started a period of faster adaptation.
    @discardableResult
    public static func update(_ state: inout AdaptiveState, with touch: LabeledTouch, layout: KeyboardLayout) -> Bool {
        guard let key = layout.key(id: touch.keyID), key.isDecodable else { return false }

        // 1. Two-timescale fix rate → change detection.
        let fixed = touch.misread ? 1.0 : 0.0
        state.recentFixRate += recentRate * (fixed - state.recentFixRate)
        state.usualFixRate += usualRate * (fixed - state.usualFixRate)
        state.updates += 1
        state.counts[touch.kind.rawValue, default: 0] += 1
        var startedFast = false
        if state.updates >= warmup, !state.isAdaptingFast, state.recentFixRate > state.usualFixRate + driftMargin {
            state.fastUntil = state.updates + fastPeriod
            startedFast = true
        }

        let r = touch.point - key.aim(for: touch.point, keyWidth: layout.keyWidth)
        guard touch.kind.weight > 0, r.length <= ModelFitter.outlierFraction * layout.keyWidth else { return startedFast }

        // 2. Fade everything learned so far.
        let retention = state.isAdaptingFast ? fastRetention : slowRetention
        fade(&state.means, by: retention)
        fade(&state.spreads, by: retention)

        // 3. Add the new touch.
        state.means[key.id, default: KeyEvidence(region: key.region)].stats.add(r, weight: touch.kind.weight)
        if touch.kind.updatesSpread {
            state.spreads[key.id, default: KeyEvidence(region: key.region)].stats.add(r, weight: touch.kind.weight)
        }
        return startedFast
    }

    /// 4. The model implied by the current evidence.
    public static func model(from state: AdaptiveState, base: TouchModel) -> TouchModel {
        ModelFitter.refit(base, means: state.means, spreads: state.spreads)
    }

    private static func fade(_ evidence: inout [String: KeyEvidence], by f: Double) {
        for id in evidence.keys { evidence[id]!.stats = evidence[id]!.stats.scaled(f) }
    }
}
