import Foundation

public struct Candidate: Equatable, Sendable {
    public let keyID: String
    /// Log-likelihood of the touch under this key's learned pattern (touch evidence only).
    public let touchScore: Double
    /// Final probability after combining touch evidence with the (weak) letter-pattern hint.
    public let probability: Double
}

public struct Decision: Equatable, Sendable {
    /// The key we act on.
    public let keyID: String
    /// What a fixed keyboard would have read from the same touch (its lift-off point).
    public let fixedKeyID: String
    /// Decodable keys, most likely first. Empty for function keys or when adaptation is off.
    public let candidates: [Candidate]
    /// True when the top choice is not likely enough, so we offer the runner-up.
    public let isAmbiguous: Bool
    /// The point the model used.
    public let point: Vec2

    public var alternativeKeyID: String? { isAmbiguous && candidates.count > 1 ? candidates[1].keyID : nil }
    /// True when the letter-pair hint picked a different key than touch evidence alone would have.
    public var hintChangedIt: Bool {
        guard let touchBest = candidates.max(by: { $0.touchScore < $1.touchScore }) else { return false }
        return touchBest.keyID != keyID
    }
    public var adaptationChangedIt: Bool { keyID != fixedKeyID }
}

public enum Decoder {
    /// Weight of the letter-pattern hint relative to touch evidence. Small on purpose.
    public static let defaultContextWeight = 0.3

    /// Interpret one gesture.
    /// - model: nil = fixed keyboard (lift-off point, key under it).
    /// - previous: the single character before the cursor, used only for the letter-pattern hint.
    public static func decode(
        _ gesture: Gesture, layout: KeyboardLayout, model: TouchModel?,
        context: LetterContext? = nil, previous: Character? = nil,
        contextWeight: Double = defaultContextWeight, askThreshold: Double = 0.7
    ) -> Decision {
        let fixed = layout.key(at: gesture.up.p)
        guard let model else {
            return Decision(keyID: fixed.id, fixedKeyID: fixed.id, candidates: [], isAmbiguous: false, point: gesture.up.p)
        }
        let p = gesture.point(model.pointKind)
        // Shift, backspace, return etc. are plain buttons: if the point — corrected by this person's overall
        // offset — is on one, that's the answer. (Without the correction, someone who always lands low
        // would hit the bottom row when aiming for Z…M.)
        let hit = layout.key(at: p - model.globalOffset)
        if !hit.isDecodable {
            return Decision(keyID: hit.id, fixedKeyID: fixed.id, candidates: [], isAmbiguous: false, point: p)
        }
        let candidates = score(point: p, layout: layout, model: model, context: context, previous: previous, contextWeight: contextWeight)
        let ambiguous = candidates.count > 1 && candidates[0].probability < askThreshold
        return Decision(keyID: candidates[0].keyID, fixedKeyID: fixed.id, candidates: candidates, isAmbiguous: ambiguous, point: p)
    }

    /// score(key) = log N(point − keyCenter − learnedOffset ; 0, learnedSpread) + w · letterHint(previous → key),
    /// turned into probabilities with softmax. Sorted most likely first.
    public static func score(
        point p: Vec2, layout: KeyboardLayout, model: TouchModel,
        context: LetterContext? = nil, previous: Character? = nil, contextWeight: Double = defaultContextWeight
    ) -> [Candidate] {
        let raw = layout.decodableKeys.map { key -> (String, Double, Double) in
            let touch = model.cov(for: key).logDensity(p - key.frame.center - model.offset(for: key))
            let hint = context?.logBoost(previous: previous, nextKeyID: key.id) ?? 0
            return (key.id, touch, touch + contextWeight * hint)
        }
        let maxTotal = raw.map(\.2).max() ?? 0
        let exps = raw.map { exp($0.2 - maxTotal) }
        let sum = exps.reduce(0, +)
        return zip(raw, exps)
            .map { Candidate(keyID: $0.0.0, touchScore: $0.0.1, probability: $0.1 / sum) }
            .sorted { $0.probability > $1.probability }
    }
}
