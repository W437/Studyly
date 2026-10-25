import Foundation

/// Every onboarding step, in order: welcome → five live demos → four questions → the first set, the first
/// session, readiness and the plan (built by the Study and Capture UI lanes) → the paywall → done.
enum OnboardingStep: Hashable, Sendable {
    case welcome
    /// The five live-demo pages, 0…4.
    case intro(Int)
    /// Goal, exam date, minutes a day, where notes live: 0…3.
    case quiz(Int)
    case firstSet
    case firstSession
    case readiness
    case plan
    case paywall
    case done
}

/// The screens on the navigation stack. The five intro pages share one pager screen.
enum OnboardingScreen: Hashable, Sendable {
    case intro
    case quiz(Int)
    case firstSet, firstSession, readiness, plan, paywall
}

/// The onboarding step machine: a value with no side effects, so every transition is unit-tested.
/// `OnboardingCoordinator` owns one and turns its changes into navigation and settings.
struct OnboardingMachine: Equatable, Sendable {
    static let introPages = 6
    static let quizQuestions = 4

    /// The whole flow, in order.
    static let sequence: [OnboardingStep] =
        [.welcome] + (0..<introPages).map(OnboardingStep.intro) + (0..<quizQuestions).map(OnboardingStep.quiz)
        + [.firstSet, .firstSession, .readiness, .plan, .paywall, .done]

    private(set) var step: OnboardingStep
    /// The intro page last shown, so leaving the quiz backwards lands where the person left the pager.
    private(set) var introPage: Int

    init(step: OnboardingStep = .welcome) {
        self.step = step
        if case .intro(let page) = step { introPage = page } else { introPage = 0 }
    }

    /// The harness numbering (`CRAMLESS_ROUTE=onboarding:<n>`): welcome 0, intro pages 1–6, quiz 7–10, first set
    /// 11, first session 12, readiness 13, plan 14, paywall 15. Out-of-range values clamp.
    init(index: Int) {
        let last = Self.sequence.count - 2 // never start on `.done`
        self.init(step: Self.sequence[max(0, min(last, index))])
    }

    var index: Int { Self.sequence.firstIndex(of: step) ?? 0 }

    var isDone: Bool { step == .done }

    /// One step forward. From any intro page that is the next page; after the last, the first question.
    mutating func advance() {
        guard let i = Self.sequence.firstIndex(of: step), i + 1 < Self.sequence.count else { return }
        move(to: Self.sequence[i + 1])
    }

    /// Skip on the intro pages: straight to the first question.
    mutating func skipIntro() {
        guard case .intro = step else { return }
        move(to: .quiz(0))
    }

    /// The pager's own swipes between intro pages.
    mutating func showIntroPage(_ page: Int) {
        guard case .intro = step else { return }
        move(to: .intro(max(0, min(Self.introPages - 1, page))))
    }

    /// Whether the screen-level back (the back button, the edge swipe) is allowed. Nothing goes back past the
    /// first set: the session, readiness, plan and paywall happen once.
    var canGoBack: Bool {
        switch step {
        case .intro, .quiz, .firstSet: true
        case .welcome, .firstSession, .readiness, .plan, .paywall, .done: false
        }
    }

    /// One screen back: the pager returns to the welcome, the first question to the pager.
    mutating func back() {
        guard canGoBack else { return }
        switch step {
        case .intro: move(to: .welcome)
        case .quiz(0): move(to: .intro(introPage))
        case .quiz(let q): move(to: .quiz(q - 1))
        case .firstSet: move(to: .quiz(Self.quizQuestions - 1))
        default: break
        }
    }

    /// The navigation stack for this step.
    var screens: [OnboardingScreen] {
        let quizzes = (0..<Self.quizQuestions).map(OnboardingScreen.quiz)
        let setup: [OnboardingScreen] = [.intro] + quizzes
        switch step {
        case .welcome: return []
        case .intro: return [.intro]
        case .quiz(let q): return [.intro] + (0...q).map(OnboardingScreen.quiz)
        case .firstSet: return setup + [.firstSet]
        case .firstSession: return setup + [.firstSet, .firstSession]
        case .readiness: return setup + [.firstSet, .firstSession, .readiness]
        case .plan: return setup + [.firstSet, .firstSession, .readiness, .plan]
        case .paywall, .done: return setup + [.firstSet, .firstSession, .readiness, .plan, .paywall]
        }
    }

    /// Follows the navigation stack when the person pops it (the edge swipe). Only ever moves backwards, and
    /// only where `canGoBack` allows.
    mutating func popTo(_ screens: [OnboardingScreen]) {
        guard screens.count < self.screens.count, canGoBack else { return }
        let target: OnboardingStep = switch screens.last {
        case nil: .welcome
        case .intro: .intro(introPage)
        case .quiz(let q): .quiz(q)
        case .firstSet: .firstSet
        case .firstSession: .firstSession
        case .readiness: .readiness
        case .plan: .plan
        case .paywall: .paywall
        }
        guard let to = Self.sequence.firstIndex(of: target), to < index else { return }
        move(to: target)
    }

    /// The top progress bar on the setup steps (the four questions, the first set and the first session),
    /// 0…1; nil on the other steps.
    var setupProgress: Double? {
        let total = Double(Self.quizQuestions + 2)
        switch step {
        case .quiz(let q): return Double(q + 1) / total
        case .firstSet: return Double(Self.quizQuestions + 1) / total
        case .firstSession: return 1
        default: return nil
        }
    }

    private mutating func move(to next: OnboardingStep) {
        step = next
        if case .intro(let page) = next { introPage = page }
    }
}
