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
        // isNewline: a Windows checkout has "\r\n", which Swift counts as one character, not "\n".
        for line in text.split(whereSeparator: { $0.isNewline }) where !line.hasPrefix("#") {
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

    /// The 40,000 most common English words (see tools/make_wordlist.py for source and license).
    public static let english: WordList = {
        guard let url = Bundle.module.url(forResource: "words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return WordList(text: "") }
        return WordList(text: text)
    }()
}

/// Fixes a whole word when space is pressed.
///
/// For every listed word with about the same number of letters (one more, the same, or one fewer):
///   score(word) = log P(taps | word)   ← how well this person's taps fit, from THEIR touch model
///               + log P(word)          ← how common the word is
/// P(taps | word) lines the taps up with the word's letters. Each tap normally means one letter (scored by the
/// touch model), but a tap can also be an extra one (a bounce or a stray touch), a letter can be missed,
/// or two neighbouring letters can be swapped. Each of those costs a fixed penalty, so the plain reading
/// wins unless the word is much better. We use the best line-up (dynamic programming, like spell checkers).
/// The typed letters compete too (as an unlisted word if they aren't on the list). Scores become
/// probabilities with softmax; we only change the word if the best one is at least `fixThreshold` likely.
/// This is a "noisy channel" decoder, the same idea phone keyboards use, small enough to explain.
public enum WordFixer {
    /// Smallest probability a tap gives any letter, so one far-off letter can't make a word impossible.
    public static let letterFloor = 1e-6
    public static let fixThreshold = 0.8
    /// Chance that a tap landed exactly where the person aimed, but they aimed at the wrong letter (a spelling
    /// slip, not a touch error). Without it, a careful typist's typos could never be fixed, because their
    /// touch model is so sure of every key.
    public static let slip = 0.03
    /// How much less likely an unlisted word is than the rarest listed one (log, e^-7 ≈ 1/1100). Most unlisted
    /// words a person types are misspellings; names still stay when no listed word is close.
    public static let unknownPenalty = -7.0
    public static let maxLength = 15

    /// How likely each kind of slip is, per word (log probabilities). Rare on purpose: a slip has to be
    /// clearly better than reading the taps as typed. A repeated tap on the letter just typed (a tremor
    /// "bounce") is the most likely extra tap.
    public static let extraTap = log(0.005)
    public static let repeatedTap = log(0.03)
    public static let missedLetter = log(0.005)
    public static let swappedLetters = log(0.003)

    public struct Fix: Equatable, Sendable {
        public let word: String
        public let probability: Double
    }

    /// log P(letter | tap) for a…z from TOUCH evidence only (the letter-pair hint is left out so it
    /// isn't counted twice). nil if the decision has no letter candidates.
    /// `scale` (≤ 1) turns down a model that was too sure of itself on this person's calibration taps.
    public static func letterEvidence(_ candidates: [Candidate], scale: Double = 1) -> [Double]? {
        var scores = Array(repeating: -Double.infinity, count: 26)
        for c in candidates where c.keyID.count == 1 {
            let i = LetterContext.index(of: c.keyID.first!)
            if i < 26 { scores[i] = scale * c.touchScore }
        }
        guard let top = scores.max(), top > -Double.infinity else { return nil }
        let sum = scores.reduce(0) { $0 + exp($1 - top) }
        return scores.map { log((1 - slip) * exp($0 - top) / sum + slip / 26) }
    }

    /// Evidence for a letter the person picked themselves in the choice bar: that letter, for sure.
    /// Every other letter is impossible, so no fix or suggestion can change it.
    public static func certain(_ letter: Character) -> [Double] {
        var e = Array(repeating: -Double.infinity, count: 26)
        let i = LetterContext.index(of: letter)
        if i < 26 { e[i] = 0 }
        return e
    }

    /// log P(taps | letters): the best line-up of taps with letters (see the type comment).
    /// A tap whose evidence is certain (picked in the choice bar) is never treated as extra or swapped.
    /// Stops early (returns -∞) once the word can't reach `atLeast`: every step only lowers the score.
    static func fit(_ letters: [Int], _ taps: Taps, atLeast: Double = -.infinity) -> Double {
        let n = taps.count, m = letters.count, w = m + 1, band = 2
        let e = taps.evidence, picked = taps.picked
        func ev(_ i: Int, _ letter: Int) -> Double { e[i * 26 + letter] }
        var d = [Double](repeating: -.infinity, count: (n + 1) * w)
        d[0] = 0
        for i in 0 ... n {
            var rowBest = -Double.infinity
            for j in max(0, i - band) ... min(m, i + band) where i + j > 0 {
                var best = -Double.infinity
                if i > 0, j > 0 { best = d[(i - 1) * w + j - 1] + ev(i - 1, letters[j - 1]) }
                if i > 0, !picked[i - 1] {
                    var extra = extraTap
                    if j > 0 { extra = max(extra, repeatedTap + ev(i - 1, letters[j - 1])) }
                    best = max(best, d[(i - 1) * w + j] + extra)
                }
                if j > 0 { best = max(best, d[i * w + j - 1] + missedLetter) }
                if i > 1, j > 1, letters[j - 1] != letters[j - 2], !picked[i - 1], !picked[i - 2] {
                    best = max(best, d[(i - 2) * w + j - 2] + ev(i - 2, letters[j - 1]) + ev(i - 1, letters[j - 2]) + swappedLetters)
                }
                d[i * w + j] = best
                rowBest = max(rowBest, best)
            }
            if rowBest < atLeast { return -.infinity }
        }
        return d[n * w + m]
    }

    /// The taps of one word, laid out once per word fix (not once per candidate word).
    struct Taps {
        let count: Int
        let evidence: [Double] // tap i, letter k at [i * 26 + k]
        let picked: [Bool]     // chosen in the choice bar: certain
        init(_ rows: [[Double]]) {
            count = rows.count
            evidence = rows.flatMap { $0 }
            picked = rows.map { $0.contains(0) && $0.filter { $0 > log(WordFixer.letterFloor) }.count == 1 }
        }
    }

    /// Words scoring this far below the best barely change the probabilities (each adds < e^-14), so stop early.
    static let ignoreBelow = 14.0

    /// The fix for `typed` (lowercase a–z, one evidence row per letter), or nil to leave it alone.
    public static func fix(typed: String, evidence: [[Double]], words: WordList) -> Fix? {
        guard let scores = fixScores(typed: typed, evidence: evidence, words: words) else { return nil }
        return bestFix(typed: typed, scores)
    }

    /// The typed letters and every listed word of about the same length (one fewer, same, one more) that
    /// scores within `ignoreBelow` of the best. nil if `typed` can't be fixed (too short/long, not a–z).
    static func fixScores(typed: String, evidence: [[Double]], words: WordList) -> [(word: String, score: Double)]? {
        guard typed.count == evidence.count, (2 ... maxLength).contains(typed.count),
              typed.allSatisfy({ LetterContext.index(of: $0) < 26 }) else { return nil }
        let entries = (typed.count - 1 ... typed.count + 1).filter { $0 >= 2 }.flatMap { words.byLength[$0] ?? [] }
        guard !entries.isEmpty else { return nil }

        let taps = Taps(evidence)
        // The typed letters as they are: a strong starting point, so most other words stop early.
        let typedScore = fit(typed.map(LetterContext.index(of:)), taps) + (words.logPriors[typed] ?? words.unknownLogPrior + unknownPenalty)
        var scores = [(word: typed, score: typedScore)]
        var best = typedScore
        for e in entries where e.word != typed {
            let score = fit(e.letters, taps, atLeast: best - ignoreBelow - e.logPrior) + e.logPrior
            guard score > best - ignoreBelow else { continue }
            scores.append((e.word, score))
            best = max(best, score)
        }
        return scores
    }

    private static func bestFix(typed: String, _ scores: [(word: String, score: Double)]) -> Fix? {
        guard let top = scores.max(by: { $0.score < $1.score }), top.word != typed else { return nil }
        let total = scores.reduce(0) { $0 + exp($1.score - top.score) }
        let p = 1 / total
        return p >= fixThreshold ? Fix(word: top.word, probability: p) : nil
    }

    /// What the suggestion bar shows for the word being typed.
    public struct Suggestions: Equatable, Sendable {
        /// The letters as typed (the bar shows them in quotes; tapping keeps them).
        public var typed: String
        /// The word space will put in instead, or nil to leave the typed word alone.
        public var autocorrect: String?
        /// Other likely words, best first: never `typed` or `autocorrect`.
        public var others: [String]
        public static let none = Suggestions(typed: "", autocorrect: nil, others: [])
    }

    /// Suggestions for a word in progress: fixes of about the same length (as in `fix`) plus completions,
    /// longer words whose first letters fit the taps so far. A completion is scored on those taps only:
    ///   score = Σ log P(letter i | tap i) + log P(word)
    /// which is the same quantity a fix is scored by, so the two kinds can be ranked together.
    public static func suggest(typed: String, evidence: [[Double]], words: WordList,
                               autocorrect: Bool = true, limit: Int = 2) -> Suggestions {
        let n = typed.count
        guard n == evidence.count, (1 ... maxLength).contains(n),
              typed.allSatisfy({ LetterContext.index(of: $0) < 26 }) else { return .none }
        var scores = fixScores(typed: typed, evidence: evidence, words: words) ?? []
        let fix = autocorrect ? bestFix(typed: typed, scores) : nil

        let e = Taps(evidence).evidence
        var best = scores.map(\.score).max() ?? -.infinity
        for length in n + 1 ... maxLength {
            for w in words.byLength[length] ?? [] {
                var s = w.logPrior
                for i in 0 ..< n {
                    s += e[i * 26 + w.letters[i]]
                    if s < best - ignoreBelow { break } // every letter only lowers it
                }
                guard s > best - ignoreBelow else { continue }
                scores.append((w.word, s))
                best = max(best, s)
            }
        }
        let others = scores.sorted { $0.score > $1.score }.map(\.word)
            .filter { $0 != typed && $0 != fix?.word }
        return Suggestions(typed: typed, autocorrect: fix?.word, others: Array(others.prefix(limit)))
    }
}
