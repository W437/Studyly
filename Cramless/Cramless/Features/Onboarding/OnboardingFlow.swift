import SwiftUI

/// Drives onboarding: owns the step machine, maps it onto a navigation stack, and performs the side effects
/// (finishing, the Exam Pass offer, the free-plan toast). Every step view reads it from the environment:
///
///     @Environment(OnboardingCoordinator.self) private var onboarding
///     Button("Continue") { onboarding.advance() }
///
/// Each step's view (`OnboardingFlow.destination(_:)`) calls `advance()` when the person is done, and the plan
/// step may set `planLine`.
@MainActor
@Observable
final class OnboardingCoordinator {
    private(set) var machine: OnboardingMachine
    /// The plan step's summary for the paywall: "Your Bio 101 plan is set: 15 minutes a day until Nov 14."
    /// Without one, the paywall builds a line from the answers.
    var planLine: String?
    /// The course the first set went into (the steps after it study from it).
    var firstCourseID: UUID?
    /// The reminder moment after the minutes question has been answered (either way) in this run.
    var reminderAsked = false
    /// "No exam yet" was the answer (as opposed to no answer).
    var noExamYet = false
    /// Questions answered in this run (a default like 15 minutes isn't shown as the person's pick until they pick).
    var answered: Set<QuizQuestion> = []
    var showsExamPass = false
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
    func skipIntro() { machine.skipIntro() }
    func showIntroPage(_ page: Int) { machine.showIntroPage(page) }

    /// The onboarding paywall closed. A purchase finishes; a decline 8 to 21 days before the next exam gets the Exam Pass
    /// offer first (`ExamPassOffer`).
    func paywallFinished(_ outcome: PaywallOutcome) {
        guard let app else { return advance() }
        switch outcome {
        case .purchased:
            advance()
        case .declined:
            declinedPaywall = true
            let examDates = [app.settings.nextExamDate].compactMap { $0 } + app.upcomingExams().map(\.date)
            if ExamPassOffer.isEligible(plan: app.purchases.plan, examDates: examDates, now: app.now, calendar: app.calendar) {
                showsExamPass = true
            } else {
                advance()
            }
        }
    }

    func examPassFinished(_ outcome: PaywallOutcome) {
        if case .purchased = outcome { declinedPaywall = false }
        showsExamPass = false
    }

    /// The Exam Pass sheet is gone (bought, declined or swiped away): onboarding is done.
    func examPassDismissed() {
        if machine.step == .paywall { advance() }
    }

    /// The last step: onboarding never shows again; the tabs take over.
    func finish() {
        guard !finished, let app else { return }
        finished = true
        withAnimation(CLMotion.fade) { app.settings.onboardingCompleted = true }
        if case .onboarding = app.router.cover { app.router.dismissCover() }
        if declinedPaywall && !app.purchases.isPro {
            Task { @MainActor in
                try? await nap(700)
                app.router.toast("You're on the free plan. Upgrade anytime.", systemImage: "sparkles", tone: .neutral)
            }
        }
    }

    /// What the onboarding paywall names: the plan step's line, or one built from the answers (the course and
    /// the exam always belong together).
    func resolvedPlanLine(app: AppModel) -> String {
        if let planLine { return planLine }
        let minutes = app.settings.dailyMinutes
        if let date = app.settings.nextExamDate {
            return PaywallCopy.planLine(courseName: app.courses.first?.name, minutes: minutes, examDate: date, now: app.now)
        }
        if let exam = app.upcomingExams().first {
            return PaywallCopy.planLine(courseName: exam.course?.name, minutes: minutes, examDate: exam.date, now: app.now)
        }
        return PaywallCopy.planLine(courseName: app.courses.first?.name, minutes: minutes, examDate: nil, now: app.now)
    }
}

/// Onboarding: the welcome, six live demos, four questions, the first set and session, readiness and the plan,
/// then the paywall. Shown by RootView until `settings.onboardingCompleted`, and as a cover by
/// `CRAMLESS_ROUTE=onboarding:<n>` (n counts welcome 0, intro pages 1–6, questions 7–10, first set 11, first
/// session 12, readiness 13, plan 14, paywall 15), which opens step n without wiping data.
struct OnboardingFlow: View {
    let startPage: Int?

    @Environment(AppModel.self) private var app
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
        .sheet(isPresented: $coordinator.showsExamPass, onDismiss: coordinator.examPassDismissed) {
            ExamPassView(examID: nil)
                .environment(\.paywallFinish, PaywallFinishAction { coordinator.examPassFinished($0) })
        }
        .sheet(isPresented: $coordinator.showsWelcomeBack) {
            WelcomeBackSheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear { coordinator.app = app }
    }

    @ViewBuilder
    private func destination(_ screen: OnboardingScreen) -> some View {
        switch screen {
        case .intro:
            IntroPager()
                .toolbar(.hidden, for: .navigationBar)
        case .quiz(let index):
            QuizStepView(question: QuizQuestion(rawValue: index) ?? .goal)
        case .firstSet:
            OnboardingFirstSetStep { courseID in
                coordinator.firstCourseID = courseID
                coordinator.advance()
            }
        case .firstSession:
            OnboardingFirstSessionStep(courseID: coordinator.firstCourseID) { coordinator.advance() }
        case .readiness:
            OnboardingReadinessStep(courseID: coordinator.firstCourseID) { coordinator.advance() }
        case .plan:
            OnboardingPlanStep(courseID: coordinator.firstCourseID) { line in
                coordinator.planLine = line
                coordinator.advance()
            }
        case .paywall:
            PaywallView(context: .onboarding(planLine: coordinator.resolvedPlanLine(app: app)))
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
