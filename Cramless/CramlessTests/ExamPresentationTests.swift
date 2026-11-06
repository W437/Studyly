import Foundation
import XCTest
@testable import Cramless

/// How the exam screen arranges the engine's values: the path chart, the week strip, the exam's phase, the Exam
/// Pass offer and the grade comparison.
final class ExamPresentationTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!

    private func day(_ offset: Int, hour: Int = 0) -> Date {
        cal.adding(days: offset, to: cal.startOfDay(for: now)).addingTimeInterval(Double(hour) * 3600)
    }

    private func plan(days: [PlanDay], curve: [ReadinessPoint], target: Double = 0.9, reached: Date? = nil) -> StudyPlan {
        StudyPlan(examID: UUID(), target: target, daysLeft: days.count - 1, dailyMinutes: 15, itemsInScope: 10, newItems: 0,
                  reviewsPlanned: 0, days: days, lastIntroDay: nil, examEve: nil, curve: curve,
                  projectedReadiness: curve.last?.value ?? 0, targetReachedOn: reached, suggestedMinutes: nil)
    }

    private func planDay(_ offset: Int, _ kind: PlanDay.Kind, minutes: Int = 10) -> PlanDay {
        PlanDay(date: day(offset), dayNumber: cal.dayNumber(for: day(offset)), kind: kind, minutes: minutes,
                sessionMinutes: max(minutes, 15), newItems: 0, reviews: 0, isToday: offset == 0, isEasyDay: false)
    }

    // MARK: Path

    func testPathJoinsHistoryAndProjectionAtNow() {
        let history = (0..<14).map { ReadinessPoint(date: day($0 - 13), value: 0.4 + Double($0) * 0.01, isProjection: false) }
        let curve = [ReadinessPoint(date: now, value: 0.53, isProjection: false)]
            + (1...5).map { ReadinessPoint(date: day($0), value: 0.53 + Double($0) * 0.05, isProjection: true) }
        let path = ExamPresentation.path(history: history, plan: plan(days: [], curve: curve), examDate: day(5, hour: 9),
                                         now: now, calendar: cal)
        XCTAssertEqual(path.history.last?.date, now)
        XCTAssertEqual(path.history.last?.value, 0.53, "the history ends on the plan's own now")
        XCTAssertEqual(path.history.count, 14, "today's end-of-day point gives way to now")
        XCTAssertEqual(path.projection.first?.date, now)
        XCTAssertEqual(path.projection.count, 6)
        XCTAssertTrue(path.projection.allSatisfy(\.isProjection))
        XCTAssertFalse(path.isCut)
        XCTAssertEqual(path.end, day(5, hour: 9))
        XCTAssertEqual(path.start, day(-12), "each past day is drawn where it ended")
        XCTAssertEqual(path.nearest(to: day(2).addingTimeInterval(3600))?.date, day(2))
    }

    func testAFarExamIsCutSoTheHistoryStaysReadable() {
        let curve = [ReadinessPoint(date: now, value: 0.16, isProjection: false)]
            + (1...196).map { ReadinessPoint(date: day($0), value: 0.16 + Double($0) * 0.003, isProjection: true) }
        let path = ExamPresentation.path(history: [], plan: plan(days: [], curve: curve), examDate: day(196, hour: 8),
                                         now: now, calendar: cal, maxDays: 56)
        XCTAssertTrue(path.isCut)
        XCTAssertEqual(path.end, cal.adding(days: 56, to: now))
        XCTAssertTrue(path.projection.allSatisfy { $0.date <= path.end })
        XCTAssertEqual(path.projectedAtExam, curve.last!.value, accuracy: 1e-9, "the exam-day projection is still the plan's")
    }

    // MARK: Week strip

    func testAMissedYesterdayLeadsTheStripAndTodayAbsorbsIt() {
        let days = [planDay(0, .study, minutes: 22), planDay(1, .study), planDay(2, .rest, minutes: 0), planDay(3, .study),
                    planDay(4, .study), planDay(5, .study), planDay(6, .examEve, minutes: 8), planDay(7, .exam, minutes: 0)]
        let p = plan(days: days, curve: [])
        let missed = DaySnapshot(dayKey: cal.dayKey(for: day(-1, hour: 12)), day: day(-1), sessions: 0)
        let strip = ExamPresentation.weekStrip(plan: p, yesterday: missed, examCreatedAt: day(-20), now: now, calendar: cal)
        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(strip.first?.kind, .missed)
        XCTAssertEqual(strip.first?.date, day(-1))
        XCTAssertTrue(strip[1].isToday)
        XCTAssertTrue(strip[1].absorbsMissedDay)
        XCTAssertFalse(strip[2].absorbsMissedDay)
        XCTAssertEqual(strip.map(\.kind), [.missed, .study, .study, .rest, .study, .study, .study])

        let frozen = DaySnapshot(dayKey: missed.dayKey, day: day(-1), sessions: 0, frozen: true)
        XCTAssertEqual(ExamPresentation.weekStrip(plan: p, yesterday: frozen, examCreatedAt: day(-20), now: now, calendar: cal).first?.kind,
                       .frozen)
    }

    func testNoMissedDayWhenYesterdayWasStudiedOrTheExamIsNew() {
        let days = [planDay(0, .study), planDay(1, .examEve, minutes: 6), planDay(2, .exam, minutes: 0)]
        let p = plan(days: days, curve: [])
        let studied = DaySnapshot(dayKey: "k", day: day(-1), studySeconds: 600, sessions: 1)
        let strip = ExamPresentation.weekStrip(plan: p, yesterday: studied, examCreatedAt: day(-20), now: now, calendar: cal)
        XCTAssertEqual(strip.map(\.kind), [.study, .eve, .exam])
        XCTAssertFalse(strip.contains { $0.absorbsMissedDay })
        let fresh = ExamPresentation.weekStrip(plan: p, yesterday: nil, examCreatedAt: now, now: now, calendar: cal)
        XCTAssertEqual(fresh.map(\.kind), [.study, .eve, .exam], "an exam set today has no yesterday to miss")
    }

    // MARK: Phase, pass and grade

    func testPhase() {
        XCTAssertEqual(ExamPresentation.phase(examDate: day(23, hour: 9), now: now, calendar: cal), .ahead(days: 23))
        XCTAssertEqual(ExamPresentation.phase(examDate: day(1, hour: 9), now: now, calendar: cal), .eve)
        XCTAssertEqual(ExamPresentation.phase(examDate: day(0, hour: 21), now: now, calendar: cal), .today)
        XCTAssertEqual(ExamPresentation.phase(examDate: day(0, hour: 9), now: now, calendar: cal), .past(days: 0))
        XCTAssertEqual(ExamPresentation.phase(examDate: day(-3, hour: 9), now: now, calendar: cal), .past(days: 3))
    }

    func testExamPassOnlyForFreeUsersEightToTwentyOneDaysOut() {
        func offers(_ days: Int, plan: Plan = .free, others: [Int] = []) -> Bool {
            ExamPresentation.offersExamPass(plan: plan, examDate: day(days, hour: 9),
                                            examDates: others.map { day($0, hour: 9) }, now: now, calendar: cal)
        }
        XCTAssertTrue(offers(21))
        XCTAssertTrue(offers(8))
        XCTAssertFalse(offers(22), "too early")
        XCTAssertFalse(offers(7), "exam week")
        XCTAssertFalse(offers(1), "the eve")
        XCTAssertFalse(offers(0), "the day")
        XCTAssertFalse(offers(-2), "past")
        XCTAssertFalse(offers(15, plan: .pro))
        XCTAssertFalse(offers(15, plan: .pass))
        XCTAssertFalse(offers(15, others: [3]), "another exam in 3 days keeps it quiet")
        XCTAssertTrue(offers(15, others: [40]))
        XCTAssertFalse(offers(30, others: [10]), "this exam is past the window, though another is in it")
    }

    // MARK: What the questions cover

    private func covering(_ title: String, words: Int, covered: Int) -> Coverage.SourceCoverage {
        Coverage.SourceCoverage(sourceID: UUID(), title: title, words: words, coveredWords: covered, sections: 10, uncovered: [])
    }

    func testTheCoverageNoteSaysHowMuchOfTheMaterialTheQuestionsReach() throws {
        // 1,850 of 6,000 words: 31%, with the long reading (17%) holding all that is left.
        let summary = try XCTUnwrap(Coverage.summary([covering("Palsgraf", words: 5000, covered: 850),
                                                       covering("Reading 2", words: 1000, covered: 1000)]))
        let note = ExamPresentation.coverageNote(summary, canAddMore: true)
        XCTAssertEqual(note.sentence, "Your questions cover 31% of your material.")
        XCTAssertEqual(note.mainGap, "Palsgraf: 17%")
        XCTAssertTrue(note.isThin, "under half is amber")
        XCTAssertTrue(note.offersMore)

        // One source says it in the sentence alone.
        let single = try XCTUnwrap(Coverage.summary([covering("Palsgraf", words: 5800, covered: 986)]))
        XCTAssertEqual(ExamPresentation.coverageNote(single, canAddMore: true).sentence, "Your questions cover 17% of your material.")
        XCTAssertNil(ExamPresentation.coverageNote(single, canAddMore: true).mainGap)
        // Nothing to write questions from (only a lecture is left): no button.
        XCTAssertFalse(ExamPresentation.coverageNote(summary, canAddMore: false).offersMore)
    }

    func testTheNoteTurnsAmberBelowHalfAndStopsOfferingWhenNearlyAllIsCovered() throws {
        func note(_ covered: Int) throws -> ExamPresentation.CoverageNote {
            ExamPresentation.coverageNote(try XCTUnwrap(Coverage.summary([covering("Reading", words: 1000, covered: covered)])), canAddMore: true)
        }
        XCTAssertTrue(try note(494).isThin)
        XCTAssertFalse(try note(495).isThin, "it reads 50%, which is not amber")
        XCTAssertTrue(try note(500).offersMore)
        XCTAssertTrue(try note(894).offersMore)
        XCTAssertFalse(try note(895).offersMore, "90% needs no nudge")
        XCTAssertEqual(try note(1000).sentence, "Your questions cover 100% of your material.")
        XCTAssertFalse(try note(1000).offersMore)
    }

    func testTheSourceScreensLine() {
        XCTAssertEqual(LibraryFormat.coverageLine(share: 0.17, kind: .pdf), "Questions cover 17% of this reading")
        XCTAssertEqual(LibraryFormat.coverageLine(share: 0.5, kind: .text), "Questions cover 50% of this reading")
        XCTAssertEqual(LibraryFormat.coverageLine(share: 1, kind: .lecture), "Questions cover 100% of this lecture")
    }

    /// After the exam, the grade sits beside readiness on the day (never beside a projection the student was never shown).
    func testPastExamComparesReadinessOnTheDay() {
        let lines = ExamPresentation.gradeComparison(onTheDay: 0.74, got: 0.81, calibratingExams: 1)
        XCTAssertEqual(lines.headline, "You got 81%, at 74% ready on the day.")
        XCTAssertEqual(lines.note, "Log one more grade and Capling can project yours.")
        XCTAssertEqual(ExamPresentation.gradeComparison(onTheDay: 0.8, got: 0.7, calibratingExams: 2).note,
                       "Capling now projects your grades from your readiness.")
        XCTAssertEqual(ExamPresentation.gradeComparison(onTheDay: nil, got: 0.7, calibratingExams: 0).headline, "You got 70%.")
        XCTAssertEqual(ExamPresentation.logGradeInvite(onTheDay: 0.74),
                       "You were 74% ready on the day. Log your grade and Capling learns how your readiness turns into grades.")
        XCTAssertEqual(ExamPresentation.logGradeInvite(onTheDay: nil),
                       "Log your grade and Capling learns how your readiness turns into grades.")
    }

    // MARK: The exam page (Thursday 18:00; the quiz is on Sunday at 10:00)

    /// A plan day with its offset and the seconds it holds for the exam.
    private func pday(_ offset: Int, _ kind: PlanDay.Kind, seconds: Double = 0, skipped: Bool = false) -> PlanDay {
        PlanDay(date: day(offset), dayNumber: cal.dayNumber(for: day(offset)), kind: kind, minutes: Int((seconds / 60).rounded(.up)),
                sessionMinutes: 15, newItems: 0, reviews: 0, isToday: offset == 0, isEasyDay: false, offset: offset, seconds: seconds,
                neededSeconds: seconds, isSkipped: skipped)
    }

    private func examPlan(_ days: [PlanDay], projected: Double, target: Double = 0.8, suggested: Int? = nil) -> StudyPlan {
        StudyPlan(examID: UUID(), target: target, daysLeft: days.count - 1, dailyMinutes: 15, itemsInScope: 20, newItems: 0,
                  reviewsPlanned: 0, days: days, lastIntroDay: nil, examEve: nil,
                  curve: [ReadinessPoint(date: now, value: 0.42, isProjection: false)], projectedReadiness: projected,
                  targetReachedOn: nil, suggestedMinutes: suggested)
    }

    /// Sunday's quiz: today (4 min for it), Friday off, Saturday evening's weak spots.
    private func sundayQuiz(projected: Double, skipped: Int? = nil) -> StudyPlan {
        examPlan([pday(0, .study, seconds: 240), pday(1, .rest), pday(2, .examEve, seconds: skipped == 2 ? 0 : 130, skipped: skipped == 2),
                  pday(3, .exam)], projected: projected)
    }

    private func projection(_ plan: StudyPlan, phase: ExamPresentation.Phase = .ahead(days: 3), examDate: Date? = nil,
                            questions: Int = 20, weakest: String? = "Limiting reagents", grade: ProjectedGrade? = nil,
                            skipping: ExamPresentation.SkipOption? = nil) -> ExamPresentation.Projection? {
        ExamPresentation.projection(phase: phase, plan: plan, questionCount: questions, weakestTopic: weakest, grade: grade,
                                    examDate: examDate ?? day(3, hour: 10), now: now, calendar: cal, skipping: skipping)
    }

    func testProjectionSaysWhatItTakes() throws {
        // Short of the goal, near: the days to study, then what else gets closer.
        let short = try XCTUnwrap(projection(sundayQuiz(projected: 0.74)))
        XCTAssertEqual(short.sentence, "Study today and Saturday evening, and you'll be about 74% ready by Sunday.")
        XCTAssertEqual(short.nudge, "Practice Limiting reagents as well to get closer to 80%.")
        XCTAssertEqual(short.footnote, "A projection from your recall so far, not a promise.")
        XCTAssertNil(short.letter)
        XCTAssertNil(short.basedOn)
        XCTAssertFalse(short.reachesGoal)

        // On track, near.
        let onTrack = try XCTUnwrap(projection(sundayQuiz(projected: 0.86)))
        XCTAssertEqual(onTrack.sentence, "Study today and Saturday evening, and you'll be about 86% ready by Sunday. That's past your 80% goal.")
        XCTAssertNil(onTrack.nudge)
        XCTAssertTrue(onTrack.reachesGoal)

        // Far: the daily goal carries it, or more minutes would.
        let far = day(23, hour: 9)
        let farDays = (0..<23).map { pday($0, $0 == 22 ? .examEve : .study, seconds: 300) } + [pday(23, .exam)]
        let farOnTrack = try XCTUnwrap(projection(examPlan(farDays, projected: 0.86), phase: .ahead(days: 23), examDate: far))
        XCTAssertEqual(farOnTrack.sentence,
                       "Keep up your 15 minutes a day, and you'll be about 86% ready by \(LibraryFormat.shortDate(far, calendar: cal)). That's past your 80% goal.")
        let farShort = try XCTUnwrap(projection(examPlan(farDays, projected: 0.62, suggested: 25), phase: .ahead(days: 23), examDate: far))
        XCTAssertEqual(farShort.sentence, "At 15 minutes a day you'll be about 62% ready by \(LibraryFormat.shortDate(far, calendar: cal)).")
        XCTAssertEqual(farShort.nudge, "About 25 minutes a day gets you closer to 80%.")

        // The eve: tonight's weak spots.
        let eve = try XCTUnwrap(projection(examPlan([pday(0, .examEve, seconds: 300), pday(1, .exam)], projected: 0.78),
                                           phase: .eve, examDate: day(1, hour: 10)))
        XCTAssertEqual(eve.sentence, "Tonight's weak spots take you to about 78% by tomorrow morning.")

        // No questions yet: nothing to project, a way to add material.
        let empty = try XCTUnwrap(projection(sundayQuiz(projected: 0), questions: 0))
        XCTAssertEqual(empty.sentence, "Nothing to study for this exam yet. Add material and Capling plans the way there.")
        XCTAssertTrue(empty.addsMaterial)
        XCTAssertNil(empty.footnote)

        // Few questions: it says how few.
        XCTAssertEqual(projection(sundayQuiz(projected: 0.74), questions: 7)?.basedOn, "Based on 7 questions so far.")
        XCTAssertEqual(projection(sundayQuiz(projected: 0.74), questions: 1)?.basedOn, "Based on 1 question so far.")

        // On the day and after there is nothing to project.
        XCTAssertNil(projection(sundayQuiz(projected: 0.74), phase: .today))
        XCTAssertNil(projection(sundayQuiz(projected: 0.74), phase: .past(days: 2)))
    }

    func testTheLetterWaitsForCalibration() throws {
        let projected = ProjectedGrade(percent: 0.88, letter: "B+", isCalibrated: false)
        XCTAssertFalse(ExamPresentation.showsLetter(projected))
        XCTAssertNil(ExamPresentation.shownGrade(projected))
        XCTAssertNil(projection(sundayQuiz(projected: 0.74), grade: projected)?.letter, "no letter from a projection alone")

        let calibrated = ProjectedGrade(percent: 0.88, letter: "B+", isCalibrated: true)
        XCTAssertEqual(projection(sundayQuiz(projected: 0.74), grade: calibrated)?.letter, "From your past grades, that's about a B+.")
        XCTAssertEqual(ExamPresentation.calibratedProjectionLine(ProjectedGrade(percent: 0.94, letter: "A", isCalibrated: true)),
                       "From your past grades, that's about an A.")
        XCTAssertEqual(ExamPresentation.calibratedGradeLine(calibrated), "Projected B+ from your grades")
    }

    private var chemToday: ExamPresentation.TodayWork {
        ExamPresentation.TodayWork(sessionMinutes: 15, examSeconds: 250, topics: ["Limiting reagents", "Moles", "Molar mass"],
                                   studiedToday: false, missedYesterday: false)
    }

    func testStopsForAQuizInTwoDays() {
        // Thursday evening, the quiz on Saturday at 10:00: today, Friday evening's weak spots, the quiz.
        let plan = examPlan([pday(0, .study, seconds: 240), pday(1, .examEve, seconds: 130), pday(2, .exam)], projected: 0.74)
        var today = chemToday
        today.missedYesterday = true
        let stops = ExamPresentation.stops(plan: plan, phase: .ahead(days: 2), examTitle: "Chem 110 Quiz", examDate: day(2, hour: 10),
                                           today: today, skipped: nil, now: now, calendar: cal)
        XCTAssertEqual(stops.map(\.kind), [.today, .eve, .exam])
        XCTAssertEqual(stops[0].title, "Today · 15 min")
        XCTAssertEqual(stops[0].detail, "About 4 min for this exam: Limiting reagents and Moles", "two topics, joined with and")
        XCTAssertEqual(stops[0].note, "Includes yesterday's reviews.")
        XCTAssertEqual(stops[1].title, "Friday evening · about 2 min")
        XCTAssertEqual(stops[1].detail, "Weak spots only, then sleep")
        XCTAssertTrue(stops[2].title.hasPrefix("Saturday · "), stops[2].title)
        XCTAssertEqual(stops[2].detail, "Chem 110 Quiz")

        // A session with nothing for this exam says so; a day already done says that.
        var other = chemToday
        other.examSeconds = 0
        XCTAssertEqual(ExamPresentation.stops(plan: plan, phase: .ahead(days: 2), examTitle: "Quiz", examDate: day(2, hour: 10),
                                              today: other, skipped: nil, now: now, calendar: cal).first?.detail,
                       "Today's session is for your other exams.")
        let done = ExamPresentation.TodayWork(sessionMinutes: 0, examSeconds: 0, topics: [], studiedToday: true, missedYesterday: false)
        XCTAssertEqual(ExamPresentation.stops(plan: plan, phase: .ahead(days: 2), examTitle: "Quiz", examDate: day(2, hour: 10),
                                              today: done, skipped: nil, now: now, calendar: cal).first?.title, "Today · done")
        // On the eve the page has tonight and the exam; on the day and after, no plan.
        let evePlan = examPlan([pday(0, .examEve, seconds: 420), pday(1, .exam)], projected: 0.78)
        XCTAssertEqual(ExamPresentation.stops(plan: evePlan, phase: .eve, examTitle: "Quiz", examDate: day(1, hour: 10), today: chemToday,
                                              skipped: nil, now: now, calendar: cal).map(\.title).first, "Tonight · about 7 min")
        // The session built for tonight says the number, the same as the button; with nothing to review it says so.
        XCTAssertEqual(ExamPresentation.stops(plan: evePlan, phase: .eve, examTitle: "Quiz", examDate: day(1, hour: 10), today: chemToday,
                                              skipped: nil, tonightMinutes: 4, now: now, calendar: cal).map(\.title).first, "Tonight · about 4 min")
        XCTAssertEqual(ExamPresentation.stops(plan: evePlan, phase: .eve, examTitle: "Quiz", examDate: day(1, hour: 10), today: chemToday,
                                              skipped: nil, tonightMinutes: 0, now: now, calendar: cal).map(\.title).first, "Tonight · nothing to review")
        XCTAssertTrue(ExamPresentation.stops(plan: plan, phase: .today, examTitle: "Quiz", examDate: day(0, hour: 20), today: chemToday,
                                             skipped: nil, now: now, calendar: cal).isEmpty)
    }

    func testThenAboutReadsTheDaysThatHaveWork() {
        // Every day has work: "a day", their average.
        let every = (0..<10).map { pday($0, $0 == 9 ? .examEve : .study, seconds: $0 == 9 ? 120 : 780) } + [pday(10, .exam)]
        let stops = ExamPresentation.stops(plan: examPlan(every, projected: 0.86), phase: .ahead(days: 10), examTitle: "Bio", examDate: day(10, hour: 9),
                                           today: chemToday, skipped: nil, now: now, calendar: cal)
        XCTAssertEqual(stops[1].title, "Then about 13 min a day until \(LibraryFormat.shortDate(day(8), calendar: cal))")
        // Days off in between don't pull the number down.
        let some = (0..<10).map { offset -> PlanDay in
            if offset == 9 { return pday(offset, .examEve, seconds: 120) }
            return pday(offset, offset % 3 == 0 ? .rest : .study, seconds: offset % 3 == 0 ? 0 : 780)
        } + [pday(10, .exam)]
        let spaced = ExamPresentation.stops(plan: examPlan(some, projected: 0.86), phase: .ahead(days: 10), examTitle: "Bio", examDate: day(10, hour: 9),
                                            today: chemToday, skipped: nil, now: now, calendar: cal)
        XCTAssertEqual(spaced[1].title, "Then about 13 min on study days until \(LibraryFormat.shortDate(day(8), calendar: cal))")
    }

    /// With one exam the whole session is for it: "11 of the 12 minutes" only showed two ways of rounding.
    func testAlmostAllOfASessionIsTheWholeSession() throws {
        func work(_ exam: Double, total: Double, minutes: Int) -> ExamPresentation.TodayWork {
            ExamPresentation.TodayWork(sessionMinutes: minutes, examSeconds: exam, topics: [], studiedToday: false, missedYesterday: false, sessionSeconds: total)
        }
        func subline(_ w: ExamPresentation.TodayWork) -> String? {
            ExamPresentation.studyAction(phase: .ahead(days: 5), today: w, weakest: nil, courseName: "Chem")?.subline
        }
        XCTAssertEqual(subline(work(660, total: 660, minutes: 12)), "The whole session is for this exam.")
        XCTAssertEqual(subline(work(620, total: 680, minutes: 12)), "The whole session is for this exam.", "91%")
        XCTAssertEqual(subline(work(600, total: 720, minutes: 12)), "About 10 of the 12 minutes are for this exam.", "83%")
        XCTAssertEqual(work(620, total: 680, minutes: 12).examMinutes, 12, "the plan's stop says the same")
        // Built from a session: the seconds decide, not two rounded minutes.
        let exam = ExamSnapshot(courseID: UUID(), date: day(5))
        let entry = SessionEntry(itemID: UUID(), reason: .due, kind: .mcq, topicID: nil, courseID: exam.courseID, estimatedSeconds: 650, examID: exam.id)
        let built = ExamPresentation.todayWork(entries: [entry], sessionMinutes: 11, exam: exam, topicNames: [:], studiedToday: false, missedYesterday: false)
        XCTAssertTrue(built.isWholeSession)
    }

    /// Once tonight's session is done the page says so: no button, and not what tonight "will" add.
    func testTheEveAfterItsSession() throws {
        let plan = examPlan([pday(0, .examEve, seconds: 300), pday(1, .exam)], projected: 0.83)
        let done = try XCTUnwrap(ExamPresentation.projection(phase: .eve, plan: plan, questionCount: 20, weakestTopic: nil, grade: nil,
                                                             examDate: day(1, hour: 10), now: now, calendar: cal, eveDone: true))
        XCTAssertEqual(done.sentence, "That's enough for tonight. You're about 42% ready for tomorrow morning.")
        XCTAssertNil(ExamPresentation.studyAction(phase: .eve, today: chemToday, weakest: nil, courseName: "Chem", eveDone: true))
        let stops = ExamPresentation.stops(plan: plan, phase: .eve, examTitle: "Quiz", examDate: day(1, hour: 10), today: chemToday, skipped: nil,
                                           tonightMinutes: 4, eveDone: true, now: now, calendar: cal)
        XCTAssertEqual(stops.first?.title, "Tonight · done")
    }

    func testStopsForAFarExam() {
        // 23 days out: today, then the days between as one stretch at their average, the eve, the exam.
        let days = (0..<23).map { offset -> PlanDay in
            if offset == 22 { return pday(offset, .examEve, seconds: 300) }
            return pday(offset, offset % 2 == 0 ? .study : .rest, seconds: offset % 2 == 0 ? 660 : 0)
        } + [pday(23, .exam)]
        let stops = ExamPresentation.stops(plan: examPlan(days, projected: 0.86), phase: .ahead(days: 23), examTitle: "Bio 101 Midterm",
                                           examDate: day(23, hour: 9), today: chemToday, skipped: nil, now: now, calendar: cal)
        XCTAssertEqual(stops.map(\.kind), [.today, .span, .eve, .exam])
        // Days 1 to 21: ten study days of 11 minutes, with days off between them: the days that have work, and it says so.
        XCTAssertEqual(stops[1].title, "Then about 11 min on study days until \(LibraryFormat.shortDate(day(21), calendar: cal))")
        XCTAssertEqual(stops[2].title, "\(LibraryFormat.shortDate(day(22), calendar: cal)) evening · about 5 min")
        XCTAssertEqual(stops[3].detail, "Bio 101 Midterm")
    }

    func testSkippingSaysWhatItCosts() throws {
        let plan = sundayQuiz(projected: 0.77)
        let option = try XCTUnwrap(ExamPresentation.skipOption(plan: plan, phase: .ahead(days: 3), calendar: cal))
        XCTAssertEqual(option.offset, 2, "the next day after today with work for this exam (Friday is a day off)")
        XCTAssertEqual(option.question, "What if I skip Saturday?")
        XCTAssertEqual(option.keep, "Keep Saturday")
        XCTAssertNil(ExamPresentation.skipOption(plan: plan, phase: .eve, calendar: cal), "the eve is the last day: nothing to skip")

        let cost = ExamPresentation.skipCost(option, planned: 0.77, skipped: 0.69, examDate: day(3, hour: 10), now: now, calendar: cal)
        XCTAssertEqual(cost.points, 8)
        XCTAssertEqual(cost.title, "Skipping Saturday costs about 8 points")
        XCTAssertEqual(cost.detail, "About 69% ready by Sunday instead of 77%.")
        let small = ExamPresentation.skipCost(option, planned: 0.77, skipped: 0.761, examDate: day(3, hour: 10), now: now, calendar: cal)
        XCTAssertEqual(small.title, "Skipping Saturday costs almost nothing")
        XCTAssertEqual(small.detail, "The days around it pick up its reviews.")

        // The what-if switches the projection and marks the day on the plan.
        let skipped = sundayQuiz(projected: 0.69, skipped: 2)
        XCTAssertEqual(projection(skipped, skipping: option)?.sentence, "Skip Saturday, and you'll be about 69% ready by Sunday.")
        let stops = ExamPresentation.stops(plan: skipped, phase: .ahead(days: 3), examTitle: "Chem 110 Quiz", examDate: day(3, hour: 10),
                                           today: chemToday, skipped: option.offset, now: now, calendar: cal)
        let saturday = try XCTUnwrap(stops.first { $0.isSkipped })
        XCTAssertEqual(saturday.title, "Saturday evening · skipped")
    }

    func testTopicsWeakestFirstGapsOnTop() {
        func topic(_ name: String, _ value: Double?, items: Int, practice: Double = 120) -> TopicReadiness {
            TopicReadiness(id: UUID(), name: name, value: value, itemCount: items, practiceSeconds: practice)
        }
        let rows = ExamPresentation.topicsWeakestFirst([topic("Moles", 0.6, items: 3), topic("Gas laws", nil, items: 0),
                                                        topic("Limiting reagents", 0.3, items: 2, practice: 170),
                                                        topic("Units", 0.9, items: 4), topic("Molar mass", 0.6, items: 2)],
                                                       target: 0.8)
        XCTAssertEqual(rows.map(\.name), ["Gas laws", "Limiting reagents", "Moles", "Molar mass", "Units"],
                       "the gap first, then the lowest readiness; ties keep the course's order")
        XCTAssertEqual(rows.filter(\.isWeakest).map(\.name), ["Limiting reagents"])
        XCTAssertEqual(rows[1].practiceMinutes, 3)
        XCTAssertNil(rows[0].practiceMinutes, "a gap has nothing to practise")
        XCTAssertTrue(rows[4].isOnTrack)
        XCTAssertNil(rows[4].practiceMinutes)
    }

    func testTheButtonIsTheDaysSession() {
        let weakest = ExamPresentation.TopicRow(id: UUID(), name: "Moles", value: 0.4, questionCount: 3, practiceMinutes: 3, isWeakest: true)
        let study = ExamPresentation.studyAction(phase: .ahead(days: 3), today: chemToday, weakest: weakest, courseName: "Chem 110")
        XCTAssertEqual(study?.kind, .daily)
        XCTAssertEqual(study?.title, "Study · 15 min")
        XCTAssertEqual(study?.subline, "About 4 of the 15 minutes are for this exam.")

        var whole = chemToday
        whole.examSeconds = 900
        XCTAssertEqual(ExamPresentation.studyAction(phase: .ahead(days: 3), today: whole, weakest: weakest, courseName: "Chem 110")?.subline,
                       "The whole session is for this exam.")
        let done = ExamPresentation.TodayWork(sessionMinutes: 0, examSeconds: 0, topics: [], studiedToday: true, missedYesterday: false)
        let practice = ExamPresentation.studyAction(phase: .ahead(days: 3), today: done, weakest: weakest, courseName: "Chem 110")
        XCTAssertEqual(practice?.kind, .practice(topicID: weakest.id, minutes: 3))
        XCTAssertEqual(practice?.title, "Practice Moles · 3 min")
        XCTAssertEqual(ExamPresentation.studyAction(phase: .eve, today: chemToday, weakest: weakest, courseName: "Chem 110")?.title,
                       "Tonight · 10 min")
        let tonight = ExamPresentation.studyAction(phase: .eve, today: chemToday, weakest: weakest, courseName: "Chem 110", eveMinutes: 4)
        XCTAssertEqual(tonight?.title, "Tonight · 4 min")
        XCTAssertEqual(tonight?.subline, "About 4 minutes on what you're shakiest on. Then stop: sleep does the rest.")
        XCTAssertEqual(ExamPresentation.studyAction(phase: .eve, today: chemToday, weakest: weakest, courseName: "Chem 110", eveMinutes: 1)?.subline,
                       "About 1 minute on what you're shakiest on. Then stop: sleep does the rest.")
        XCTAssertNil(ExamPresentation.studyAction(phase: .eve, today: chemToday, weakest: weakest, courseName: "Chem 110", eveMinutes: 0),
                     "nothing to review tonight: no button")
        XCTAssertNil(ExamPresentation.studyAction(phase: .today, today: chemToday, weakest: weakest, courseName: "Chem 110"))
    }

    func testTodaysWorkIsTheSessionsQuestionsTheExamCovers() {
        let course = UUID(), other = UUID(), moles = UUID(), gas = UUID(), offScope = UUID()
        func entry(_ topic: UUID, _ course: UUID, _ seconds: Double) -> SessionEntry {
            SessionEntry(itemID: UUID(), reason: .due, kind: .flashcard, topicID: topic, courseID: course, estimatedSeconds: seconds)
        }
        let exam = ExamSnapshot(courseID: course, date: day(3, hour: 10), scope: [moles, gas])
        let work = ExamPresentation.todayWork(entries: [entry(gas, course, 40), entry(moles, course, 60), entry(moles, course, 60),
                                                        entry(offScope, course, 100), entry(moles, other, 200)],
                                              sessionMinutes: 9, exam: exam, topicNames: [moles: "Moles", gas: "Gas laws"],
                                              studiedToday: false, missedYesterday: false)
        XCTAssertEqual(work.examSeconds, 160)
        XCTAssertEqual(work.topics, ["Moles", "Gas laws"], "the most time first")
        XCTAssertEqual(work.examMinutes, 3)
    }
}
