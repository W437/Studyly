import ActivityKit
import Foundation
import OSLog

/// The two Live Activities.
///
/// - **Study session** — the session screen calls `startSession(title:total:)` when the first question shows,
///   `update(answered:correct:topic:)` after each answer, and `end()` with the summary. One at a time; starting a
///   new one ends any other. If the app goes away mid-session the activity turns stale after 15 minutes ("Paused")
///   and the next launch ends it.
/// - **Exam week** — one at a time, for the next exam once it's 7 days away or less, updated with readiness and days
///   left, ended after the exam. `WidgetSync.refresh()` drives it on launch and after every change
///   (`syncExamWeek(with:)`). Activities live at most 8 hours, so the week is covered by restarting it whenever the
///   app is opened.
///
/// Respects the person's Live Activities switch for Capling (Settings ▸ Capling): when it's off nothing starts
/// and the exam-week activity is ended. Requests only succeed with the app in the foreground; failures are logged
/// and ignored. Inert in unit tests (`sideEffectsEnabled` is off there).
@MainActor
final class LiveActivityController {
    weak var app: AppModel?

    private var session: Activity<StudySessionAttributes>?
    private var sessionState = StudySessionAttributes.ContentState(answered: 0, correct: 0, topic: nil)
    private var sessionQueue: Task<Void, Never>?
    private var examQueue: Task<Void, Never>?
    private var reconciledAtLaunch = false

    /// How long a session activity stays fresh without an update before it reads "Paused".
    static let sessionStaleAfter: TimeInterval = 15 * 60
    /// How long the finished session stays on the Lock Screen.
    static let finishedLingers: TimeInterval = 2 * 60

    init(app: AppModel) {
        self.app = app
    }

    /// Live Activities are allowed for Capling (the person's switch in Settings) and this isn't a unit test.
    var isEnabled: Bool {
        guard app?.sideEffectsEnabled == true else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var hasSession: Bool { session != nil }

    // MARK: Study session

    /// Starts the session activity. `title`: "Today's session", "Bio 101 practice", "2-minute fix".
    func startSession(title: String, total: Int, plannedMinutes: Int? = nil) {
        endOtherSessions(keeping: nil)
        session = nil
        guard isEnabled, total > 0 else { return }
        let attributes = StudySessionAttributes(title: title, total: total, startedAt: Date(), plannedMinutes: plannedMinutes)
        sessionState = .init(answered: 0, correct: 0, topic: nil)
        do {
            session = try Activity.request(attributes: attributes, content: sessionContent(sessionState), pushType: nil)
        } catch {
            Self.log.notice("session activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After each answer.
    func update(answered: Int, correct: Int, topic: String?) {
        guard let activity = session else { return }
        sessionState = .init(answered: max(0, answered), correct: max(0, min(correct, answered)), topic: topic)
        let content = sessionContent(sessionState)
        enqueueSession { await activity.update(content) }
    }

    /// With the summary: shows "Session done" briefly, then goes.
    func end() {
        guard let activity = session else { return }
        session = nil
        var final = sessionState
        final.finished = true
        final.topic = nil
        let content = ActivityContent(state: final, staleDate: nil, relevanceScore: 100)
        let dismissal = ActivityUIDismissalPolicy.after(Date().addingTimeInterval(Self.finishedLingers))
        enqueueSession { await activity.end(content, dismissalPolicy: dismissal) }
    }

    private func sessionContent(_ state: StudySessionAttributes.ContentState) -> ActivityContent<StudySessionAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.sessionStaleAfter), relevanceScore: 100)
    }

    /// Ends session activities left over from an earlier run (the app was closed mid-session).
    private func endOtherSessions(keeping id: String?) {
        guard app?.sideEffectsEnabled == true else { return }
        let others = Activity<StudySessionAttributes>.activities.filter { $0.id != id && $0.isRunning }
        guard !others.isEmpty else { return }
        enqueueSession {
            for activity in others { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func enqueueSession(_ work: @escaping @MainActor () async -> Void) {
        let previous = sessionQueue
        sessionQueue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    // MARK: Exam week

    /// Starts, updates or ends the exam-week activity to match the snapshot. Cheap when nothing changed.
    func syncExamWeek(with snapshot: WidgetSnapshot) {
        guard let app, app.sideEffectsEnabled else { return }
        if !reconciledAtLaunch {
            reconciledAtLaunch = true
            endOtherSessions(keeping: session?.id)
        }
        let now = app.now
        let calendar = app.calendar
        let focus = isEnabled ? ExamWeekPlan.focus(in: snapshot, now: now, calendar: calendar) : nil
        let attributes = focus.map(ExamWeekPlan.attributes(for:))
        let state = focus.map { ExamWeekPlan.state(for: $0, in: snapshot, now: now, calendar: calendar) }
        // Days left changes at midnight; after that the activity shows the exam's date instead of a stale count.
        let staleDate = WidgetCalendar.nextMidnight(after: Date(), calendar: calendar)
        let previous = examQueue
        examQueue = Task { @MainActor in
            await previous?.value
            let running = Activity<ExamWeekAttributes>.activities.filter(\.isRunning)
            var kept: Activity<ExamWeekAttributes>?
            for activity in running {
                if kept == nil, let attributes, activity.attributes == attributes {
                    kept = activity
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            guard let attributes, let state else { return }
            let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 10)
            if let kept {
                if kept.content.state != state || kept.activityState == .stale { await kept.update(content) }
            } else {
                do {
                    _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                } catch {
                    Self.log.notice("exam-week activity not started: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    static let log = Logger(subsystem: "com.loopware.Capling", category: "live-activity")
}

private extension Activity {
    var isRunning: Bool {
        switch activityState {
        case .active, .stale, .pending: true
        default: false
        }
    }
}
