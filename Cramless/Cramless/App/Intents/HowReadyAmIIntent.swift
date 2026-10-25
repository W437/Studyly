import AppIntents
import SwiftUI

/// "How ready am I?": answers out loud and on screen without opening the app ("64% ready for Bio 101 Midterm,
/// 23 days to go."). Reads the live data when the app is running (it is, in the background, while the intent
/// runs: the app process hosts it), else the last widget snapshot.
struct HowReadyAmIIntent: AppIntent {
    static let title: LocalizedStringResource = "How ready am I?"
    static let description = IntentDescription("Tells you how ready you are for your next exam and how many days are left.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let app = AppModel.live
        let now = app?.now ?? Date()
        let calendar = app?.calendar ?? .current
        let snapshot = Self.snapshot(app: app, now: now, calendar: calendar)
        let answer = WidgetCopy.readinessAnswer(snapshot, now: now, calendar: calendar)
        return .result(dialog: IntentDialog(stringLiteral: answer),
                       view: ReadinessSnippet(snapshot: snapshot, now: now, calendar: calendar))
    }

    /// Live data when the app model exists, else what the widgets last saw.
    @MainActor
    static func snapshot(app: AppModel?, now: Date, calendar: Calendar) -> WidgetSnapshot? {
        if let app { return app.makeWidgetSnapshot() }
        return WidgetSnapshotStore.shared.read()?.rolled(to: now, calendar: calendar)
    }
}

/// The card under Siri's answer: the ring, the exam, the days left.
struct ReadinessSnippet: View {
    var snapshot: WidgetSnapshot?
    var now: Date
    var calendar: Calendar

    var body: some View {
        if let s = snapshot, let exam = s.nextExam {
            let days = s.daysLeft(to: exam, from: now, calendar: calendar)
            HStack(spacing: 14) {
                WidgetReadinessRing(value: exam.readiness, size: 64, lineWidth: 8)
                VStack(alignment: .leading, spacing: 3) {
                    WidgetEyebrow(text: "Next exam", dot: exam.color)
                    Text(exam.title)
                        .font(.system(.headline))
                        .foregroundStyle(CLColor.ink)
                    HStack(spacing: 8) {
                        Text(WidgetCopy.days(days))
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(days <= 2 ? CLColor.tangerineInk : CLColor.ink2)
                        WidgetDelta(delta: exam.delta)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(WidgetCopy.examAccessibility(exam, daysLeft: days)))
        }
    }
}
