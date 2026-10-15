import Foundation

/// What one person's calibration taught us about how they touch.
/// Everything is in points relative to the intended key's center, so it carries over when key height changes.
public struct TouchModel: Codable, Equatable, Sendable {
    public var pointKind: PointKind
    public var keyWidth: Double
    public var globalOffset: Vec2
    public var regionOffsets: [Int: Vec2]
    public var keyOffsets: [String: Vec2]
    public var globalCov: Cov2
    public var regionCovs: [Int: Cov2]
    public var sampleCount: Int
    public var repeatFilter: RepeatFilter
    /// Leave-one-out accuracy on the calibration taps for each PointKind (keyed by rawValue).
    public var heldOutAccuracy: [String: Double]
    /// How often a fixed keyboard read the same calibration taps correctly.
    public var fixedAccuracy: Double
    /// What each layer of the model adds, on this person's calibration taps.
    public var evaluation: [EvaluationRow]

    /// No calibration: zero offset and a round spread a bit narrower than a key.
    /// This behaves almost exactly like a fixed keyboard.
    public static func untrained(keyWidth: Double, pointKind: PointKind = .up) -> TouchModel {
        TouchModel(
            pointKind: pointKind, keyWidth: keyWidth, globalOffset: .zero, regionOffsets: [:], keyOffsets: [:],
            globalCov: .isotropic(ModelFitter.defaultSigmaFraction * keyWidth), regionCovs: [:],
            sampleCount: 0, repeatFilter: .off, heldOutAccuracy: [:], fixedAccuracy: 0, evaluation: []
        )
    }

    /// Most specific learned offset available: this key → its screen region → everywhere.
    public func offset(for key: Key) -> Vec2 { keyOffsets[key.id] ?? regionOffsets[key.region] ?? globalOffset }
    public func cov(for key: Key) -> Cov2 { regionCovs[key.region] ?? globalCov }
}

/// Distinguishes an accidental extra contact ("bounce") from an intentional double letter.
public struct RepeatFilter: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Max seconds between the previous touch-up and the next touch-down for a bounce.
    public var window: Double
    /// Max distance (points) between them for a bounce.
    public var radius: Double

    public init(enabled: Bool, window: Double, radius: Double) {
        self.enabled = enabled
        self.window = window
        self.radius = radius
    }

    public static let off = RepeatFilter(enabled: false, window: 0, radius: 0)

    public func isLikelyBounce(previous: Gesture?, next: Gesture) -> Bool {
        guard enabled, let prev = previous else { return false }
        let gap = next.down.t - prev.up.t
        return gap >= 0 && gap < window && (next.down.p - prev.up.p).length < radius
    }

    /// Turn filtering on ONLY if calibration saw repeated accidental taps, and only with a window
    /// shorter than this person's own intentional double-letter speed.
    public static func learn(extraTapGaps: [Double], intentionalRepeatGaps: [Double], keyWidth: Double) -> RepeatFilter {
        guard extraTapGaps.count >= 2, let slowestExtra = extraTapGaps.max() else { return .off }
        var window = slowestExtra * 1.5
        if let fastestIntentional = intentionalRepeatGaps.min() {
            window = min(window, fastestIntentional * 0.6)
            // Accidental and intentional repeats overlap in timing: filtering would eat real letters.
            if window <= slowestExtra { return .off }
        } else {
            window = min(window, 0.15)
        }
        return RepeatFilter(enabled: true, window: window, radius: 0.6 * keyWidth)
    }
}
