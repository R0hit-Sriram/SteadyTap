import Foundation
import XCTest
@testable import TouchEngine

final class EvaluationTests: XCTestCase {
    func testRegionLayerHelpsWhenOffsetsDifferAcrossTheScreen() {
        // SYNTHETIC user who lands 25pt right on the left third and 25pt left on the right third.
        // One overall shift averages to ~0 and can't capture this; per-region shifts can.
        var user = SyntheticUser(sigma: 4, offsetByPosition: { c in
            c.x < 130 ? Vec2(25, 0) : c.x > 260 ? Vec2(-25, 0) : .zero
        })
        let model = ModelFitter.fit(user.calibrate(letters + letters + letters, layout: layout390), layout: layout390)
        let rows = model.evaluation
        XCTAssertEqual(rows.count, model.pointKind == .up ? 5 : 6)
        let global = rows[1].accuracy, region = rows[2].accuracy
        XCTAssertGreaterThan(region, global + 0.2)
        XCTAssertGreaterThan(rows[3].accuracy, rows[0].accuracy)
        XCTAssertFalse(rows[3].isComparison)
        XCTAssertTrue(rows[4].isComparison)
        XCTAssertTrue(rows.allSatisfy { (0 ... 1).contains($0.accuracy) })
    }

    func testRunningTotalsGiveSameSpreadAsDirectComputation() {
        let pts = [Vec2(1, 2), Vec2(-3, 4), Vec2(5, -1), Vec2(0, 0)]
        var st = ResidualStats()
        pts.forEach { st.add($0) }
        let mean = st.sum / st.n
        let direct = Cov2.scatter(pts, about: mean)
        let fromTotals = st.scatter(about: mean)
        XCTAssertEqual(direct.xx, fromTotals.xx, accuracy: 1e-9)
        XCTAssertEqual(direct.xy, fromTotals.xy, accuracy: 1e-9)
        XCTAssertEqual(direct.yy, fromTotals.yy, accuracy: 1e-9)
    }
}

final class BackspaceAndHintTests: XCTestCase {
    func testHeldBackspaceDeletesRepeatedly() {
        let buffer = BufferTarget()
        buffer.insert("hello")
        let session = TypingSession(target: buffer)
        for _ in 0 ..< 3 { session.repeatBackspace() }
        XCTAssertEqual(buffer.text, "he")
        XCTAssertEqual(session.stats.backspaces, 3)
    }

    func testHintFlipsANearTieAndIsCounted() {
        let h = layout390.key(id: "h")!.frame.center, j = layout390.key(id: "j")!.frame.center
        let p = (h + j) / 2 + Vec2(1, 0) // a hair closer to j
        let model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        let touchOnly = Decoder.decode(tapAt(p), layout: layout390, model: model)
        XCTAssertEqual(touchOnly.keyID, "j")
        XCTAssertFalse(touchOnly.hintChangedIt)
        let withHint = Decoder.decode(tapAt(p), layout: layout390, model: model, context: .english, previous: "t")
        XCTAssertEqual(withHint.keyID, "h")
        XCTAssertTrue(withHint.hintChangedIt)
    }
}

final class ComparisonStatsTests: XCTestCase {
    func result(_ mode: ComparisonMode, seconds: Double, acc: Double) -> TrialResult {
        TrialResult(mode: mode, seconds: seconds, accuracy: acc, characters: 21, stats: SessionStats())
    }

    func testWordsPerMinuteNormalizesLength() {
        // 21 characters in 12 s = 20/12*60/5 = 20 wpm
        XCTAssertEqual(result(.standard, seconds: 12, acc: 1).wordsPerMinute, 20, accuracy: 1e-9)
        XCTAssertEqual(result(.standard, seconds: 0, acc: 1).wordsPerMinute, 0)
    }

    func testMedianAndRanges() {
        XCTAssertEqual(ComparisonStats.median([3, 1, 2]), 2)
        XCTAssertEqual(ComparisonStats.median([4, 1, 3, 2]), 2.5)
        let rows = ComparisonStats.summarize([
            result(.standard, seconds: 12, acc: 0.8), result(.standard, seconds: 24, acc: 0.9),
            result(.personalized, seconds: 10, acc: 1),
        ])
        XCTAssertEqual(rows.map(\.mode), [.standard, .personalized])
        XCTAssertEqual(rows[0].wpmRange, 10 ... 20)
        XCTAssertEqual(rows[0].accuracyMedian, 0.85, accuracy: 1e-9)
    }

    func testReportFlagsOverlappingResults() {
        let close = ComparisonStats.report([
            result(.standard, seconds: 12, acc: 0.9), result(.standard, seconds: 14, acc: 1),
            result(.personalized, seconds: 13, acc: 0.95), result(.personalized, seconds: 15, acc: 1),
        ])
        XCTAssertTrue(close.contains("may be chance"))
        let clear = ComparisonStats.report([
            result(.standard, seconds: 30, acc: 0.6), result(.standard, seconds: 32, acc: 0.7),
            result(.personalized, seconds: 12, acc: 0.95), result(.personalized, seconds: 13, acc: 1),
        ])
        XCTAssertFalse(clear.contains("may be chance"))
    }

    func testSettingsFromOlderBuildsStillLoad() throws {
        let old = #"{"adaptationOn":false,"keySize":"large"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(KeyboardSettings.self, from: old)
        XCTAssertFalse(s.adaptationOn)
        XCTAssertEqual(s.keySize, .large)
        XCTAssertTrue(s.holdToDelete)
    }
}
