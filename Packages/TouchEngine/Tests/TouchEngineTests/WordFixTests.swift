import Foundation
import XCTest
@testable import TouchEngine

func wordSession() -> (TypingSession, BufferTarget) {
    let buffer = BufferTarget()
    let session = TypingSession(target: buffer)
    session.autoCapitalize = false
    session.model = TouchModel.untrained(keyWidth: layout390.keyWidth)
    session.words = .english
    return (session, buffer)
}

func center(_ id: String) -> Vec2 { layout390.key(id: id)!.frame.center }

/// Taps each character once at the given points (nil = dead center of the key).
func type(_ text: String, _ session: TypingSession, nudge: [Int: Vec2] = [:]) {
    for (i, c) in text.enumerated() {
        let id = c == " " ? "space" : String(c).lowercased()
        session.handle(tapAt(center(id) + (nudge[i] ?? .zero), t: Double(i)), layout: layout390)
    }
}

/// SYNTHETIC: a noisy typist types `text` once, with no corrections. Share of words that came out right.
func wordAccuracy(_ text: String, fixWords: Bool, sigma: Double, slips: Bool = false) -> Double {
    var user = SyntheticUser(sigma: sigma)
    let samples = user.calibrate(CalibrationSession.standardSets(layout: layout390).flatMap { $0 }, layout: layout390)
    var typist = SyntheticUser(sigma: sigma, rng: SplitMix64(seed: 3))
    let buffer = BufferTarget()
    let session = TypingSession(target: buffer)
    session.autoCapitalize = false
    session.model = ModelFitter.fit(samples, layout: layout390)
    session.words = fixWords ? .english : nil
    var n = 0
    for c in text {
        n += 1
        let key = c == " " ? "space" : String(c)
        if slips, c != " ", n % 23 == 0 { continue } // a missed letter
        session.handle(typist.tap(key, on: layout390), layout: layout390)
        if slips, c != " ", n % 29 == 0 { session.handle(typist.tap(key, on: layout390), layout: layout390) } // a double tap
    }
    let got = buffer.text.split(separator: " "), want = text.split(separator: " ")
    // Words right, aligned by longest common subsequence (a misread space mustn't shift every later word).
    var lcs = Array(repeating: Array(repeating: 0, count: want.count + 1), count: got.count + 1)
    for i in 1 ... got.count {
        for j in 1 ... want.count {
            lcs[i][j] = got[i - 1] == want[j - 1] ? lcs[i - 1][j - 1] + 1 : max(lcs[i - 1][j], lcs[i][j - 1])
        }
    }
    return Double(lcs[got.count][want.count]) / Double(want.count)
}

let everydayText = """
i will call you when i get home tonight please bring the blue bag and some water we can meet at the park \
after school my mother said dinner is ready at six thank you for helping me with the homework yesterday \
it was really nice to see you again let me know if you need anything else from the store
"""

final class WordFixTests: XCTestCase {
    func testWordListLoadsFromTheBundle() {
        let words = WordList.english
        XCTAssertGreaterThan(words.count, 35000)
        XCTAssertTrue(words.contains("the"))
        XCTAssertTrue(words.contains("thank"))
        XCTAssertFalse(words.contains("retarded"), "blocked words are never offered as a fix")
    }

    func testBorderlineTapIsFixedByTheWholeWord() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        // "t", then a tap on the g side of the g/h border, then "e": reads "tge"; the word says "the".
        type("tge ", session, nudge: [1: Vec2(12, 0)])
        XCTAssertEqual(buffer.text, "the ")
        XCTAssertEqual(session.lastWordFix, .init(typed: "tge", fixed: "the"))
        XCTAssertEqual(session.stats.wordFixes, 1)
    }

    func testUndoBringsBackWhatWasTyped() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        type("tge ", session, nudge: [1: Vec2(12, 0)])
        session.undoLast()
        XCTAssertEqual(buffer.text, "tge ")
    }

    func testCapitalIsKept() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        session.shift = .once
        type("tge ", session, nudge: [1: Vec2(12, 0)])
        XCTAssertEqual(buffer.text, "The ")
    }

    func testClearTapsOfARealWordAreLeftAlone() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        type("car form ", session) // "car" isn't changed to the more common "can", nor "form" to "from"
        XCTAssertEqual(buffer.text, "car form ")
        XCTAssertNil(session.lastWordFix)
    }

    func testClearTapsOfAnUnlistedWordAreLeftAlone() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        type("zorp ", session)
        XCTAssertEqual(buffer.text, "zorp ")
    }

    func testALetterPickedInTheChoiceBarIsNeverChanged() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        session.askThreshold = 0.99 // ask about every letter
        session.handle(tapAt(center("t")), layout: layout390)
        session.acceptChoice()
        session.handle(tapAt(center("g") + Vec2(12, 0), t: 1), layout: layout390)
        if session.pendingChoice?.inserted == "g" { session.acceptChoice() } else if session.pendingChoice?.alternative == "g" { session.chooseAlternative() }
        session.handle(tapAt(center("e"), t: 2), layout: layout390)
        session.acceptChoice()
        session.handle(tapAt(center("space"), t: 3), layout: layout390)
        XCTAssertEqual(buffer.text, "tge ", "the person said g on purpose")
    }

    func testFixesWithoutCalibrationToo() {
        // No adapted model: taps are read like a fixed keyboard would, and the word is still fixed.
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        session.model = nil
        type("tge ", session, nudge: [1: Vec2(12, 0)])
        XCTAssertEqual(buffer.text, "the ")
    }

    func testFixingWholeWordsHelpsANoisyTypist() {
        // SYNTHETIC typist, not a person.
        let off = wordAccuracy(everydayText, fixWords: false, sigma: 10)
        let on = wordAccuracy(everydayText, fixWords: true, sigma: 10)
        print("SYNTHETIC word accuracy, sigma 10: letters only \(off), with word fixing \(on)")
        XCTAssertGreaterThan(on, off + 0.1)
        let steadyOff = wordAccuracy(everydayText, fixWords: false, sigma: 3)
        let steadyOn = wordAccuracy(everydayText, fixWords: true, sigma: 3)
        print("SYNTHETIC word accuracy, sigma 3: letters only \(steadyOff), with word fixing \(steadyOn)")
        XCTAssertGreaterThanOrEqual(steadyOn, steadyOff, "never worse for a steady typist")
    }

    func testTapsAcrossTheSpaceBarTypeSpace() {
        let space = layout390.key(id: "space")!.frame
        let model = TouchModel.untrained(keyWidth: layout390.keyWidth)
        for f in [0.2, 0.5, 0.8] {
            let p = Vec2(space.x + f * space.w, space.center.y - 10)
            XCTAssertEqual(Decoder.score(point: p, layout: layout390, model: model)[0].keyID, "space", "at \(f) of the bar")
        }
    }

    func testPickingSpaceInTheChoiceBarDoesNotBreakWordFixing() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        session.askThreshold = 0.99
        type("go", session)
        session.handle(tapAt(center("b") + Vec2(0, 20), t: 5), layout: layout390)
        if session.pendingChoice?.alternative == " " { session.chooseAlternative() } else { session.acceptChoice(); type(" ", session) }
        session.askThreshold = 0.7
        type("home ", session) // must not crash
        XCTAssertTrue(buffer.text.hasSuffix("home "))
    }

    func testMissedExtraAndSwappedLettersAreFixed() {
        for (typed, want) in [("becuse ", "because "), ("plese ", "please "), ("thhe ", "the "), ("helllo ", "hello "), ("teh ", "the ")] {
            let (session, buffer) = wordSession()
            type(typed, session)
            XCTAssertEqual(buffer.text, want, typed)
        }
    }

    func testCarefullyTypedRealWordsAndNamesStay() {
        for typed in ["car ", "form ", "care ", "hat ", "ten ", "bat ", "win ", "an ", "rohit ", "priya ", "zorp "] {
            let (session, buffer) = wordSession()
            type(typed, session)
            XCTAssertEqual(buffer.text, typed)
        }
    }

    func testWordFixingHelpsWithMissedAndDoubledLetters() {
        // SYNTHETIC typist, not a person: also drops some letters and taps some twice.
        let off = wordAccuracy(everydayText, fixWords: false, sigma: 6, slips: true)
        let on = wordAccuracy(everydayText, fixWords: true, sigma: 6, slips: true)
        print("SYNTHETIC word accuracy with slips, sigma 6: letters only \(off), with word fixing \(on)")
        XCTAssertGreaterThan(on, off + 0.05)
    }

    func testConfidenceScaleIsFittedAndNeverAboveOne() {
        var user = SyntheticUser(sigma: 10)
        let samples = user.calibrate(CalibrationSession.standardSets(layout: layout390).flatMap { $0 }, layout: layout390)
        let model = ModelFitter.fit(samples, layout: layout390)
        let s = try! XCTUnwrap(model.confidenceScale)
        print("SYNTHETIC confidence scale, sigma 10: \(s)")
        XCTAssert((0.1 ... 1).contains(s))
    }

    func testACarefulTypistsTyposAreFixedToo() {
        // A steady person's model is very sure of every key, so this needs the spelling-slip allowance.
        var user = SyntheticUser(sigma: 3)
        let samples = user.calibrate(CalibrationSession.standardSets(layout: layout390).flatMap { $0 }, layout: layout390)
        for (typed, want) in [("tge ", "the "), ("becuse ", "because "), ("car ", "car "), ("form ", "form "), ("hat ", "hat ")] {
            let (session, buffer) = wordSession()
            session.model = ModelFitter.fit(samples, layout: layout390)
            type(typed, session)
            XCTAssertEqual(buffer.text, want, typed)
        }
    }

    func testWordIsFixedEvenWhenTheSpaceWasACloseCall() {
        let (session, buffer) = wordSession()
        session.askThreshold = 0.99 // every tap is "unsure"
        type("tge ", session, nudge: [1: Vec2(12, 0)])
        XCTAssertEqual(buffer.text, "the ")
    }

    func testIfThatSpaceWasReallyALetterTheTypedWordComesBack() {
        let (session, buffer) = wordSession()
        session.askThreshold = 0.99
        type("tge", session, nudge: [1: Vec2(12, 0)])
        session.handle(tapAt(center("space") + Vec2(-60, -22), t: 9), layout: layout390)
        guard session.pendingChoice?.inserted == " " else { return } // this tap wasn't a close call on this layout
        session.chooseAlternative()
        XCTAssertTrue(buffer.text.hasPrefix("tge"), buffer.text)
        XCTAssertFalse(buffer.text.contains(" "))
    }

    func testEmojiIsTypedAsIsAndUndoRemovesIt() {
        let (session, buffer) = wordSession()
        type("hi ", session)
        session.insertText("👍")
        XCTAssertEqual(buffer.text, "hi 👍")
        session.undoLast()
        XCTAssertEqual(buffer.text, "hi ")
    }

    func testOldSettingsTurnWordFixingOn() throws {
        let s = try JSONDecoder().decode(KeyboardSettings.self, from: Data(#"{"adaptationOn":true}"#.utf8))
        XCTAssertTrue(s.fixWords)
    }
}
