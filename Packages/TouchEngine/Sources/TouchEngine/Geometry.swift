import Foundation

/// A point or offset in keyboard coordinates (iOS points, origin top-left of the key area).
public struct Vec2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    public var length: Double { (x * x + y * y).squareRoot() }
}

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var center: Vec2 { Vec2(x + w / 2, y + h / 2) }
    public func contains(_ p: Vec2) -> Bool { p.x >= x && p.x < x + w && p.y >= y && p.y < y + h }
}

/// Symmetric 2×2 covariance matrix: how a person's touches spread around their average.
/// A full matrix (not just one radius) lets sideways shake differ from up-down shake.
public struct Cov2: Codable, Equatable, Sendable {
    public var xx: Double
    public var xy: Double
    public var yy: Double

    public init(xx: Double, xy: Double, yy: Double) {
        self.xx = xx
        self.xy = xy
        self.yy = yy
    }

    public static func isotropic(_ sigma: Double) -> Cov2 { Cov2(xx: sigma * sigma, xy: 0, yy: sigma * sigma) }
    public static func + (a: Cov2, b: Cov2) -> Cov2 { Cov2(xx: a.xx + b.xx, xy: a.xy + b.xy, yy: a.yy + b.yy) }
    public static func * (a: Cov2, s: Double) -> Cov2 { Cov2(xx: a.xx * s, xy: a.xy * s, yy: a.yy * s) }

    public var det: Double { xx * yy - xy * xy }

    /// Squared Mahalanobis distance: "how many spreads away" an offset is.
    public func mahalanobis2(_ d: Vec2) -> Double {
        (yy * d.x * d.x - 2 * xy * d.x * d.y + xx * d.y * d.y) / det
    }

    /// Log of the 2-D Gaussian density at offset `d`.
    public func logDensity(_ d: Vec2) -> Double {
        -0.5 * mahalanobis2(d) - 0.5 * log(det) - log(2 * Double.pi)
    }

    /// Never let the spread get smaller than `minSigma`, and keep the matrix safely invertible.
    public func floored(minSigma: Double) -> Cov2 {
        let m = minSigma * minSigma
        let fx = max(xx, m), fy = max(yy, m)
        let maxXY = 0.9 * (fx * fy).squareRoot()
        return Cov2(xx: fx, xy: min(max(xy, -maxXY), maxXY), yy: fy)
    }

    /// One-sigma ellipse for drawing: semi-axes and rotation (radians).
    public var ellipse: (major: Double, minor: Double, angle: Double) {
        let mid = (xx + yy) / 2
        let r = (((xx - yy) / 2) * ((xx - yy) / 2) + xy * xy).squareRoot()
        return ((mid + r).squareRoot(), max(mid - r, 0).squareRoot(), 0.5 * atan2(2 * xy, xx - yy))
    }

    /// Sum of outer products of `points - mean`.
    static func scatter(_ points: [Vec2], about mean: Vec2) -> Cov2 {
        points.reduce(Cov2(xx: 0, xy: 0, yy: 0)) { acc, p in
            let d = p - mean
            return acc + Cov2(xx: d.x * d.x, xy: d.x * d.y, yy: d.y * d.y)
        }
    }
}

/// Small deterministic RNG so calibration order and test fixtures are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
