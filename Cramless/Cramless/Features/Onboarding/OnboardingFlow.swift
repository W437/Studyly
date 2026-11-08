import DeclaredAgeRange
import SwiftUI

/// Drives onboarding: owns the step machine, maps it onto a navigation stack, and performs the side effects (whether the date step
/// is asked, finishing, the free-plan toast). Every step view reads it from the environment:
///
///     @Environment(OnboardingCoordinator.self) private var onboarding
///     Button("Continue") { onboarding.advance() }
///
/// Each step's view (`OnboardingFlow.destination(_:)`) calls `advance()` when the person is done.
@MainActor
@Observable
final class OnboardingCoordinator {
    private(set) var machine: OnboardingMachine
    /// The course the first set went into (the steps after it study from it).
    var firstCourseID: UUID?
    /// The first set came from the sample page: it files under "Sample" and no exam is made from it.
    var firstSetIsSample = false
    /// "I already have an account" on the welcome screen: sign in and bring the person's material back.
    var showsWelcomeBack = false

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var declinedPaywall = false
    @ObservationIgnored private var finished = false

    init(start: OnboardingMachine) {
        machine = start
    }

    var step: OnboardingStep { machine.step }

    /// The navigation stack. Pushes follow the machine; a pop (the back button, the edge swipe) moves it back.
    var path: [OnboardingScreen] {
        get { machine.screens }
        set { machine.popTo(newValue) }
    }

    func advance() {
        machine.advance()
        if machine.isDone { finish() }
    }

    func back() { machine.back() }

    /// The first set is in. The date is asked only for a real page whose course has no exam coming yet: a sample makes no exam.
    func firstSetMade(_ result: OnboardingFirstSet) {
        firstCourseID = result.courseID
        firstSetIsSample = result.isSample
        let hasExam = app.map { app in
            app.onboardingCourse(result.courseID)?.liveExams.contains { $0.date > app.now } ?? false
        } ?? false
        machine.firstSetMade(asksExamDate: !result.isSample && !hasExam)
    }

    /// The onboarding paywall closed: bought or not, onboarding is done and Today is next.
    func paywallFinished(_ outcome: PaywallOutcome) {
        if case .declined = outcome { declinedPaywall = true }
        advance()
    }

    /// The last step: onboarding never shows again; the tabs take over.
    func finish() {
        guard !finished, let app else { return }
        finished = true
        withAnimation(CLMotion.fade) { app.settings.onboardingCompleted = true }
        if case .onboarding = app.router.cover { app.router.dismissCover() }
        if declinedPaywall && !app.purchases.isPro && app.settings.canBuyPro {
            Task { @MainActor in
                try? await nap(700)
                app.router.toast("You're on the free plan. Upgrade anytime.", systemImage: "sparkles", tone: .neutral)
            }
        }
    }
}

/// What the first-set step hands on: the course the set went to, and whether it was the sample page.
struct OnboardingFirstSet: Equatable, Sendable {
    var courseID: UUID?
    var isSample: Bool
}

/// Onboarding: the welcome, the first set (a page made into questions), two of its questions, the exam's date, the plan, then the
/// paywall. Shown by RootView until `settings.onboardingCompleted`, and as a cover by `CRAMLESS_ROUTE=onboarding:<n>` (welcome 0,
/// first set 1, first session 2, exam date 3, plan 4, paywall 5), which opens step n without wiping data.
struct OnboardingFlow: View {
    let startPage: Int?

    @Environment(AppModel.self) private var app
    @Environment(\.requestAgeRange) private var requestAgeRange
    @State private var coordinator: OnboardingCoordinator

    init(startPage: Int?) {
        self.startPage = startPage
        _coordinator = State(initialValue: OnboardingCoordinator(start: OnboardingMachine(index: startPage ?? 0)))
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.path) {
            WelcomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: OnboardingScreen.self) { destination($0) }
        }
        .environment(coordinator)
        // The welcome and the paywall are night-coloured to the top edge, where dark status bar text would
        // vanish (RootView's colour-scheme preference outranks one set in here), so the status bar steps aside.
        .statusBarHidden(coordinator.step == .welcome || coordinator.step == .paywall)
        .sheet(isPresented: $coordinator.showsWelcomeBack) {
            WelcomeBackSheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear { coordinator.app = app }
        // The age range is asked once, as the first set opens, before anything that depends on it (Cloud AI's consent, Cap's
        // tutor). The system's own sheet; nothing waits for it (`AgeRange.checkIfNeeded`).
        .onChange(of: coordinator.step) { _, step in
            guard step == .firstSet else { return }
            Task {
                try? await nap(700)
                await AgeRange.checkIfNeeded(app: app, using: requestAgeRange)
            }
        }
    }

    @ViewBuilder
    private func destination(_ screen: OnboardingScreen) -> some View {
        switch screen {
        case .firstSet:
            OnboardingFirstSetStep { coordinator.firstSetMade($0) }
        case .firstSession:
            OnboardingFirstSessionStep(courseID: coordinator.firstCourseID) { coordinator.advance() }
        case .examDate:
            OnboardingExamDateStep(courseID: coordinator.firstCourseID) { coordinator.advance() }
        case .plan:
            OnboardingPlanStep(courseID: coordinator.firstCourseID, isSample: coordinator.firstSetIsSample) { coordinator.advance() }
        case .paywall:
            // The plan was the screen just before: the paywall says what Pro adds, not the plan again.
            PaywallView(context: .onboarding(planLine: ""))
                .environment(\.paywallFinish, PaywallFinishAction { coordinator.paywallFinished($0) })
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden()
        }
    }
}

/// "I already have an account": sign in, bring the person's material down, and skip the rest of onboarding.
private struct WelcomeBackSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var syncing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CapFace(size: 44)
                    Spacer()
                    CLIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
                Text("Welcome back").clFont(.brandTitle(28)).foregroundStyle(CLColor.ink)
                Text("Sign in and your courses, questions and streak come back to this iPhone.")
                    .clFont(.callout).foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                SignInPanel()
                if syncing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Bringing your material back…").clFont(.subheadline).foregroundStyle(CLColor.ink2)
                    }
                }
            }
            .padding(CLSpace.gutter)
        }
        .clScreenBackground()
        .onChange(of: app.account.isSignedIn) { _, signedIn in
            guard signedIn, !syncing else { return }
            syncing = true
            Task {
                await app.syncNow()
                app.settings.onboardingCompleted = true
                dismiss()
            }
        }
    }
}
