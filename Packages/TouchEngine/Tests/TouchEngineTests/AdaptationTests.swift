import Foundation
import XCTest
@testable import TouchEngine

/// Types `text` like a person would: tap each letter; if the keyboard offers the right letter in the
/// choice bar, pick it; if the wrong letter appears, backspace and try again (up to 3 retries).
/// Returns, for each character, whether the FIRST tap produced the right letter.
/// ⚠️ SYNTHETIC: a scripted typist, not a person.
func simulateTyping(_ text: String, user: inout SyntheticUser, session: TypingSession, buffer: BufferTarget,
                    layout: KeyboardLayout) -> [Bool] {
    var firstTry: [Bool] = []
    for ch in text {
        let keyID = ch == " " ? "space" : String(ch)
        for attempt in 0 ..< 4 {
            session.handle(user.tap(keyID, on: layout), layout: layout)
            if let choice = session.pendingChoice {
                if choice.alternativeKeyID == keyID { session.chooseAlternative() } else if choice.insertedKeyID == keyID { session.acceptChoice() }
            }
            let ok = buffer.text.last == ch
            if attempt == 0 { firstTry.append(ok) }
            if ok { break }
            session.repeatBackspace() // same delete path as the backspace key
        }
    }
    return firstTry
}

func rate(_ xs: ArraySlice<Bool>) -> Double { Double(xs.filter { $0 }.count) / Double(max(xs.count, 1)) }

let practiceText = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 12)

/// Calibrate with one touch pattern, then type with a DIFFERENT one (22pt further right).
/// Returns first-try accuracy over the last 150 characters, static vs adapting.
func driftScenario(adapt: Bool) -> (accuracy: Double, profile: CalibrationProfile) {
    var calUser = SyntheticUser(sigma: 5)
    let samples = calUser.calibrate(CalibrationSession.standardSets(layout: layout390).flatMap { $0 }, layout: layout390)
    var profile = CalibrationProfile(createdAt: Date(), samples: samples, model: ModelFitter.fit(samples, layout: layout390))

    var typist = SyntheticUser(downOffset: Vec2(22, 0), sigma: 5, rng: SplitMix64(seed: 99))
    let buffer = BufferTarget()
    let session = TypingSession(target: buffer)
    session.autoCapitalize = false
    session.model = profile.model
    if adapt {
        session.onLabeledTouch = { label in
            profile.learn(label, layout: layout390)
            session.model = profile.model
        }
    }
    let results = simulateTyping(practiceText, user: &typist, session: session, buffer: buffer, layout: layout390)
    return (rate(results.suffix(150)), profile)
}

final class AdaptationTests: XCTestCase {
    func testAdaptsWhenTouchPatternChangesAfterCalibration() {
        let staticRun = driftScenario(adapt: false)
        let adaptive = driftScenario(adapt: true)
        print("SYNTHETIC drift: static \(staticRun.accuracy), adaptive \(adaptive.accuracy)")
        XCTAssertGreaterThan(adaptive.accuracy, staticRun.accuracy + 0.2)
        XCTAssertGreaterThan(adaptive.profile.model.globalOffset.x, 12, "learned the new rightward shift")
        let state = adaptive.profile.adaptive!
        XCTAssertGreaterThan(state.count(.corrected) + state.count(.picked), 0)
        XCTAssertGreaterThan(state.count(.confident), 0)
    }

    func testDoesNotDriftAwayWhenNothingChanged() {
        var calUser = SyntheticUser(downOffset: Vec2(0, 10), sigma: 5)
        let samples = calUser.calibrate(CalibrationSession.standardSets(layout: layout390).flatMap { $0 }, layout: layout390)
        let calibrated = ModelFitter.fit(samples, layout: layout390)
        var profile = CalibrationProfile(createdAt: Date(), samples: samples, model: calibrated)

        func run(adapt: Bool) -> Double {
            var typist = SyntheticUser(downOffset: Vec2(0, 10), sigma: 5, rng: SplitMix64(seed: 5))
            let buffer = BufferTarget()
            let session = TypingSession(target: buffer)
            session.autoCapitalize = false
            session.model = calibrated
            if adapt {
                session.onLabeledTouch = { label in
                    profile.learn(label, layout: layout390)
                    session.model = profile.model
                }
            }
            return rate(simulateTyping(practiceText, user: &typist, session: session, buffer: buffer, layout: layout390)[...])
        }
        let staticAcc = run(adapt: false), adaptiveAcc = run(adapt: true)
        XCTAssertGreaterThanOrEqual(adaptiveAcc, staticAcc - 0.02, "adapting must not make a stable typist worse")
        XCTAssertEqual(profile.model.globalOffset.y, 10, accuracy: 3)
        XCTAssertFalse(profile.adaptive!.isAdaptingFast)
    }

    func testFixRateJumpTriggersFasterLearning() {
        var state = AdaptiveState(means: [:], spreads: [:])
        let a = layout390.key(id: "a")!.frame.center
        for _ in 0 ..< 60 { OnlineLearner.update(&state, with: LabeledTouch(kind: .confident, keyID: "a", point: a, misread: false), layout: layout390) }
        XCTAssertFalse(state.isAdaptingFast)
        var started = false
        for _ in 0 ..< 10 where !started {
            started = OnlineLearner.update(&state, with: LabeledTouch(kind: .corrected, keyID: "a", point: a, misread: true), layout: layout390)
        }
        XCTAssertTrue(started)
        XCTAssertTrue(state.isAdaptingFast)
    }

    func testUnverifiedTapsMoveAveragesButNeverTheSpread() {
        var state = AdaptiveState(means: [:], spreads: [:])
        let a = layout390.key(id: "a")!.frame.center
        OnlineLearner.update(&state, with: LabeledTouch(kind: .confident, keyID: "a", point: a + Vec2(5, 0), misread: false), layout: layout390)
        XCTAssertEqual(state.means["a"]!.stats.n, 0.3, accuracy: 1e-9)
        XCTAssertNil(state.spreads["a"])
        OnlineLearner.update(&state, with: LabeledTouch(kind: .kept, keyID: "a", point: a, misread: false), layout: layout390)
        XCTAssertEqual(state.means["a"]!.stats.n, 0.3, accuracy: 1e-9, "uncertain kept letters teach nothing")
    }

    func testResetGoesBackToCalibration() {
        var (_, profile) = driftScenario(adapt: true)
        let calibrationOnly = ModelFitter.fitParameters(profile.samples, kind: profile.model.pointKind, keyWidth: layout390.keyWidth)
        profile.resetAdaptation()
        XCTAssertNil(profile.adaptive)
        XCTAssertEqual(profile.model.globalOffset.x, calibrationOnly.globalOffset.x, accuracy: 1e-9)
        XCTAssertFalse(profile.model.evaluation.isEmpty, "evaluation table survives")
    }
}

final class LabelingTests: XCTestCase {
    func makeSession() -> (TypingSession, BufferTarget, () -> [LabeledTouch]) {
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        session.autoCapitalize = false
        session.model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        var labels: [LabeledTouch] = []
        session.onLabeledTouch = { labels.append($0) }
        return (session, buffer, { labels })
    }

    func center(_ id: String) -> Vec2 { layout390.key(id: id)!.frame.center }

    func testNearMissCorrectionTeachesTheRetypedKey() {
        let (session, buffer, labels) = makeSession()
        defer { withExtendedLifetime(buffer) {} } // the session holds its text target weakly
        let between = center("r") + Vec2(-14, 0) // near e/r border, read as r
        session.handle(tapAt(between, t: 0), layout: layout390)
        session.acceptChoice() // dismiss any bar without labeling the other letter
        let typed = session.lastDecision!.keyID
        session.repeatBackspace()
        session.handle(tapAt(center("e"), t: 1), layout: layout390)
        let corrected = labels().filter { $0.kind == .corrected }
        if typed == "r" {
            XCTAssertEqual(corrected.count, 1)
            XCTAssertEqual(corrected.first?.keyID, "e")
            XCTAssertEqual(corrected.first?.point, between, "the label is for the ORIGINAL touch")
        }
    }

    func testChangingAWordIsNotACorrection() {
        let (session, buffer, labels) = makeSession()
        defer { withExtendedLifetime(buffer) {} } // the session holds its text target weakly
        for (i, c) in "cat".enumerated() { session.handle(tapAt(center(String(c)), t: Double(i)), layout: layout390) }
        session.repeatBackspace() // delete a confidently typed "t"
        session.handle(tapAt(center("r"), t: 4), layout: layout390) // …to make "car"
        XCTAssertTrue(labels().filter { $0.kind == .corrected }.isEmpty)
        XCTAssertEqual(labels().filter { $0.misread }.count, 1, "still counted as a fix for the fix rate")
    }

    func testKeptLettersBecomeConfidentLabelsAfterThreeMore() {
        let (session, buffer, labels) = makeSession()
        defer { withExtendedLifetime(buffer) {} } // the session holds its text target weakly
        for (i, c) in "dog".enumerated() { session.handle(tapAt(center(String(c)), t: Double(i)), layout: layout390) }
        XCTAssertTrue(labels().isEmpty, "the last 3 letters are still undecided")
        session.handle(tapAt(center("s"), t: 3), layout: layout390)
        XCTAssertEqual(labels().map(\.keyID), ["d"])
        XCTAssertEqual(labels().first?.kind, .confident)
    }

    func testNoLabelsWithoutAnAdaptedModel() {
        let (session, buffer, labels) = makeSession()
        defer { withExtendedLifetime(buffer) {} } // the session holds its text target weakly
        session.model = nil
        for (i, c) in "hello".enumerated() { session.handle(tapAt(center(String(c)), t: Double(i)), layout: layout390) }
        XCTAssertTrue(labels().isEmpty)
    }

    func testAdaptiveProfileSurvivesSaveAndLoad() throws {
        var profile = driftScenario(adapt: true).profile
        profile.createdAt = Date(timeIntervalSince1970: 0)
        let store = ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.save(profile)
        XCTAssertEqual(store.loadProfile(), profile)
    }
}
