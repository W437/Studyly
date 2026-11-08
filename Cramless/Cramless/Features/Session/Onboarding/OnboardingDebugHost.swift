#if DEBUG
import SwiftUI

/// Onboarding's steps after the first set, outside onboarding, for screenshots and checks: `CRAMLESS_STEP=firstSession|examDate|
/// plan` (read by `TodayView`) opens this over Today. The steps then run on in order, the way the real flow chains them; the plan's
/// Continue closes it with a toast.
enum OnboardingDebugStep: String, Identifiable {
    case firstSession, examDate, plan
    var id: String { rawValue }
}

struct OnboardingDebugHost: View {
    let start: OnboardingDebugStep

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var step: OnboardingDebugStep?

    var body: some View {
        NavigationStack {
            Group {
                switch step ?? start {
                case .firstSession:
                    OnboardingFirstSessionStep(courseID: nil) { step = .examDate }
                case .examDate:
                    OnboardingExamDateStep(courseID: nil) { step = .plan }
                case .plan:
                    OnboardingPlanStep(courseID: nil) {
                        dismiss()
                        app.router.toast("Your plan is set.", systemImage: "checkmark.circle.fill")
                    }
                }
            }
            .id(step ?? start)
        }
    }
}
#endif
