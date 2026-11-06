import XCTest
@testable import Cramless

/// `StudyHabits`: the follow-through and first-look figures as blends, with no threshold to jump at.
final class EngineStudyHabitsTests: XCTestCase {
    func testWithNoRecordTheyAreThePriors() {
        XCTAssertEqual(StudyHabits.followThrough(studied: 0, span: 0), 0.95, accuracy: 1e-9)
        XCTAssertEqual(StudyHabits.firstLookSuccess(right: 0, looks: 0), 0.75, accuracy: 1e-9)
    }

    /// The old rule jumped on day 8, when a week's record replaced the default: with no change in the student, it doesn't move now, and
    /// a missed day moves it by a day's weight at most, whichever day it is.
    func testFollowThroughHasNoStep() {
        for span in 1...14 {
            XCTAssertEqual(StudyHabits.followThrough(studied: span, span: span), 0.95, accuracy: 1e-9, "day \(span)")
        }
        for pattern in ["sxsxsxsxsxsxsx", "xxxxxxxxxxxxxx", "sssssssxxxxxxx"] {
            var studied = 0
            var previous = StudyHabits.followThrough(studied: 0, span: 0)
            for (day, mark) in pattern.enumerated() {
                if mark == "s" { studied += 1 }
                let now = StudyHabits.followThrough(studied: studied, span: day + 1)
                XCTAssertLessThan(abs(now - previous), 0.125, "\(pattern) day \(day + 1)")
                previous = now
            }
        }
    }

    func testSomeoneWhoStudiesDaysStaysHighAndSomeoneWhoSkipsComesDown() {
        XCTAssertEqual(StudyHabits.followThrough(studied: 14, span: 14), 0.95, accuracy: 1e-9)
        let half = StudyHabits.followThrough(studied: 7, span: 14)
        XCTAssertLessThan(half, 0.7)
        XCTAssertGreaterThan(half, 0.5)
        XCTAssertEqual(StudyHabits.followThrough(studied: 0, span: 14), 0.5, accuracy: 1e-9, "the floor")
    }

    /// The old rule jumped at the 20th first look.
    func testFirstLooksHaveNoStep() {
        var previous = StudyHabits.firstLookSuccess(right: 0, looks: 0)
        for looks in 1...60 {
            let now = StudyHabits.firstLookSuccess(right: 0, looks: looks)
            XCTAssertLessThan(abs(now - previous), 0.04, "\(looks)")
            previous = now
        }
        XCTAssertEqual(previous, 0.4, accuracy: 1e-9, "the floor")
        XCTAssertEqual(StudyHabits.firstLookSuccess(right: 200, looks: 200), 0.95, accuracy: 1e-9, "the ceiling")
    }
}
