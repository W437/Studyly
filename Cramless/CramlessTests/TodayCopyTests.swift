import XCTest
@testable import Cramless

/// Today's words: the greeting by the hour, the band's pill, the chip's day, topic and course lists joined with "and", the ring, the
/// card's lines, the quests row and Cap's quiet line. Counts read right in the singular (their plural forms are in docs/l10n/plurals.json).
final class TodayCopyTests: XCTestCase {
    /// A British calendar, so dates read "29 Nov" and times "10:00" whatever the machine's locale.
    private let cal: Calendar = {
        var c = EngineTest.calendar()
        c.locale = Locale(identifier: "en_GB")
        return c
    }()
    private lazy var now = EngineTest.date(2026, 11, 6, 14, in: cal)   // a Friday afternoon

    // MARK: The band

    func testTheGreetingFollowsTheHour() {
        XCTAssertEqual(TodayCopy.greeting(hour: 8, name: "Maya", firstDay: false), "Good morning, Maya")
        XCTAssertEqual(TodayCopy.greeting(hour: 12, name: "Maya", firstDay: false), "Good afternoon, Maya")
        XCTAssertEqual(TodayCopy.greeting(hour: 16, name: "Maya Rivera", firstDay: false), "Good afternoon, Maya", "the first name")
        XCTAssertEqual(TodayCopy.greeting(hour: 19, name: "Maya", firstDay: false), "Good evening, Maya")
        XCTAssertEqual(TodayCopy.greeting(hour: 2, name: "Maya", firstDay: false), "Good evening, Maya")
        XCTAssertEqual(TodayCopy.greeting(hour: 8, name: "", firstDay: false), "Good morning")
        XCTAssertEqual(TodayCopy.greeting(hour: 8, name: "Maya", firstDay: true), "Welcome, Maya")
        XCTAssertEqual(TodayCopy.greeting(hour: 8, name: "", firstDay: true), "Welcome")
    }

    func testThePillSaysWhatIsToReviewOrHowManyStars() {
        XCTAssertEqual(TodayCopy.starsPill(stars: 63, toReview: 17), "17 to review")
        XCTAssertEqual(TodayCopy.starsPill(stars: 63, toReview: 1), "1 to review")
        XCTAssertEqual(TodayCopy.starsPill(stars: 63, toReview: 0), "63 stars")
    }

    // MARK: When

    func testTheChipSaysTheExamsDayShort() {
        func at(_ days: Int, _ hour: Int = 10) -> Date { cal.date(byAdding: .day, value: days, to: EngineTest.date(2026, 11, 6, hour, in: cal))! }
        XCTAssertEqual(TodayCopy.examDay(at(0, 18), now: now, calendar: cal), "Today at 18:00")
        XCTAssertEqual(TodayCopy.examDay(at(1), now: now, calendar: cal), "Tomorrow at 10:00")
        XCTAssertEqual(TodayCopy.examDay(at(4), now: now, calendar: cal), "Tue")
        XCTAssertEqual(TodayCopy.examDay(at(4), now: now, calendar: cal, spoken: true), "Tuesday")
        XCTAssertEqual(TodayCopy.examDay(at(23), now: now, calendar: cal), "29 Nov")
        XCTAssertEqual(TodayCopy.examDay(at(23), now: now, calendar: cal, spoken: true), "29 November")
        XCTAssertEqual(TodayCopy.chip("Chem 110 Quiz", day: "Tue"), "Chem 110 Quiz · Tue")
    }

    func testDistancesForWhatWaits() {
        XCTAssertEqual(TodayCopy.distance(days: 1), "1 day")
        XCTAssertEqual(TodayCopy.distance(days: 23), "23 days")
        XCTAssertEqual(TodayCopy.distance(days: 196), "6 months")
        XCTAssertEqual(TodayCopy.distance(days: 61), "2 months")
    }

    // MARK: The day card

    func testTopicsAndCoursesAreJoinedWithAndAndNeverLowerCased() {
        XCTAssertEqual(TodayCopy.topics(["Limiting reagents"]), "Limiting reagents")
        XCTAssertEqual(TodayCopy.topics(["Limiting reagents", "Stoichiometry"]), "Limiting reagents and Stoichiometry")
        XCTAssertEqual(TodayCopy.topics(["DNA", "Moles", "Yield"]), "DNA, Moles, and 1 more")
        XCTAssertEqual(TodayCopy.topics(["A", "B", "C", "D", "E"]), "A, B, and 3 more")
        XCTAssertEqual(TodayCopy.topics([]), "")
        XCTAssertEqual(TodayCopy.courses(["Chem 110", "Bio 101", "AP Psychology"]), "Chem 110, Bio 101, and AP Psychology")
        XCTAssertEqual(TodayCopy.courses(["Chem 110", "Bio 101"]), "Chem 110 and Bio 101")
    }

    func testTheRingAndTheLines() {
        XCTAssertEqual(TodayCopy.ready(0.42), "42% ready")
        XCTAssertEqual(TodayCopy.readySpoken(0.42), "42 percent ready")
        XCTAssertEqual(TodayCopy.partWay(done: 6, goal: 15), "6 of 15 minutes done.")
        XCTAssertEqual(TodayCopy.partWay(done: 1, goal: 1), "1 of 1 minute done.")
        XCTAssertEqual(TodayCopy.catchUp(goal: 15, days: 4), "Catching up: about 4 days at 15 minutes a day.")
        XCTAssertEqual(TodayCopy.catchUp(goal: 1, days: 0), "Catching up: about a day at 1 minute a day.")
        XCTAssertEqual(TodayCopy.quests(done: 0, of: 3), "0 of 3 quests")
        XCTAssertEqual(TodayCopy.quests(done: 1, of: 1), "1 of 1 quest")
    }

    func testTheNightBeforeAndTheDoneCard() {
        XCTAssertEqual(TodayCopy.eveLine(topics: ["Limiting reagents", "Stoichiometry"]), "Limiting reagents and Stoichiometry, then sleep.")
        XCTAssertEqual(TodayCopy.eveLine(topics: []), "Then sleep. That's the whole plan tonight.")
        XCTAssertEqual(TodayCopy.sleep, "Sleep is part of studying.")
        XCTAssertEqual(TodayCopy.doneLine(quiet: false), "Back tomorrow. Your streak is safe.")
        XCTAssertEqual(TodayCopy.doneLine(quiet: true), "Back tomorrow.")
    }

    // MARK: Cap

    func testCapIsQuietOnTheNightBefore() {
        XCTAssertEqual(TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: []), "Cap is quiet today.")
        XCTAssertEqual(TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: ["Bio 101", "AP Psychology"]),
                       "Cap is quiet today. Bio 101 and AP Psychology can wait until after Chem 110 Quiz.")
        XCTAssertEqual(TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: ["Bio 101", "AP Psychology", "Spanish II"]),
                       "Cap is quiet today. Your other exams can wait until after Chem 110 Quiz.")
    }
}
