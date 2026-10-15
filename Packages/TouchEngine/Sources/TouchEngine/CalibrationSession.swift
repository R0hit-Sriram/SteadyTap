import Foundation

/// Runs calibration: shows one requested key at a time and records what the finger did.
/// Every tap counts as an attempt at the requested key wherever it lands — that is what we learn from.
/// The only exception is a quick accidental extra contact right next to the previous tap.
public final class CalibrationSession {
    public enum Outcome: Equatable { case accepted, extraTap, setComplete, finished }

    /// Seconds/points within which a tap aimed elsewhere is treated as an accidental extra contact.
    public static let extraTapMaxGap = 0.3
    public static let extraTapRadiusFraction = 0.6

    public let sets: [[String]]
    public private(set) var setIndex = 0
    public private(set) var position = 0
    public private(set) var isOnBreak = false
    public private(set) var samples: [CalibrationSample] = []
    public private(set) var extraTapGaps: [Double] = []
    public private(set) var intentionalRepeatGaps: [Double] = []
    private var lastGesture: Gesture?
    private var lastTarget: String?

    public init(sets: [[String]]) {
        self.sets = sets.filter { !$0.isEmpty }
    }

    public var isFinished: Bool { setIndex >= sets.count }
    public var currentTarget: String? { isFinished || isOnBreak ? nil : sets[setIndex][position] }
    public var totalTargets: Int { sets.reduce(0) { $0 + $1.count } }
    public var completedTargets: Int { samples.count }

    public func record(_ gesture: Gesture, layout: KeyboardLayout) -> Outcome {
        guard let target = currentTarget, let key = layout.key(id: target) else { return .finished }

        if let prev = lastGesture, let prevTarget = lastTarget, prevTarget != target {
            let gap = gesture.down.t - prev.up.t
            let near = (gesture.down.p - prev.up.p).length < Self.extraTapRadiusFraction * layout.keyWidth
            if gap >= 0, gap < Self.extraTapMaxGap, near {
                extraTapGaps.append(gap)
                lastGesture = gesture
                return .extraTap
            }
        }
        if let prev = lastGesture, lastTarget == target {
            intentionalRepeatGaps.append(gesture.down.t - prev.up.t)
        }

        samples.append(CalibrationSample(keyID: target, keyCenter: key.frame.center, region: key.region, gesture: gesture.downsampled(to: 16)))
        lastGesture = gesture
        lastTarget = target
        position += 1
        guard position >= sets[setIndex].count else { return .accepted }

        setIndex += 1
        position = 0
        lastGesture = nil
        lastTarget = nil
        if isFinished { return .finished }
        isOnBreak = true
        return .setComplete
    }

    public func continueAfterBreak() { isOnBreak = false }

    /// Fit a model from whatever has been collected so far (works after any number of sets).
    public func makeModel(layout: KeyboardLayout) -> TouchModel {
        let filter = RepeatFilter.learn(extraTapGaps: extraTapGaps, intentionalRepeatGaps: intentionalRepeatGaps, keyWidth: layout.keyWidth)
        return ModelFitter.fit(samples, layout: layout, repeatFilter: filter)
    }

    /// About 63 taps in 3 sets: every letter twice, four double letters, three spaces.
    /// Consecutive targets are kept at least 2 key widths apart (except intentional doubles),
    /// so an accidental extra contact can't be confused with the next target.
    public static func standardSets(layout: KeyboardLayout, seed: UInt64 = 2026, setCount: Int = 3) -> [[String]] {
        var units: [[String]] = []
        for c in "abcdefghijklmnopqrstuvwxyz" { units += [[String(c)], [String(c)]] }
        for c in ["l", "e", "o", "s"] { units.append([c, c]) }
        units += [["space"], ["space"], ["space"]]

        var rng = SplitMix64(seed: seed)
        units.shuffle(using: &rng)
        var ordered: [[String]] = []
        while !units.isEmpty {
            let lastCenter = ordered.last.flatMap { layout.key(id: $0[$0.count - 1])?.frame.center }
            let farEnough = units.indices.first { i in
                guard let last = lastCenter, let c = layout.key(id: units[i][0])?.frame.center else { return true }
                return (c - last).length >= 2 * layout.keyWidth
            }
            ordered.append(units.remove(at: farEnough ?? 0))
        }

        let total = ordered.reduce(0) { $0 + $1.count }
        let perSet = Int((Double(total) / Double(setCount)).rounded(.up))
        var sets: [[String]] = [[]]
        for unit in ordered {
            if sets[sets.count - 1].count + unit.count > perSet, sets.count < setCount { sets.append([]) }
            sets[sets.count - 1] += unit
        }
        return sets
    }
}
