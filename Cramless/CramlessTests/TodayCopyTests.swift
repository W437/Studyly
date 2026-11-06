import XCTest
@testable import Cramless

/// Today's words: the greeting by the hour, when an exam is, topic lists joined with "and", the reasons, the rings, the done card,
/// the strip and Cap's quiet line. Counts read right in the singular (their plural forms are in docs/l10n/plurals.json).
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

    func testThePillSaysWhatIsDimmingOrHowManyStars() {
        XCTAssertEqual(TodayCopy.starsPill(stars: 63, dimming: 17), "17 stars dimming")
        XCTAssertEqual(TodayCopy.starsPill(stars: 63, dimming: 1), "1 star dimming")
        XCTAssertEqual(TodayCopy.starsPill(stars: 63, dimming: 0), "63 stars")
    }

    // MARK: When

    func testWhenAnExamIs() {
        func at(_ days: Int, _ hour: Int = 10) -> Date { cal.date(byAdding: .day, value: days, to: EngineTest.date(2026, 11, 6, hour, in: cal))! }
        XCTAssertEqual(TodayCopy.when(at(0, 18), now: now, calendar: cal), "Today · 18:00")
        XCTAssertEqual(TodayCopy.when(at(1), now: now, calendar: cal), "Tomorrow · 10:00")
        XCTAssertEqual(TodayCopy.when(at(2), now: now, calendar: cal), "Sun · in 2 days")
        XCTAssertEqual(TodayCopy.when(at(23), now: now, calendar: cal), "29 Nov · in 23 days")
        XCTAssertEqual(TodayCopy.when(at(196), now: now, calendar: cal), "21 May", "far off: just the date")
    }

    func testDistancesForWhatWaits() {
        XCTAssertEqual(TodayCopy.distance(days: 1), "1 day")
        XCTAssertEqual(TodayCopy.distance(days: 23), "23 days")
        XCTAssertEqual(TodayCopy.distance(days: 196), "6 months")
        XCTAssertEqual(TodayCopy.distance(days: 61), "2 months")
    }

    // MARK: The day card

    func testTopicsAreJoinedWithAndAndNeverLowerCased() {
        XCTAssertEqual(TodayCopy.topics(["Limiting reagents"]), "Limiting reagents")
        XCTAssertEqual(TodayCopy.topics(["Limiting reagents", "Stoichiometry"]), "Limiting reagents and Stoichiometry")
        XCTAssertEqual(TodayCopy.topics(["DNA", "Moles", "Yield"]), "DNA, Moles, and 1 more")
        XCTAssertEqual(TodayCopy.topics(["A", "B", "C", "D", "E"]), "A, B, and 3 more")
        XCTAssertEqual(TodayCopy.topics([]), "")
    }

    func testReasonsSayWhyInOneSentence() {
        XCTAssertEqual(TodayCopy.reason(weak: true, due: 12, new: 0, forExam: true),
                       "The weakest topics for this exam, plus 12 questions you're about to forget.")
        XCTAssertEqual(TodayCopy.reason(weak: true, due: 1, new: 0, forExam: true),
                       "The weakest topics for this exam, plus 1 question you're about to forget.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 12, new: 5, forExam: true), "12 questions you're about to forget, and 5 new ones.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 1, new: 1, forExam: true), "1 question you're about to forget, and 1 new one.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 0, new: 5, forExam: true), "5 new questions, so it's all in before the exam.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 0, new: 1, forExam: false), "1 new question.")
        XCTAssertEqual(TodayCopy.reason(weak: true, due: 0, new: 3, forExam: false), "Your weakest topics, plus 3 new questions.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 0, new: 0, forExam: true), "A short review of what you know.")
        XCTAssertEqual(TodayCopy.partWay(done: 6, goal: 15), "6 of 15 minutes done.")
        XCTAssertEqual(TodayCopy.partWay(done: 1, goal: 1), "1 of 1 minute done.")
    }

    /// The session from the card holds more than this exam's questions: the line says this exam's share and the whole, so it's true of what the button starts.
    func testTheReasonSaysTheExamsShareAndTheWholeSession() {
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 6, new: 1, forExam: true, sessionTotal: 39),
                       "6 questions you're about to forget and 1 new one for this exam. About 39 questions in all today.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 1, new: 3, forExam: true, sessionTotal: 39),
                       "1 question you're about to forget and 3 new ones for this exam. About 39 questions in all today.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 6, new: 0, forExam: true, sessionTotal: 39),
                       "6 questions you're about to forget for this exam. About 39 questions in all today.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 0, new: 1, forExam: true, sessionTotal: 2),
                       "1 new question for this exam. About 2 questions in all today.")
        XCTAssertEqual(TodayCopy.reason(weak: true, due: 12, new: 0, forExam: true, sessionTotal: 30),
                       "The weakest topics for this exam, plus 12 questions you're about to forget. About 30 questions in all today.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 0, new: 0, forExam: true, sessionTotal: 12), "About 12 questions in all today.")
        XCTAssertEqual(TodayCopy.reason(weak: false, due: 6, new: 1, forExam: true), "6 questions you're about to forget, and 1 new one.",
                       "the session is all for this exam: the counts are the whole")
    }

    func testTheRingsAreReadinessNowAndAProjectionThatSaysSo() {
        XCTAssertEqual(TodayCopy.readyNow(0.42), "42% ready now")
        XCTAssertEqual(TodayCopy.afterToday(0.523), "about 52% after today")
        XCTAssertEqual(TodayCopy.ringsSpoken(now: 0.42, after: 0.52), "42 percent ready now, about 52 percent after today, projected")
        XCTAssertEqual(TodayCopy.ringsSpoken(now: 0.42, after: nil), "42 percent ready now")
        XCTAssertEqual(TodayCopy.basedOn(7), "Based on 7 questions so far.")
        XCTAssertEqual(TodayCopy.basedOn(1), "Based on 1 question so far.")
    }

    func testTheEveAndTheDoneCard() {
        XCTAssertEqual(TodayCopy.eveReason(minutes: 10, topics: ["Limiting reagents", "Stoichiometry"]),
                       "10 minutes on Limiting reagents and Stoichiometry, then sleep. That's the whole plan tonight.")
        XCTAssertEqual(TodayCopy.eveReason(minutes: 10, topics: []), "10 minutes on your weak spots, then sleep. That's the whole plan tonight.")
        XCTAssertEqual(TodayCopy.eveRest(title: "Chem 110 Quiz", time: nil), "Chem 110 Quiz is tomorrow. Sleep is part of studying.")
        XCTAssertEqual(TodayCopy.eveRest(title: "Chem 110 Quiz and Bio 101 Midterm", several: true, time: nil),
                       "Chem 110 Quiz and Bio 101 Midterm are tomorrow. Sleep is part of studying.")
        XCTAssertEqual(TodayCopy.doneLine(minutes: 15, answers: 24), "15 min · 24 answers")
        XCTAssertEqual(TodayCopy.doneLine(minutes: 3, answers: 1), "3 min · 1 answer")
        XCTAssertEqual(TodayCopy.doneRing(title: "Chem 110 Quiz", value: 0.52), "Chem 110 Quiz: 52% ready")
        XCTAssertEqual(TodayCopy.doneDelta(0.10, daysLeft: 2), "+10% today · 2 days to go")
        XCTAssertEqual(TodayCopy.doneDelta(0.10, daysLeft: 1), "+10% today · 1 day to go")
        XCTAssertEqual(TodayCopy.doneDelta(0.001, daysLeft: 5), "Steady today · 5 days to go")
        XCTAssertEqual(TodayCopy.doneDelta(0.05, daysLeft: 0), "+5% today")
    }

    // MARK: Your plan and Cap

    func testTheStripInWords() {
        let today = EngineTest.date(2026, 11, 6, 0, in: cal)
        func day(_ offset: Int, _ mark: TodayPlanDay.Mark, _ titles: [String] = []) -> TodayPlanDay {
            TodayPlanDay(offset: offset, date: cal.date(byAdding: .day, value: offset, to: today)!, mark: mark, examTitles: titles)
        }
        XCTAssertEqual(TodayCopy.stripDay(day(-1, .studied), calendar: cal), "Thursday: studied")
        XCTAssertEqual(TodayCopy.stripDay(day(-2, .frozen), calendar: cal), "Wednesday: covered by a freeze")
        XCTAssertEqual(TodayCopy.stripDay(day(0, .minutes(15)), calendar: cal), "Today: 15 minutes planned")
        XCTAssertEqual(TodayCopy.stripDay(day(1, .eve(minutes: 10), ["Chem 110 Quiz"]), calendar: cal),
                       "Saturday: the night before Chem 110 Quiz, 10 minutes")
        XCTAssertEqual(TodayCopy.stripDay(day(2, .exam(count: 2), ["Chem 110 Quiz", "Bio 101 Midterm"]), calendar: cal),
                       "Sunday: Chem 110 Quiz and Bio 101 Midterm")
        XCTAssertEqual(TodayCopy.stripCaption(day(1, .eve(minutes: 10))), "10m")
        XCTAssertEqual(TodayCopy.stripCaption(day(-1, .missed)), "")
        XCTAssertEqual(TodayCopy.questsLine(done: 0, of: 3, week: 5, weekGoal: 12), "0 of 3 quests today · 5 of 12 this week")
    }

    func testCapIsQuietOnTheEve() {
        XCTAssertEqual(TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: []), "Cap is quiet tonight.")
        XCTAssertEqual(TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: ["Bio 101", "AP Psychology"]),
                       "Cap is quiet tonight. Bio 101 and AP Psychology can wait until after Chem 110 Quiz.")
        XCTAssertEqual(TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: ["Bio 101", "AP Psychology", "Spanish II"]),
                       "Cap is quiet tonight. Your other exams can wait until after Chem 110 Quiz.")
        XCTAssertEqual(TodayCopy.noticeCount(1, of: 3), "1 of 3")
    }
}
