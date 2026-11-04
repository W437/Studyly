import Foundation
import FoundationModels
import NaturalLanguage

// What this iPhone's own model (tier T1) can do right now, the gate on what it may read (English, within its
// window), and the build switches. `SystemOnDeviceProbe` is the only code that reads `SystemLanguageModel`'s
// availability; the router and Settings read the value it returns, and tests write one.

/// The build's switches for the model tiers. Turning one off takes that tier out without touching other code.
enum AIBuild {
    /// This iPhone's model (Foundation Models). Off since 2026-11-04 (docs/BUILD.md, "Apple's answer tier is off"): Cap answers
    /// from Cloud AI, or from the offline rules when there is no network or no allowance. The tutor, grading, question writing,
    /// lecture notes and cards that had an on-device model step take the offline path instead.
    static let onDeviceModelEnabled = false
    /// Private Cloud Compute (iOS 27). It needs an entitlement Apple grants on request; no key is guessed and it
    /// stays off. Switching it on also needs a consent line and an `AIConsent.currentVersion` bump.
    static let privateCloudEnabled = false
}

enum OnDeviceUnavailableReason: String, Equatable, Sendable, CaseIterable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    /// The model is still downloading.
    case modelNotReady
    /// Low Power Mode: the model isn't run, to save battery.
    case lowPower
    /// The phone is hot.
    case thermal
    /// The simulator has no Apple Intelligence model (and may claim otherwise), so it is never asked.
    case simulator
    /// `AIBuild.onDeviceModelEnabled` is false.
    case disabledByBuild
    /// Under unit tests nothing is asked of the device.
    case notChecked
    case unknown

    /// It will pass by itself.
    var isTransient: Bool { self == .modelNotReady || self == .lowPower || self == .thermal }

    /// For Settings ▸ AI and privacy.
    var message: String {
        switch self {
        case .deviceNotEligible: "This iPhone doesn't have Apple Intelligence, so Capling uses its offline rules."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to use this iPhone's own AI."
        case .modelNotReady: "Apple Intelligence is still getting ready. Capling uses its offline rules until then."
        case .lowPower: "Paused in Low Power Mode."
        case .thermal: "Paused while your iPhone cools down."
        case .simulator: "The simulator has no Apple Intelligence model."
        case .disabledByBuild: "Off in this version."
        case .notChecked, .unknown: "Apple Intelligence isn't available right now."
        }
    }
}

enum OnDeviceAvailability: Equatable, Sendable {
    case available
    case unavailable(OnDeviceUnavailableReason)

    var isAvailable: Bool { self == .available }
}

struct OnDeviceCapability: Equatable, Sendable {
    var availability: OnDeviceAvailability
    /// Tokens the model reads and writes in one session: 4,096 on iOS 26; the system reports the size after.
    var contextSize: Int
    /// Private Cloud Compute could serve a request now. Always false while `AIBuild.privateCloudEnabled` is off.
    var privateCloudAvailable: Bool

    static func unavailable(_ reason: OnDeviceUnavailableReason) -> OnDeviceCapability {
        OnDeviceCapability(availability: .unavailable(reason), contextSize: OnDeviceBudget.defaultContextSize,
                           privateCloudAvailable: false)
    }

    static let ready = OnDeviceCapability(availability: .available, contextSize: OnDeviceBudget.defaultContextSize,
                                          privateCloudAvailable: false)
}

/// Reads what the device can do.
@MainActor
protocol OnDeviceProbe {
    func capability() -> OnDeviceCapability
    /// The model's `supportsLocale`, asked about the content's language.
    func supportsLocale(_ locale: Locale) -> Bool
}

/// The real probe. Under unit tests (`allowed` false) it reads nothing and says `.notChecked`.
@MainActor
struct SystemOnDeviceProbe: OnDeviceProbe {
    var allowed: Bool
    /// The build switch as this probe reads it. Only tests and the phone lab (`OfflineBench`, DEBUG) pass `true` to look at
    /// the model while the build keeps it off.
    var buildEnabled: Bool

    nonisolated init(allowed: Bool, buildEnabled: Bool = AIBuild.onDeviceModelEnabled) {
        self.allowed = allowed
        self.buildEnabled = buildEnabled
    }

    func capability() -> OnDeviceCapability {
        guard buildEnabled else { return .unavailable(.disabledByBuild) }
        guard allowed else { return .unavailable(.notChecked) }
        #if targetEnvironment(simulator)
        // A simulator whose Mac lacks the model assets still reports "available" (measured in Dozen), and the
        // simulator has no Apple Intelligence model to answer. `CRAMLESS_SIM_MODEL=1` opts in on a Mac that has one.
        guard ProcessInfo.processInfo.environment["CRAMLESS_SIM_MODEL"] == "1" else { return .unavailable(.simulator) }
        #endif
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return .unavailable(.lowPower) }
        if info.thermalState == .serious || info.thermalState == .critical { return .unavailable(.thermal) }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return OnDeviceCapability(availability: .available, contextSize: OnDeviceBudget(contextSize: model.contextSize).contextSize,
                                      privateCloudAvailable: privateCloudAvailable())
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady: return .unavailable(.modelNotReady)
            @unknown default: return .unavailable(.unknown)
            }
        }
    }

    func supportsLocale(_ locale: Locale) -> Bool {
        guard buildEnabled, allowed else { return false }
        return SystemLanguageModel.default.supportsLocale(locale)
    }

    private func privateCloudAvailable() -> Bool {
        #if HAS_IOS27_SDK
        if AIBuild.privateCloudEnabled, #available(iOS 27.0, *) { return PrivateCloudModel.isAvailable() }
        #endif
        return false
    }
}

#if DEBUG
/// A probe that answers what it is given: the tests' and the harness's stand-in for a device.
@MainActor
struct FixedOnDeviceProbe: OnDeviceProbe {
    var value: OnDeviceCapability
    /// The language codes `supportsLocale` says yes to.
    var supportedLanguages: Set<String> = ["en"]

    nonisolated init(_ value: OnDeviceCapability, supportedLanguages: Set<String> = ["en"]) {
        self.value = value
        self.supportedLanguages = supportedLanguages
    }

    func capability() -> OnDeviceCapability { value }
    func supportsLocale(_ locale: Locale) -> Bool {
        supportedLanguages.contains(locale.language.languageCode?.identifier ?? "")
    }
}
#endif

// MARK: - The language gate

/// May this text go to the on-device model? It reads English only here, and it doesn't refuse another language:
/// given one it answers anyway, in nonsense (measured in Dozen with Hebrew), so this gate is the only protection.
/// Three steps, each able to stop the text: too few letters; a script other than Latin for more than a tenth of
/// the letters (a few Greek letters in a physics page pass); for text long enough to judge, the recogniser's
/// dominant language, when it is sure of it (`minimumConfidence`), must be English; then the model's `supportsLocale` for English.
///
/// The recogniser runs **without language hints**. Measured (macOS 27, Oct 2026) on full sentences: with no hints
/// it read Spanish 0.99, French, German and English 1.00 correctly; with an English hint of 1.0, or even 0.6, it read
/// all four as English at 1.00, which would wave every Latin-script language through. Short text (under 24 letters)
/// is too little to judge without hints (Dozen measured "call Sam" read as Polish), so it is let through.
enum OnDeviceLanguageGate {
    enum Verdict: Equatable, Sendable {
        case supported
        case tooShort
        case foreignScript
        case notEnglish(String)
        case unsupportedByModel

        var isSupported: Bool { self == .supported }
    }

    static func verdict(for text: String, supportsLocale: (Locale) -> Bool) -> Verdict {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard letters.count >= 2 else { return .tooShort }
        let foreign = letters.filter { !isLatin($0) }.count
        if Double(foreign) / Double(letters.count) > 0.1 { return .foreignScript }
        if letters.count >= 24, let dominant = dominantLanguage(text), dominant != .english {
            return .notEnglish(dominant.rawValue)
        }
        return supportsLocale(Locale(identifier: "en")) ? .supported : .unsupportedByModel
    }

    /// How sure the recogniser must be of a language for it to count: its probability for it, at least this. A real paragraph reads
    /// 0.95 or more. An English chemistry worksheet of equations read Polish at 0.63, so a lower bar made the app write the
    /// questions in Polish, and would have kept the page from this iPhone's model as "not English".
    static let minimumConfidence = 0.8

    /// The recogniser's answer with no hints, when it is sure (`minimumConfidence`); nil otherwise.
    static func dominantLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        return confidence >= minimumConfidence ? dominant : nil
    }

    private static func isLatin(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A, 0xAA, 0xBA, 0xC0...0x24F, 0x250...0x2AF, 0x1E00...0x1EFF, 0x2C60...0x2C7F,
             0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return true
        default:
            return false
        }
    }
}

// MARK: - The budget

/// How much a prompt may hold, and how to cut a page so every piece fits. The model reads `contextSize` tokens in
/// all: instructions, schema, prompt and answer together.
struct OnDeviceBudget: Equatable, Sendable {
    static let defaultContextSize = 4096
    /// Of what is left after the answer's reserve, this much is used: the estimate is not a count.
    static let usableFraction = 0.9

    let contextSize: Int

    init(contextSize: Int = OnDeviceBudget.defaultContextSize) {
        // A size that can't be right (a simulator says 0) reads as the 4,096 every iOS 26 model has.
        self.contextSize = contextSize >= 1024 ? contextSize : Self.defaultContextSize
    }

    /// Deliberately high: UTF-8 bytes over three (English runs about four characters a token).
    static func estimateTokens(_ text: String) -> Int {
        let bytes = text.utf8.count
        return bytes == 0 ? 0 : (bytes + 2) / 3
    }

    /// Tokens left for the prompt after the instructions, the schema and the answer's reserve.
    func promptTokens(instructions: String, schemaTokens: Int, responseTokens: Int) -> Int {
        let usable = Int(Double(contextSize - responseTokens) * Self.usableFraction)
        return max(0, usable - Self.estimateTokens(instructions) - schemaTokens)
    }

    func fits(_ prompt: String, instructions: String, schemaTokens: Int, responseTokens: Int) -> Bool {
        Self.estimateTokens(prompt) <= promptTokens(instructions: instructions, schemaTokens: schemaTokens, responseTokens: responseTokens)
    }

    /// Cuts `items` into consecutive groups whose rendered text stays within `limit` tokens, never splitting an
    /// item. An item larger than the limit alone is dropped (it can't be read whole).
    func chunks<T>(_ items: [T], limit: Int, render: (T) -> String) -> [[T]] {
        var out: [[T]] = []
        var current: [T] = []
        var used = 0
        for item in items {
            let cost = Self.estimateTokens(render(item)) + 1
            if cost > limit { continue }
            if used + cost > limit, !current.isEmpty {
                out.append(current)
                current = []
                used = 0
            }
            current.append(item)
            used += cost
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
