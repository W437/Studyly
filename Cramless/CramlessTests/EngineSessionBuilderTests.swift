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
}
