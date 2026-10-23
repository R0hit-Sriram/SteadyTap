import XCTest
@testable import TouchEngine

/// The Apple-style suggestion bar and autocorrect, with NO calibration (model = nil): taps land on key centers.
final class AutocorrectTests: XCTestCase {
    private func session() -> (TypingSession, BufferTarget) {
        let buffer = BufferTarget()
        let s = TypingSession(target: buffer)
        s.autoCapitalize = false
        s.words = .english
        return (s, buffer)
    }

    private var t = 0.0
    private func type(_ text: String, into s: TypingSession) {
        for c in text {
            let id = c == " " ? "space" : String(c)
            t += 0.5
            s.handle(tapAt(layout390.key(id: id)!.frame.center, t: t), layout: layout390)
        }
    }

    func testFixesTyposWithoutCalibration() {
        let (s, buffer) = session()
        type("teh ", into: s)
        XCTAssertEqual(buffer.text, "the ")
    }

    func testBarShowsTypedWordAndTheCorrectionSpaceWillMake() {
        let (s, buffer) = session()
        defer { withExtendedLifetime(buffer) {} }
        type("teh", into: s)
        XCTAssertEqual(s.suggestions.typed, "teh")
        XCTAssertEqual(s.suggestions.autocorrect, "the")
    }

    func testBarCompletesWordsWhileTyping() {
        let (s, buffer) = session()
        defer { withExtendedLifetime(buffer) {} }
        type("becau", into: s)
        XCTAssertTrue(([s.suggestions.autocorrect].compactMap { $0 } + s.suggestions.others).contains("because"),
                      "\(s.suggestions)")
    }

    func testRealWordsAreNotAutocorrected() {
        let (s, buffer) = session()
        type("hello world ", into: s)
        XCTAssertEqual(buffer.text, "hello world ")
    }

    func testPickingASuggestionReplacesTheWordAndAddsASpace() {
        let (s, buffer) = session()
        type("becau", into: s)
        s.acceptSuggestion("because")
        XCTAssertEqual(buffer.text, "because ")
        s.undoLast()
        XCTAssertEqual(buffer.text, "becau")
    }

    func testKeepingTheTypedWordStopsAutocorrectForIt() {
        let (s, buffer) = session()
        type("teh", into: s)
        s.acceptSuggestion("teh") // tapped “teh” in the bar
        XCTAssertEqual(buffer.text, "teh ")
        type("teh ", into: s)
        XCTAssertEqual(buffer.text, "teh teh ")
    }

    func testRevertingAnAutocorrectPutsTheTypedWordBack() {
        let (s, buffer) = session()
        type("teh ", into: s)
        XCTAssertEqual(s.lastWordFix?.typed, "teh")
        s.revertWordFix()
        XCTAssertEqual(buffer.text, "teh ")
        XCTAssertNil(s.lastWordFix)
        type("teh ", into: s) // remembered for the rest of the session
        XCTAssertEqual(buffer.text, "teh teh ")
    }

    func testPunctuationAlsoAppliesTheCorrection() {
        let (s, buffer) = session()
        type("teh.", into: s)
        XCTAssertEqual(buffer.text, "the.")
    }

    func testCapitalIsKept() {
        let (s, buffer) = session()
        s.shift = .once
        type("teh ", into: s)
        XCTAssertEqual(buffer.text, "The ")
    }

    func testAutocorrectOffStillSuggestsButNeverChangesTheWord() {
        let (s, buffer) = session()
        s.autocorrects = false
        type("teh", into: s)
        XCTAssertNil(s.suggestions.autocorrect)
        XCTAssertTrue(s.suggestions.others.contains("the"), "\(s.suggestions)")
        type(" ", into: s)
        XCTAssertEqual(buffer.text, "teh ")
    }
}
