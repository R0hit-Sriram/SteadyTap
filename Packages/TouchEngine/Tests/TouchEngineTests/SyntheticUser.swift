import Foundation
@testable import TouchEngine

// ⚠️ SYNTHETIC — NOT USER DATA.
// Generates fake taps with a known, deliberately simple error pattern so tests can check the math.
// These fixtures say nothing about how any real person, or any condition, moves.
struct SyntheticUser {
    var downOffset = Vec2.zero      // systematic offset of first contact
    var slide = Vec2.zero           // finger travel from touch-down to touch-up
    var sigma = 4.0                 // random spread (points)
    var liftJitter = 0.0            // extra random spread of the lift-off point only
    var offsetByPosition: (Vec2) -> Vec2 = { _ in .zero } // offset that depends on where the key is
    var rng = SplitMix64(seed: 7)
    var clock = 0.0

    mutating func gaussian() -> Double {
        let u1 = max(Double(rng.next() % 1_000_000) / 1_000_000, 1e-9)
        let u2 = Double(rng.next() % 1_000_000) / 1_000_000
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    mutating func tap(_ keyID: String, on layout: KeyboardLayout, gap: Double = 0.4) -> Gesture {
        let center = layout.key(id: keyID)!.frame.center
        let down = center + downOffset + offsetByPosition(center) + Vec2(gaussian() * sigma, gaussian() * sigma)
        clock += gap
        let t0 = clock
        clock += 0.1
        let samples = [
            TouchSample(down, t0),
            TouchSample(down + slide * 0.5, t0 + 0.05),
            TouchSample(down + slide + Vec2(gaussian() * liftJitter, gaussian() * liftJitter), clock),
        ]
        return Gesture(samples: samples)
    }

    mutating func calibrate(_ keys: [String], layout: KeyboardLayout) -> [CalibrationSample] {
        keys.map { id in
            let k = layout.key(id: id)!
            return CalibrationSample(keyID: id, keyCenter: k.frame.center, region: k.region, gesture: tap(id, on: layout))
        }
    }
}

let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
let layout390 = KeyboardLayout.make(page: .letters, width: 390, rowHeight: 54, showNextKeyboard: true)

/// Exact gesture at a point, for hand-placed taps.
func tapAt(_ p: Vec2, t: Double = 0) -> Gesture {
    Gesture(samples: [TouchSample(p, t), TouchSample(p, t + 0.08)])
}
