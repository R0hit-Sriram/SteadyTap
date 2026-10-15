import Foundation

public enum ComparisonMode: String, Codable, CaseIterable, Sendable {
    case standard, larger, personalized

    public var title: String {
        switch self {
        case .standard: return "Standard keys"
        case .larger: return "Larger keys"
        case .personalized: return "Adapted to you"
        }
    }
}

/// One phrase typed in one mode. Measures only — the typed text is not kept.
public struct TrialResult: Codable, Equatable, Sendable {
    public var mode: ComparisonMode
    public var seconds: Double
    public var accuracy: Double
    /// Length of what was typed (for words-per-minute); the text itself is not kept.
    public var characters: Int
    public var stats: SessionStats

    public init(mode: ComparisonMode, seconds: Double, accuracy: Double, characters: Int, stats: SessionStats) {
        self.mode = mode
        self.seconds = seconds
        self.accuracy = accuracy
        self.characters = characters
        self.stats = stats
    }

    /// Standard text-entry speed: (characters − 1) / seconds × 60 / 5. Normalizes for phrase length.
    public var wordsPerMinute: Double {
        guard seconds > 0, characters > 1 else { return 0 }
        return Double(characters - 1) / seconds * 60 / 5
    }
}

public enum ComparisonPlan {
    public static let phrasesPerMode = 3

    /// Short, everyday phrases written for this app. Each set includes a name or non-dictionary
    /// word, so improvement can't come from guessing words.
    public static let phraseSets: [[String]] = [
        ["the bus comes at noon", "meet priya at the park", "bring two pens"],
        ["call mom after school", "zoe sent the quiz link", "the soup is hot"],
        ["see you on friday", "my dog likes warm toast", "ask jamal for help"],
    ]

    /// Rotates which mode goes first, so practice/fatigue doesn't always favor the same mode.
    /// Phrase sets stay in position order, so each mode meets different phrases across runs.
    public static func modeOrder(run: Int) -> [ComparisonMode] {
        let all = ComparisonMode.allCases
        return all.indices.map { all[($0 + run) % all.count] }
    }
}

/// Typical value and spread for one mode.
public struct ModeSummary: Equatable, Sendable {
    public var mode: ComparisonMode
    public var trials: Int
    public var wpmMedian: Double
    public var wpmRange: ClosedRange<Double>
    public var accuracyMedian: Double
    public var accuracyRange: ClosedRange<Double>
    public var corrections: Int
    public var choicesShown: Int
    public var choicesChanged: Int
    public var hintChanges: Int
}

public enum ComparisonStats {
    public static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    public static func summarize(_ results: [TrialResult]) -> [ModeSummary] {
        ComparisonMode.allCases.compactMap { mode in
            let r = results.filter { $0.mode == mode }
            guard !r.isEmpty else { return nil }
            let wpm = r.map(\.wordsPerMinute), acc = r.map(\.accuracy)
            return ModeSummary(
                mode: mode, trials: r.count,
                wpmMedian: median(wpm), wpmRange: wpm.min()! ... wpm.max()!,
                accuracyMedian: median(acc), accuracyRange: acc.min()! ... acc.max()!,
                corrections: r.reduce(0) { $0 + $1.stats.backspaces + $1.stats.undos },
                choicesShown: r.reduce(0) { $0 + $1.stats.choicesShown },
                choicesChanged: r.reduce(0) { $0 + $1.stats.choicesChanged },
                hintChanges: r.reduce(0) { $0 + $1.stats.hintChanges }
            )
        }
    }

    /// Plain-text report, including an honest note when results are too close to call.
    public static func report(_ results: [TrialResult]) -> String {
        let rows = summarize(results)
        var lines = ["Typing comparison — my own test on this phone, not a medical or clinical result."]
        for s in rows {
            let numbers = String(
                format: "%.1f words/min (%.1f–%.1f), %.0f%% accurate (%.0f–%.0f%%)",
                s.wpmMedian, s.wpmRange.lowerBound, s.wpmRange.upperBound,
                s.accuracyMedian * 100, s.accuracyRange.lowerBound * 100, s.accuracyRange.upperBound * 100)
            lines.append("\(s.mode.title) (\(s.trials) phrases): \(numbers), \(s.corrections) corrections, "
                + "\(s.choicesShown) choices (\(s.choicesChanged) changed)")
        }
        if let adapted = rows.first(where: { $0.mode == .personalized }) {
            if adapted.hintChanges > 0 {
                lines.append("Letter-pair hint decided \(adapted.hintChanges) tap(s) in the adapted mode; touch decided the rest.")
            }
            for other in rows where other.mode != .personalized {
                if adapted.wpmRange.overlaps(other.wpmRange) && adapted.accuracyRange.overlaps(other.accuracyRange) {
                    lines.append("\(adapted.mode.title) vs \(other.mode.title): the ranges overlap, so the difference may be chance. More runs would make it clearer.")
                }
            }
        }
        lines.append("Typical value shown first (median), then lowest–highest.")
        return lines.joined(separator: "\n")
    }
}

public enum TextMetrics {
    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0 ... b.count)
        for i in 1 ... a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1 ... b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// 1 − (edit distance / longer length), ignoring case and surrounding spaces. 1.0 = perfect.
    public static func accuracy(typed: String, target: String) -> Double {
        let t = typed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let g = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let longest = max(t.count, g.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(t, g)) / Double(longest)
    }
}
