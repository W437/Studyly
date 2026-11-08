import Foundation

/// Every onboarding step, in order: the welcome → a page made into questions (the first set) → two of them answered (the first
/// session) → the exam's date → the plan → the paywall → done. The student's own questions come at the third tap.
enum OnboardingStep: Hashable, Sendable {
    case welcome
    case firstSet
    case firstSession
    /// "When's your Bio 101 exam?", asked once there is a course to name. Skipped after the sample page (no exam is made from a
    /// sample) and when the course already has an exam coming.
    case examDate
    case plan
    case paywall
    case done
}

/// The screens on the navigation stack (the welcome is its root).
enum OnboardingScreen: Hashable, Sendable {
    case firstSet, firstSession, examDate, plan, paywall
}

/// The onboarding step machine: a value with no side effects, so every transition is unit-tested.
/// `OnboardingCoordinator` owns one and turns its changes into navigation and settings.
struct OnboardingMachine: Equatable, Sendable {
    /// The whole flow, in order.
    static let sequence: [OnboardingStep] = [.welcome, .firstSet, .firstSession, .examDate, .plan, .paywall, .done]

    private(set) var step: OnboardingStep
    /// Whether the date step is shown; decided when the first set is made (`firstSetMade(asksExamDate:)`).
    private(set) var asksExamDate = true

    init(step: OnboardingStep = .welcome) {
        self.step = step
    }

    /// The harness numbering (`CRAMLESS_ROUTE=onboarding:<n>`): welcome 0, first set 1, first session 2, exam date 3, plan 4,
    /// paywall 5. Out-of-range values clamp.
    init(index: Int) {
        let last = Self.sequence.count - 2 // never start on `.done`
        self.init(step: Self.sequence[max(0, min(last, index))])
    }

    var index: Int { Self.sequence.firstIndex(of: step) ?? 0 }

    var isDone: Bool { step == .done }

    /// One step forward (past the date step when it isn't asked).
    mutating func advance() {
        guard var i = Self.sequence.firstIndex(of: step), i + 1 < Self.sequence.count else { return }
        i += 1
        if Self.sequence[i] == .examDate && !asksExamDate { i += 1 }
        step = Self.sequence[i]
    }

    /// The first set is in: on to the first session. `asksExamDate` is false after the sample page, or when the course already
    /// has an exam coming.
    mutating func firstSetMade(asksExamDate: Bool) {
        guard step == .firstSet else { return }
        self.asksExamDate = asksExamDate
        advance()
    }

    /// Whether the screen-level back (the back button, the edge swipe) is allowed: only from the first set to the welcome. The
    /// session, the date, the plan and the paywall happen once.
    var canGoBack: Bool { step == .firstSet }

    /// One screen back: the first set returns to the welcome.
    mutating func back() {
        guard canGoBack else { return }
        step = .welcome
    }

    /// The navigation stack for this step.
    var screens: [OnboardingScreen] {
        let all: [(OnboardingStep, OnboardingScreen)] = [(.firstSet, .firstSet), (.firstSession, .firstSession),
                                                         (.examDate, .examDate), (.plan, .plan), (.paywall, .paywall)]
        let through = min(index, Self.sequence.count - 2)
        return all.filter { pair in
            guard let at = Self.sequence.firstIndex(of: pair.0), at <= through else { return false }
            return pair.0 != .examDate || asksExamDate || step == .examDate
        }.map(\.1)
    }

    /// Follows the navigation stack when the person pops it (the edge swipe). Only ever moves backwards, and only where `canGoBack`
    /// allows.
    mutating func popTo(_ screens: [OnboardingScreen]) {
        guard screens.count < self.screens.count, canGoBack, screens.isEmpty else { return }
        step = .welcome
    }
}
