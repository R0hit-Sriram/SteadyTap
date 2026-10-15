import Foundation

/// A small, local letter-pair table: "after letter X, how common is letter Y?"
/// It is a SECONDARY hint only. Its effect is clamped so it can nudge a borderline touch
/// but can never overrule a clear one. Built at launch from a short public-domain text
/// (the Gettysburg Address); no dictionary, no network, no model download.
public struct LetterContext: Sendable {
    /// 27×27 table (a–z plus "space/other") of log(P(next | previous) / uniform), clamped.
    private let boosts: [[Double]]
    public static let maxBoost = 2.0

    public init(corpus: String) {
        var counts = Array(repeating: Array(repeating: 1.0, count: 27), count: 27) // add-one smoothing
        var prev = 26
        for c in corpus.lowercased() {
            let i = LetterContext.index(of: c)
            if !(prev == 26 && i == 26) { counts[prev][i] += 1 }
            prev = i
        }
        boosts = counts.map { row in
            let total = row.reduce(0, +)
            return row.map { min(max(log($0 / total * 27), -LetterContext.maxBoost), LetterContext.maxBoost) }
        }
    }

    public static let english = LetterContext(corpus: gettysburgAddress)

    /// Positive = this key is more common than average after `previous`; 0 = no opinion.
    public func logBoost(previous: Character?, nextKeyID: String) -> Double {
        let next: Int
        if nextKeyID == "space" {
            next = 26
        } else if nextKeyID.count == 1, let c = nextKeyID.first, c.isLetter, c.isASCII {
            next = LetterContext.index(of: c)
        } else {
            return 0 // punctuation: no opinion
        }
        return boosts[previous.map(LetterContext.index(of:)) ?? 26][next]
    }

    static func index(of c: Character) -> Int {
        guard let a = c.lowercased().unicodeScalars.first, c.isASCII, c.isLetter else { return 26 }
        return Int(a.value) - 97
    }

    static let gettysburgAddress = """
    Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in \
    Liberty, and dedicated to the proposition that all men are created equal. Now we are engaged in a great \
    civil war, testing whether that nation, or any nation so conceived and so dedicated, can long endure. We \
    are met on a great battle-field of that war. We have come to dedicate a portion of that field, as a final \
    resting place for those who here gave their lives that that nation might live. It is altogether fitting and \
    proper that we should do this. But, in a larger sense, we can not dedicate, we can not consecrate, we can \
    not hallow this ground. The brave men, living and dead, who struggled here, have consecrated it, far above \
    our poor power to add or detract. The world will little note, nor long remember what we say here, but it \
    can never forget what they did here. It is for us the living, rather, to be dedicated here to the \
    unfinished work which they who fought here have thus far so nobly advanced. It is rather for us to be here \
    dedicated to the great task remaining before us, that from these honored dead we take increased devotion \
    to that cause for which they gave the last full measure of devotion, that we here highly resolve that \
    these dead shall not have died in vain, that this nation, under God, shall have a new birth of freedom, \
    and that government of the people, by the people, for the people, shall not perish from the earth.
    """
}
