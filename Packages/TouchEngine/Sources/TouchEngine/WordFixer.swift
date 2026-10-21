import Foundation

/// Common English words and how often each is used (bundled file, read on the phone; no network).
public struct WordList: Sendable {
    struct Entry: Sendable {
        let word: String
        let letters: [Int]
        let logPrior: Double
    }

    let byLength: [Int: [Entry]]
    let logPriors: [String: Double]
    /// Prior for a word that isn't on the list (a name, slang): the rarest listed word's.
    let unknownLogPrior: Double

    /// `text`: one "word count" per line; lines starting with # are ignored.
    public init(text: String) {
        var counts: [(String, Double)] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let n = Double(parts[1]), n > 0 else { continue }
            counts.append((String(parts[0]), n))
        }
        let total = counts.reduce(0) { $0 + $1.1 }
        var byLength: [Int: [Entry]] = [:]
        var logPriors: [String: Double] = [:]
        for (word, n) in counts {
            let letters = word.map(LetterContext.index(of:))
            guard !letters.contains(26) else { continue }
            let prior = log(n / total)
            byLength[word.count, default: []].append(Entry(word: word, letters: letters, logPrior: prior))
            logPriors[word] = prior
        }
        self.byLength = byLength
        self.logPriors = logPriors
        unknownLogPrior = logPriors.values.min() ?? 0
    }

    public var count: Int { logPriors.count }
    public func contains(_ word: String) -> Bool { logPriors[word] != nil }

    /// The 20,000 most common English words (see tools/make_wordlist.py for source and license).
    public static let english: WordList = {
        guard let url = Bundle.module.url(forResource: "words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return WordList(text: "") }
        return WordList(text: text)
    }()
}

/// Fixes a whole word when space is pressed.
///
/// For every listed word with the same number of letters:
///   score(word) = Σ log P(letter i | tap i)   ← how well this person's taps fit, from THEIR touch model
///               + log P(word)                  ← how common the word is
/// The typed letters compete too (as an unlisted word if they aren't on the list). Scores become
/// probabilities with softmax; we only change the word if the best one is at least `fixThreshold` likely.
/// This is a "noisy channel" decoder, the same idea phone keyboards use, small enough to explain.
public enum WordFixer {
    /// Smallest probability a tap gives any letter, so one far-off letter can't make a word impossible.
    public static let letterFloor = 1e-6
    public static let fixThreshold = 0.8
    public static let maxLength = 15

    public struct Fix: Equatable, Sendable {
        public let word: String
        public let probability: Double
    }

    /// log P(letter | tap) for a…z from TOUCH evidence only (the letter-pair hint is left out so it
    /// isn't counted twice). nil if the decision has no letter candidates.
    public static func letterEvidence(_ candidates: [Candidate]) -> [Double]? {
        var scores = Array(repeating: -Double.infinity, count: 26)
        for c in candidates where c.keyID.count == 1 {
            let i = LetterContext.index(of: c.keyID.first!)
            if i < 26 { scores[i] = c.touchScore }
        }
        guard let top = scores.max(), top > -Double.infinity else { return nil }
        let sum = scores.reduce(0) { $0 + exp($1 - top) }
        return scores.map { max($0 - top - log(sum), log(letterFloor)) }
    }

    /// Evidence for a letter the person picked themselves in the choice bar: that letter, for sure.
    public static func certain(_ letter: Character) -> [Double] {
        var e = Array(repeating: log(letterFloor), count: 26)
        let i = LetterContext.index(of: letter)
        if i < 26 { e[i] = 0 }
        return e
    }

    /// The fix for `typed` (lowercase a–z, one evidence row per letter), or nil to leave it alone.
    public static func fix(typed: String, evidence: [[Double]], words: WordList) -> Fix? {
        guard typed.count == evidence.count, (2 ... maxLength).contains(typed.count),
              let entries = words.byLength[typed.count] else { return nil }

        func touch(_ letters: [Int]) -> Double { zip(letters, evidence).reduce(0) { $0 + $1.1[$1.0] } }
        var scores = entries.map { (word: $0.word, score: touch($0.letters) + $0.logPrior) }
        if !words.contains(typed) {
            scores.append((typed, touch(typed.map(LetterContext.index(of:))) + words.unknownLogPrior))
        }
        guard let best = scores.max(by: { $0.score < $1.score }), best.word != typed else { return nil }
        let total = scores.reduce(0) { $0 + exp($1.score - best.score) }
        let p = 1 / total
        return p >= fixThreshold ? Fix(word: best.word, probability: p) : nil
    }
}
