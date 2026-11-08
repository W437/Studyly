import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The swipe's rule, pure.
final class SwipeRuleTests: XCTestCase {
    private let width = 340.0

    func testADragPastTheLineCounts() {
        XCTAssertEqual(SwipeRule.decide(dx: 120, velocity: 0, width: width), .good)
        XCTAssertEqual(SwipeRule.decide(dx: -120, velocity: 0, width: width), .again)
    }

    func testADragShortOfTheLineSpringsBack() {
        XCTAssertNil(SwipeRule.decide(dx: 118, velocity: 0, width: width), "35% of 340 is 119")
        XCTAssertNil(SwipeRule.decide(dx: -118, velocity: 200, width: width))
        XCTAssertNil(SwipeRule.decide(dx: 0, velocity: 900, width: width))
    }

    func testAFlickCountsFromAnywhere() {
        XCTAssertEqual(SwipeRule.decide(dx: 30, velocity: 700, width: width), .good)
        XCTAssertEqual(SwipeRule.decide(dx: -30, velocity: -900, width: width), .again)
        XCTAssertNil(SwipeRule.decide(dx: 30, velocity: 699, width: width))
    }

    func testAFlickBackIsAChangeOfMind() {
        XCTAssertNil(SwipeRule.decide(dx: 200, velocity: -900, width: width), "past the line, then thrown back")
        XCTAssertNil(SwipeRule.decide(dx: -200, velocity: 900, width: width))
        XCTAssertEqual(SwipeRule.decide(dx: 200, velocity: -300, width: width), .good, "a slow drift back is not a flick")
    }

    func testADragThatStartsUpOrDownIsLeftToTheScrollView() {
        XCTAssertTrue(SwipeRule.startsSideways(dx: 14, dy: 2))
        XCTAssertFalse(SwipeRule.startsSideways(dx: 2, dy: 14))
        XCTAssertFalse(SwipeRule.startsSideways(dx: 12, dy: 8), "exactly 1.5 times sideways is not enough")
        XCTAssertTrue(SwipeRule.startsSideways(dx: -13, dy: 8))
    }

    func testTheTiltAndTheStampStayInBounds() {
        XCTAssertEqual(SwipeRule.tilt(dx: 0, width: width), 0)
        XCTAssertEqual(SwipeRule.tilt(dx: 2000, width: width), 8)
        XCTAssertEqual(SwipeRule.tilt(dx: -2000, width: width), -8)
        XCTAssertEqual(SwipeRule.stampOpacity(dx: 0, width: width), 0)
        XCTAssertEqual(SwipeRule.stampOpacity(dx: 119, width: width), 1, accuracy: 0.001)
        XCTAssertEqual(SwipeRule.stampOpacity(dx: -500, width: width), 1)
        XCTAssertEqual(SwipeRule.armed(dx: 119, width: width), .good)
        XCTAssertNil(SwipeRule.armed(dx: 100, width: width))
    }
}

/// What a swipe writes, the count left, and the hint.
@MainActor
final class FlashcardSwipeTests: XCTestCase {
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

    private func runner(_ count: Int, kinds: [ItemKind] = [.flashcard], window: Duration? = .seconds(600)) -> SessionRunner {
        let course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
        let made = (0..<count).map { n -> StudyItem in
            let item = StudyItem(course: course, kind: kinds[n % kinds.count], status: .active, origin: .person, prompt: "Question \(n)?",
                                 answer: "Answer", now: clock.now)
            app.context.insert(item)
            course.items.append(item)
            return item
        }
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, undoWindow: window))
        runner.start()
        return runner
    }

    /// A swipe's rating, as the card gives it.
    private func swipe(_ runner: SessionRunner, _ rating: Rating) {
        runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: 3000, outcome: .init(rating: rating),
                      undo: .flashcard(flippedAtMs: 3000))
        runner.advance(arriving: .rise)
    }

    func testASwipeLogsTheRatingAsThePersonsOwn() throws {
        let runner = runner(4)
        swipe(runner, .good)
        swipe(runner, .again)
        runner.commitPending()
        let logs = app.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.ratingRaw)]))
        XCTAssertEqual(logs.map(\.ratingRaw), [Rating.again.rawValue, Rating.good.rawValue])
        XCTAssertEqual(Set(logs.map(\.gradedBy)), ["person"])
        XCTAssertEqual(Set(logs.map(\.score)), [-1])
    }

    func testTheCountLeftGoesDownAsCardsAreRatedAndBackOnUndo() {
        // Easy: a new card that graduates at once, so nothing is queued to come back.
        let runner = runner(3)
        XCTAssertEqual(runner.questionsLeft, 3)
        XCTAssertEqual(runner.progress, 0, accuracy: 0.001)
        swipe(runner, .easy)
        XCTAssertEqual(runner.questionsLeft, 2, "at once, while it can still be taken back")
        runner.undoPending()
        XCTAssertEqual(runner.questionsLeft, 3)
        swipe(runner, .easy)
        swipe(runner, .easy)
        XCTAssertEqual(runner.questionsLeft, 1)
        XCTAssertEqual(runner.progress, 2.0 / 3.0, accuracy: 0.001)
    }

    func testAgainBringsTheCardBackSoOneMoreIsLeft() {
        let runner = runner(3)
        let before = runner.questionsLeft
        swipe(runner, .again)
        XCTAssertEqual(runner.questionsLeft, before, "rated, and queued to come back")
    }

    func testTheSwipeHintIsForTheFirstThreeFlashcardsEver() {
        XCTAssertTrue(app.showsSwipeHint)
        for _ in 0..<FlashcardSwipeHint.shownCards { app.noteSwipeHintShown() }
        XCTAssertFalse(app.showsSwipeHint)
        app.noteSwipeHintShown()
        XCTAssertEqual(app.settings.swipeHintsShown, 3, "counted no further")
    }

    func testARisingArrivalIsOnlyForTheNextQuestion() {
        let runner = runner(3)
        swipe(runner, .good)
        XCTAssertEqual(runner.arrival, .rise)
        runner.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 3000, outcome: .right)
        runner.advance()
        XCTAssertEqual(runner.arrival, .forward)
    }

    func testTheWordsOnTheCard() {
        XCTAssertEqual(String(localized: SessionCopy.swipeWord(.good)), "Got it", "no interval: Undo says when it's back")
        XCTAssertEqual(String(localized: SessionCopy.swipeWord(.hard)), "Got it")
        XCTAssertEqual(String(localized: SessionCopy.swipeWord(.again)), "Again")
        XCTAssertEqual(String(localized: SessionCopy.swipeHint), "Swipe right if you got it, left if not")
    }
}
