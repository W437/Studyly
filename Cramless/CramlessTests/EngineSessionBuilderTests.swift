import Foundation
import XCTest
@testable import Cramless

final class EngineSessionBuilderTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID()
    let topics = (0..<4).map { _ in UUID() }
    lazy var names: [UUID: String] = Dictionary(uniqueKeysWithValues: topics.enumerated().map { ($1, "Topic \($0)") })

    func builder(minutes: Int = 15, easyDays: [Int] = []) -> SessionBuilder {
        SessionBuilder(settings: EngineTest.settings(dailyMinutes: minutes, easyDays: easyDays), calendar: cal, now: now)
    }

    /// Due reviews over three topics (topic 2 weak), strong not-due items, and new items in topic 3.
    func world() -> [ItemSnapshot] {
        let kinds: [ItemKind] = [.flashcard, .mcq, .cloze, .recall]
        var items: [ItemSnapshot] = []
        for i in 0..<15 {
            let topic = topics[i % 3]
            let recall = topic == topics[2] ? 0.5 + Double(i % 3) * 0.02 : 0.84 + Double(i % 4) * 0.015
            items.append(EngineTest.studied(kind: kinds[i % kinds.count], topic: topic, course: course, recall: recall,
                                            daysAgo: 4 + i % 3, now: now, cal: cal))
        }
        for i in 0..<6 {
            items.append(EngineTest.studied(kind: kinds[i % kinds.count], topic: topics[i % 2], course: course,
                                            recall: 0.97, daysAgo: 1, now: now, cal: cal))
        }
        for i in 0..<8 {
            items.append(EngineTest.fresh(kind: kinds[i % kinds.count], topic: topics[3], course: course,
                                          createdAt: cal.adding(days: -10 + i, to: now)))
        }
        return items
    }

    func testASessionOfOnlySomeKinds() {
        let items = world()
        let plain = builder().build(SessionSpec(kind: .daily), items: items, topicNames: names)
        XCTAssertTrue(Set(plain.entries.map(\.kind)).contains(.mcq))
        let spoken = builder().build(SessionSpec(kind: .daily, kinds: [.flashcard, .recall]), items: items, topicNames: names)
        XCTAssertFalse(spoken.entries.isEmpty)
        XCTAssertEqual(Set(spoken.entries.map(\.kind)), [.flashcard, .recall])
        XCTAssertEqual(builder().build(SessionSpec(kind: .practice, kinds: []), items: items, topicNames: names).entries, [])
    }

    func testSpokenQuestionsTakeLonger() {
        let items = world()
        let plain = builder().build(SessionSpec(kind: .daily), items: items, topicNames: names)
        var spoken = builder()
        spoken.costsSpoken = true
        let out = spoken.build(SessionSpec(kind: .daily), items: items, topicNames: names)
        XCTAssertLessThan(out.entries.count, plain.entries.count, "the same minutes hold fewer")
        XCTAssertEqual(out.entries.first.map { $0.estimatedSeconds >= OutLoudPolicy.spokenSeconds($0.kind) }, true)
        XCTAssertLessThanOrEqual(out.plannedSeconds, 15 * 60 + OutLoudPolicy.spokenSeconds(.apply) * 2)
    }

    func testASessionLeavesOutWhatItIsToldTo() {
        let items = world()
        let plain = builder().build(SessionSpec(kind: .daily), items: items, topicNames: names)
        let first = plain.entries[0].itemID
        let without = builder().build(SessionSpec(kind: .daily, excludedItemIDs: [first]), items: items, topicNames: names)
        XCTAssertFalse(without.entries.contains { $0.itemID == first })
    }

    func testFocusQuestionsComeFirstAndNothingChangesWithoutThem() {
        let items = world()
        let plain = builder().build(SessionSpec(kind: .daily), items: items, topicNames: names)
        let same = builder().build(SessionSpec(kind: .daily, focusItemIDs: []), items: items, topicNames: names)
        XCTAssertEqual(plain.entries.map(\.itemID), same.entries.map(\.itemID))

        // A tiny budget, and a due question that wouldn't otherwise make it (the highest recall of the due ones).
        let due = items.filter { ($0.memory.due ?? .distantFuture) < cal.adding(days: 1, to: cal.startOfDay(for: now)) && $0.isStudied }
        let strongest = due.max { fsrsRecall($0) < fsrsRecall($1) }!
        let small = builder().build(SessionSpec(kind: .daily, minutes: 1), items: items, topicNames: names)
        XCTAssertFalse(small.entries.contains { $0.itemID == strongest.id })
        let focused = builder().build(SessionSpec(kind: .daily, minutes: 1, focusItemIDs: [strongest.id]), items: items, topicNames: names)
        XCTAssertTrue(focused.entries.contains { $0.itemID == strongest.id }, "in, ahead of the rest")
    }

    func testAFocusQuestionNoLongerDueIsLeftOut() {
        let items = world()
        let solid = items.first { ($0.memory.due ?? .distantPast) > cal.adding(days: 1, to: now) }!
        let built = builder().build(SessionSpec(kind: .daily, minutes: 2, focusItemIDs: [solid.id]), items: items, topicNames: names)
        XCTAssertFalse(built.entries.contains { $0.itemID == solid.id && $0.reason == .due })
    }

    private func fsrsRecall(_ item: ItemSnapshot) -> Double { FSRS().retrievability(of: item.memory, at: now) }

    func testDailyMixesDueNewAndWeakSpots() {
        let built = builder().build(SessionSpec(kind: .daily), items: world(), topicNames: names)
        XCTAssertGreaterThan(built.reviewCount, 8)
        XCTAssertGreaterThan(built.newCount, 0)
        XCTAssertLessThanOrEqual(built.newCount, 5)
        XCTAssertEqual(built.weakSpots.first?.name, "Topic 2")
        XCTAssertEqual(built.weakChips.count, built.weakSpots.count)
        XCTAssertLessThanOrEqual(built.plannedSeconds, built.budgetSeconds + 0.5)
        XCTAssertEqual(Set(built.entries.map(\.itemID)).count, built.entries.count, "no item twice")
        XCTAssertNil(built.catchUp)
        XCTAssertEqual(built.dueTotal, 15)
        for e in built.entries { XCTAssertEqual(e.estimatedSeconds, e.reason == .new ? e.kind.typicalSeconds * 2 : e.kind.typicalSeconds) }
    }

    // MARK: After an exam

    /// `count` reviews overdue on `course`.
    private func due(_ count: Int, course: UUID, recall: Double = 0.5) -> [ItemSnapshot] {
        (0..<count).map { _ in EngineTest.studied(kind: .mcq, topic: topics[0], course: course, recall: recall, daysAgo: 5, now: now, cal: cal) }
    }

    /// The day after one exam: its reviews used to fill the review share, and the next exam's new questions stopped at 40%, so the next exam
    /// got half its plan. Questions only on a finished exam now wait behind everything for one still to come.
    func testQuestionsWhoseExamIsOverWaitBehindTheNextExam() {
        let next = UUID()
        let over = ExamSnapshot(courseID: course, title: "Networks final", date: cal.adding(days: -1, to: now))
        let apush = ExamSnapshot(courseID: next, title: "APUSH exam", date: cal.adding(days: 3, to: now))
        let items = due(60, course: course) + (0..<90).map { _ in EngineTest.fresh(kind: .mcq, topic: topics[1], course: next, createdAt: cal.adding(days: -2, to: now)) }
        let built = builder(minutes: 25).build(SessionSpec(kind: .daily), items: items, exams: [over, apush], topicNames: names)
        XCTAssertLessThanOrEqual(built.entries.filter { $0.courseID == course }.count, 1, "only the seconds no new question fits into")
        let forNext = built.entries.filter { $0.examID == apush.id }.reduce(0) { $0 + $1.estimatedSeconds }
        XCTAssertGreaterThan(forNext, 0.8 * built.budgetSeconds)
        XCTAssertNil(built.catchUp, "they aren't a backlog either")
        XCTAssertEqual(built.dueTotal, 0)
        XCTAssertTrue(built.weakSpots.isEmpty, "nor a weak spot")
    }

    func testWithTimeLeftTheyStillComeUp() {
        let next = UUID()
        let over = ExamSnapshot(courseID: course, date: cal.adding(days: -1, to: now))
        let apush = ExamSnapshot(courseID: next, date: cal.adding(days: 3, to: now))
        let items = due(40, course: course) + due(2, course: next, recall: 0.8)
        let built = builder(minutes: 15).build(SessionSpec(kind: .daily), items: items, exams: [over, apush], topicNames: names)
        XCTAssertEqual(built.entries.filter { $0.courseID == next }.count, 2, "the next exam's first")
        XCTAssertGreaterThan(built.entries.filter { $0.courseID == course && $0.reason == .due }.count, 5, "then what's left of the day")
        XCTAssertLessThanOrEqual(built.plannedSeconds, built.budgetSeconds + 0.5)
    }

    func testWithNoExamToComeTheyAreJustReviews() {
        let over = ExamSnapshot(courseID: course, date: cal.adding(days: -1, to: now))
        let items = due(10, course: course)
        let alone = builder(minutes: 15).build(SessionSpec(kind: .daily), items: items, exams: [over], topicNames: names)
        XCTAssertEqual(alone.dueTotal, 10)
        XCTAssertEqual(alone.reviewCount, builder(minutes: 15).build(SessionSpec(kind: .daily), items: items, topicNames: names).reviewCount)
    }

    /// A course that never had an exam isn't "over": it keeps its place among the reviews, by recall.
    func testACourseThatNeverHadAnExamKeepsItsPlace() {
        let spanish = UUID(), bio = UUID()
        let midterm = ExamSnapshot(courseID: bio, date: cal.adding(days: 20, to: now))
        let items = due(3, course: spanish, recall: 0.4) + due(3, course: bio, recall: 0.8)
        let built = builder(minutes: 15).build(SessionSpec(kind: .daily), items: items, exams: [midterm], topicNames: names)
        XCTAssertEqual(built.entries.filter { $0.courseID == spanish }.count, 3)
        XCTAssertEqual(built.dueTotal, 6)
    }

    /// A quiz on one topic is over, the final on the whole course isn't: its questions are still for the final.
    func testAQuestionStillOnALaterExamIsNotDoneWith() {
        let quiz = ExamSnapshot(courseID: course, date: cal.adding(days: -1, to: now), scope: [topics[0]])
        let final = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let built = builder(minutes: 15).build(SessionSpec(kind: .daily), items: due(5, course: course), exams: [quiz, final], topicNames: names)
        XCTAssertEqual(built.entries.filter { $0.examID == final.id }.count, 5)
        XCTAssertEqual(built.dueTotal, 5)
    }

    func testAMixUpOnAFinishedExamWaitsToo() {
        let next = UUID()
        let over = ExamSnapshot(courseID: course, date: cal.adding(days: -1, to: now))
        let apush = ExamSnapshot(courseID: next, date: cal.adding(days: 3, to: now))
        let old = due(4, course: course)
        let mixUp = ConfusionSnapshot(id: UUID(), courseID: course, name: "TCP vs UDP", itemIDs: old.map(\.id), status: .open)
        let items = old + (0..<40).map { _ in EngineTest.fresh(kind: .mcq, topic: topics[1], course: next, createdAt: cal.adding(days: -2, to: now)) }
        let built = builder(minutes: 15).build(SessionSpec(kind: .daily), items: items, exams: [over, apush], confusions: [mixUp], topicNames: names)
        XCTAssertTrue(built.weakSpots.isEmpty)
        XCTAssertEqual(built.entries.filter { $0.courseID == course }.count, 0)
    }

    // MARK: Two exams on one day

    /// They share the evening: one session with each exam's own weak spots, up to 10 minutes each, whichever page starts it.
    func testExamsOnOneDayShareTheEvening() {
        let other = UUID()
        let a = ExamSnapshot(courseID: course, title: "Hydrology", date: cal.adding(days: 1, to: now), target: 0.9)
        let b = ExamSnapshot(courseID: other, title: "Org Chem", date: cal.adding(days: 1, to: now).addingTimeInterval(3 * 3600), target: 0.9)
        let later = ExamSnapshot(courseID: UUID(), title: "Later", date: cal.adding(days: 2, to: now))
        let items = due(60, course: course) + due(60, course: other)
        let spec = SessionSpec(kind: .examEve, examID: a.id)
        let built = builder().build(spec, items: items, exams: [a, b, later], topicNames: names)
        XCTAssertEqual(built.examID, a.id, "tracked under the one it started from")
        XCTAssertEqual(built.budgetSeconds, 1200)
        XCTAssertEqual(Set(built.entries.compactMap(\.examID)), [a.id, b.id])
        for exam in [a, b] {
            let seconds = built.entries.filter { $0.examID == exam.id }.reduce(0) { $0 + $1.estimatedSeconds }
            XCTAssertGreaterThan(seconds, 300, exam.title)
            XCTAssertLessThanOrEqual(seconds, 600, "each up to its 10 minutes")
        }
        XCTAssertEqual(built.tonightMinutes, built.plannedMinutes)
        XCTAssertGreaterThan(built.tonightMinutes, 10)
        XCTAssertNil(built.courseID, "two courses")
        let fromTheOther = builder().build(SessionSpec(kind: .examEve, examID: b.id), items: items, exams: [a, b, later], topicNames: names)
        XCTAssertEqual(fromTheOther.examID, b.id)
        XCTAssertEqual(Set(fromTheOther.entries.map(\.itemID)), Set(built.entries.map(\.itemID)), "the same evening")
        // An exam alone keeps its evening to itself.
        let alone = builder().build(SessionSpec(kind: .examEve, examID: later.id), items: items, exams: [a, b, later], topicNames: names)
        XCTAssertEqual(alone.budgetSeconds, 600)
        XCTAssertLessThanOrEqual(alone.tonightMinutes, 10)
    }

    func testNoTopicTwiceInARowWhenAvoidable() {
        let built = builder(minutes: 30).build(SessionSpec(kind: .daily), items: world(), topicNames: names)
        let topicsInOrder = built.entries.map(\.topicID)
        var repeats = 0
        for i in 1..<topicsInOrder.count where topicsInOrder[i] != nil && topicsInOrder[i] == topicsInOrder[i - 1] {
            repeats += 1
        }
        XCTAssertEqual(repeats, 0, "\(topicsInOrder)")
        // Formats are mixed too.
        let kindRepeats = (1..<built.entries.count).filter { built.entries[$0].kind == built.entries[$0 - 1].kind }.count
        XCTAssertLessThan(kindRepeats, built.entries.count / 3)
    }

    func testInterleaveKeepsUnavoidableRepeats() {
        let t = UUID()
        let entries = (0..<4).map { _ in SessionEntry(itemID: UUID(), reason: .due, kind: .mcq, topicID: t, estimatedSeconds: 16) }
        XCTAssertEqual(SessionBuilder.interleave(entries).count, 4)
    }

    func testOpensWithTheEasiestItemNeverTheHardest() {
        let items = world()
        let built = builder().build(SessionSpec(kind: .daily), items: items, topicNames: names)
        let fsrs = FSRS()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let recalls = built.entries.compactMap { byID[$0.itemID] }.filter(\.isStudied)
            .map { fsrs.retrievability(of: $0.memory, at: now) }
        let first = fsrs.retrievability(of: byID[built.entries[0].itemID]!.memory, at: now)
        XCTAssertEqual(first, recalls.max()!, accuracy: 1e-9)
        XCTAssertGreaterThan(first, recalls.min()!)
    }

    func testNewItemsAreSpreadThroughTheSession() {
        let built = builder(minutes: 30).build(SessionSpec(kind: .daily), items: world(), topicNames: names)
        let positions = built.entries.enumerated().filter { $0.element.reason == .new }.map(\.offset)
        XCTAssertGreaterThan(positions.count, 1)
        XCTAssertLessThan(Double(positions.max()!), Double(built.entries.count) * 0.9)
        XCTAssertGreaterThan(positions.max()! - positions.min()!, 2)
    }

    func testCatchUpModeForABigBacklog() {
        var items: [ItemSnapshot] = []
        for i in 0..<400 {
            items.append(EngineTest.studied(kind: .flashcard, topic: topics[i % 3], course: course, recall: 0.6 + Double(i % 10) / 100,
                                            daysAgo: 12, now: now, cal: cal))
        }
        items += (0..<10).map { _ in EngineTest.fresh(topic: topics[3], course: course) }
        let built = builder().build(SessionSpec(kind: .daily), items: items, topicNames: names)
        let info = try? XCTUnwrap(built.catchUp)
        XCTAssertEqual(info?.backlog, 400)
        XCTAssertEqual(info?.daysToClear, Int((400 * 9.0 / 900).rounded(.up)))
        XCTAssertEqual(built.newCount, 0, "no new material while catching up")
        XCTAssertTrue(built.weakSpots.isEmpty)
        XCTAssertLessThanOrEqual(built.plannedSeconds, 900)
        XCTAssertGreaterThan(built.reviewCount, 80)
        // Lowest recall first.
        let fsrs = FSRS()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let maxPicked = built.entries.map { fsrs.retrievability(of: byID[$0.itemID]!.memory, at: now) }.max()!
        XCTAssertLessThan(maxPicked, 0.66)
    }

    func testAShorterDayIsNotACatchUpDay() {
        // 15 minutes of questions due: nothing unusual on a 15-minute day, but over twice a 5-minute one.
        let items = (0..<100).map { i in
            EngineTest.studied(kind: .flashcard, topic: topics[i % 3], course: course, recall: 0.8, daysAgo: 12, now: now, cal: cal)
        }
        XCTAssertNotNil(builder().build(SessionSpec(kind: .daily, minutes: 5), items: items, topicNames: names).catchUp)
        let busy = builder().build(SessionSpec(kind: .daily, minutes: 5, backlogMinutes: 15), items: items, topicNames: names)
        XCTAssertNil(busy.catchUp, "a long day gave its minutes away; nothing has fallen behind")
        XCTAssertLessThanOrEqual(busy.plannedSeconds, 300)
        // A real backlog still is one.
        let many = (0..<400).map { i in
            EngineTest.studied(kind: .flashcard, topic: topics[i % 3], course: course, recall: 0.8, daysAgo: 12, now: now, cal: cal)
        }
        let behind = builder().build(SessionSpec(kind: .daily, minutes: 5, backlogMinutes: 15), items: many, topicNames: names)
        XCTAssertEqual(behind.catchUp?.daysToClear, Int((400 * 9.0 / 900).rounded(.up)), "counted in usual days")
    }

    func testCatchUpPutsTheNearestExamFirst() {
        let examCourse = UUID()
        let exam = ExamSnapshot(courseID: examCourse, date: cal.adding(days: 4, to: now))
        var items: [ItemSnapshot] = []
        for i in 0..<300 {
            items.append(EngineTest.studied(topic: topics[i % 3], course: i % 2 == 0 ? examCourse : course,
                                            recall: i % 2 == 0 ? 0.8 : 0.5, daysAgo: 12, now: now, cal: cal))
        }
        let built = builder().build(SessionSpec(kind: .daily), items: items, exams: [exam], topicNames: names)
        XCTAssertNotNil(built.catchUp)
        XCTAssertTrue(built.entries.allSatisfy { $0.courseID == examCourse }, "the exam's items fill today first")
    }

    func testExamEveIsWeakSpotsInScopeOnly() {
        let items = world()
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 1, to: now), scope: [topics[1], topics[2]],
                                target: 0.9)
        let built = builder().build(SessionSpec(kind: .examEve, examID: exam.id), items: items, exams: [exam],
                                    topicNames: names)
        XCTAssertTrue(built.stopsAfter)
        XCTAssertLessThanOrEqual(built.plannedSeconds, 600)
        XCTAssertFalse(built.entries.isEmpty)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let engine = SessionBuilder(settings: AppSettings(), calendar: cal, now: now)
        for e in built.entries {
            let item = byID[e.itemID]!
            XCTAssertTrue(exam.covers(item))
            XCTAssertTrue(item.isStudied, "no new material the night before")
            XCTAssertLessThan(engine.examRecall(item.memory, on: exam.date), 0.9)
            XCTAssertEqual(e.reason, .weak)
        }
    }

    func testExamEveIsCappedAtTenMinutes() {
        let items = (0..<200).map { i in
            EngineTest.studied(kind: .recall, topic: topics[i % 3], course: course, recall: 0.5, daysAgo: 6, now: now, cal: cal)
        }
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 1, to: now))
        let built = builder().build(SessionSpec(kind: .examEve, minutes: 30, examID: exam.id), items: items, exams: [exam])
        XCTAssertLessThanOrEqual(built.plannedSeconds, 600)
        XCTAssertEqual(built.entries.count, 12) // 12 × 50 s
    }

    func testFixPutsTheLessonQuestionsFirst() {
        let a = EngineTest.studied(topic: topics[0], course: course, recall: 0.7, daysAgo: 3, now: now, cal: cal)
        let b = EngineTest.studied(topic: topics[0], course: course, recall: 0.6, daysAgo: 3, now: now, cal: cal)
        let f1 = EngineTest.fresh(kind: .mcq, topic: topics[0], course: course)
        let f2 = EngineTest.fresh(kind: .mcq, topic: topics[0], course: course)
        let confusion = ConfusionSnapshot(id: UUID(), courseID: course, name: "Anaphase vs telophase",
                                          itemIDs: [a.id, b.id], fixItemIDs: [f1.id, f2.id])
        let built = builder().build(SessionSpec(kind: .fix, confusionID: confusion.id), items: [a, b, f1, f2],
                                    confusions: [confusion])
        XCTAssertEqual(built.entries.map(\.itemID), [f1.id, f2.id, a.id, b.id])
        XCTAssertEqual(built.weakSpots.first?.name, "Anaphase vs telophase")
    }

    func testQuickCheckKeepsTheGivenOrder() {
        let items = world()
        let picks = [items[20].id, items[3].id]
        let built = builder().build(SessionSpec(kind: .quickCheck, itemIDs: picks), items: items)
        XCTAssertEqual(built.entries.map(\.itemID), picks)
    }

    func testPracticeOneTopic() {
        let built = builder().build(SessionSpec(kind: .practice, topicID: topics[0]), items: world(), topicNames: names)
        XCTAssertFalse(built.entries.isEmpty)
        XCTAssertTrue(built.entries.allSatisfy { $0.topicID == topics[0] })
        XCTAssertTrue(built.entries.contains { $0.reason == .practice }, "not-due items as extra practice")
    }

    func testExamPriorityPullsInItemsTheExamNeeds() {
        // Not due until after the exam, but under target on exam day.
        let item = EngineTest.studied(topic: topics[0], course: course, recall: 0.95, daysAgo: 1, now: now, cal: cal)
        var late = item
        late.memory.due = cal.adding(days: 10, to: now)
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 2, to: now), target: 0.99)
        let built = builder().build(SessionSpec(kind: .daily), items: [late], exams: [exam])
        XCTAssertEqual(built.entries.map(\.reason), [.examPriority])
        // A week before the exam it isn't pulled yet.
        let far = ExamSnapshot(courseID: course, date: cal.adding(days: 7, to: now), target: 0.99)
        XCTAssertTrue(builder().build(SessionSpec(kind: .daily), items: [late], exams: [far]).entries.isEmpty)
    }

    func testNewMaterialFollowsTheExamPlan() {
        let fresh = (0..<20).map { i in EngineTest.fresh(topic: topics[i % 3], course: course, createdAt: cal.adding(days: -1, to: now)) }
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 5, to: now))
        let built = builder().build(SessionSpec(kind: .daily), items: fresh, exams: [exam])
        // In by 3 days before: today, tomorrow and the day after share 20 → 7 today.
        XCTAssertEqual(built.newCount, 7)
        XCTAssertEqual(PlanMath.newItemsPerDay(unseen: 20, today: 0, examDay: 5, isEasyDay: { _ in false }), [0: 7, 1: 7, 2: 6])
    }

    /// Each question carries the soonest upcoming exam that covers it (what `SessionFocus` reads); an eve session's carry its exam.
    func testEntriesCarryTheSoonestCoveringExam() {
        let items = world()
        let quiz = ExamSnapshot(courseID: course, title: "Quiz", date: cal.adding(days: 3, to: now), scope: [topics[2]])
        let midterm = ExamSnapshot(courseID: course, title: "Midterm", date: cal.adding(days: 20, to: now))
        let past = ExamSnapshot(courseID: course, title: "Past", date: cal.adding(days: -1, to: now))
        let built = builder().build(SessionSpec(kind: .daily), items: items, exams: [midterm, quiz, past], topicNames: names)
        XCTAssertFalse(built.entries.isEmpty)
        XCTAssertTrue(built.entries.contains { $0.topicID == topics[2] })
        for e in built.entries {
            XCTAssertEqual(e.examID, e.topicID == topics[2] ? quiz.id : midterm.id)
        }
        let elsewhere = EngineTest.studied(course: UUID(), recall: 0.5, daysAgo: 4, now: now, cal: cal)
        XCTAssertEqual(builder().build(SessionSpec(kind: .daily), items: [elsewhere], exams: [quiz, midterm]).entries.map(\.examID),
                       [nil], "no exam covers it")
        let eve = builder().build(SessionSpec(kind: .examEve, examID: midterm.id), items: items, exams: [quiz, midterm])
        XCTAssertFalse(eve.entries.isEmpty)
        XCTAssertTrue(eve.entries.allSatisfy { $0.examID == midterm.id })
        let practice = builder().build(SessionSpec(kind: .practice, courseID: course, topicID: topics[2]), items: items,
                                       exams: [quiz, midterm])
        XCTAssertTrue(practice.entries.allSatisfy { $0.examID == quiz.id })
    }

    func testEmptyWorldBuildsAnEmptySession() {
        let built = builder().build(SessionSpec(kind: .daily), items: [])
        XCTAssertTrue(built.isEmpty)
        XCTAssertEqual(built.plannedMinutes, 0)
    }

    // MARK: Queue

    func testQueueBringsAnAgainBackThreeLater() {
        let entries = (0..<6).map { _ in SessionEntry(itemID: UUID(), reason: .due, kind: .flashcard, estimatedSeconds: 9) }
        var queue = SessionQueue(entries: entries)
        var relearning = MemoryState()
        relearning.state = .relearning
        let first = queue.current!
        XCTAssertEqual(queue.advance(rating: .again, memoryAfter: relearning), 4)
        XCTAssertEqual(queue.entries[4].itemID, first.itemID)
        XCTAssertEqual(queue.entries[4].attempt, 1)
        XCTAssertEqual(queue.count, 7)
        var review = MemoryState()
        review.state = .review
        XCTAssertNil(queue.advance(rating: .good, memoryAfter: review))
        // Repeats are capped.
        var q2 = SessionQueue(entries: entries)
        XCTAssertNotNil(q2.advance(rating: .again, memoryAfter: relearning))
        while q2.current?.itemID != first.itemID { q2.skip() }
        XCTAssertNotNil(q2.advance(rating: .again, memoryAfter: relearning))
        while q2.current?.itemID != first.itemID { q2.skip() }
        XCTAssertNil(q2.advance(rating: .again, memoryAfter: relearning))
        // The last entry isn't re-shown straight away.
        var q3 = SessionQueue(entries: Array(entries.prefix(1)))
        XCTAssertNil(q3.advance(rating: .again, memoryAfter: relearning))
        XCTAssertTrue(q3.isFinished)
    }

    func testQueueBringsANewItemBackForItsLearningStep() {
        let entries = (0..<8).map { _ in SessionEntry(itemID: UUID(), reason: .new, kind: .flashcard, estimatedSeconds: 18) }
        var queue = SessionQueue(entries: entries)
        var learning = MemoryState()
        learning.state = .learning
        learning.step = 1
        XCTAssertEqual(queue.advance(rating: .good, memoryAfter: learning), 1 + SessionQueue.stepGap)
    }

    // MARK: Speed

    func testAMockRequestBuildsTheExamsMock() {
        let exam = ExamSnapshot(courseID: course, title: "Midterm", date: cal.adding(days: 9, to: now), format: ExamFormat())
        let session = builder().build(SessionSpec(kind: .mock, examID: exam.id, questionCount: 10), items: world(), exams: [exam], topicNames: names)
        XCTAssertEqual(session.kind, .mock)
        XCTAssertEqual(session.examID, exam.id)
        XCTAssertEqual(session.courseID, course)
        XCTAssertEqual(session.entries.count, 10)
        XCTAssertGreaterThan(session.budgetSeconds, 0)
        XCTAssertTrue(session.entries.allSatisfy { $0.kind != .flashcard && $0.examID == exam.id })
        XCTAssertEqual(session.entries.first?.kind, .mcq, "multiple choice first")
        XCTAssertFalse(session.stopsAfter)

        XCTAssertTrue(builder().build(SessionSpec(kind: .mock, examID: UUID()), items: world(), exams: [exam], topicNames: names).isEmpty, "an exam that has gone")
        XCTAssertTrue(builder().build(SessionSpec(kind: .mock, examID: exam.id), items: Array(world().prefix(3)), exams: [exam], topicNames: names).isEmpty, "too few")
    }

    func testFiveThousandItemsUnderFiftyMilliseconds() {
        let courses = (0..<5).map { _ in UUID() }
        let topicIDs = (0..<40).map { _ in UUID() }
        var items: [ItemSnapshot] = []
        items.reserveCapacity(5000)
        for i in 0..<5000 {
            let c = courses[i % 5], t = topicIDs[i % 40]
            if i % 7 == 0 {
                items.append(EngineTest.fresh(kind: ItemKind.allCases[i % 6], topic: t, course: c))
            } else {
                items.append(EngineTest.studied(kind: ItemKind.allCases[i % 6], topic: t, course: c,
                                                recall: 0.55 + Double(i % 45) / 100, daysAgo: 1 + i % 20, now: now, cal: cal))
            }
        }
        let exams = [ExamSnapshot(courseID: courses[0], date: cal.adding(days: 3, to: now)),
                     ExamSnapshot(courseID: courses[1], date: cal.adding(days: 20, to: now), scope: Set(topicIDs.prefix(8))),
                     ExamSnapshot(courseID: courses[2], date: cal.adding(days: 90, to: now))]
        let confusions = (0..<3).map { k in
            ConfusionSnapshot(id: UUID(), courseID: courses[k], name: "Mix-up \(k)", itemIDs: [items[k * 11].id, items[k * 11 + 1].id])
        }
        let names = Dictionary(uniqueKeysWithValues: topicIDs.enumerated().map { ($1, "Topic \($0)") })
        let b = builder()
        _ = b.build(SessionSpec(kind: .daily), items: items, exams: exams, confusions: confusions, topicNames: names)
        var times: [Double] = []
        var built: BuiltSession?
        for _ in 0..<5 {
            let start = Date()
            built = b.build(SessionSpec(kind: .daily), items: items, exams: exams, confusions: confusions, topicNames: names)
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        let median = times.sorted()[2]
        print("SessionBuilder over 5,000 items: median \(String(format: "%.1f", median)) ms (runs: \(times.map { String(format: "%.1f", $0) }))")
        XCTAssertLessThan(median, 50)
        XCTAssertFalse(built!.isEmpty)
        XCTAssertNotNil(built!.catchUp, "thousands due at once is a catch-up day")
    }

    // MARK: Questions a lecturer marked for the exam

    private func entries(_ session: BuiltSession) -> [UUID] { session.entries.map(\.itemID) }

    func testAQuestionMarkedForTheExamGoesFirstAmongTiesAndNothingChangesWithoutOne() {
        // Thirty due reviews about as weak as each other: more than a minute holds.
        let items = (0..<30).map { i in
            EngineTest.studied(topic: topics[0], course: course, recall: 0.70 + 0.0005 * Double(i), daysAgo: 12, now: now, cal: cal)
        }
        let spec = SessionSpec(kind: .daily)
        let plain = builder(minutes: 1).build(spec, items: items, topicNames: names)
        XCTAssertLessThan(plain.entries.count, items.count)
        XCTAssertTrue(entries(plain).contains(items[0].id), "the lowest recall first")
        XCTAssertFalse(entries(plain).contains(items[29].id))
        var marked = items
        marked[29].examFlagged = true
        let flagged = builder(minutes: 1).build(spec, items: marked, topicNames: names)
        XCTAssertTrue(entries(flagged).contains(items[29].id), "the marked one makes the session, though it is the strongest of the tie")
        XCTAssertEqual(flagged.entries.count, plain.entries.count, "and takes one place")
    }

    func testAMarkedQuestionDoesNotJumpOverAClearlyWeakerOne() {
        let weak = EngineTest.studied(course: course, recall: 0.4, daysAgo: 12, now: now, cal: cal)
        var marked = EngineTest.studied(course: course, recall: 0.8, daysAgo: 12, now: now, cal: cal)
        marked.examFlagged = true
        XCTAssertTrue(SessionBuilder.weaker(0.4, weak, than: 0.8, marked))
        XCTAssertFalse(SessionBuilder.weaker(0.8, marked, than: 0.4, weak))
        // In a tie the mark decides, either way round; with no mark in it, the lower recall does.
        let tied = EngineTest.studied(course: course, recall: 0.81, daysAgo: 12, now: now, cal: cal)
        XCTAssertTrue(SessionBuilder.weaker(0.81, marked, than: 0.8, tied))
        XCTAssertFalse(SessionBuilder.weaker(0.8, tied, than: 0.81, marked))
        XCTAssertTrue(SessionBuilder.weaker(0.8, tied, than: 0.81, tied))
        XCTAssertFalse(SessionBuilder.weaker(0.81, tied, than: 0.8, tied))
    }

    func testAMarkedNewQuestionComesFirstAmongOneExamsNewOnes() {
        let exam = ExamSnapshot(courseID: course, title: "Midterm", date: cal.adding(days: 12, to: now))
        var items = (0..<12).map { i in
            EngineTest.fresh(topic: topics[0], course: course, createdAt: cal.adding(days: -20 + i, to: now))
        }
        items[11].examFlagged = true
        let session = builder().build(SessionSpec(kind: .daily), items: items, exams: [exam], topicNames: names)
        XCTAssertTrue(entries(session).contains(items[11].id), "the last one made, but the one the lecturer stressed")
    }

    func testTheEveTakesMarkedQuestionsFirstAmongTies() {
        let exam = ExamSnapshot(courseID: course, title: "Midterm", date: cal.adding(days: 1, to: now), target: 0.99)
        var items = (0..<40).map { _ in EngineTest.studied(kind: .recall, topic: topics[0], course: course, recall: 0.7, daysAgo: 12, now: now, cal: cal) }
        items[39].examFlagged = true
        let spec = SessionSpec(kind: .examEve, examID: exam.id)
        let session = builder().build(spec, items: items, exams: [exam], topicNames: names)
        XCTAssertLessThan(session.entries.count, items.count, "only some fit tonight")
        XCTAssertTrue(entries(session).contains(items[39].id))
    }

    func testReadinessDoesNotReadTheMark() {
        let exam = ExamSnapshot(courseID: course, title: "Midterm", date: cal.adding(days: 5, to: now))
        var item = EngineTest.studied(course: course, recall: 0.8, daysAgo: 12, now: now, cal: cal)
        let engine = ReadinessEngine(fsrs: FSRS(), calendar: cal, now: now)
        let plain = engine.value(of: exam, items: [item])
        item.examFlagged = true
        XCTAssertEqual(engine.value(of: exam, items: [item]), plain)
    }
}
