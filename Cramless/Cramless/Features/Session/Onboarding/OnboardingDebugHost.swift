#if DEBUG
import SwiftUI

/// The Study lane's onboarding steps outside onboarding, for screenshots and checks: `CRAMLESS_STEP=firstSession|
/// readiness|plan` (read by `TodayView`) opens this over Today. The steps then run on in order, the way the real
/// flow chains them; the plan's line ends it as a toast.
enum OnboardingDebugStep: String, Identifiable {
    case firstSession, readiness, plan
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
                    OnboardingFirstSessionStep(courseID: nil) { step = .readiness }
                case .readiness:
                    OnboardingReadinessStep(courseID: nil) { step = .plan }
                case .plan:
                    OnboardingPlanStep(courseID: nil) { line in
                        dismiss()
                        app.router.toast(line.map { .verbatim($0) } ?? "Your plan is set.", systemImage: "checkmark.circle.fill")
                    }
                }
            }
            .id(step ?? start)
        }
    }
}
#endif
