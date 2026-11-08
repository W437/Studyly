import SwiftUI

/// Onboarding's first session: two quick questions on the set just made (one multiple choice, one in the
/// person's own words), graded live with the same question views as every session. The answers are real reviews,
/// so the plan that follows has an honest readiness to show. Calls `onDone` after the second answer (or at
/// once when the set has no questions). The header is "Two quick questions" / "From your page." over the session's
/// segments, which are the count; there is no other progress bar in onboarding.
///
///     OnboardingFirstSessionStep(courseID: firstSetCourse) { onboarding.advance() }
struct OnboardingFirstSessionStep: View {
    let courseID: UUID?
    let onDone: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var runner: SessionRunner?
    @State private var done = false

    init(courseID: UUID?, onDone: @escaping () -> Void) {
        self.courseID = courseID
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            if let runner {
                header(runner)
                SessionQuestionHost(runner: runner)
            }
        }
        .background(CLColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: start)
        .onChange(of: runner?.phase) { _, phase in
            if phase == .finished { finish() }
        }
    }

    private func header(_ runner: SessionRunner) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !typeSize.isAccessibilitySize {
                Text("Two quick questions")
                    .clFont(.brandTitle(28))
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("From your page.")
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SessionSegments(runner: runner)
                .frame(width: 72)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func start() {
        guard runner == nil else { return }
        let ids = app.quickCheckItemIDs(courseID: courseID)
        guard !ids.isEmpty else { finish(); return }
        let request = SessionRequest(kind: .quickCheck, courseID: app.onboardingCourse(courseID)?.id, itemIDs: ids)
        let next = SessionRunner(app: app, request: request, options: .init(liveActivity: false, requeues: false))
        guard next.phase == .ready else { finish(); return }
        next.start()
        CLHaptics.prepare()
        runner = next
    }

    private func finish() {
        guard !done else { return }
        done = true
        runner?.finish()
        if (runner?.distinctAnswered ?? 0) > 0 { CLHaptics.success() }
        onDone()
    }
}
