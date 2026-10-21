import Foundation
import XCTest
@testable import TouchEngine

final class LayoutTests: XCTestCase {
    func testFixedReadingUsesKeyUnderPoint() {
        let g = layout390.key(id: "g")!
        XCTAssertEqual(layout390.key(at: g.frame.center).id, "g")
        // Left of "a" is an empty half-key gap → nearest key.
        XCTAssertEqual(layout390.key(at: Vec2(2, 54 + 27)).id, "a")
    }

    func testGlobeOnlyWhenNeeded() {
        XCTAssertNotNil(layout390.key(id: "globe"))
        XCTAssertNil(KeyboardLayout.make(page: .letters, width: 390, rowHeight: 54, showNextKeyboard: false).key(id: "globe"))
    }

    func testBottomRowFillsWidth() {
        let bottom = layout390.keys.filter { $0.row == 3 }
        XCTAssertEqual(bottom.reduce(0) { $0 + $1.frame.w }, 390, accuracy: 0.001)
    }
}

final class FitAndDecodeTests: XCTestCase {
    func testLearnsConsistentOffsetAndBeatsFixedKeyboard() {
        // SYNTHETIC user who lands 30pt low (more than half a key).
        var user = SyntheticUser(downOffset: Vec2(0, 30), sigma: 5)
        let samples = user.calibrate(letters + letters + letters, layout: layout390)
        let model = ModelFitter.fit(samples, layout: layout390)

        XCTAssertEqual(model.globalOffset.y, 30, accuracy: 3)
        XCTAssertEqual(model.globalOffset.x, 0, accuracy: 3)
        XCTAssertGreaterThan(model.heldOutAccuracy[model.pointKind.rawValue]!, model.fixedAccuracy + 0.3)

        // Fresh taps the model never saw
        var fixedRight = 0, adaptedRight = 0
        for id in letters {
            let g = user.tap(id, on: layout390)
            if Decoder.decode(g, layout: layout390, model: nil).keyID == id { fixedRight += 1 }
            if Decoder.decode(g, layout: layout390, model: model).keyID == id { adaptedRight += 1 }
        }
        XCTAssertGreaterThan(adaptedRight, fixedRight)
    }

    func testSparseKeyBorrowsFromRegionAndGlobal() {
        // Ten accurate taps on "p", one tap on "q" that's 20pt to the right.
        let p = layout390.key(id: "p")!, q = layout390.key(id: "q")!
        var samples = (0 ..< 10).map { _ in CalibrationSample(keyID: "p", keyCenter: p.frame.center, region: p.region, gesture: tapAt(p.frame.center)) }
        samples.append(CalibrationSample(keyID: "q", keyCenter: q.frame.center, region: q.region, gesture: tapAt(q.frame.center + Vec2(20, 0))))
        let model = ModelFitter.fitParameters(samples, kind: .up, keyWidth: layout390.keyWidth)

        let qOffset = model.keyOffsets["q"]!.x
        XCTAssertGreaterThan(qOffset, 0)
        XCTAssertLessThan(qOffset, 10, "one sample must not fully define a key's offset")
        XCTAssertTrue(model.globalCov.det > 0)
    }

    func testSingleSampleAndNoSamplesAreSafe() {
        let a = layout390.key(id: "a")!
        let one = [CalibrationSample(keyID: "a", keyCenter: a.frame.center, region: a.region, gesture: tapAt(a.frame.center))]
        let m1 = ModelFitter.fit(one, layout: layout390)
        XCTAssertFalse(m1.globalCov.det.isNaN)
        XCTAssertEqual(Decoder.decode(tapAt(a.frame.center), layout: layout390, model: m1).keyID, "a")

        let m0 = ModelFitter.fit([], layout: layout390)
        XCTAssertEqual(m0.sampleCount, 0)
        for id in letters {
            XCTAssertEqual(Decoder.decode(tapAt(layout390.key(id: id)!.frame.center), layout: layout390, model: m0).keyID, id)
        }
    }

    func testChoosesTouchDownWhenLiftOffDrifts() {
        // SYNTHETIC user whose first contact is accurate but whose lift-off point wanders unpredictably.
        var user = SyntheticUser(sigma: 4, liftJitter: 25)
        let samples = user.calibrate(letters + letters, layout: layout390)
        let model = ModelFitter.fit(samples, layout: layout390)
        XCTAssertNotEqual(model.pointKind, .up)
        XCTAssertGreaterThan(model.heldOutAccuracy[model.pointKind.rawValue]!, model.heldOutAccuracy["up"]!)
    }

    func testMidpointBetweenTwoKeysAsksWithThoseTwo() {
        let e = layout390.key(id: "e")!.frame.center, r = layout390.key(id: "r")!.frame.center
        let model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        let d = Decoder.decode(tapAt((e + r) / 2), layout: layout390, model: model)
        XCTAssertTrue(d.isAmbiguous)
        XCTAssertEqual(Set(d.candidates.prefix(2).map(\.keyID)), ["e", "r"])
    }

    func testClearTouchIsNotAmbiguous() {
        let model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        let d = Decoder.decode(tapAt(layout390.key(id: "g")!.frame.center), layout: layout390, model: model)
        XCTAssertFalse(d.isAmbiguous)
    }

    func testFunctionKeysStayButtons() {
        let model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        for id in ["shift", "backspace", "return", "page"] {
            XCTAssertEqual(Decoder.decode(tapAt(layout390.key(id: id)!.frame.center), layout: layout390, model: model).keyID, id)
        }
    }

    func testLetterHintCannotOverruleAClearTouch() {
        let model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        // "q" after "q" is rare in English; a touch squarely on q must still be q.
        let d = Decoder.decode(tapAt(layout390.key(id: "q")!.frame.center), layout: layout390, model: model,
                               context: .english, previous: "q")
        XCTAssertEqual(d.keyID, "q")
    }

    func testLetterHintCanTipABorderlineTouch() {
        let ctx = LetterContext.english
        XCTAssertGreaterThan(ctx.logBoost(previous: "t", nextKeyID: "h"), ctx.logBoost(previous: "t", nextKeyID: "j"))
        XCTAssertEqual(ctx.logBoost(previous: "t", nextKeyID: ","), 0)
    }

    func testModelSurvivesJSONRoundTrip() throws {
        var user = SyntheticUser(downOffset: Vec2(5, 10))
        let model = ModelFitter.fit(user.calibrate(letters, layout: layout390), layout: layout390)
        let back = try JSONDecoder().decode(TouchModel.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(back, model)
    }
}

final class RepeatTests: XCTestCase {
    func testLearnsFilterOnlyFromRepeatedExtraTaps() {
        XCTAssertFalse(RepeatFilter.learn(extraTapGaps: [], intentionalRepeatGaps: [0.2], keyWidth: 39).enabled)
        XCTAssertFalse(RepeatFilter.learn(extraTapGaps: [0.04], intentionalRepeatGaps: [0.2], keyWidth: 39).enabled)
        let f = RepeatFilter.learn(extraTapGaps: [0.04, 0.05], intentionalRepeatGaps: [0.2, 0.25], keyWidth: 39)
        XCTAssertTrue(f.enabled)
        XCTAssertEqual(f.window, 0.075, accuracy: 1e-9)
        XCTAssertLessThan(f.window, 0.2, "window must stay below this person's intentional repeat speed")
    }

    func testOverlappingTimingDisablesFilter() {
        XCTAssertFalse(RepeatFilter.learn(extraTapGaps: [0.10, 0.12], intentionalRepeatGaps: [0.15], keyWidth: 39).enabled)
    }

    func makeSession(filter: RepeatFilter) -> (TypingSession, BufferTarget) {
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        session.autoCapitalize = false
        var model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        model.repeatFilter = filter
        session.model = model
        return (session, buffer)
    }

    func testIntentionalDoubleLetterIsKept() {
        let (session, buffer) = makeSession(filter: RepeatFilter(enabled: true, window: 0.08, radius: 23))
        let l = layout390.key(id: "l")!.frame.center
        session.handle(tapAt(l, t: 0), layout: layout390)
        session.handle(tapAt(l, t: 0.3), layout: layout390)
        XCTAssertEqual(buffer.text, "ll")
    }

    func testBounceIsHeldBackButRecoverable() {
        let (session, buffer) = makeSession(filter: RepeatFilter(enabled: true, window: 0.08, radius: 23))
        let l = layout390.key(id: "l")!.frame.center
        session.handle(tapAt(l, t: 0), layout: layout390)
        session.handle(tapAt(l + Vec2(2, 1), t: 0.11), layout: layout390) // 0.03s after lift-off
        XCTAssertEqual(buffer.text, "l")
        XCTAssertEqual(session.pendingExtra, "l")
        session.keepExtra()
        XCTAssertEqual(buffer.text, "ll")
    }

    func testFastRepeatsAllCountWhenFilterOff() {
        let (session, buffer) = makeSession(filter: .off)
        let l = layout390.key(id: "l")!.frame.center
        session.handle(tapAt(l, t: 0), layout: layout390)
        session.handle(tapAt(l, t: 0.11), layout: layout390)
        XCTAssertEqual(buffer.text, "ll")
    }
}

final class TypingSessionTests: XCTestCase {
    func testChoiceSwapAndUndo() {
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        session.autoCapitalize = false
        session.model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        let e = layout390.key(id: "e")!.frame.center, r = layout390.key(id: "r")!.frame.center

        session.handle(tapAt((e + r) / 2), layout: layout390)
        let first = buffer.text
        XCTAssertNotNil(session.pendingChoice)
        session.chooseAlternative()
        XCTAssertNotEqual(buffer.text, first)
        XCTAssertEqual(session.stats.choicesChanged, 1)
        session.undoLast()
        XCTAssertEqual(buffer.text, first)
    }

    func testChoiceIgnoredIfTextMovedOn() {
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        session.autoCapitalize = false
        session.model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        let e = layout390.key(id: "e")!.frame.center, r = layout390.key(id: "r")!.frame.center
        session.handle(tapAt((e + r) / 2), layout: layout390)
        buffer.insert("xyz") // host text changed underneath us
        let before = buffer.text
        session.chooseAlternative()
        XCTAssertEqual(buffer.text, before)
    }

    func testBackspaceUndoAndShift() {
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        let a = layout390.key(id: "a")!.frame.center
        session.handle(tapAt(a, t: 0), layout: layout390) // auto-capitalized at start
        session.handle(tapAt(a, t: 1), layout: layout390)
        XCTAssertEqual(buffer.text, "Aa")
        session.handle(tapAt(layout390.key(id: "backspace")!.frame.center, t: 2), layout: layout390)
        XCTAssertEqual(buffer.text, "A")
        session.undoLast()
        XCTAssertEqual(buffer.text, "Aa")
        XCTAssertEqual(session.stats.backspaces, 1)
    }

    func testTurningOffAutoCapitalStaysOff() {
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        let a = layout390.key(id: "a")!.frame.center, shift = layout390.key(id: "shift")!.frame.center
        XCTAssertEqual(session.shift, .once) // auto-capital at the start
        session.handle(tapAt(shift, t: 0), layout: layout390)
        XCTAssertEqual(session.shift, .off)
        session.hostTextChanged() // the host app reports a change; must not bring it back
        session.autoCapitalize = true
        XCTAssertEqual(session.shift, .off)
        session.handle(tapAt(a, t: 1), layout: layout390)
        XCTAssertEqual(buffer.text, "a")
        // Still capitalizes the next sentence.
        buffer.insert(". ")
        session.hostTextChanged()
        XCTAssertEqual(session.shift, .once)
        // Double-tap from an automatic capital still gives caps lock.
        session.handle(tapAt(shift, t: 2), layout: layout390)
        session.handle(tapAt(shift, t: 2.2), layout: layout390)
        XCTAssertEqual(session.shift, .locked)
    }

    func testSpaceBarIsWider() {
        let withGlobe = KeyboardLayout.make(page: .letters, width: 390, rowHeight: 50, showNextKeyboard: true)
        XCTAssertEqual(withGlobe.key(id: "space")!.frame.w / withGlobe.keyWidth, 4, accuracy: 0.001)
        XCTAssertEqual(layout390.key(id: "return")!.frame.x + layout390.key(id: "return")!.frame.w, 390, accuracy: 0.001)
    }

    func testDemoLineShowsFixedVersusAdapted() {
        // SYNTHETIC user 30pt low: a fixed keyboard reads the row below.
        var user = SyntheticUser(downOffset: Vec2(0, 30), sigma: 3)
        let model = ModelFitter.fit(user.calibrate(letters + letters + letters, layout: layout390), layout: layout390)
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        session.autoCapitalize = false
        session.model = model
        session.askThreshold = 0
        session.recordsDemoLine = true
        for c in "wet" { session.handle(user.tap(String(c), on: layout390), layout: layout390) }
        XCTAssertEqual(buffer.text, "wet")
        XCTAssertEqual(session.demoAdapted, "wet")
        XCTAssertNotEqual(session.demoFixed, "wet")
    }
}

final class CalibrationTests: XCTestCase {
    func testStandardSetsCoverEveryLetterAndSpaceTargetsApart() {
        let sets = CalibrationSession.standardSets(layout: layout390)
        XCTAssertEqual(sets.count, 3)
        let flat = sets.flatMap { $0 }
        XCTAssertEqual(flat.count, 52 + 8 + 3)
        XCTAssertEqual(Set(flat), Set(letters + ["space"]))
    }

    func testSetsBreaksExtraTapsAndRepeats() {
        let session = CalibrationSession(sets: [["a", "l", "l"], ["p"]])
        let c = { (id: String) in layout390.key(id: id)!.frame.center }
        XCTAssertEqual(session.currentTarget, "a")
        XCTAssertEqual(session.record(tapAt(c("a"), t: 0), layout: layout390), .accepted)
        // Accidental extra contact right where "a" was, 0.05s after lift-off — while "l" is requested.
        XCTAssertEqual(session.record(tapAt(c("a"), t: 0.13), layout: layout390), .extraTap)
        XCTAssertEqual(session.record(tapAt(c("l"), t: 1), layout: layout390), .accepted)
        XCTAssertEqual(session.record(tapAt(c("l"), t: 1.3), layout: layout390), .setComplete)
        XCTAssertTrue(session.isOnBreak)
        XCTAssertNil(session.currentTarget)
        session.continueAfterBreak()
        XCTAssertEqual(session.record(tapAt(c("o"), t: 9), layout: layout390), .finished) // landed on o, counts for p
        XCTAssertEqual(session.samples.count, 4)
        XCTAssertEqual(session.extraTapGaps.count, 1)
        XCTAssertEqual(session.intentionalRepeatGaps.count, 1)
        XCTAssertEqual(session.intentionalRepeatGaps[0], 0.22, accuracy: 1e-9)
    }
}

final class ComparisonAndMetricsTests: XCTestCase {
    func testLevenshteinAndAccuracy() {
        XCTAssertEqual(TextMetrics.levenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(TextMetrics.accuracy(typed: "Hello ", target: "hello"), 1)
        XCTAssertEqual(TextMetrics.accuracy(typed: "hrllo", target: "hello"), 0.8, accuracy: 1e-9)
        XCTAssertEqual(TextMetrics.accuracy(typed: "", target: ""), 1)
    }

    func testModeOrderRotatesEveryModeThroughEveryPosition() {
        let runs = (0 ..< 3).map(ComparisonPlan.modeOrder(run:))
        for position in 0 ..< 3 {
            XCTAssertEqual(Set(runs.map { $0[position] }), Set(ComparisonMode.allCases))
        }
    }
}

final class StoreTests: XCTestCase {
    func tempStore() -> ProfileStore {
        ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testRoundTripAndDeleteAll() throws {
        let store = tempStore()
        var user = SyntheticUser()
        let samples = user.calibrate(letters, layout: layout390)
        let profile = CalibrationProfile(createdAt: Date(timeIntervalSince1970: 0), samples: samples,
                                         model: ModelFitter.fit(samples, layout: layout390))
        try store.save(profile)
        var settings = KeyboardSettings()
        settings.keySize = .large
        try store.save(settings)
        XCTAssertEqual(store.loadProfile(), profile)
        XCTAssertEqual(store.loadSettings().keySize, .large)

        try store.deleteAll()
        XCTAssertNil(store.loadProfile())
        XCTAssertEqual(store.loadSettings(), KeyboardSettings())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testTypedTextNeverReachesDisk() throws {
        let store = tempStore()
        let buffer = BufferTarget()
        let session = TypingSession(target: buffer)
        session.autoCapitalize = false
        session.model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        for (i, c) in "secretword".enumerated() {
            session.handle(tapAt(layout390.key(id: String(c))!.frame.center, t: Double(i)), layout: layout390)
        }
        XCTAssertEqual(buffer.text, "secretword")
        try store.save(KeyboardSettings())
        try store.save([TrialResult(mode: .personalized, seconds: 3, accuracy: 1, characters: 10, stats: session.stats)])
        try store.save(CalibrationProfile(createdAt: Date(), samples: [], model: session.model!))
        for file in try FileManager.default.contentsOfDirectory(atPath: store.directory.path) {
            let text = try String(contentsOf: store.directory.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("secretword"), file)
        }
    }
}
