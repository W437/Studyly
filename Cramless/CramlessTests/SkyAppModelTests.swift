import SwiftData
import XCTest
@testable import Cramless

/// The memory sky read from a real store: what is a star, how the layout stays put, and what a session does to it.
@MainActor
final class SkyAppModelTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    // MARK: Helpers

    private func course(_ name: String, color: CourseColor = .mint, order: Int = 0) -> Course {
        let c = Course(name: name, now: clock.now)
        c.color = color
        c.sortOrder = order
        app.context.insert(c)
        return c
    }

    private func topic(_ name: String, in course: Course, order: Int = 0) -> Topic {
        let t = Topic(course: course, name: name, sortOrder: order, now: clock.now)
        app.context.insert(t)
        course.topics.append(t)
        return t
    }

    /// An active flashcard; `recall` and `daysAgo` make it a studied item whose recall now is `recall`.
    @discardableResult
    private func item(in course: Course, topic: Topic? = nil, recall: Double? = nil, daysAgo: Int = 6,
                      status: ItemStatus = .active, kind: ItemKind = .flashcard) -> StudyItem {
        let item = StudyItem(course: course, topicID: topic?.id, kind: kind, status: status, origin: .person,
                             prompt: "Question?", answer: "Answer", now: clock.now)
        if let recall {
            item.memory = EngineTest.studied(recall: recall, daysAgo: daysAgo, now: clock.now, cal: cal).memory
        }
        app.context.insert(item)
        course.items.append(item)
        return item
    }

    private func positions(_ scene: SkyScene) -> [UUID: SkyPoint] {
        Dictionary(uniqueKeysWithValues: scene.layout.stars.map { ($0.id, $0.point) })
    }

    // MARK: Reading

    func testEveryActiveItemInALiveCourseIsAStar() {
        let bio = course("Bio 101", color: .mint), chem = course("Chem 110", color: .tangerine, order: 1)
        let meiosis = topic("Meiosis", in: bio)
        for _ in 0..<5 { item(in: bio, topic: meiosis, recall: 0.9) }
        for _ in 0..<3 { item(in: bio) }
        for _ in 0..<4 { item(in: chem, recall: 0.5) }
        app.save()

        let scene = app.skyScene(aspect: 1.4)
        XCTAssertEqual(scene.starCount, 12)
        XCTAssertEqual(scene.hollowCount, 3, "never studied")
        XCTAssertEqual(scene.layout.constellations.count, 3, "Meiosis, Bio's loose items, and Chem's")
        XCTAssertEqual(scene.courseColors[bio.id], .mint)
        XCTAssertEqual(scene.courseColors[chem.id], .tangerine)
        XCTAssertEqual(scene.courseNames[chem.id], "Chem 110")
        XCTAssertEqual(scene.dimCount, 4, "recall 0.5 is below the fading line")
        XCTAssertEqual(scene.brightCount, 5)
    }

    func testTrashedCoursesAndInactiveItemsLeaveTheSky() {
        let bio = course("Bio 101"), old = course("Old course", order: 1)
        item(in: bio, recall: 0.9)
        item(in: bio, recall: 0.9, status: .draft)
        item(in: bio, recall: 0.9, status: .rejected)
        item(in: old, recall: 0.9)
        old.deletedAt = clock.now
        let deleted = item(in: bio, recall: 0.9)
        deleted.deletedAt = clock.now
        app.save()

        let scene = app.skyScene(aspect: 1)
        XCTAssertEqual(scene.starCount, 1)
        XCTAssertNil(scene.courseNames[old.id])
    }

    func testOnlyUpcomingExamsGetARegion() {
        let bio = course("Bio 101")
        let meiosis = topic("Meiosis", in: bio)
        for _ in 0..<4 { item(in: bio, topic: meiosis, recall: 0.9) }
        let soon = Exam(course: bio, title: "Midterm", date: clock.now.addingTimeInterval(5 * 86_400), scope: [meiosis.id], now: clock.now)
        let past = Exam(course: bio, title: "Quiz", date: clock.now.addingTimeInterval(-5 * 86_400), now: clock.now)
        app.context.insert(soon)
        app.context.insert(past)
        app.save()

        let scene = app.skyScene(aspect: 1)
        XCTAssertEqual(scene.layout.regions.map(\.title), ["Midterm"])
        XCTAssertNotNil(scene.examDates[soon.id])
    }

    func testTheLayoutIsCachedAndNothingMovesWhenItemsAreReviewedOrAdded() {
        let bio = course("Bio 101")
        let meiosis = topic("Meiosis", in: bio)
        for _ in 0..<5 { item(in: bio, topic: meiosis, recall: 0.8) }
        app.save()
        let before = positions(app.skyScene(aspect: 1.4))

        // Reviewing changes the light, not the places.
        let studied = app.itemSnapshots().first!
        app.recordReview(itemID: studied.id, rating: .good)
        clock.advance(86_400 * 3)
        XCTAssertEqual(positions(app.skyScene(aspect: 1.4)), before)

        // Room for three more.
        for _ in 0..<3 { item(in: bio, topic: meiosis) }
        app.save()
        let after = positions(app.skyScene(aspect: 1.4))
        for (id, point) in before { XCTAssertEqual(after[id], point) }
        XCTAssertEqual(after.count, before.count + 3)
    }

    func testTheSkyAgesWithTheDateNotTheStore() {
        let bio = course("Bio 101")
        for _ in 0..<4 { item(in: bio, recall: 0.9, daysAgo: 1) }
        app.save()
        let now = app.skyScene(aspect: 1)
        let later = app.skyScene(aspect: 1, at: clock.now.addingTimeInterval(20 * 86_400))
        XCTAssertEqual(now.layout, later.layout)
        XCTAssertEqual(now.dimCount, 0)
        XCTAssertEqual(later.dimCount, 4, "twenty days on, nothing studied: all of it has faded")
    }

    func testRelightingAConstellationIsAPracticeSessionForItsTopic() throws {
        let bio = course("Bio 101")
        let meiosis = topic("Meiosis", in: bio)
        for _ in 0..<6 { item(in: bio, topic: meiosis, recall: 0.4, kind: .recall) }
        app.save()
        let scene = app.skyScene(aspect: 1)
        let c = try XCTUnwrap(scene.layout.constellations.first { $0.topicID == meiosis.id })
        let request = app.relightRequest(c, in: scene)
        XCTAssertEqual(request.kind, .practice)
        XCTAssertEqual(request.courseID, bio.id)
        XCTAssertEqual(request.topicID, meiosis.id)
        // Six recall questions at about 50 s: five minutes.
        XCTAssertEqual(request.minutes, 5)
        // And the session it builds is made of that topic's stars.
        let built = app.buildSession(request)
        XCTAssertFalse(built.entries.isEmpty)
        XCTAssertTrue(built.entries.allSatisfy { $0.topicID == meiosis.id })
    }

    // MARK: A session's effect

    func testFinishingASessionRelightsTheStarsItChangedAndCountsTheSaves() throws {
        let bio = course("Bio 101")
        let fading = item(in: bio, recall: 0.5)      // right: relit, and a save
        let alsoFading = item(in: bio, recall: 0.6)  // wrong: stays dim
        let bright = item(in: bio, recall: 0.97, daysAgo: 1)  // right, but already bright: kept, not relit
        let fresh = item(in: bio)                    // right on a first look: lit for the first time
        app.save()

        let (session, _) = app.startSession(SessionRequest(kind: .practice, courseID: bio.id))
        let saved = try XCTUnwrap(app.recordReview(itemID: fading.id, rating: .good, sessionID: session.id))
        let missed = try XCTUnwrap(app.recordReview(itemID: alsoFading.id, rating: .again, sessionID: session.id))
        let kept = try XCTUnwrap(app.recordReview(itemID: bright.id, rating: .good, sessionID: session.id))
        let first = try XCTUnwrap(app.recordReview(itemID: fresh.id, rating: .good, sessionID: session.id))
        XCTAssertTrue(saved.isSave)
        XCTAssertFalse(missed.isSave)
        XCTAssertFalse(kept.isSave)
        XCTAssertFalse(first.isSave, "a first look is never a save")

        let summary = app.finishSession(session)
        XCTAssertEqual(summary.starsSaved, 1, "the same count as the 'Saved it.' moments the person saw")
        XCTAssertEqual(summary.starsRelit, 2, "the fading star and the new one; not the bright one, not the miss")
        let pending = app.pendingSkyRelight
        XCTAssertEqual(pending.relit, [fading.id, fresh.id])
        XCTAssertEqual(pending.lit, [fresh.id])
        XCTAssertEqual(pending.saved, [fading.id])
        XCTAssertEqual(pending.from[fresh.id], 0)
        XCTAssertEqual(try XCTUnwrap(pending.from[fading.id]), SkyEngine.brightness(recall: saved.recallBefore), accuracy: 1e-9)
    }

    func testAnAlmostRelightsTheStarButIsNotCountedAsSaved() throws {
        let bio = course("Bio 101")
        let right = item(in: bio, recall: 0.5), almost = item(in: bio, recall: 0.55)
        app.save()
        let (session, _) = app.startSession(SessionRequest(kind: .practice, courseID: bio.id))
        app.recordReview(itemID: right.id, rating: .good, sessionID: session.id)
        app.recordReview(itemID: almost.id, rating: .hard, sessionID: session.id)
        let summary = app.finishSession(session)
        XCTAssertEqual(summary.starsRelit, 2, "both were remembered, one with difficulty")
        XCTAssertEqual(summary.starsSaved, 1, "but only the right answer was a 'Saved it.'")
        XCTAssertEqual(app.pendingSkyRelight.saved, [right.id])
        XCTAssertEqual(app.pendingSkyRelight.relit, [right.id, almost.id])
    }

    func testFinishingTwiceCountsOnceAndTheSkyHandsTheRelightOverOnce() throws {
        let bio = course("Bio 101")
        let a = item(in: bio, recall: 0.5), b = item(in: bio, recall: 0.55)
        app.save()
        let (session, _) = app.startSession(SessionRequest(kind: .practice, courseID: bio.id))
        app.recordReview(itemID: a.id, rating: .good, sessionID: session.id)
        let first = app.finishSession(session)
        let again = app.finishSession(session)
        XCTAssertEqual(first.starsRelit, again.starsRelit)
        XCTAssertEqual(app.pendingSkyRelight.relit, [a.id], "finishing again adds nothing")

        // A later session adds to what hasn't been shown yet.
        clock.advance(600)
        let (second, _) = app.startSession(SessionRequest(kind: .practice, courseID: bio.id))
        app.recordReview(itemID: b.id, rating: .good, sessionID: second.id)
        app.finishSession(second)
        XCTAssertEqual(app.pendingSkyRelight.relit, [a.id, b.id])

        let handed = app.takeSkyRelight()
        XCTAssertEqual(handed.relit, [a.id, b.id])
        XCTAssertTrue(app.takeSkyRelight().isEmpty, "played once")
        XCTAssertTrue(app.pendingSkyRelight.isEmpty)
    }

    func testASessionWithNothingToRelightLeavesNothingPending() throws {
        let bio = course("Bio 101")
        let missed = item(in: bio, recall: 0.5)
        app.save()
        let (session, _) = app.startSession(SessionRequest(kind: .practice, courseID: bio.id))
        app.recordReview(itemID: missed.id, rating: .again, sessionID: session.id)
        let summary = app.finishSession(session)
        XCTAssertEqual(summary.starsRelit, 0)
        XCTAssertEqual(summary.starsSaved, 0)
        XCTAssertTrue(app.pendingSkyRelight.isEmpty)
    }
}
