import Foundation

/// One calibration tap: the key we asked for and what the finger actually did.
public struct CalibrationSample: Codable, Equatable, Sendable {
    public var keyID: String
    public var keyCenter: Vec2
    public var region: Int
    public var gesture: Gesture

    public init(keyID: String, keyCenter: Vec2, region: Int, gesture: Gesture) {
        self.keyID = keyID
        self.keyCenter = keyCenter
        self.region = region
        self.gesture = gesture
    }
}

/// Running totals of touch offsets ("sufficient statistics"): enough to compute an average and a
/// spread without keeping individual touches.
public struct ResidualStats: Codable, Equatable, Sendable {
    public var n = 0.0
    public var sx = 0.0
    public var sy = 0.0
    public var sxx = 0.0
    public var sxy = 0.0
    public var syy = 0.0

    public init() {}

    public mutating func add(_ r: Vec2) {
        n += 1
        sx += r.x
        sy += r.y
        sxx += r.x * r.x
        sxy += r.x * r.y
        syy += r.y * r.y
    }

    public static func + (a: ResidualStats, b: ResidualStats) -> ResidualStats {
        var s = a
        s.n += b.n; s.sx += b.sx; s.sy += b.sy; s.sxx += b.sxx; s.sxy += b.sxy; s.syy += b.syy
        return s
    }

    /// Shrink the weight of everything so far (used to let newer touches count more).
    public func scaled(_ f: Double) -> ResidualStats {
        var s = self
        s.n *= f; s.sx *= f; s.sy *= f; s.sxx *= f; s.sxy *= f; s.syy *= f
        return s
    }

    public var sum: Vec2 { Vec2(sx, sy) }

    /// Σ (r − m)(r − m)ᵀ, computed from the totals.
    public func scatter(about m: Vec2) -> Cov2 {
        Cov2(xx: sxx - 2 * m.x * sx + n * m.x * m.x,
             xy: sxy - m.x * sy - m.y * sx + n * m.x * m.y,
             yy: syy - 2 * m.y * sy + n * m.y * m.y)
    }
}

/// Offsets observed for one key, plus which screen region the key is in.
public struct KeyEvidence: Codable, Equatable, Sendable {
    public var region: Int
    public var stats: ResidualStats

    public init(region: Int, stats: ResidualStats = ResidualStats()) {
        self.region = region
        self.stats = stats
    }
}

/// How much of the model to use. Exists so we can measure what each layer adds.
public enum ModelDepth: Sendable {
    /// One shift for the whole keyboard.
    case global
    /// A shift and spread per screen region.
    case region
    /// Plus a shift per key (the full model).
    case perKey
}

/// Learns a TouchModel from calibration samples.
///
/// 1. For each candidate point (lift-off, first contact, path average, dwell), fit offsets + spread.
/// 2. Score each by leave-one-out accuracy: predict every tap using a model that never saw it.
/// 3. Keep the best one (ties → lift-off, the conventional choice).
///
/// Offsets are "shrunk": a key with few samples borrows from its region, a region borrows from the
/// overall average. With κ = 4, a key needs about 4 samples before its own data outweighs its region.
public enum ModelFitter {
    public static let kappa = 4.0
    public static let minSigmaFraction = 0.15
    public static let defaultSigmaFraction = 0.35
    /// Taps more than this many key widths from the target are treated as slips and ignored.
    public static let outlierFraction = 3.0

    public static func fit(_ samples: [CalibrationSample], layout: KeyboardLayout, repeatFilter: RepeatFilter = .off) -> TouchModel {
        var accuracies: [String: Double] = [:]
        var bestKind = PointKind.up
        var bestAccuracy = -1.0
        for kind in PointKind.allCases {
            let acc = leaveOneOutAccuracy(samples, kind: kind, layout: layout)
            accuracies[kind.rawValue] = acc
            if acc > bestAccuracy + 1e-9 {
                bestAccuracy = acc
                bestKind = kind
            }
        }
        var model = fitParameters(samples, kind: bestKind, keyWidth: layout.keyWidth)
        model.heldOutAccuracy = accuracies
        model.fixedAccuracy = fixedAccuracy(samples, layout: layout)
        model.evaluation = evaluate(samples, layout: layout, bestKind: bestKind, accuracies: accuracies)
        model.repeatFilter = repeatFilter
        return model
    }

    /// Same point type and evaluation as before, but including offsets confirmed while typing.
    public static func refit(_ previous: TouchModel, samples: [CalibrationSample], evidence: [String: KeyEvidence]) -> TouchModel {
        var model = fitParameters(samples, kind: previous.pointKind, keyWidth: previous.keyWidth, evidence: evidence)
        model.heldOutAccuracy = previous.heldOutAccuracy
        model.fixedAccuracy = previous.fixedAccuracy
        model.evaluation = previous.evaluation
        model.repeatFilter = previous.repeatFilter
        return model
    }

    public static func fitParameters(
        _ samples: [CalibrationSample], kind: PointKind, keyWidth kw: Double,
        depth: ModelDepth = .perKey, kappa k: Double = kappa, evidence: [String: KeyEvidence] = [:]
    ) -> TouchModel {
        var model = TouchModel.untrained(keyWidth: kw, pointKind: kind)

        var perKey = evidence
        for s in samples {
            let r = s.gesture.point(kind) - s.keyCenter
            guard r.length <= outlierFraction * kw else { continue }
            perKey[s.keyID, default: KeyEvidence(region: s.region)].stats.add(r)
        }
        let all = perKey.values.reduce(ResidualStats()) { $0 + $1.stats }
        guard all.n > 0 else { return model }
        model.sampleCount = Int(all.n.rounded())

        let defaultCov = Cov2.isotropic(defaultSigmaFraction * kw)
        let minSigma = minSigmaFraction * kw
        func shrunkMean(_ st: ResidualStats, toward prior: Vec2) -> Vec2 {
            st.n + k > 0 ? (st.sum + prior * k) / (st.n + k) : prior
        }
        func shrunkCov(_ st: ResidualStats, mean: Vec2, toward prior: Cov2) -> Cov2 {
            guard st.n + k > 0 else { return prior }
            return ((st.scatter(about: mean) + prior * k) * (1 / (st.n + k))).floored(minSigma: minSigma)
        }

        // Everywhere (the global mean itself is not shrunk; its spread is shrunk toward a default)
        let gMean = all.sum / all.n
        let gCov = shrunkCov(all, mean: gMean, toward: defaultCov)
        model.globalOffset = gMean
        model.globalCov = gCov
        if depth == .global { return model }

        // Per region, shrunk toward everywhere
        var regionStats: [Int: ResidualStats] = [:]
        for e in perKey.values { regionStats[e.region, default: ResidualStats()] = regionStats[e.region, default: ResidualStats()] + e.stats }
        for (region, st) in regionStats {
            let mean = shrunkMean(st, toward: gMean)
            model.regionOffsets[region] = mean
            model.regionCovs[region] = shrunkCov(st, mean: mean, toward: gCov)
        }
        if depth == .region { return model }

        // Per key, shrunk toward its region
        for (keyID, e) in perKey {
            model.keyOffsets[keyID] = shrunkMean(e.stats, toward: model.regionOffsets[e.region] ?? gMean)
        }
        return model
    }

    public static func fixedAccuracy(_ samples: [CalibrationSample], layout: KeyboardLayout) -> Double {
        guard !samples.isEmpty else { return 0 }
        return Double(samples.filter { layout.key(at: $0.gesture.up.p).id == $0.keyID }.count) / Double(samples.count)
    }

    /// Fraction of calibration taps decoded correctly by a model fitted WITHOUT that tap.
    public static func leaveOneOutAccuracy(
        _ samples: [CalibrationSample], kind: PointKind, layout: KeyboardLayout,
        depth: ModelDepth = .perKey, kappa k: Double = kappa
    ) -> Double {
        guard !samples.isEmpty else { return 0 }
        var correct = 0
        for i in samples.indices {
            var rest = samples
            rest.remove(at: i)
            let model = fitParameters(rest, kind: kind, keyWidth: layout.keyWidth, depth: depth, kappa: k)
            let scores = Decoder.score(point: samples[i].gesture.point(kind), layout: layout, model: model)
            if scores.first?.keyID == samples[i].keyID { correct += 1 }
        }
        return Double(correct) / Double(samples.count)
    }

    /// What each layer of the model adds, measured on this person's calibration taps
    /// (every tap predicted by a model that never saw it).
    public static func evaluate(
        _ samples: [CalibrationSample], layout: KeyboardLayout, bestKind: PointKind, accuracies: [String: Double]
    ) -> [EvaluationRow] {
        guard !samples.isEmpty else { return [] }
        let loo = { (kind: PointKind, depth: ModelDepth, k: Double) in
            leaveOneOutAccuracy(samples, kind: kind, layout: layout, depth: depth, kappa: k)
        }
        // Build-up rows all use this person's best point, so each row adds exactly one layer.
        var rows = [
            EvaluationRow(label: "Standard keyboard", accuracy: fixedAccuracy(samples, layout: layout)),
            EvaluationRow(label: "One shift for the whole keyboard", accuracy: loo(bestKind, .global, kappa)),
            EvaluationRow(label: "+ a shift for each screen area", accuracy: loo(bestKind, .region, kappa)),
            EvaluationRow(label: "+ a shift for each key, borrowing from its area (used)", accuracy: accuracies[bestKind.rawValue] ?? 0),
            EvaluationRow(label: "Instead: each key on its own, no borrowing", accuracy: loo(bestKind, .perKey, 0), isComparison: true),
        ]
        if bestKind != .up {
            rows.append(EvaluationRow(label: "Instead: same model on the lift-off point",
                                      accuracy: accuracies[PointKind.up.rawValue] ?? 0, isComparison: true))
        }
        return rows
    }
}

/// One line of the "what each part adds" table.
public struct EvaluationRow: Codable, Equatable, Sendable {
    public var label: String
    public var accuracy: Double
    /// An alternative shown for contrast, not a step in the build-up.
    public var isComparison: Bool

    public init(label: String, accuracy: Double, isComparison: Bool = false) {
        self.label = label
        self.accuracy = accuracy
        self.isComparison = isComparison
    }
}
