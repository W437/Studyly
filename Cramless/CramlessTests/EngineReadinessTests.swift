import Foundation
import XCTest
@testable import Cramless

final class EngineReadinessTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID()
    let topicA = UUID(), topicB = UUID(), topicGap = UUID()
    lazy var engine = ReadinessEngine(fsrs: FSRS(), calendar: cal, now: now)
    lazy var topics = [TopicSnapshot(id: topicA, courseID: course, name: "A", sortOrder: 0),
                       TopicSnapshot(id: topicB, courseID: course, name: "B", sortOrder: 1),
                       TopicSnapshot(id: topicGap, courseID: course, name: "No material", sortOrder: 2)]

    func testNeverStudiedItemsCountZero() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let studied = EngineTest.studied(topic: topicA, course: course, recall: 0.9, daysAgo: 5, now: now, cal: cal)
        let fresh = EngineTest.fresh(topic: topicB, course: course)
        let r = engine.examRecall(studied.memory, on: exam.date)
        XCTAssertLessThan(r, 0.9, "recall falls by exam day")
        XCTAssertEqual(engine.value(of: exam, items: [studied, fresh]), r / 2, accuracy: 1e-12)
        // Suspended items and other courses are out of scope.
        var suspended = studied
        suspended.id = UUID()
        suspended.status = .suspended
        let other = EngineTest.studied(course: UUID(), recall: 0.2, daysAgo: 5, now: now, cal: cal)
        XCTAssertEqual(engine.value(of: exam, items: [studied, fresh, suspended, other]), r / 2, accuracy: 1e-12)
    }

    func testTopicsAndCoverageGaps() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let items = [EngineTest.studied(topic: topicA, course: course, recall: 0.9, daysAgo: 5, now: now, cal: cal),
                     EngineTest.fresh(topic: topicB, course: course)]
        let list = engine.topicReadiness(for: exam, items: items, topics: topics)
        XCTAssertEqual(list.map(\.name), ["A", "B", "No material"])
        XCTAssertGreaterThan(list[0].value!, 0.5)
        XCTAssertEqual(list[1].value, 0)
        XCTAssertNil(list[2].value, "a topic with no items is a coverage gap")
        // A scoped exam lists only its topics.
        let scoped = ExamSnapshot(courseID: course, date: exam.date, scope: [topicB])
        XCTAssertEqual(engine.topicReadiness(for: scoped, items: items, topics: topics).map(\.name), ["B"])
    }

    /// Topic recall is internal (Ask Cap and Teach Cap pick a weak topic with it): current recall of the studied questions, 0 for a
    /// topic none of whose questions is studied, nil for a gap. The course-wide mastery number is gone: readiness is the only one.
    func testTopicRecallIsCurrentRecallOfStudiedItems() {
        let items = [EngineTest.studied(topic: topicA, course: course, recall: 0.8, daysAgo: 3, now: now, cal: cal),
                     EngineTest.studied(topic: topicA, course: course, recall: 0.6, daysAgo: 3, now: now, cal: cal),
                     EngineTest.fresh(topic: topicA, course: course),
                     EngineTest.fresh(topic: topicB, course: course)]
        let byTopic = engine.topicMastery(courseID: course, items: items, topics: topics)
        XCTAssertEqual(byTopic[0].value ?? -1, 0.7, accuracy: 1e-9)
        XCTAssertEqual(byTopic.map(\.itemCount), [3, 1, 0])
        XCTAssertEqual(byTopic[1].value, 0)
        XCTAssertNil(byTopic[2].value)
    }

    // MARK: New questions

    /// Fifteen new questions lower the ring at once, and say why; they don't take ground back from "this week", and the line goes as they are studied.
    func testAddingQuestionsKeepsTheNumberAndTheWeek() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let reviewed = cal.adding(days: -3, to: now)
        var settled: [ItemSnapshot] = []
        var logs: [ReviewSnapshot] = []
        for _ in 0..<20 {
            var item = EngineTest.studied(topic: topicA, course: course, recall: 0.9, daysAgo: 3, now: now, cal: cal)
            item.addedAt = cal.adding(days: -40, to: now)
            settled.append(item)
            logs.append(ReviewSnapshot(itemID: item.id, reviewedAt: reviewed, rating: .good, stateBefore: .review,
                                       stabilityAfter: item.memory.stability))
        }
        let plan = StudyPlan(examID: exam.id, target: 0.9, daysLeft: 14, dailyMinutes: 15, itemsInScope: 20, newItems: 0, reviewsPlanned: 0,
                             days: [PlanDay(date: now, dayNumber: 0, kind: .study, minutes: 10, sessionMinutes: 15, newItems: 3, reviews: 0, isToday: true, isEasyDay: false)],
                             lastIntroDay: nil, examEve: nil, curve: [], projectedReadiness: 0.8, targetReachedOn: nil, suggestedMinutes: nil)
        func read(_ items: [ItemSnapshot]) -> ExamReadiness {
            engine.readiness(for: exam, items: items, topics: topics, logs: logs, plan: plan, grade: GradeModel.uncalibrated(for: ExamFormat()))
        }
        let before = read(settled)
        XCTAssertEqual(before.newQuestions, 0)
        XCTAssertGreaterThan(before.deltaThisWeek, 0)

        var new = (0..<15).map { _ in EngineTest.fresh(topic: topicB, course: course) }
        for index in new.indices { new[index].addedAt = cal.adding(days: -1, to: now) }
        let after = read(settled + new)
        XCTAssertLessThan(after.value, before.value - 0.1, "the number stays honest: they count as nothing yet")
        XCTAssertEqual(after.newQuestions, 15)
        XCTAssertTrue(after.newQuestionsInPlan)
        XCTAssertEqual(after.deltaThisWeek, min(before.deltaThisWeek, after.value), accuracy: 1e-9, "adding questions isn't losing ground")
        XCTAssertEqual(after.deltaToday, before.deltaToday, accuracy: 1e-9)

        // Added more than a week ago and still not studied: no longer news.
        var old = new
        for index in old.indices { old[index].addedAt = cal.adding(days: -8, to: now) }
        XCTAssertEqual(read(settled + old).newQuestions, 0)

        // Studied, they leave the line; a last one left that moves the ring by under a point doesn't keep it up.
        var almost = new.map { item -> ItemSnapshot in
            var studied = EngineTest.studied(topic: topicB, course: course, recall: 0.9, daysAgo: 0, now: now, cal: cal)
            studied.id = item.id
            return studied
        }
        XCTAssertEqual(read(settled + almost).newQuestions, 0)
        almost.removeLast()
        var many = (0..<200).map { _ in EngineTest.studied(topic: topicA, course: course, recall: 0.2, daysAgo: 3, now: now, cal: cal) }
        many.append(new[0])
        XCTAssertEqual(engine.newQuestionsShown(of: exam, in: many), 0, "under a point: nothing to explain")
    }

    /// A first week reads as what it gained, never more than the ring holds.
    func testAFirstWeekIsNeverMoreThanTheRing() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        var items: [ItemSnapshot] = (0..<10).map { _ in
            var item = EngineTest.studied(topic: topicA, course: course, recall: 0.9, daysAgo: 1, now: now, cal: cal)
            item.addedAt = cal.adding(days: -2, to: now)
            return item
        }
        items += (0..<20).map { _ in
            var item = EngineTest.fresh(topic: topicA, course: course)
            item.addedAt = cal.adding(days: -2, to: now)
            return item
        }
        let logs = items.prefix(10).map { ReviewSnapshot(itemID: $0.id, reviewedAt: cal.adding(days: -1, to: now), rating: .good, stateBefore: .new,
                                                         stabilityAfter: $0.memory.stability) }
        let plan = StudyPlan(examID: exam.id, target: 0.9, daysLeft: 14, dailyMinutes: 15, itemsInScope: 30, newItems: 20, reviewsPlanned: 0, days: [],
                             lastIntroDay: nil, examEve: nil, curve: [], projectedReadiness: 0.8, targetReachedOn: nil, suggestedMinutes: nil)
        let r = engine.readiness(for: exam, items: items, topics: topics, logs: logs, plan: plan, grade: GradeModel.uncalibrated(for: ExamFormat()))
        XCTAssertEqual(r.deltaThisWeek, r.value, accuracy: 1e-9)
        XCTAssertEqual(r.newQuestions, 20)
        XCTAssertFalse(r.newQuestionsInPlan, "no place for them in this plan")
    }

    func testDeltaThisWeekComesFromTheReviewLog() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let id = UUID()
        let tenDaysAgo = cal.adding(days: -10, to: now)
        let twoDaysAgo = cal.adding(days: -2, to: now)
        let memory = MemoryState(state: .review, stability: 20, difficulty: 5, due: cal.adding(days: 18, to: twoDaysAgo),
                                 lastReview: twoDaysAgo, reps: 2)
        let item = ItemSnapshot(id: id, topicID: topicA, courseID: course, memory: memory)
        let logs = [ReviewSnapshot(itemID: id, reviewedAt: tenDaysAgo, rating: .good, stabilityAfter: 4),
                    ReviewSnapshot(itemID: id, reviewedAt: twoDaysAgo, rating: .good, stabilityAfter: 20)]
        let fresh = EngineTest.fresh(topic: topicB, course: course)
        let plan = PlanBuilder(fsrs: FSRS(), calendar: cal, now: now, dailyMinutes: 15).plan(for: exam, items: [item, fresh])
        let r = engine.readiness(for: exam, items: [item, fresh], topics: topics, logs: logs, plan: plan,
                                 grade: .uncalibrated(for: exam.format))
        let nowValue = engine.recall(stability: 20, last: twoDaysAgo, on: exam.date) / 2
        let weekAgo = engine.recall(stability: 4, last: tenDaysAgo, on: exam.date) / 2
        XCTAssertEqual(r.value, nowValue, accuracy: 1e-12)
        XCTAssertEqual(r.deltaThisWeek, nowValue - weekAgo, accuracy: 1e-12)
        XCTAssertGreaterThan(r.deltaThisWeek, 0)
        XCTAssertEqual(r.daysLeft, 14)
        XCTAssertEqual(r.itemsInScope, 2)
        XCTAssertEqual(r.unseenItems, 1)
        XCTAssertEqual(r.coverageGaps, 1)
        XCTAssertGreaterThan(r.projected, r.value, "following the plan beats stopping now")
        XCTAssertEqual(r.projectedGrade, GradeModel.uncalibrated(for: exam.format).grade(r.projected))
    }

    func testDeltaTodayComesFromTheReviewLogSinceMorning() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 5, to: now))
        let id = UUID()
        let yesterday = cal.adding(days: -1, to: now)
        let earlier = now.addingTimeInterval(-3600)
        let memory = MemoryState(state: .review, stability: 6, difficulty: 5, due: cal.adding(days: 6, to: earlier),
                                 lastReview: earlier, reps: 3)
        let item = ItemSnapshot(id: id, topicID: topicA, courseID: course, memory: memory)
        let logs = [ReviewSnapshot(itemID: id, reviewedAt: yesterday, rating: .again, stabilityAfter: 0.5),
                    ReviewSnapshot(itemID: id, reviewedAt: earlier, rating: .good, stabilityAfter: 6)]
        let plan = PlanBuilder(fsrs: FSRS(), calendar: cal, now: now, dailyMinutes: 15).plan(for: exam, items: [item])
        let r = engine.readiness(for: exam, items: [item], topics: topics, logs: logs, plan: plan,
                                 grade: .uncalibrated(for: exam.format))
        let morning = engine.recall(stability: 0.5, last: yesterday, on: exam.date)
        XCTAssertEqual(r.deltaToday, r.value - morning, accuracy: 1e-12, "since the start of today, from the log")
        XCTAssertGreaterThan(r.deltaToday, 0.2)
        XCTAssertEqual(r.deltaThisWeek, r.value, accuracy: 1e-12, "nothing a week ago")
    }

    func testHistoryIsOldestFirstAndEndsNow() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let id = UUID()
        let fiveDaysAgo = cal.adding(days: -5, to: now)
        let item = ItemSnapshot(id: id, courseID: course, memory: MemoryState(state: .review, stability: 10, difficulty: 5,
                                                                              due: cal.adding(days: 10, to: fiveDaysAgo),
                                                                              lastReview: fiveDaysAgo, reps: 1))
        let logs = [ReviewSnapshot(itemID: id, reviewedAt: fiveDaysAgo, rating: .good, stabilityAfter: 10)]
        let points = engine.history(of: exam, items: [item], logs: logs, days: 14)
        XCTAssertEqual(points.count, 14)
        XCTAssertEqual(points.last!.value, engine.value(of: exam, items: [item]), accuracy: 1e-12)
        XCTAssertEqual(points.first!.value, 0, "nothing studied two weeks ago")
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.date < $1.date })
        XCTAssertEqual(points.firstIndex { $0.value > 0 }, 14 - 6, "studied five days ago")
    }

    func testImportedMemoryWithoutLogsCountsOnceReviewed() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let item = EngineTest.studied(course: course, recall: 0.9, daysAgo: 3, now: now, cal: cal)
        XCTAssertGreaterThan(engine.value(of: exam, items: [item], at: cal.adding(days: -1, to: now), logsByItem: [:]), 0)
        XCTAssertEqual(engine.value(of: exam, items: [item], at: cal.adding(days: -5, to: now), logsByItem: [:]), 0)
    }

    // MARK: Hours, not whole days

    /// 18:00 to 10:00 the next morning is 16 hours, not the "0 days" the scheduler counts: recall falls in those hours like any
    /// others, so a weak question reviewed the evening before is not certain on the morning of the exam.
    func testExamDayRecallCountsHoursNotWholeDays() {
        let fsrs = FSRS()
        let eve = EngineTest.date(2026, 10, 24, 18, in: cal)
        let exam = EngineTest.date(2026, 10, 25, 10, in: cal)
        XCTAssertEqual(FSRS.elapsedDays(from: eve, to: exam), 0, "the scheduler's whole days")
        let r = engine.recall(stability: 0.05, last: eve, on: exam)
        XCTAssertEqual(r, fsrs.retrievability(elapsedDays: 16.0 / 24, stability: 0.05), accuracy: 1e-12)
        XCTAssertEqual(r, fsrs.forecastRecall(stability: 0.05, last: eve, at: exam), accuracy: 1e-12)
        XCTAssertLessThan(r, 0.8, "a weak question reviewed the evening before")
        let memory = MemoryState(state: .review, stability: 0.05, difficulty: 7, due: exam, lastReview: eve, reps: 2)
        XCTAssertEqual(engine.examRecall(memory, on: exam), r, accuracy: 1e-12, "the ring counts the same hours")
        XCTAssertEqual(engine.value(of: ExamSnapshot(courseID: course, date: exam),
                                    items: [ItemSnapshot(courseID: course, memory: memory)]), r, accuracy: 1e-12)
        // Whole days are unchanged.
        XCTAssertEqual(engine.recall(stability: 3, last: eve, on: cal.adding(days: 2, to: eve)),
                       fsrs.retrievability(elapsedDays: 2, stability: 3), accuracy: 1e-9)
        // The scheduler still floors (py-fsrs parity).
        XCTAssertEqual(fsrs.retrievability(of: memory, at: exam), 1, accuracy: 1e-12)
    }

    // MARK: After today

    func testAfterTodayIsTheRingsOwnFunctionWithTodaysQuestionsStudied() throws {
        let fsrs = FSRS()
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 2, to: now).addingTimeInterval(3600), target: 0.8)
        let weak = EngineTest.studied(topic: topicA, course: course, recall: 0.6, daysAgo: 3, now: now, cal: cal)
        let strong = EngineTest.studied(topic: topicA, course: course, recall: 0.95, daysAgo: 2, now: now, cal: cal)
        let fresh = EngineTest.fresh(topic: topicB, course: course)
        let outside = EngineTest.studied(course: UUID(), recall: 0.5, daysAgo: 3, now: now, cal: cal)
        let items = [weak, strong, fresh, outside]
        let nowValue = engine.value(of: exam, items: items)
        func entry(_ item: ItemSnapshot, _ reason: SessionEntry.Reason) -> SessionEntry {
            SessionEntry(itemID: item.id, reason: reason, kind: item.kind, topicID: item.topicID, courseID: item.courseID,
                         estimatedSeconds: item.kind.typicalSeconds)
        }

        XCTAssertEqual(engine.valueAfter([], exam: exam, items: items, newItemSuccess: 0.75), nowValue, accuracy: 1e-12,
                       "no session: the ring now")
        XCTAssertEqual(engine.valueAfter([entry(outside, .due)], exam: exam, items: items, newItemSuccess: 0.75), nowValue,
                       accuracy: 1e-12, "a question outside the exam moves nothing")

        // One question: its expected state after a review now, over a right and a wrong answer.
        let step = try XCTUnwrap(fsrs.expectedReview(of: weak.memory, at: now))
        let one = engine.valueAfter([entry(weak, .due)], exam: exam, items: items, newItemSuccess: 0.75)
        XCTAssertEqual(one, nowValue + (step.recall(at: exam.date, fsrs: fsrs) - engine.examRecall(weak.memory, on: exam.date)) / 3,
                       accuracy: 1e-12)
        XCTAssertGreaterThan(one, nowValue)

        // The whole session: at least now, at most 1.
        let all = engine.valueAfter([entry(weak, .due), entry(strong, .weak), entry(fresh, .new)], exam: exam, items: items,
                                    newItemSuccess: 0.75)
        XCTAssertGreaterThanOrEqual(all, one)
        XCTAssertLessThanOrEqual(all, 1)

        // A new question counts after its first look, at the person's first-try rate; there is no adherence factor.
        let firstLook = fsrs.expectedFirstLook(success: 0.95, at: now).recall(at: exam.date, fsrs: fsrs)
        let surer = engine.valueAfter([entry(fresh, .new)], exam: exam, items: items, newItemSuccess: 0.95)
        XCTAssertEqual(surer, nowValue + firstLook / 3, accuracy: 1e-12)
        XCTAssertGreaterThan(surer, engine.valueAfter([entry(fresh, .new)], exam: exam, items: items, newItemSuccess: 0.5))
        XCTAssertEqual(engine.valueAfter([entry(weak, .due)], exam: exam, items: [], newItemSuccess: 0.75), 0, "nothing in scope")
    }

    // MARK: Practice

    func testTopicPracticeIsTheQuestionsUnderTheGoalAndTheUnseenTwice() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now), target: 0.8)
        let items = [EngineTest.studied(kind: .recall, topic: topicA, course: course, recall: 0.5, daysAgo: 3, now: now, cal: cal),
                     EngineTest.studied(kind: .flashcard, topic: topicA, course: course, recall: 0.99, daysAgo: 1, now: now, cal: cal),
                     EngineTest.fresh(kind: .mcq, topic: topicA, course: course),
                     EngineTest.fresh(kind: .flashcard, topic: topicB, course: course)]
        let list = engine.topicReadiness(for: exam, items: items, topics: topics)
        XCTAssertGreaterThan(engine.examRecall(items[1].memory, on: exam.date), 0.8, "at the goal: no practice needed")
        XCTAssertEqual(list.map(\.practiceSeconds), [50 + 16 * 2, 9 * 2, 0])
        XCTAssertEqual(list.map(\.practiceMinutes), [2, 2, 2], "at least two minutes")
        XCTAssertEqual(TopicReadiness(id: UUID(), name: "", value: 0.3, itemCount: 40, practiceSeconds: 2_000).practiceMinutes, 10,
                       "at most ten")
        XCTAssertEqual(TopicReadiness(id: UUID(), name: "", value: 0.3, itemCount: 4, practiceSeconds: 200).practiceMinutes, 4)
        // A course's topics (no exam) have none.
        XCTAssertTrue(engine.topicMastery(courseID: course, items: items, topics: topics).allSatisfy { $0.practiceSeconds == 0 })
    }

    // MARK: Grades

    func testDefaultGradeMapping() {
        let mixed = GradeModel.uncalibrated(for: ExamFormat(multipleChoice: true, shortAnswer: true, essay: false))
        XCTAssertEqual(mixed.percent(0.8), 0.125 + 0.875 * 0.8, accuracy: 1e-12)
        XCTAssertFalse(mixed.isCalibrated)
        XCTAssertEqual(GradeModel.uncalibrated(for: ExamFormat(multipleChoice: true, shortAnswer: false)).percent(0), 0.25)
        XCTAssertEqual(GradeModel.uncalibrated(for: ExamFormat(multipleChoice: false, shortAnswer: true)).percent(0.7), 0.7,
                       accuracy: 1e-12)
        XCTAssertEqual(GradeModel.letter(0.87), "B+")
        XCTAssertEqual(GradeModel.letter(0.905), "A−")
        XCTAssertEqual(GradeModel.letter(0.5), "F")
        XCTAssertEqual(GradeModel.letter(1), "A+")
    }

    /// 94% on 16 questions that reach 17% of a 14-page reading is not an A: the rest of the reading is worth what nobody practised.
    func testWhatTheQuestionsCoverDecidesTheProjectedGradeNotTheRing() {
        let shortAnswer = GradeModel.uncalibrated(for: ExamFormat(multipleChoice: false, shortAnswer: true))
        XCTAssertEqual(GradeModel.adjusted(readiness: 0.94, coverage: 0.17), 0.17 * 0.94 + 0.83 * 0.35, accuracy: 1e-12)
        let thin = shortAnswer.grade(0.94, coverage: 0.17)
        XCTAssertEqual(thin.letter, "F", "\(thin)")
        XCTAssertLessThan(thin.percent, 0.5)
        XCTAssertEqual(shortAnswer.grade(0.94).letter, "A", "what it said before")

        // Full coverage, and a coverage nobody could tell, change nothing.
        XCTAssertEqual(shortAnswer.grade(0.94, coverage: 1), shortAnswer.grade(0.94))
        XCTAssertEqual(shortAnswer.grade(0.94, coverage: nil), shortAnswer.grade(0.94))
        XCTAssertEqual(GradeModel.adjusted(readiness: 0.6, coverage: 1), 0.6)
        // More of the material covered never lowers it, and no coverage ever raises it.
        let steps = stride(from: 0.0, through: 1.0, by: 0.1).map { GradeModel.adjusted(readiness: 0.9, coverage: $0) }
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(GradeModel.adjusted(readiness: 0.1, coverage: 0.5), 0.1, "a readiness under the floor is not lifted by it")
        XCTAssertEqual(GradeModel.adjusted(readiness: 0, coverage: 0), 0)
        XCTAssertEqual(GradeModel.unpractisedFloor, 0.35, "a judgement, not a measurement: the share of what nobody practised that still earns marks")
        XCTAssertEqual(GradeModel.adjusted(readiness: 0.9, coverage: 2), 0.9, "a share is kept within 0…1")

        // A multiple-choice exam keeps its guessing on top.
        let choice = GradeModel.uncalibrated(for: ExamFormat(multipleChoice: true, shortAnswer: false))
        XCTAssertEqual(choice.grade(0.94, coverage: 0.17).percent, 0.25 + 0.75 * GradeModel.adjusted(readiness: 0.94, coverage: 0.17), accuracy: 1e-12)
        XCTAssertEqual(choice.grade(0.94, coverage: 0.17).letter, "F")
    }

    func testTheRingStaysTheMeanRecallOfTheQuestionsWhileTheGradeKnowsTheCoverage() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let id = UUID()
        let twoDaysAgo = cal.adding(days: -2, to: now)
        let memory = MemoryState(state: .review, stability: 60, difficulty: 3, due: cal.adding(days: 58, to: twoDaysAgo),
                                 lastReview: twoDaysAgo, reps: 6)
        let item = ItemSnapshot(id: id, topicID: topicA, courseID: course, memory: memory)
        let plan = PlanBuilder(fsrs: FSRS(), calendar: cal, now: now, dailyMinutes: 15).plan(for: exam, items: [item])
        let model = GradeModel.uncalibrated(for: ExamFormat(multipleChoice: false, shortAnswer: true))
        let blind = engine.readiness(for: exam, items: [item], topics: topics, logs: [], plan: plan, grade: model)
        let thin = engine.readiness(for: exam, items: [item], topics: topics, logs: [], plan: plan, grade: model, coverage: 0.17)
        XCTAssertGreaterThan(blind.value, 0.9, "a well-practised handful of questions")
        XCTAssertEqual(thin.value, blind.value, "the ring is the person's own practice")
        XCTAssertEqual(thin.projected, blind.projected)
        XCTAssertEqual(thin.coverage, 0.17)
        XCTAssertNil(blind.coverage)
        XCTAssertEqual(blind.projectedGrade, model.grade(plan.projectedReadiness))
        XCTAssertEqual(thin.projectedGrade, model.grade(plan.projectedReadiness, coverage: 0.17))
        XCTAssertLessThan(thin.projectedGrade.percent, blind.projectedGrade.percent - 0.4)
        XCTAssertEqual(thin.projectedGrade.letter, "F")
    }

    /// The floor is gentler than it was (0.2): the free plan's 24 questions can't cover a long reading, and a grade pulled to the floor
    /// had no remedy; a student who practised half the material and knows it well is no longer projected as failing it.
    func testTheFloorIsGentleEnoughForAReadingTheQuestionsCannotCoverInFull() {
        let shortAnswer = GradeModel.uncalibrated(for: ExamFormat(multipleChoice: false, shortAnswer: true))
        let half = shortAnswer.grade(0.9, coverage: 0.5)
        XCTAssertEqual(half.percent, 0.5 * 0.9 + 0.5 * 0.35, accuracy: 1e-12)
        XCTAssertEqual(half.letter, "D", "62.5%, not the F it would have been at the old floor: \(half)")
        XCTAssertGreaterThan(half.percent, 0.6)
        XCTAssertEqual(GradeModel.adjusted(readiness: 0.9, coverage: 0), 0.35, "nothing practised is projected at the floor")
        XCTAssertEqual(GradeModel.adjusted(readiness: 0.3, coverage: 0), 0.3, "never above the readiness itself")
    }

    /// Calibration is fitted to what each exam was projected from, so coverage is not held against a calibrated student twice: once in
    /// the readiness the line is fitted to, and again in the readiness it is given.
    func testACalibratedLineIsFittedToTheAdjustedReadinessAndReadsItAfterTheExamToo() {
        let format = ExamFormat(multipleChoice: false, shortAnswer: true)
        func started(_ ring: Double, coverage: Double?, got: Double) -> ExamSnapshot {
            ExamSnapshot(courseID: course, date: now, format: format, readinessAtExam: ring, resultScore: got, coverageAtExam: coverage)
        }
        // Two exams on thin readings: a ring of 0.9 on a third of the material, and 0.8 on half.
        let a = started(0.9, coverage: 1.0 / 3, got: 0.55)
        let b = started(0.8, coverage: 0.5, got: 0.62)
        XCTAssertEqual(a.adjustedReadinessAtExam ?? 0, GradeModel.adjusted(readiness: 0.9, coverage: 1.0 / 3), accuracy: 1e-12)
        XCTAssertLessThan(a.adjustedReadinessAtExam ?? 1, a.readinessAtExam ?? 0)
        XCTAssertEqual(ExamSnapshot(courseID: course, date: now, readinessAtExam: 0.9).adjustedReadinessAtExam, 0.9,
                       "an exam that started before the coverage was kept is as it was")
        XCTAssertNil(ExamSnapshot(courseID: course, date: now).adjustedReadinessAtExam)

        let adjusted = GradeModel.make(format: format, history: [(a.adjustedReadinessAtExam!, 0.55), (b.adjustedReadinessAtExam!, 0.62)])
        let raw = GradeModel.make(format: format, history: [(0.9, 0.55), (0.8, 0.62)])
        XCTAssertTrue(adjusted.isCalibrated)
        // The same exam on the same thin reading, projected by each line from what it is given now (the adjusted readiness):
        let given = GradeModel.adjusted(readiness: 0.85, coverage: 0.4)
        XCTAssertEqual(adjusted.percent(given), adjusted.grade(0.85, coverage: 0.4).percent, accuracy: 1e-12)
        // A line fitted to the raw ring and then given an adjusted readiness would take the coverage off twice and project it lower.
        XCTAssertLessThan(raw.percent(given), adjusted.percent(given) + 1e-9)
    }

    func testCalibrationFitsLoggedGrades() {
        let format = ExamFormat()
        XCTAssertFalse(GradeModel.make(format: format, history: [(0.7, 0.8)]).isCalibrated, "one exam isn't enough")
        let fit = GradeModel.make(format: format, history: [(0.6, 0.7), (0.8, 0.86)])
        XCTAssertTrue(fit.isCalibrated)
        XCTAssertEqual(fit.slope, 0.8, accuracy: 1e-9)
        XCTAssertEqual(fit.intercept, 0.22, accuracy: 1e-9)
        XCTAssertEqual(fit.percent(0.7), 0.78, accuracy: 1e-9)
        // No spread in readiness: the default slope, shifted.
        let flat = GradeModel.make(format: format, history: [(0.7, 0.8), (0.7, 0.9)])
        XCTAssertEqual(flat.slope, GradeModel.uncalibrated(for: format).slope)
        XCTAssertEqual(flat.percent(0.7), 0.85, accuracy: 1e-9)
    }
}

final class EnginePlanTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID()

    func builder(at date: Date? = nil, minutes: Int = 15, easyDays: [Int] = []) -> PlanBuilder {
        PlanBuilder(fsrs: FSRS(), calendar: cal, now: date ?? now, dailyMinutes: minutes, easyDays: easyDays)
    }

    func world(new: Int = 30, studied: Int = 20) -> [ItemSnapshot] {
        (0..<new).map { i in EngineTest.fresh(course: course, createdAt: cal.adding(days: -5, to: now), hint: Double(i) / 100) }
            + (0..<studied).map { i in
                EngineTest.studied(course: course, recall: 0.7 + Double(i % 5) * 0.05, daysAgo: 2 + i % 6, now: now, cal: cal)
            }
    }

    func testBoostsAddMinutesToTheDaysSessionAndNothingChangesWithoutThem() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let items = world()
        let plain = builder().plan(for: exam, items: items)
        var b = builder()
        b.boosts = [:]
        b.pinned = [:]
        XCTAssertEqual(b.plan(for: exam, items: items), plain, "no boosts: the same plan to the byte")
        b.boosts = [1: 6]
        let boosted = b.plan(for: exam, items: items)
        XCTAssertEqual(boosted.days[1].sessionMinutes, max(plain.days[1].minutes, 15 + 6))
        XCTAssertEqual(boosted.days[2].sessionMinutes, plain.days[2].sessionMinutes)
    }

    func testPinnedQuestionsAreReviewedOnTheirDayFirst() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        // Overdue questions, more than a day holds: they'd spread over three days, and the strongest of them would be last.
        var items = (0..<120).map { i -> ItemSnapshot in
            var item = EngineTest.studied(course: course, recall: 0.5 + Double(i) * 0.003, daysAgo: 12, now: now, cal: cal)
            item.memory.due = cal.adding(days: -5, to: now)
            return item
        }
        let last = items.removeLast()
        items.append(last)
        var b = builder()
        b.capacity = [0: 300, 1: 300, 2: 300]
        let plain = b.plan(for: exam, items: items)
        b.pinned = [last.id: 0]
        let pinned = b.plan(for: exam, items: items)
        // One review moves to today, and today's day holds the same number: the plan is otherwise the same shape.
        XCTAssertEqual(pinned.days[0].reviews, plain.days[0].reviews)
        XCTAssertEqual(pinned.days.count, plain.days.count)
        XCTAssertNotEqual(pinned.curve.last, plain.curve.last, "and the projection follows what moved")
    }

    func testNewMaterialIsInByThreeDaysBeforeTheExam() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 20, to: now))
        let plan = builder().plan(for: exam, items: world())
        let today = cal.dayNumber(for: now), examDay = cal.dayNumber(for: exam.date)
        XCTAssertEqual(plan.daysLeft, 20)
        XCTAssertEqual(plan.days.count, 21, "today through exam day")
        XCTAssertEqual(plan.days.reduce(0) { $0 + $1.newItems }, 30)
        XCTAssertTrue(plan.days.filter { $0.dayNumber > examDay - 3 }.allSatisfy { $0.newItems == 0 })
        XCTAssertEqual(plan.lastIntroDay, cal.startOfDay(dayNumber: examDay - 3))
        XCTAssertEqual(plan.days.first?.isToday, true)
        XCTAssertEqual(plan.days.first?.dayNumber, today)
        XCTAssertEqual(plan.days.last?.kind, .exam)
    }

    func testTheLastEveningIsTheExamEve() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let plan = builder().plan(for: exam, items: world())
        let eve = plan.days[plan.days.count - 2]
        XCTAssertEqual(eve.kind, .examEve)
        XCTAssertEqual(eve.newItems, 0)
        XCTAssertEqual(plan.examEve, eve.date)
        XCTAssertEqual(plan.days.filter { $0.kind == .examEve }.count, 1)
    }

    func testEasyDaysGetNoNewMaterialAndALighterSession() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let saturday = 7
        let plan = builder(easyDays: [saturday]).plan(for: exam, items: world())
        let easy = plan.days.filter(\.isEasyDay)
        XCTAssertFalse(easy.isEmpty)
        for day in easy where day.kind != .examEve && day.kind != .exam {
            XCTAssertEqual(day.newItems, 0)
            XCTAssertTrue(day.kind == .light || day.kind == .rest)
        }
        XCTAssertEqual(plan.days.reduce(0) { $0 + $1.newItems }, 30)
        let normal = plan.days.first { !$0.isEasyDay && $0.kind == .study }!
        XCTAssertGreaterThanOrEqual(normal.sessionMinutes, 15)
    }

    func testTheCurveRisesToTheProjection() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 23, to: now), target: 0.9)
        let plan = builder().plan(for: exam, items: world())
        XCTAssertEqual(plan.curve.count, 24, "now, then each morning to exam day")
        XCTAssertFalse(plan.curve[0].isProjection)
        XCTAssertTrue(plan.curve.dropFirst().allSatisfy(\.isProjection))
        XCTAssertEqual(plan.projectedReadiness, plan.curve.last!.value)
        XCTAssertGreaterThan(plan.projectedReadiness, plan.currentReadiness + 0.3)
        XCTAssertGreaterThan(plan.projectedReadiness, 0.8)
        if let reached = plan.targetReachedOn {
            XCTAssertGreaterThanOrEqual(plan.curve.first { $0.date == reached }!.value, 0.9)
        }
        XCTAssertEqual(plan.curve.last!.date, cal.startOfDay(for: exam.date))
    }

    /// Miss a day: the following days absorb it (the new material still goes in by three days before, and the
    /// overdue reviews spread instead of piling onto one day).
    func testThePlanBendsAfterAMissedDay() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 12, to: now))
        let items = world(new: 40, studied: 150)
        let planned = builder().plan(for: exam, items: items)
        let tomorrow = cal.adding(days: 1, to: now)
        let bent = builder(at: tomorrow).plan(for: exam, items: items) // nothing was studied today
        let examDay = cal.dayNumber(for: exam.date)
        XCTAssertEqual(bent.days.reduce(0) { $0 + $1.newItems }, 40)
        XCTAssertTrue(bent.days.filter { $0.dayNumber > examDay - 3 }.allSatisfy { $0.newItems == 0 })
        // The new items planned for the missed day are spread over the days left, not dumped on tomorrow. (A session's own floor may already cover the spread.)
        let firstPlanned = planned.days.first!.newItems
        XCTAssertGreaterThanOrEqual(bent.days.first!.newItems, planned.days[1].newItems)
        XCTAssertLessThan(bent.days.first!.newItems, planned.days[1].newItems + firstPlanned)
        // 150 overdue reviews (more than a day's 15 minutes) spread over the next three days.
        XCTAssertLessThan(bent.days[0].reviews, 120)
        XCTAssertGreaterThan(bent.days[1].reviews, 30)
        XCTAssertGreaterThan(bent.days[2].reviews, 30)
    }

    func testAPlanAcrossTheDaylightSavingChangeCountsCalendarDays() {
        // Oct 22 → Nov 14 crosses the end of US daylight saving (Nov 1): still 23 days, one entry per day.
        let exam = ExamSnapshot(courseID: course, date: EngineTest.date(2026, 11, 14, 9, in: cal))
        let plan = builder().plan(for: exam, items: world())
        XCTAssertEqual(plan.daysLeft, 23)
        XCTAssertEqual(plan.days.count, 24)
        let keys = plan.days.map { cal.dayKey(for: $0.date.addingTimeInterval(12 * 3600)) }
        XCTAssertEqual(Set(keys).count, 24)
        XCTAssertEqual(keys.first, "2026-10-22")
        XCTAssertEqual(keys.last, "2026-11-14")
        XCTAssertTrue(plan.days.allSatisfy { cal.component(.hour, from: $0.date) == 0 })
    }

    func testAnExamTomorrowIsAllEve() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 1, to: now))
        let plan = builder().plan(for: exam, items: world(new: 3, studied: 5))
        XCTAssertEqual(plan.days.map(\.kind), [.examEve, .exam])
        XCTAssertEqual(plan.days[0].newItems, 3, "with one day left the new material goes in today")
    }

    func testSuggestsMoreMinutesWhenTheGoalIsTooSmall() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 4, to: now))
        let items = (0..<120).map { _ in EngineTest.fresh(kind: .recall, course: course) }
        let plan = builder(minutes: 10).plan(for: exam, items: items)
        XCTAssertNotNil(plan.suggestedMinutes)
        XCTAssertEqual(plan.suggestedMinutes! % 5, 0)
        XCTAssertGreaterThan(plan.suggestedMinutes!, 10)
    }

    func testNoItemsNoPlan() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 9, to: now))
        let plan = builder().plan(for: exam, items: [])
        XCTAssertEqual(plan.projectedReadiness, 0)
        XCTAssertEqual(plan.itemsInScope, 0)
    }

    /// A big library still plans in a moment: every upcoming exam is planned again after each change (`AppModel.examPlans()`), and
    /// each simulated question follows up to eight branches.
    func testABigLibraryPlansQuickly() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 30, to: now))
        let items = world(new: 500, studied: 2_500)
        var b = builder()
        b.capacity = Dictionary(uniqueKeysWithValues: (0..<30).map { ($0, 900.0) })
        let start = Date()
        let plan = b.plan(for: exam, items: items)
        let elapsed = Date().timeIntervalSince(start)
        print("Plan for 3,000 questions over 30 days: \(Int(elapsed * 1000)) ms, \(plan.reviewsPlanned) reviews")
        XCTAssertGreaterThan(plan.reviewsPlanned, 1_000)
        XCTAssertLessThan(elapsed, 1.0)
    }

    // MARK: Honest projections

    /// The eve's review at 18:00 before a 10:00 exam leaves 16 hours to forget in. Counted in whole days that was "0 days" and
    /// certain recall, whatever the question's stability.
    func testAReviewTheEveningBeforeIsNotCertainRecall() {
        let afternoon = EngineTest.date(2026, 10, 22, 14, in: cal)
        let exam = ExamSnapshot(courseID: course, date: EngineTest.date(2026, 10, 23, 10, in: cal), target: 0.9)
        let last = EngineTest.date(2026, 10, 21, 18, in: cal)
        let weak = EngineTest.item(MemoryState(state: .review, stability: 0.05, difficulty: 8, due: afternoon, lastReview: last,
                                               reps: 3, lapses: 1), course: course)
        var b = builder(at: afternoon)
        b.adherence = 1
        let plan = b.plan(for: exam, items: [weak])
        XCTAssertEqual(plan.days.map(\.kind), [.examEve, .exam])
        XCTAssertEqual(plan.days[0].reviews, 1, "reviewed on the eve")
        XCTAssertLessThan(plan.projectedReadiness, 0.9, "not certain: \(plan.projectedReadiness)")
        XCTAssertGreaterThan(plan.projectedReadiness, plan.currentReadiness)
        // Exactly the expected review at 18:00, read 16 hours later.
        let step = FSRS().expectedReview(stability: 0.05, difficulty: 8, last: last, at: EngineTest.date(2026, 10, 22, 18, in: cal))
        XCTAssertEqual(plan.projectedReadiness, step.recall(at: exam.date, fsrs: FSRS()), accuracy: 1e-9)
    }

    /// An answer is right or wrong, not the average of the two: recall after a review is the expectation over both outcomes, which is
    /// below the recall of the mean stability whenever a lapse is possible. The stabilities are the scheduler's.
    func testRecallIsExpectedOverRightAndWrong() {
        let fsrs = FSRS()
        let last = cal.adding(days: -4, to: now)
        let exam = cal.adding(days: 6, to: now)
        let step = fsrs.expectedReview(stability: 2, difficulty: 6, last: last, at: now)
        XCTAssertEqual(step.p, fsrs.forecastRecall(stability: 2, last: last, at: now), accuracy: 1e-12)
        XCTAssertGreaterThan(step.p, 0.5)
        XCTAssertLessThan(step.p, 1)
        let expected = step.p * fsrs.forecastRecall(stability: step.sGood, last: now, at: exam)
            + (1 - step.p) * fsrs.forecastRecall(stability: step.sLapse, last: now, at: exam)
        XCTAssertEqual(step.recall(at: exam, fsrs: fsrs), expected, accuracy: 1e-12)
        XCTAssertLessThan(step.recall(at: exam, fsrs: fsrs), fsrs.forecastRecall(stability: step.meanStability, last: now, at: exam))
        XCTAssertEqual(step.meanStability, step.p * step.sGood + (1 - step.p) * step.sLapse, accuracy: 1e-12,
                       "the mean is what scheduling carries on")
        // What answering would store: Good, or Again and then its learning step.
        let memory = MemoryState(state: .review, stability: 2, difficulty: 6, due: now, lastReview: last, reps: 3)
        XCTAssertEqual(fsrs.review(memory, rating: .good, at: now).memory.stability, step.sGood, accuracy: 1e-12)
        let forgot = fsrs.review(memory, rating: .again, at: now).memory
        XCTAssertEqual(fsrs.review(forgot, rating: .good, at: now.addingTimeInterval(600)).memory.stability, step.sLapse,
                       accuracy: 1e-12)
        // A first look: right at the first-try rate.
        let look = fsrs.expectedFirstLook(success: 0.75, at: now)
        XCTAssertEqual(look.p, 0.75)
        XCTAssertGreaterThan(look.sGood, look.sLapse)
    }

    /// With a share of each day (another exam's work comes first), the plan holds only what fits: reviews that don't fit move on to
    /// the next day and new material to the next day that isn't the eve. The suggestion still reads what the exam alone needs.
    func testThePlanFitsTheDayItIsGiven() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let items = world(new: 40, studied: 150)
        let free = builder().plan(for: exam, items: items)
        var b = builder()
        b.capacity = Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, $0 == 9 ? PlanBuilder.examEveSeconds : 300.0) })
        let tight = b.plan(for: exam, items: items)
        XCTAssertEqual(tight.days.map(\.offset), Array(0...10))
        for day in tight.days where day.kind != .exam {
            XCTAssertLessThanOrEqual(day.seconds, (b.capacity?[day.offset] ?? 0) + 1e-9, "day \(day.offset)")
            XCTAssertEqual(day.minutes, day.seconds > 0 ? max(1, Int((day.seconds / 60).rounded(.up))) : 0)
        }
        XCTAssertGreaterThan(free.days[0].seconds, 300, "alone, the exam takes more than five minutes today")
        XCTAssertLessThan(tight.projectedReadiness, free.projectedReadiness)
        XCTAssertTrue(free.days.allSatisfy { abs($0.seconds - $0.neededSeconds) < 1e-9 }, "no limit: everything fits")
        XCTAssertGreaterThan(tight.days[0].neededSeconds, tight.days[0].seconds)
        XCTAssertGreaterThan(tight.days.dropFirst().reduce(0) { $0 + $1.reviews }, 0, "what didn't fit came later")

        // A goal far too small: nothing new fits, and the suggestion reads what the exam needs, not the little it was given.
        let quiz = ExamSnapshot(courseID: course, date: cal.adding(days: 4, to: now))
        let crowded = (0..<120).map { _ in EngineTest.fresh(kind: .recall, course: course) }
        var small = builder(minutes: 10)
        small.capacity = [0: 60, 1: 60, 2: 60, 3: PlanBuilder.examEveSeconds]
        let squeezed = small.plan(for: quiz, items: crowded)
        XCTAssertTrue(squeezed.days.allSatisfy { $0.seconds <= 60 || $0.kind == .examEve })
        XCTAssertEqual(squeezed.days.reduce(0) { $0 + $1.newItems }, 0, "a first look takes 100 seconds")
        XCTAssertEqual(squeezed.suggestedMinutes, builder(minutes: 10).plan(for: quiz, items: crowded).suggestedMinutes)
        XCTAssertGreaterThan(squeezed.suggestedMinutes ?? 0, 10)
    }

    /// "What if I skip Saturday?": no work that day, its reviews move on and no new material is spread there. Skipping the eve costs
    /// its weak spots; a day in the middle of a plan can cost next to nothing, since its reviews land a day nearer the exam (the
    /// exam page says "almost nothing" under two points).
    func testSkippingADayCostsReadiness() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 6, to: now))
        let items = world(new: 12, studied: 40)
        let plan = builder().plan(for: exam, items: items)
        var b = builder()
        b.skipping = [1]
        let skipped = b.plan(for: exam, items: items)
        XCTAssertGreaterThan(plan.days[1].seconds, 0, "the day had work")
        let off = skipped.days[1]
        XCTAssertTrue(off.isSkipped)
        XCTAssertEqual(off.kind, .rest)
        XCTAssertEqual(off.seconds, 0)
        XCTAssertEqual(off.reviews, 0)
        XCTAssertEqual(off.newItems, 0)
        XCTAssertEqual(off.sessionMinutes, 0)
        XCTAssertEqual(skipped.days.reduce(0) { $0 + $1.newItems }, 12, "the new material goes in on the other days")
        XCTAssertGreaterThanOrEqual(skipped.days[2].reviews, plan.days[2].reviews, "its reviews moved on")
        XCTAssertLessThan(skipped.projectedReadiness, plan.projectedReadiness + 0.01)
        XCTAssertFalse(plan.days.contains(where: \.isSkipped))

        // The eve: its weak spots are lost.
        var noEve = builder()
        noEve.skipping = [5]
        let lostEve = noEve.plan(for: exam, items: items)
        XCTAssertEqual(lostEve.days[5].kind, .examEve)
        XCTAssertEqual(lostEve.days[5].reviews, 0)
        XCTAssertGreaterThan(plan.days[5].reviews, 0)
        XCTAssertLessThan(lostEve.projectedReadiness, plan.projectedReadiness - 0.005)
        XCTAssertEqual(PlanMath.newItemsPerDay(unseen: 6, today: 0, examDay: 4, isEasyDay: { _ in false }, isSkipped: { $0 == 0 }),
                       [1: 6], "with one day left to spread over, all of it")
    }
}
