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
func wordAccuracy(_ text: String, fixWords: Bool, sigma: Double) -> Double {
    var user = SyntheticUser(sigma: sigma)
    let samples = user.calibrate(CalibrationSession.standardSets(layout: layout390).flatMap { $0 }, layout: layout390)
    var typist = SyntheticUser(sigma: sigma, rng: SplitMix64(seed: 3))
    let buffer = BufferTarget()
    let session = TypingSession(target: buffer)
    session.autoCapitalize = false
    session.model = ModelFitter.fit(samples, layout: layout390)
    session.words = fixWords ? .english : nil
    for c in text { session.handle(typist.tap(c == " " ? "space" : String(c), on: layout390), layout: layout390) }
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
        XCTAssertGreaterThan(words.count, 15000)
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

    func testNoFixingWithoutAnAdaptedModel() {
        let (session, buffer) = wordSession()
        defer { withExtendedLifetime(buffer) {} }
        session.model = nil
        type("tge ", session, nudge: [1: Vec2(12, 0)])
        XCTAssertEqual(buffer.text, "tge ")
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

    func testOldSettingsTurnWordFixingOn() throws {
        let s = try JSONDecoder().decode(KeyboardSettings.self, from: Data(#"{"adaptationOn":true}"#.utf8))
        XCTAssertTrue(s.fixWords)
    }
}
