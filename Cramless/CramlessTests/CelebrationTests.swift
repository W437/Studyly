import SwiftData
import UIKit
import XCTest
@testable import Cramless

/// Cap's poses: the drawn ones have art. A pose that arrives before its art stands in with a drawn one.
final class CapPoseTests: XCTestCase {
    func testDrawnPosesAreExactlyTheOnesWithArt() {
        for pose in CapPose.allCases {
            let art = UIImage(named: "Cap-\(pose.rawValue)") != nil
            XCTAssertEqual(art, CapPose.drawn.contains(pose), "\(pose): the art and `CapPose.drawn` disagree")
        }
    }

    func testEveryPoseShowsADrawing() {
        for pose in CapPose.allCases {
            XCTAssertTrue(CapPose.drawn.contains(pose.fallback), "\(pose) stands in with an undrawn pose")
            XCTAssertNotNil(UIImage(named: pose.assetName), "\(pose)")
        }
        // Every pose has its own art now, so each shows itself; `fallback` is for the next one to arrive early.
        for pose in CapPose.allCases { XCTAssertEqual(pose.shown, pose) }
    }

    func testEveryPoseHasItsOwnWordsForVoiceOver() {
        let words = CapPose.allCases.map { String(localized: $0.accessibilityDescription) }
        XCTAssertEqual(Set(words).count, CapPose.allCases.count, "two poses are described the same way")
        XCTAssertFalse(words.contains("Cap the capybara"), "a pose has only the generic words")
    }

    func testTheArtSitsOnOneFeetLine() throws {
        // Every drawing ends the same distance above the bottom of its frame, so a hop or a cross-fade between poses
        // keeps Cap's feet where they were.
        for pose in CapPose.allCases where ![CapPose.sleep, .celebrate].contains(pose) {
            let image = try XCTUnwrap(UIImage(named: pose.assetName)?.cgImage, "\(pose)")
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var lowest = 0
            for y in 0..<height where (0..<width).contains(where: { pixels[(y * width + $0) * 4 + 3] > 20 }) { lowest = y }
            let margin = Double(height - 1 - lowest) / Double(height)
            XCTAssertEqual(margin, 0.035, accuracy: 0.012, "\(pose): feet \(margin) of the frame above the bottom")
        }
    }
}

/// Cap's motions are curves over time: they start and end at rest, and each does what its name says.
final class CapMotionTests: XCTestCase {
    private func samples(_ motion: CapMotion) -> [CapFrame] {
        stride(from: 0.0, through: motion.duration, by: 0.005).map(motion.frame(at:))
    }

    func testEveryMotionEndsAtRest() {
        for motion in CapMotion.allCases {
            XCTAssertEqual(motion.frame(at: motion.duration), CapFrame(), "\(motion)")
            XCTAssertEqual(motion.frame(at: 60), CapFrame(), "\(motion)")
            let last = motion.frame(at: motion.duration - 0.001)
            XCTAssertEqual(last.lift, 0, accuracy: 0.002, "\(motion) lands without a jump")
            XCTAssertEqual(last.scaleY * last.grow, 1, accuracy: 0.01, "\(motion)")
            XCTAssertEqual(last.tilt, 0, accuracy: 0.1, "\(motion)")
        }
    }

    func testAHopSquashesLeavesTheGroundAndLands() {
        let frames = samples(.hop)
        XCTAssertEqual(CapMotion.hop.frame(at: 0), CapFrame())
        XCTAssertGreaterThan(frames.map(\.lift).max() ?? 0, 0.15)
        XCTAssertLessThan(frames.prefix(16).map(\.scaleY).min() ?? 1, 0.93, "it crouches before the jump")
        XCTAssertLessThan(frames.suffix(50).map(\.scaleY).min() ?? 1, 0.95, "and squashes as it lands")
    }

    func testArriveGrowsInFromTheFeet() {
        let first = CapMotion.arrive.frame(at: 0)
        XCTAssertEqual(first.opacity, 0)
        XCTAssertEqual(first.grow, 0.6, accuracy: 0.001)
        XCTAssertGreaterThan(samples(.arrive).map(\.grow).max() ?? 0, 1.02, "a little overshoot")
    }

    func testWiggleAndNodStayGentle() {
        let tilts = samples(.wiggle).map { abs($0.tilt) }
        XCTAssertGreaterThan(tilts.max() ?? 0, 5)
        XCTAssertLessThanOrEqual(tilts.max() ?? 0, 8)
        let lifts = samples(.nod).map(\.lift)
        XCTAssertLessThan(lifts.min() ?? 0, -0.02, "a nod dips")
        XCTAssertLessThanOrEqual(lifts.max() ?? 1, 0.0001, "and never leaves the ground")
    }

    func testSparklesSetTheMomentsLength() {
        XCTAssertEqual(CapMotion.length(.hop, sparkles: false), CapMotion.hop.duration)
        XCTAssertEqual(CapMotion.length(.hop, sparkles: true), CapSparkles.duration)
        XCTAssertEqual(CapMotion.length(nil, sparkles: false), 0)
    }

    func testTheAnswerPanelsMoments() {
        XCTAssertEqual(CapMoment.verdict(.right, combo: 1), .nice)
        XCTAssertEqual(CapMoment.verdict(.right, combo: 5), .runMilestone)
        XCTAssertEqual(CapMoment.verdict(.right, saved: true, combo: 2), .saved)
        XCTAssertEqual(CapMoment.verdict(.partial, combo: 0), .almost)
        XCTAssertEqual(CapMoment.verdict(.wrong, combo: 0), .notYet)
        XCTAssertEqual(CapMoment.verdict(.wrong, answered: false, combo: 0), .answerShown)
        XCTAssertEqual(CapMoment.nice.motion, .hop)
        XCTAssertEqual(CapMoment.almost.motion, .wiggle)
        XCTAssertEqual(CapMoment.notYet.motion, .nod)
        XCTAssertTrue(CapMoment.saved.sparkles)
    }
}

/// When a moment celebrates, and how big.
final class CelebrationPolicyTests: XCTestCase {
    private func decide(_ change: (inout CelebrationFacts) -> Void) -> CelebrationDecision {
        var facts = CelebrationFacts()
        change(&facts)
        return CelebrationPolicy.decide(facts)
    }

    func testNothingEarnedIsNoCelebration() {
        XCTAssertEqual(decide { _ in }, .none)
        XCTAssertEqual(decide { $0.streakExtended = true }, CelebrationDecision(size: .nudge, reason: nil),
                       "another day on the streak: Cap hops, no confetti")
    }

    func testEachReasonHasItsSize() {
        XCTAssertEqual(decide { $0.firstSession = true }, .init(size: .big, reason: .firstSession))
        XCTAssertEqual(decide { $0.readinessReachedGoal = true }, .init(size: .medium, reason: .readinessGoal))
        XCTAssertEqual(decide { $0.mixUpFixed = true }, .init(size: .medium, reason: .mixUpFixed))
        XCTAssertEqual(decide { $0.badgeEarned = true }, .init(size: .medium, reason: .badge))
        XCTAssertEqual(decide { $0.perfect = true }, .init(size: .small, reason: .perfect))
    }

    func testStreakMilestonesGrow() {
        XCTAssertEqual(decide { $0.streakMilestone = 3 }.size, .small)
        XCTAssertEqual(decide { $0.streakMilestone = 7 }.size, .medium)
        for days in [30, 100, 365] {
            XCTAssertEqual(decide { $0.streakMilestone = days }, .init(size: .big, reason: .streakMilestone(days: days)))
        }
        XCTAssertEqual(decide { $0.streakMilestone = 12 }, .none, "only the listed lengths are milestones")
    }

    func testOneCelebrationAndTheBiggestReasonNamesIt() {
        XCTAssertEqual(decide { $0.perfect = true; $0.readinessReachedGoal = true },
                       .init(size: .medium, reason: .readinessGoal))
        XCTAssertEqual(decide { $0.firstSession = true; $0.perfect = true; $0.streakExtended = true },
                       .init(size: .big, reason: .firstSession))
        XCTAssertEqual(decide { $0.perfect = true; $0.streakMilestone = 3 },
                       .init(size: .small, reason: .streakMilestone(days: 3)), "equal sizes: the earlier reason")
    }

    func testABigOneAtMostOnceADay() {
        XCTAssertEqual(decide { $0.firstSession = true; $0.bigToday = true }, .init(size: .medium, reason: .firstSession))
        XCTAssertEqual(decide { $0.readinessReachedGoal = true; $0.bigToday = true }.size, .medium)
    }

    func testExamEveIsAlwaysCalm() {
        XCTAssertEqual(decide { $0.examEve = true }, .init(size: .calm, reason: nil))
        XCTAssertEqual(decide { $0.examEve = true; $0.firstSession = true; $0.streakExtended = true },
                       .init(size: .calm, reason: .firstSession))
    }

    func testQuietHoursKeepTheConfettiAway() {
        XCTAssertEqual(decide { $0.quietHours = true; $0.streakMilestone = 7 },
                       .init(size: .calm, reason: .streakMilestone(days: 7)))
        XCTAssertEqual(decide { $0.quietHours = true; $0.streakExtended = true }.size, .nudge, "a hop is quiet enough")
        XCTAssertFalse(Celebration.calm.hasConfetti)
        XCTAssertFalse(Celebration.nudge.hasConfetti)
    }

    func testStreakMilestoneCrossing() {
        XCTAssertEqual(CelebrationPolicy.milestone(from: 6, to: 7), 7)
        XCTAssertNil(CelebrationPolicy.milestone(from: 7, to: 8))
        XCTAssertNil(CelebrationPolicy.milestone(from: 0, to: 2))
        XCTAssertEqual(CelebrationPolicy.milestone(from: 5, to: 8), 7, "a repair can jump past one")
        XCTAssertEqual(CelebrationPolicy.milestone(from: 2, to: 30), 30, "the biggest one passed")
    }
}

/// The facts a session's summary hands the policy.
@MainActor
final class CelebrationFactsTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
    }

    override func tearDown() async throws {
        AppModel.live = previousLive
        app = nil
    }

    private func summary(_ kind: SessionKind = .daily, extended: Bool = true, streak: Int = 1, items: Int = 6,
                         right: Int = 4, readiness: (Double, Double)? = nil) -> SessionSummary {
        SessionSummary(sessionID: UUID(), kind: kind, answers: items, itemsReviewed: items, correctFirstTry: right,
                       accuracy: items == 0 ? 0 : Double(right) / Double(items), newLearned: 0, minutes: 5,
                       examID: nil, examTitle: nil, readinessBefore: readiness?.0, readinessAfter: readiness?.1,
                       streak: StreakState(current: streak, best: streak, studiedToday: true), streakExtended: extended,
                       repairedDay: nil, stopNow: kind == .examEve)
    }

    private func facts(_ summary: SessionSummary, streakBefore: Int = 0, target: Double? = nil,
                       fixed: Bool = false) -> CelebrationFacts {
        app.celebrationFacts(for: summary, streakBefore: StreakState(current: streakBefore), readinessTarget: target,
                             mixUpFixed: fixed)
    }

    private func finishedSession(_ kind: SessionKind) {
        let session = StudySession(kind: kind, startedAt: clock.now.addingTimeInterval(-600), plannedSeconds: 600)
        session.endedAt = clock.now.addingTimeInterval(-60)
        app.context.insert(session)
        app.save()
    }

    func testTheFirstSessionIsTheFirstAfterOnboardingsQuickCheck() {
        XCTAssertTrue(facts(summary()).firstSession)
        finishedSession(.quickCheck)
        XCTAssertTrue(facts(summary()).firstSession, "onboarding's quick check doesn't count")
        finishedSession(.daily)
        XCTAssertFalse(facts(summary()).firstSession)
    }

    func testStreakMilestonesNeedTheStreakToMove() {
        XCTAssertEqual(facts(summary(streak: 7), streakBefore: 6).streakMilestone, 7)
        XCTAssertNil(facts(summary(extended: false, streak: 7), streakBefore: 7).streakMilestone,
                     "a second session today doesn't celebrate the same day again")
    }

    func testReadinessGoalIsCrossingIt() {
        XCTAssertTrue(facts(summary(readiness: (0.86, 0.91)), target: 0.9).readinessReachedGoal)
        XCTAssertFalse(facts(summary(readiness: (0.9, 0.93)), target: 0.9).readinessReachedGoal, "already there")
        XCTAssertFalse(facts(summary(readiness: (0.7, 0.8)), target: 0.9).readinessReachedGoal)
        XCTAssertFalse(facts(summary(readiness: (0.86, 0.91))).readinessReachedGoal, "no exam, no goal")
    }

    func testPerfectNeedsFiveRightFirstTime() {
        XCTAssertTrue(facts(summary(items: 5, right: 5)).perfect)
        XCTAssertFalse(facts(summary(items: 4, right: 4)).perfect)
        XCTAssertFalse(facts(summary(items: 6, right: 5)).perfect)
    }

    func testExamEveAndQuietHours() {
        XCTAssertTrue(facts(summary(.examEve)).examEve)
        XCTAssertFalse(facts(summary()).quietHours, "18:00")
        clock.now = EngineTest.date(2026, 10, 22, 23, in: cal)
        XCTAssertTrue(facts(summary()).quietHours, "23:00 is inside the default 22:00–7:00")
    }

    func testABigCelebrationIsRememberedForTheDay() {
        XCTAssertFalse(facts(summary()).bigToday)
        app.noteCelebration(.init(size: .medium, reason: .readinessGoal))
        XCTAssertFalse(facts(summary()).bigToday, "only a big one counts")
        app.noteCelebration(.init(size: .big, reason: .firstSession))
        XCTAssertTrue(facts(summary()).bigToday)
        clock.advance(86_400)
        XCTAssertFalse(facts(summary()).bigToday, "a new day")
    }
}

/// Confetti is seeded: the same celebration falls the same way every time, and every piece is gone when it ends.
final class ConfettiFieldTests: XCTestCase {
    let screen = CGSize(width: 402, height: 874)

    func testTheSameSeedFallsTheSameWay() {
        XCTAssertEqual(ConfettiField(burst: .cannons, seed: 7, colours: 7).pieces,
                       ConfettiField(burst: .cannons, seed: 7, colours: 7).pieces)
        XCTAssertNotEqual(ConfettiField(burst: .cannons, seed: 7, colours: 7).pieces,
                          ConfettiField(burst: .cannons, seed: 8, colours: 7).pieces)
    }

    func testBurstSizes() {
        XCTAssertEqual(ConfettiField(burst: .puff(CGPoint(x: 0.5, y: 0.2)), seed: 1, colours: 7).pieces.count, 26)
        XCTAssertEqual(ConfettiField(burst: .burst(CGPoint(x: 0.5, y: 0.2)), seed: 1, colours: 7).pieces.count, 64)
        XCTAssertEqual(ConfettiField(burst: .cannons, seed: 1, colours: 7).pieces.count, 140)
    }

    func testPiecesStartAtTheirOriginGoUpAndAreGoneAtTheEnd() {
        for burst in [ConfettiField.Burst.puff(CGPoint(x: 0.5, y: 0.25)), .burst(CGPoint(x: 0.5, y: 0.25)), .cannons] {
            let field = ConfettiField(burst: burst, seed: 3, colours: 7)
            for piece in field.pieces {
                let start = field.spot(of: piece, at: piece.delay, in: screen)
                XCTAssertEqual(start?.x ?? -1, piece.origin.x * screen.width, accuracy: 0.001)
                XCTAssertEqual(start?.y ?? -1, piece.origin.y * screen.height, accuracy: 0.001)
                XCTAssertLessThan(piece.velocity.dy, 0, "every piece is thrown upward")
                XCTAssertNil(field.spot(of: piece, at: field.duration + 0.01, in: screen))
                XCTAssertNil(field.spot(of: piece, at: piece.delay - 0.01, in: screen), "nothing before its launch")
                XCTAssertTrue((0..<7).contains(piece.colour))
            }
        }
    }

    func testPiecesFadeOutRatherThanVanish() {
        let field = ConfettiField(burst: .puff(CGPoint(x: 0.5, y: 0.1)), seed: 5, colours: 7)
        let tall = CGSize(width: 402, height: 100_000)
        for piece in field.pieces {
            let late = field.spot(of: piece, at: piece.delay + field.life - 0.05, in: tall)
            XCTAssertLessThan(late?.opacity ?? 0, 0.2)
        }
    }
}

/// The summary's count-ups: at most 12 ticks along the fill curve, ending exactly on the number.
final class CountUpTests: XCTestCase {
    func testStepsAreOnePerUnitUpToTwelve() {
        XCTAssertEqual(CountUp.steps(to: [8, 3]), 8)
        XCTAssertEqual(CountUp.steps(to: [40, 6]), 12)
        XCTAssertEqual(CountUp.steps(to: [0]), 0)
        XCTAssertEqual(CountUp.steps(to: []), 0)
    }

    func testValuesClimbAndLandOnTheTarget() {
        let steps = 12
        let values = (0...steps).map { CountUp.value(40, step: $0, of: steps) }
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, 40)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(CountUp.value(5, step: 3, of: 0), 5, "nothing to count shows the number")
        XCTAssertEqual(CountUp.value(5, step: 99, of: 8), 5)
    }

    func testTicksFollowTheCurve() {
        let times = CountUp.times(steps: 8, duration: 0.8)
        XCTAssertEqual(times.count, 8)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(times.last ?? 0, 0.8, accuracy: 0.001)
        XCTAssertLessThan(times[0], 0.8 / 8, "fast at first, like the ring")
        XCTAssertTrue(CountUp.times(steps: 0, duration: 1).isEmpty)
    }
}
