import Foundation
import SwiftData

// Reads for Today's page that no other screen needs: which exam today's finished sessions counted toward, and the week of
// "Your plan". The rest of Today comes from the shared reads (`todayPlan()`, `sessionFocus`, `readinessAfter`, `examPlans()`).
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

    /// "Your plan": two days back, today and four ahead, across every exam's share of the daily goal (`TodayPlanStrip`).
    func todayStrip(summary: TodaySummary) -> [TodayPlanDay] {
        let titles = Dictionary(examSnapshots(upcomingOnly: true).map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let plans = examPlans().map { TodayPlanStrip.ExamPlan(title: titles[$0.examID] ?? "", days: $0.days) }
        let past = daySnapshots(since: calendar.adding(days: -TodayPlanStrip.back, to: now))
        let done = summary.studiedToday && summary.minutesDone >= summary.minutesGoal
        return TodayPlanStrip.make(today: now, plans: plans, past: past, todayMinutes: summary.plannedMinutes, todayDone: done,
                                   goal: settings.dailyMinutes, easyDays: settings.easyDays, calendar: calendar)
    }

    /// What "Why these?" says about today's session (`TodayReasons`): its exam and scope, the exam's weakest topic and how many of
    /// today's questions are on it, what is due and new, and the exams that wait.
    func todayReasonsInput() -> TodayReasons.Input {
        let (summary, session) = todayPlan()
        let focus = sessionFocus(session)
        let exams = examSnapshots(upcomingOnly: true)
        var input = TodayReasons.Input()
        if let id = focus.examID, let snapshot = exams.first(where: { $0.id == id }), let model = exam(id) {
            input.examTitle = snapshot.title
            input.when = TodayCopy.when(snapshot.date, now: now, calendar: calendar)
            input.courseName = model.course?.name ?? ""
            input.scopeTopics = topicSnapshots(in: model.course)
                .filter { snapshot.scope.contains($0.id) }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.name)
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
        input.others = focus.otherExamIDs.compactMap { id in
            guard let other = exams.first(where: { $0.id == id }) else { return nil }
            let courseName = other.courseID.flatMap { self.course($0) }?.name ?? ""
            return TodayReasons.Other(name: courseName.isEmpty ? other.title : courseName,
                                      daysLeft: calendar.dayDistance(from: now, to: other.date),
                                      inToday: (focus.secondsByExam[id] ?? 0) > 0)
        }
        return input
    }
}
