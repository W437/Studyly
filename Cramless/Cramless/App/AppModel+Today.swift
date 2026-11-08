import Foundation
import SwiftData

// Reads for Today's page that no other screen needs: which exam today's finished sessions counted toward, the night before's minutes
// and what "Why these?" says. The rest of Today comes from the shared reads (`todayPlan()`, `sessionFocus`).
extension AppModel {
    /// The exam today's last finished session counted toward (its tracked exam, `StudySession.examID`), if it is still ahead.
    func todayDoneExamID() -> UUID? {
        let start = calendar.startOfDay(for: now)
        let quick = SessionKind.quickCheck.rawValue
        var descriptor = FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.startedAt >= start && $0.endedAt != nil && $0.itemCount > 0 && $0.kindRaw != quick && $0.examID != nil
        }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return fetch(descriptor).first?.examID
    }

    /// The night before's session minutes as its button and the plan say them, built from what is true now. One number for the button, the
    /// exam page's plan, the widgets and the evening's notification.
    func builtEveMinutes(examID: UUID) -> Int {
        buildSession(SessionRequest(kind: .examEve, examID: examID)).tonightMinutes
    }

    /// What "Why these?" says about today's session (`TodayReasons`): how it is shared, the exam's weakest topic and how many of today's
    /// questions are on it, what is to review and new, and the exams that wait.
    func todayReasonsInput() -> TodayReasons.Input {
        let (summary, session) = todayPlan()
        let focus = sessionFocus(session)
        let exams = examSnapshots(upcomingOnly: true)
        var input = TodayReasons.Input()
        input.sessionTotal = session.entries.count
        input.examQuestions = focus.examID == nil ? 0 : focus.questionCount
        if let id = focus.examID, let snapshot = exams.first(where: { $0.id == id }), let model = exam(id) {
            input.examTitle = snapshot.title
            input.daysLeft = calendar.dayDistance(from: now, to: snapshot.date)
            input.focusSeconds = focus.focusSeconds
            let (readiness, _) = readinessAndPlan(for: model)
            input.scopeCount = readiness.itemsInScope
            if let weakest = topicReadiness(for: model).filter({ $0.value != nil && $0.itemCount > 0 })
                .min(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
                input.weakestName = weakest.name
                input.weakestValue = weakest.value ?? 0
                input.weakestToday = session.entries.filter { $0.topicID == weakest.id }.count
            }
            input.due = focus.dueCount
            input.new = focus.newCount
        } else {
            input.due = summary.reviews
            input.new = summary.newItems
        }
        // Every other upcoming exam: the ones with none of today's minutes wait, the ones with a smaller share are "in too".
        input.others = exams.filter { $0.id != focus.examID }.compactMap { other in
            let id = other.id
            let courseName = other.courseID.flatMap { self.course($0) }?.name ?? ""
            let seconds = focus.secondsByExam[id] ?? 0
            return TodayReasons.Other(name: courseName.isEmpty ? other.title : courseName,
                                      daysLeft: calendar.dayDistance(from: now, to: other.date),
                                      inToday: seconds > 0, seconds: seconds,
                                      due: !session.entries.contains { $0.examID == id && $0.reason == .new })
        }
        return input
    }
}
