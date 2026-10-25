import XCTest
@testable import Cramless

/// The onboarding step machine: order, skips, back rules, the navigation stack and the harness numbering.
final class OnboardingMachineTests: XCTestCase {
    func testTheWholeFlowInOrder() {
        var m = OnboardingMachine()
        var seen: [OnboardingStep] = [m.step]
        while !m.isDone {
            m.advance()
            seen.append(m.step)
        }
        XCTAssertEqual(seen, [.welcome, .intro(0), .intro(1), .intro(2), .intro(3), .intro(4), .intro(5),
                              .quiz(0), .quiz(1), .quiz(2), .quiz(3),
                              .firstSet, .firstSession, .readiness, .plan, .paywall, .done])
        m.advance()
        XCTAssertEqual(m.step, .done, "done stays done")
    }

    func testHarnessNumbering() {
        XCTAssertEqual(OnboardingMachine(index: 0).step, .welcome)
        XCTAssertEqual(OnboardingMachine(index: 1).step, .intro(0))
        XCTAssertEqual(OnboardingMachine(index: 6).step, .intro(5))
        XCTAssertEqual(OnboardingMachine(index: 7).step, .quiz(0))
        XCTAssertEqual(OnboardingMachine(index: 10).step, .quiz(3))
        XCTAssertEqual(OnboardingMachine(index: 11).step, .firstSet)
        XCTAssertEqual(OnboardingMachine(index: 14).step, .plan)
        XCTAssertEqual(OnboardingMachine(index: 15).step, .paywall)
        XCTAssertEqual(OnboardingMachine(index: 99).step, .paywall, "clamps, and never starts on done")
        XCTAssertEqual(OnboardingMachine(index: -3).step, .welcome)
        for (i, step) in OnboardingMachine.sequence.dropLast().enumerated() {
            XCTAssertEqual(OnboardingMachine(index: i).index, i, "\(step)")
        }
    }

    func testSkipGoesFromAnyIntroPageToTheFirstQuestion() {
        var m = OnboardingMachine(step: .intro(2))
        m.skipIntro()
        XCTAssertEqual(m.step, .quiz(0))
        var notIntro = OnboardingMachine(step: .quiz(1))
        notIntro.skipIntro()
        XCTAssertEqual(notIntro.step, .quiz(1), "skip only means something on the intro pages")
    }

    func testPagerSwipesStayInsideTheIntro() {
        var m = OnboardingMachine(step: .intro(0))
        m.showIntroPage(3)
        XCTAssertEqual(m.step, .intro(3))
        m.showIntroPage(42)
        XCTAssertEqual(m.step, .intro(5))
        var quiz = OnboardingMachine(step: .quiz(0))
        quiz.showIntroPage(1)
        XCTAssertEqual(quiz.step, .quiz(0))
    }

    func testBackReturnsToWhereThePersonLeftThePager() {
        var m = OnboardingMachine(step: .intro(0))
        m.showIntroPage(2)
        m.skipIntro()
        m.back()
        XCTAssertEqual(m.step, .intro(2))
        m.back()
        XCTAssertEqual(m.step, .welcome)
        XCTAssertFalse(m.canGoBack)
    }

    func testBackThroughTheQuestions() {
        var m = OnboardingMachine(step: .firstSet)
        m.back()
        XCTAssertEqual(m.step, .quiz(3))
        m.back()
        XCTAssertEqual(m.step, .quiz(2))
    }

    func testNothingGoesBackPastTheFirstSet() {
        for step in [OnboardingStep.firstSession, .readiness, .plan, .paywall, .done] {
            var m = OnboardingMachine(step: step)
            XCTAssertFalse(m.canGoBack, "\(step)")
            m.back()
            XCTAssertEqual(m.step, step)
        }
    }

    func testScreensFollowTheStep() {
        XCTAssertEqual(OnboardingMachine(step: .welcome).screens, [])
        XCTAssertEqual(OnboardingMachine(step: .intro(3)).screens, [.intro])
        XCTAssertEqual(OnboardingMachine(step: .quiz(1)).screens, [.intro, .quiz(0), .quiz(1)])
        XCTAssertEqual(OnboardingMachine(step: .paywall).screens.last, .paywall)
        XCTAssertEqual(OnboardingMachine(step: .done).screens, OnboardingMachine(step: .paywall).screens)
    }

    func testThePopGestureMovesTheMachineBack() {
        var m = OnboardingMachine(step: .intro(1))
        m.skipIntro()
        m.advance() // quiz(1)
        m.popTo([.intro, .quiz(0)])
        XCTAssertEqual(m.step, .quiz(0))
        m.popTo([.intro])
        XCTAssertEqual(m.step, .intro(1))
        m.popTo([])
        XCTAssertEqual(m.step, .welcome)
    }

    func testPopsCantSkipPastLockedSteps() {
        var m = OnboardingMachine(step: .readiness)
        m.popTo([.intro, .quiz(0)])
        XCTAssertEqual(m.step, .readiness)
        var forward = OnboardingMachine(step: .quiz(0))
        forward.popTo([.intro, .quiz(0), .quiz(1)])
        XCTAssertEqual(forward.step, .quiz(0), "a pop never moves forward")
    }

    func testSetupProgress() {
        XCTAssertNil(OnboardingMachine(step: .intro(0)).setupProgress)
        XCTAssertEqual(OnboardingMachine(step: .quiz(0)).setupProgress!, 1 / 6, accuracy: 0.0001)
        XCTAssertEqual(OnboardingMachine(step: .quiz(3)).setupProgress!, 4 / 6, accuracy: 0.0001)
        XCTAssertEqual(OnboardingMachine(step: .firstSet).setupProgress!, 5 / 6, accuracy: 0.0001)
        XCTAssertEqual(OnboardingMachine(step: .firstSession).setupProgress, 1)
        XCTAssertNil(OnboardingMachine(step: .paywall).setupProgress)
    }
}
