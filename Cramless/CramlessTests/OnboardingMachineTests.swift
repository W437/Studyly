import XCTest
@testable import Cramless

/// The onboarding step machine: order, the date step's skip, back rules, the navigation stack and the harness numbering.
final class OnboardingMachineTests: XCTestCase {
    func testTheWholeFlowInOrder() {
        var m = OnboardingMachine()
        var seen: [OnboardingStep] = [m.step]
        while !m.isDone {
            if m.step == .firstSet { m.firstSetMade(asksExamDate: true) } else { m.advance() }
            seen.append(m.step)
        }
        XCTAssertEqual(seen, [.welcome, .firstSet, .firstSession, .examDate, .plan, .paywall, .done])
        m.advance()
        XCTAssertEqual(m.step, .done, "done stays done")
    }

    /// The person's own page is the second screen: the questions from it come at the third tap.
    func testTheFirstSetComesStraightAfterTheWelcome() {
        var m = OnboardingMachine()
        m.advance()
        XCTAssertEqual(m.step, .firstSet)
    }

    func testTheSamplePageSkipsTheDate() {
        var m = OnboardingMachine(step: .firstSet)
        m.firstSetMade(asksExamDate: false)
        XCTAssertEqual(m.step, .firstSession)
        m.advance()
        XCTAssertEqual(m.step, .plan, "no exam is made from a sample, so its date isn't asked")
        XCTAssertEqual(m.screens, [.firstSet, .firstSession, .plan])
        m.advance()
        XCTAssertEqual(m.step, .paywall)
    }

    func testFirstSetMadeOnlyCountsOnTheFirstSet() {
        var m = OnboardingMachine(step: .plan)
        m.firstSetMade(asksExamDate: false)
        XCTAssertEqual(m.step, .plan)
        XCTAssertTrue(m.asksExamDate)
    }

    func testHarnessNumbering() {
        XCTAssertEqual(OnboardingMachine(index: 0).step, .welcome)
        XCTAssertEqual(OnboardingMachine(index: 1).step, .firstSet)
        XCTAssertEqual(OnboardingMachine(index: 2).step, .firstSession)
        XCTAssertEqual(OnboardingMachine(index: 3).step, .examDate)
        XCTAssertEqual(OnboardingMachine(index: 4).step, .plan)
        XCTAssertEqual(OnboardingMachine(index: 5).step, .paywall)
        XCTAssertEqual(OnboardingMachine(index: 99).step, .paywall, "clamps, and never starts on done")
        XCTAssertEqual(OnboardingMachine(index: -3).step, .welcome)
        for (i, step) in OnboardingMachine.sequence.dropLast().enumerated() {
            XCTAssertEqual(OnboardingMachine(index: i).index, i, "\(step)")
        }
    }

    func testOnlyTheFirstSetGoesBack() {
        var m = OnboardingMachine(step: .firstSet)
        XCTAssertTrue(m.canGoBack)
        m.back()
        XCTAssertEqual(m.step, .welcome)
        XCTAssertFalse(m.canGoBack)
    }

    func testNothingGoesBackPastTheFirstSet() {
        for step in [OnboardingStep.firstSession, .examDate, .plan, .paywall, .done] {
            var m = OnboardingMachine(step: step)
            XCTAssertFalse(m.canGoBack, "\(step)")
            m.back()
            XCTAssertEqual(m.step, step)
            m.popTo([])
            XCTAssertEqual(m.step, step, "\(step): the edge swipe can't either")
        }
    }

    func testScreensFollowTheStep() {
        XCTAssertEqual(OnboardingMachine(step: .welcome).screens, [])
        XCTAssertEqual(OnboardingMachine(step: .firstSet).screens, [.firstSet])
        XCTAssertEqual(OnboardingMachine(step: .examDate).screens, [.firstSet, .firstSession, .examDate])
        XCTAssertEqual(OnboardingMachine(step: .plan).screens, [.firstSet, .firstSession, .examDate, .plan])
        XCTAssertEqual(OnboardingMachine(step: .paywall).screens.last, .paywall)
        XCTAssertEqual(OnboardingMachine(step: .done).screens, OnboardingMachine(step: .paywall).screens)
    }

    func testThePopGestureLeavesTheFirstSetForTheWelcome() {
        var m = OnboardingMachine(step: .firstSet)
        m.popTo([.firstSet])
        XCTAssertEqual(m.step, .firstSet, "not a pop")
        m.popTo([])
        XCTAssertEqual(m.step, .welcome)
    }
}
