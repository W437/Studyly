import DeclaredAgeRange
import OSLog
import SwiftUI
import UIKit

/// The person's age band from Apple's Declared Age Range (iOS 26), written to `settings.ageBand`, which keeps
/// under-18 accounts on the teen-safe tutor (`settings.isMinor`).
///
/// Asks with age gates 13 and 18; the system shows its own sheet the first time, so call it at a moment that
/// makes sense (onboarding's profile step). When the range isn't shared or the service isn't available (the
/// simulator, a build without the `com.apple.developer.declared-age-range` entitlement, an account it doesn't
/// apply to), it falls back to the level the person gave (high school → teen), never overwriting a band the person
/// already shared. It never throws and never blocks anything.
@MainActor
enum AgeRange {
    static let gates = (first: 13, second: 18)

    /// From a view: pass `@Environment(\.requestAgeRange)`.
    static func refresh(app: AppModel, using request: DeclaredAgeRangeAction) async {
        let declared: AppSettings.AgeBand?
        do {
            declared = band(from: try await request(ageGates: gates.first, gates.second))
        } catch {
            log.notice("age range unavailable: \(String(describing: error), privacy: .public)")
            declared = nil
        }
        apply(declared, to: app)
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

    /// The level the person gave, when no range was shared.
    nonisolated static func fallback(level: AppSettings.Level?) -> AppSettings.AgeBand {
        switch level {
        case .highSchool: .teen
        case .college, .grad: .adult
        case .other, nil: .unknown
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
