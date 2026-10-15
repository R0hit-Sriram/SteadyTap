import Foundation

public struct TouchSample: Codable, Equatable, Sendable {
    public var p: Vec2
    /// Seconds (any monotonic clock; iOS uses `UITouch.timestamp`).
    public var t: Double

    public init(_ p: Vec2, _ t: Double) {
        self.p = p
        self.t = t
    }
}

/// Which single point of a touch best represents what the person meant.
/// Declaration order matters: ties during calibration go to the earlier case (`up`).
public enum PointKind: String, Codable, CaseIterable, Sendable {
    /// Where the finger lifted.
    case up
    /// Where the finger first landed.
    case down
    /// Plain average of every sampled position.
    case pathMean
    /// Time-weighted average: where the finger spent the most time.
    case dwell

    public var plainName: String {
        switch self {
        case .up: return "lift-off point"
        case .down: return "first-contact point"
        case .pathMean: return "average of the path"
        case .dwell: return "where the finger rested longest"
        }
    }
}

/// One touch on our keyboard: touch-down, sampled movement, touch-up.
public struct Gesture: Codable, Equatable, Sendable {
    /// Never empty. First sample = touch-down, last = touch-up.
    public private(set) var samples: [TouchSample]

    public init(samples: [TouchSample]) {
        precondition(!samples.isEmpty, "a gesture needs at least one sample")
        self.samples = samples
    }

    public var down: TouchSample { samples[0] }
    public var up: TouchSample { samples[samples.count - 1] }

    public func point(_ kind: PointKind) -> Vec2 {
        switch kind {
        case .down:
            return down.p
        case .up:
            return up.p
        case .pathMean:
            return samples.reduce(Vec2.zero) { $0 + $1.p } / Double(samples.count)
        case .dwell:
            // Each position is weighted by how long the finger stayed there before the next sample.
            var sum = Vec2.zero
            var total = 0.0
            for i in 0 ..< samples.count - 1 {
                let dt = max(0, samples[i + 1].t - samples[i].t)
                sum = sum + samples[i].p * dt
                total += dt
            }
            return total > 0 ? sum / total : down.p
        }
    }

    /// Keep at most `count` samples (always keeping first and last) so stored calibration stays small.
    public func downsampled(to count: Int) -> Gesture {
        guard samples.count > count, count >= 2 else { return self }
        let step = Double(samples.count - 1) / Double(count - 1)
        return Gesture(samples: (0 ..< count).map { samples[Int((Double($0) * step).rounded())] })
    }
}
