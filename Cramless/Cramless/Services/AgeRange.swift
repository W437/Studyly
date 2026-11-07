import DeclaredAgeRange
import OSLog
import SwiftUI
import UIKit

/// The person's age band from Apple's Declared Age Range (iOS 26), written to `settings.ageBand`, which keeps
/// under-18 accounts on the teen-safe tutor (`settings.isMinor`): hints first, no web research, every "Let Cap do it" switch on
/// ask-first; under 13, no Cloud AI at all.
///
/// Asks with age gates 13 and 18; the system shows its own sheet the first time, so it is asked at a moment that makes sense:
/// once in onboarding, after the four questions about the person (`OnboardingFlow`), and once for someone who finished onboarding
/// before this existed (`RootView`, a moment after launch). `checkIfNeeded` asks only while the band is unknown and never twice
/// (`AgeCheck`): an answer, a "Don't share", or a system with no answer for this account is final; only a passing failure (no
/// network) is tried again at a later launch, three times at most. When the range isn't shared or the service has no answer (a build
/// without the `com.apple.developer.declared-age-range` entitlement, an account it doesn't apply to), it falls back to the level the
/// person gave (high school: teen; college or grad school: adult), and with no level that says so, to the under-18 rules (`notShared`):
/// never an adult by default, and never overwriting a band the person already shared. Under 13 is only ever what iOS says. It never throws
/// and never blocks anything. Not asked in the harness or in tests, and not on the simulator, which has no answer to give (the band stays
/// `unknown` there). Settings ▸ AI and privacy can ask again for someone on `notShared`, who may be an adult.
@MainActor
enum AgeRange {
    static let gates = (first: 13, second: 18)

    /// Asks once, when it should (`AgeCheck.shouldAsk`), from a view: pass `@Environment(\.requestAgeRange)`.
    static func checkIfNeeded(app: AppModel, using request: DeclaredAgeRangeAction) async {
        guard app.sideEffectsEnabled, !app.config.isHarness else { return }
        let record = AgeCheck.record(in: app.defaults)
        guard AgeCheck.shouldAsk(band: app.settings.ageBand, record: record) else { return }
        #if targetEnvironment(simulator)
        log.notice("age range not asked: the simulator has no answer")
        #else
        await refresh(app: app, using: request, previous: record)
        #endif
    }

    /// From a view: pass `@Environment(\.requestAgeRange)`. Asks now, whatever was asked before (`checkIfNeeded` decides when).
    static func refresh(app: AppModel, using request: DeclaredAgeRangeAction, previous: AgeCheck.Record? = nil) async {
        let declared: AppSettings.AgeBand?
        let outcome: AgeCheck.Outcome
        do {
            let response = try await request(ageGates: gates.first, gates.second)
            declared = band(from: response)
            outcome = AgeCheck.outcome(of: response)
        } catch {
            log.notice("age range unavailable: \(String(describing: error), privacy: .public)")
            declared = nil
            outcome = AgeCheck.outcome(of: error)
        }
        apply(declared, to: app)
        AgeCheck.store(AgeCheck.Record(outcome: outcome, askedAt: app.now, attempts: (previous?.attempts ?? 0) + 1),
                       in: app.defaults)
    }

    /// From anywhere: presents over the frontmost screen.
    static func refresh(app: AppModel) async {
        let declared: AppSettings.AgeBand?
        if let presenter = frontmostViewController() {
            do {
                let response = try await AgeRangeService.shared.requestAgeRange(ageGates: gates.first, gates.second,
                                                                                in: presenter)
                declared = band(from: response)
            } catch {
                log.notice("age range unavailable: \(String(describing: error), privacy: .public)")
                declared = nil
            }
        } else {
            declared = nil
        }
        apply(declared, to: app)
    }

    private static func apply(_ declared: AppSettings.AgeBand?, to app: AppModel) {
        let band = resolved(declared: declared, current: app.settings.ageBand, level: app.settings.level)
        if band != app.settings.ageBand { app.settings.ageBand = band }
    }

    private static func band(from response: AgeRangeService.Response) -> AppSettings.AgeBand? {
        switch response {
        case .sharing(let range): band(lowerBound: range.lowerBound, upperBound: range.upperBound)
        case .declinedSharing: nil
        @unknown default: nil
        }
    }

    // MARK: Pure rules (tested)

    /// A shared range as a band. With gates 13 and 18 the system answers "under 13", "13 to 17" or "18 and over".
    nonisolated static func band(lowerBound: Int?, upperBound: Int?) -> AppSettings.AgeBand {
        if let upper = upperBound, upper < 13 { return .under13 }
        if let lower = lowerBound, lower >= 18 { return .adult }
        // 13 to 17, or a minor whose exact band wasn't given: teen-safe either way.
        if let upper = upperBound, upper < 18 { return .teen }
        return .unknown
    }

    /// The level the person gave, when no range was shared. "Something else", or no level at all, says nothing about an adult, so the under-18 rules hold.
    nonisolated static func fallback(level: AppSettings.Level?) -> AppSettings.AgeBand {
        switch level {
        case .highSchool: .teen
        case .college, .grad: .adult
        case .other, nil: .notShared
        }
    }

    /// A shared range wins; otherwise keep a band already known, else fall back to the level.
    nonisolated static func resolved(declared: AppSettings.AgeBand?, current: AppSettings.AgeBand,
                                     level: AppSettings.Level?) -> AppSettings.AgeBand {
        if let declared, declared != .unknown { return declared }
        if current != .unknown { return current }
        return fallback(level: level)
    }

    private static func frontmostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    static let log = Logger(subsystem: "com.loopware.Capling", category: "age-range")
}

/// When the age check asks, and what each answer means for asking again: pure, apart from the record it keeps in UserDefaults
/// (`capling.ageRange.v1`, on this iPhone).
enum AgeCheck {
    enum Outcome: String, Codable, Sendable {
        /// A range was shared: the band is set.
        case shared
        /// The person (or a parent) chose not to share: the band stays as it was. Never asked again.
        case declined
        /// The system has no answer here (not available, an account or a request it won't take). Never asked again.
        case unavailable
        /// A passing failure (no network): tried again at a later launch.
        case failed
    }

    struct Record: Codable, Equatable, Sendable {
        var outcome: Outcome
        var askedAt: Date
        var attempts: Int
    }

    static let defaultsKey = "capling.ageRange.v1"
    /// A passing failure is tried this many times in all, one launch apart, then left.
    static let maxAttempts = 3

    /// Ask while the band is unknown, never twice after an answer or a decline, and again after a passing failure until `maxAttempts`, whatever
    /// the level gave the band meanwhile: a range shared later wins over that fallback (`AgeRange.resolved`).
    static func shouldAsk(band: AppSettings.AgeBand, record: Record?) -> Bool {
        guard let record else { return band == .unknown }
        return record.outcome == .failed && record.attempts < maxAttempts
    }

    static func outcome(of response: AgeRangeService.Response) -> Outcome {
        switch response {
        case .sharing: .shared
        case .declinedSharing: .declined
        @unknown default: .unavailable
        }
    }

    static func outcome(of error: Error) -> Outcome {
        guard let error = error as? AgeRangeService.Error else { return .failed }
        switch error {
        case .notAvailable, .invalidRequest: return .unavailable
        default:
            #if HAS_IOS27_SDK
            if #available(iOS 27.0, *) {
                switch error {
                case .declinedOnboarding: return .declined
                case .invalidAccount: return .unavailable
                case .network: return .failed
                default: break
                }
            }
            #endif
            return .failed
        }
    }

    static func record(in defaults: UserDefaults) -> Record? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder.cramless.decode(Record.self, from: data)
    }

    static func store(_ record: Record, in defaults: UserDefaults) {
        if let data = try? JSONEncoder.cramless.encode(record) { defaults.set(data, forKey: defaultsKey) }
    }
}

