import XCTest
@testable import Cramless

/// Pull to refresh on Today's hero: when a pull counts, the curves of the flourish that follows, and the model that runs the refresh.
final class HeroPullTests: XCTestCase {
    /// Feeds readings (distance, finger down) in order; returns where it ended up and what happened.
    private func run(_ readings: [(Double, Bool)], from start: HeroPull = HeroPull()) -> (pull: HeroPull, events: [HeroPull.Event]) {
        var pull = start
        var events: [HeroPull.Event] = []
        for (distance, down) in readings {
            if let event = pull.update(distance: distance, dragging: down) { events.append(event) }
        }
        return (pull, events)
    }

    func testAFingerDraggingDownIsPullingUntilTheLine() {
        let r = run([(0, true), (10, true), (40, true), (70, true)])
        XCTAssertEqual(r.pull.phase, .pulling)
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertTrue(r.pull.dragging)
    }

    func testReachingTheLineArmsOnce() {
        let r = run([(30, true), (HeroPull.threshold, true), (90, true), (110, true), (100, true)])
        XCTAssertEqual(r.events, [.armed], "one tick, not one per frame")
        XCTAssertEqual(r.pull.phase, .armed)
    }

    func testLettingGoOfALongPullRefreshes() {
        let r = run([(30, true), (90, true), (95, false)])
        XCTAssertEqual(r.events, [.armed, .started])
        XCTAssertEqual(r.pull.phase, .refreshing)
    }

    func testLettingGoOfAShortPullSpringsBack() {
        let r = run([(30, true), (50, true), (50, false), (30, false), (0, false)])
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(r.pull.phase, .idle)
        XCTAssertEqual(r.pull.distance, 0)
    }

    func testAHandWobblingOverTheLineDoesNotFlicker() {
        let wobble = [(70.0, true), (73, true), (68, true), (74, true), (60, true), (75, true), (66, true)]
        let r = run(wobble)
        XCTAssertEqual(r.events, [.armed], "armed once at 73, and the dips to 68, 60 and 66 stay above the way back")
        XCTAssertEqual(r.pull.phase, .armed)
    }

    func testComingBackWellShortOfTheLineBeforeLettingGoDisarms() {
        let r = run([(30, true), (90, true), (40, true), (40, false)])
        XCTAssertEqual(r.events, [.armed, .disarmed])
        XCTAssertEqual(r.pull.phase, .idle)
    }

    func testPullingBackOverTheLineArmsAgain() {
        let r = run([(90, true), (40, true), (80, true), (80, false)])
        XCTAssertEqual(r.events, [.armed, .disarmed, .armed, .started])
    }

    func testAQuickFlickThatReachedTheLineBeforeAnyoneSawItStarts() {
        // The finger was seen at 40, then the next reading is already past the line with the finger gone.
        let r = run([(10, true), (40, true), (95, false)])
        XCTAssertEqual(r.events, [.started])
    }

    func testAFlickLetGoShortButCarriedPastTheLineByMomentumRefreshes() {
        // What a hard swipe down does: the finger lifts at 31, the page carries on to 220 by itself.
        let r = run([(8, true), (16, true), (31, true), (31, false), (220, false), (180, false), (60, false)])
        XCTAssertEqual(r.events, [.started])
        XCTAssertEqual(r.pull.phase, .refreshing)
    }

    func testAFlickThatDiesBeforeTheLineDoesNot() {
        let r = run([(10, true), (40, true), (40, false), (60, false), (30, false), (0, false), (120, false)])
        XCTAssertTrue(r.events.isEmpty, "back at rest the flick is over; later movement with no finger is not a pull")
    }

    func testAPageBouncingOffItsTopWithNoFingerPullingNeverRefreshes() {
        // Flung up the page, it hits the top and rebounds; no finger ever pulled it down.
        let r = run([(0, false), (40, false), (95, false), (50, false), (0, false)])
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(r.pull.phase, .idle)
    }

    func testAGrazeIsNotAFlick() {
        let r = run([(5, true), (12, true), (12, false), (100, false)])
        XCTAssertTrue(r.events.isEmpty, "let go at 12 points: too little to be meant")
    }

    func testANewDragForgetsAnEarlierFlick() {
        let r = run([(10, true), (40, true), (40, false), (20, false), (15, true), (15, false), (100, false)])
        XCTAssertTrue(r.events.isEmpty, "the second gesture let go at 15, under the flick's minimum")
    }

    func testWhileRefreshingEverythingIsIgnored() {
        var r = run([(95, true), (95, false)])
        XCTAssertEqual(r.events, [.armed, .started])
        r = run([(200, true), (10, true), (200, false), (0, false)], from: r.pull)
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(r.pull.phase, .refreshing)
        XCTAssertEqual(r.pull.distance, 0, "the readings still show the world where the page is")
    }

    func testFinishingReturnsToIdleAndAllowsAnother() {
        var pull = run([(95, true), (95, false)]).pull
        pull.finish()
        XCTAssertEqual(pull.phase, .idle)
        let again = run([(95, true), (95, false)], from: pull)
        XCTAssertEqual(again.events, [.armed, .started])
    }

    func testARefreshWithNoPullStartsOnce() {
        var pull = HeroPull()
        XCTAssertEqual(pull.begin(), .started)
        XCTAssertNil(pull.begin(), "already refreshing")
        pull.finish()
        XCTAssertEqual(pull.begin(), .started)
    }

    func testProgressRunsToTheLineAndPastItALittle() {
        XCTAssertEqual(HeroPull.progress(distance: 0), 0)
        XCTAssertEqual(HeroPull.progress(distance: HeroPull.threshold / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HeroPull.progress(distance: HeroPull.threshold), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroPull.progress(distance: 10_000), 1.25)
        XCTAssertEqual(HeroPull.progress(distance: -30), 0)
    }

    func testTheLineIsAFirmPullAndNotAStretch() {
        XCTAssertTrue((55...90).contains(HeroPull.threshold))
        XCTAssertLessThan(HeroPull.release, HeroPull.threshold)
        XCTAssertGreaterThan(HeroPull.release, HeroPull.threshold / 2)
        XCTAssertLessThan(HeroPull.flick, HeroPull.release)
    }

    func testTheLayersLeanFartherTheNearerTheyAre() {
        XCTAssertEqual(HeroPullLook.dust, HeroPullLook.dust.sorted())
        XCTAssertLessThan(HeroPullLook.dust.last!, HeroPullLook.sky)
        XCTAssertGreaterThan(HeroPullLook.dust.first!, 0)
        XCTAssertLessThan(HeroPullLook.milkyWay, HeroPullLook.clouds)
        // At the furthest pull nothing leans past a quarter of the hero's height.
        XCTAssertLessThan(HeroPullLook.sky * 1.25, 30)
    }
}

final class HeroRefreshWaveTests: XCTestCase {
    func testTheArcClimbsFromTheHorizonToAboveTheSky() {
        XCTAssertEqual(HeroRefreshWave.front(at: 0), 0)
        XCTAssertEqual(HeroRefreshWave.front(at: HeroRefreshWave.climb), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRefreshWave.front(at: HeroRefreshWave.climb / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HeroRefreshWave.front(at: -3), 0)
        XCTAssertEqual(HeroRefreshWave.front(at: 9), 1)
        var last = 0.0
        for t in stride(from: 0.0, through: HeroRefreshWave.climb, by: 0.01) {
            let now = HeroRefreshWave.front(at: t)
            XCTAssertGreaterThanOrEqual(now, last, "the arc never goes back down")
            last = now
        }
    }

    func testTheFlourishComesUpQuicklyHoldsAndFadesToNothing() {
        XCTAssertEqual(HeroRefreshWave.glow(at: -1), 0)
        XCTAssertEqual(HeroRefreshWave.glow(at: 0), 0)
        XCTAssertEqual(HeroRefreshWave.glow(at: 0.1), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRefreshWave.glow(at: 0.6), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRefreshWave.glow(at: HeroRefreshWave.climb), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRefreshWave.glow(at: HeroRefreshWave.seconds), 0)
        XCTAssertEqual(HeroRefreshWave.glow(at: 5), 0)
        var last = HeroRefreshWave.glow(at: 0)
        for t in stride(from: 0.0, to: HeroRefreshWave.seconds, by: 1.0 / 60) {
            let now = HeroRefreshWave.glow(at: t)
            XCTAssertTrue((0...1).contains(now))
            XCTAssertLessThan(abs(now - last), 0.2, "no jump at \(t)")
            last = now
        }
    }

    func testAStarIsLitMostRightOnTheArc() {
        XCTAssertEqual(HeroRefreshWave.flash(distance: 0), 1)
        XCTAssertEqual(HeroRefreshWave.flash(distance: 30), HeroRefreshWave.flash(distance: -30), "the same either side")
        XCTAssertGreaterThan(HeroRefreshWave.flash(distance: 10), HeroRefreshWave.flash(distance: 40))
        XCTAssertGreaterThan(HeroRefreshWave.flash(distance: 40), HeroRefreshWave.flash(distance: 70))
        XCTAssertEqual(HeroRefreshWave.flash(distance: 72), 0)
        XCTAssertEqual(HeroRefreshWave.flash(distance: 500), 0)
    }

    func testTheCalmVersionBrightensAndSettlesWithNothingMoving() {
        XCTAssertEqual(HeroRefreshWave.calm(at: 0), 0)
        XCTAssertEqual(HeroRefreshWave.calm(at: 0.4), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRefreshWave.calm(at: 0.8), 0)
        XCTAssertEqual(HeroRefreshWave.calm(at: 2), 0)
        XCTAssertLessThan(0.8, HeroRefreshWave.seconds, "it is over before the flourish is")
    }

    func testAStarFallsAfterAMomentAndLandsInsideTheSky() throws {
        XCTAssertNil(HeroShootingStar.burst(at: 0))
        XCTAssertNil(HeroShootingStar.burst(at: HeroShootingStar.burstDelay - 0.01))
        let first = try XCTUnwrap(HeroShootingStar.burst(at: HeroShootingStar.burstDelay + 0.001))
        XCTAssertLessThan(first.progress, 0.01)
        let last = try XCTUnwrap(HeroShootingStar.burst(at: HeroShootingStar.burstDelay + HeroShootingStar.burstFlight - 0.001))
        XCTAssertGreaterThan(last.progress, 0.99)
        XCTAssertNil(HeroShootingStar.burst(at: HeroShootingStar.burstDelay + HeroShootingStar.burstFlight))
        for streak in [first, last] {
            XCTAssertTrue((0...1).contains(streak.from.x) && (0...1).contains(streak.from.y))
            XCTAssertTrue((0...1).contains(streak.to.x) && (0...1).contains(streak.to.y))
            XCTAssertGreaterThan(streak.to.y, streak.from.y, "it falls")
        }
        XCTAssertLessThan(HeroShootingStar.burstDelay + HeroShootingStar.burstFlight, HeroRefreshWave.climb + 0.001,
                          "it is gone before the arc has left the sky")
    }
}

@MainActor
final class HeroPullModelTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func pullHard(_ model: HeroPullModel) {
        model.finger(dragging: true)
        model.scrolled(to: 30)
        model.scrolled(to: 95)
        model.finger(dragging: false)
    }

    func testALongPullRunsTheWorkOnceAndFinishes() async {
        let model = HeroPullModel(minimum: 0.05, haptics: false)
        var calls = 0
        model.work = { calls += 1; return .fresh }
        pullHard(model)
        XCTAssertEqual(model.phase, .refreshing)
        XCTAssertNotNil(model.startedAt)
        await waitUntil { model.finished == 1 }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.finished, 1)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.outcome, .fresh)
    }

    func testAnUnreachableAccountIsReported() async {
        let model = HeroPullModel(minimum: 0.05, haptics: false)
        model.work = { .offline }
        pullHard(model)
        await waitUntil { model.finished == 1 }
        XCTAssertEqual(model.outcome, .offline)
    }

    func testAShortPullDoesNothing() async {
        let model = HeroPullModel(minimum: 0.05, haptics: false)
        var calls = 0
        model.work = { calls += 1; return .fresh }
        model.finger(dragging: true)
        model.scrolled(to: 40)
        model.finger(dragging: false)
        model.scrolled(to: 0)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.finished, 0)
        XCTAssertNil(model.startedAt)
        XCTAssertEqual(model.phase, .idle)
    }

    func testTheFlourishIsNeverCutShort() async {
        let model = HeroPullModel(minimum: 0.3, haptics: false)
        model.work = { .fresh }
        let began = Date()
        pullHard(model)
        await waitUntil { model.finished == 1 }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), 0.29, "the work took no time at all, the flourish still ran")
    }

    func testAnotherPullWhileRefreshingDoesNotRunItTwice() async {
        let model = HeroPullModel(minimum: 0.2, haptics: false)
        var calls = 0
        model.work = { calls += 1; return .fresh }
        pullHard(model)
        pullHard(model)
        await waitUntil { model.finished == 1 }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.finished, 1)
    }

    func testAfterOneRefreshAnotherCanRun() async {
        let model = HeroPullModel(minimum: 0.02, haptics: false)
        var calls = 0
        model.work = { calls += 1; return .fresh }
        pullHard(model)
        await waitUntil { model.finished == 1 }
        model.scrolled(to: 0)
        pullHard(model)
        await waitUntil { model.finished == 2 }
        XCTAssertEqual(calls, 2)
    }

    func testRefreshingWithoutAPullIsWhatVoiceOverDoes() async {
        let model = HeroPullModel(minimum: 0.02, haptics: false)
        var calls = 0
        model.work = { calls += 1; return .fresh }
        model.refreshNow()
        model.refreshNow()
        await waitUntil { model.finished == 1 }
        XCTAssertEqual(calls, 1)
    }

    func testAFlickRefreshesThroughTheModelToo() async {
        let model = HeroPullModel(minimum: 0.02, haptics: false)
        var calls = 0
        model.work = { calls += 1; return .fresh }
        model.finger(dragging: true)
        model.scrolled(to: 16)
        model.scrolled(to: 31)
        model.finger(dragging: false)
        model.scrolled(to: 220)
        await waitUntil { model.finished == 1 }
        XCTAssertEqual(calls, 1)
    }

    func testDistanceFollowsThePageEvenWhileRefreshing() async {
        let model = HeroPullModel(minimum: 0.2, haptics: false)
        model.work = { .fresh }
        pullHard(model)
        model.scrolled(to: 60)
        XCTAssertEqual(model.distance, 60)
        model.scrolled(to: 0)
        XCTAssertEqual(model.distance, 0)
    }

    func testTheFlourishHasATimeOnlyWhileItRuns() throws {
        let model = HeroPullModel(minimum: 5, haptics: false)
        model.work = { .fresh }
        XCTAssertNil(model.waveTime(at: Date()))
        model.refreshNow()
        let start = try XCTUnwrap(model.startedAt)
        XCTAssertEqual(try XCTUnwrap(model.waveTime(at: start.addingTimeInterval(0.5))), 0.5, accuracy: 1e-6)
        XCTAssertNil(model.waveTime(at: start.addingTimeInterval(HeroRefreshWave.seconds + 0.01)))
        XCTAssertNil(model.waveTime(at: start.addingTimeInterval(-1)))
    }
}
