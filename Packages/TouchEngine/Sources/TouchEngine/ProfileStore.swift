import Foundation

public enum KeySize: String, Codable, CaseIterable, Sendable {
    case standard, large
    public var rowHeightMultiplier: Double { self == .standard ? 1.0 : 1.4 }
}

public enum AskLevel: String, Codable, CaseIterable, Sendable {
    case often, sometimes, rarely
    public var threshold: Double {
        switch self {
        case .often: return 0.85
        case .sometimes: return 0.7
        case .rarely: return 0.55
        }
    }
}

public struct KeyboardSettings: Codable, Equatable, Sendable {
    public var adaptationOn = true
    public var keySize = KeySize.standard
    public var askLevel = AskLevel.sometimes
    public var useLetterPatterns = true
    public var showTouches = false
    /// Keep updating the touch model from everyday typing (picks, corrections, confident taps).
    public var keepAdapting = true
    /// When space is pressed, replace a misspelled word if a common word fits the taps much better.
    public var fixWords = true
    public var holdToDelete = true
    /// Start each sentence with a capital letter (still only where the app's text field asks for it).
    public var capitalizeSentences = true
    public var comparisonRuns = 0
    public init() {}

    /// Missing fields (e.g. settings saved by an older build) fall back to defaults instead of failing.
    public init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyboardSettings()
        adaptationOn = try c.decodeIfPresent(Bool.self, forKey: .adaptationOn) ?? d.adaptationOn
        keySize = try c.decodeIfPresent(KeySize.self, forKey: .keySize) ?? d.keySize
        askLevel = try c.decodeIfPresent(AskLevel.self, forKey: .askLevel) ?? d.askLevel
        useLetterPatterns = try c.decodeIfPresent(Bool.self, forKey: .useLetterPatterns) ?? d.useLetterPatterns
        showTouches = try c.decodeIfPresent(Bool.self, forKey: .showTouches) ?? d.showTouches
        keepAdapting = try c.decodeIfPresent(Bool.self, forKey: .keepAdapting) ?? d.keepAdapting
        fixWords = try c.decodeIfPresent(Bool.self, forKey: .fixWords) ?? d.fixWords
        holdToDelete = try c.decodeIfPresent(Bool.self, forKey: .holdToDelete) ?? d.holdToDelete
        capitalizeSentences = try c.decodeIfPresent(Bool.self, forKey: .capitalizeSentences) ?? d.capitalizeSentences
        comparisonRuns = try c.decodeIfPresent(Int.self, forKey: .comparisonRuns) ?? d.comparisonRuns
    }
}

/// Calibration taps (known targets only — never real typing) and the model learned from them.
public struct CalibrationProfile: Codable, Equatable, Sendable {
    public var version = 1
    public var createdAt: Date
    public var samples: [CalibrationSample]
    public var model: TouchModel
    /// What was learned while typing (per-key running totals only). nil = nothing yet.
    public var adaptive: AdaptiveState?

    public init(createdAt: Date, samples: [CalibrationSample], model: TouchModel) {
        self.createdAt = createdAt
        self.samples = samples
        self.model = model
    }

    /// Learn from one labeled touch and update the model. Returns true if a change in the person's
    /// touch was just detected (learning speeds up for a while).
    @discardableResult
    public mutating func learn(_ touch: LabeledTouch, layout: KeyboardLayout) -> Bool {
        var state = adaptive ?? OnlineLearner.seed(samples: samples, model: model)
        let startedFast = OnlineLearner.update(&state, with: touch, layout: layout)
        adaptive = state
        model = OnlineLearner.model(from: state, base: model)
        return startedFast
    }

    /// Forget everything learned while typing and go back to the calibration model.
    public mutating func resetAdaptation() {
        adaptive = nil
        model = calibrationModel
    }

    /// The model from the calibration taps alone, before anything learned while typing.
    public var calibrationModel: TouchModel {
        let e = ModelFitter.evidence(from: samples, kind: model.pointKind, keyWidth: model.keyWidth)
        return ModelFitter.refit(model, means: e, spreads: e)
    }
}

/// Everything we store, as three small JSON files in the keyboard's own private folder.
/// There is deliberately no type here that can hold typed text.
public final class ProfileStore {
    public let directory: URL
    private var profileURL: URL { directory.appendingPathComponent("calibration.json") }
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    private var resultsURL: URL { directory.appendingPathComponent("comparison-results.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app (or keyboard) sandbox's Application Support folder.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TouchProfile", isDirectory: true)
    }

    public func loadProfile() -> CalibrationProfile? { read(profileURL) }
    public func save(_ profile: CalibrationProfile) throws { try write(profile, to: profileURL) }

    public func loadSettings() -> KeyboardSettings { read(settingsURL) ?? KeyboardSettings() }
    public func save(_ settings: KeyboardSettings) throws { try write(settings, to: settingsURL) }

    public func loadResults() -> [TrialResult] { read(resultsURL) ?? [] }
    public func save(_ results: [TrialResult]) throws { try write(results, to: resultsURL) }

    /// Removes calibration, settings and saved comparison results.
    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
