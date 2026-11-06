import EventKit
import Foundation
import XCTest
@testable import Cramless

/// "Monday looks busy" through the app: the card, the question iOS asks once, minutes moved on the plan and taken back. The engine's rules are in `NoticeEngineTests`.
@MainActor
final class BusyDayTests: AskTestCase {
    /// Bio 101 with ten studied questions, an exam 9 days from now and a long day 3 days from now.
    private func world(_ app: AppModel, access: CalendarAccess = .granted, answers: CalendarAccess = .granted) -> DemoBusyCalendar {
        let bio = makeBio(app)
        var clock = app.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: app.now)!
        clock = app.calendar.startOfDay(for: clock).addingTimeInterval(10 * 3600)
        let start = clock
        app.clock = { start }
        let exam = Exam(course: bio.course, title: "Bio 101 Midterm", date: app.calendar.adding(days: 9, to: start), now: start)
        app.context.insert(exam)
        for index in 0..<10 {
            let item = StudyItem(course: bio.course, kind: .flashcard, status: .active, origin: .person, prompt: "Q\(index)", answer: "A\(index)", now: start)
            var memory = item.memory
            memory.state = .review
            memory.stability = 30
            memory.difficulty = 5
            memory.lastReview = app.calendar.adding(days: -2, to: start)
            memory.due = app.calendar.adding(days: 20, to: start)
            memory.reps = 3
            item.memory = memory
            app.context.insert(item)
            bio.course.items.append(item)
        }
        for days in 1...3 {
            let record = app.dayRecord(for: app.calendar.adding(days: -days, to: start))
            record.studySeconds = 900
            record.sessions = 1
        }
        app.save()
        let day = app.calendar.adding(days: 3, to: app.calendar.startOfDay(for: start))
        let from = app.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let calendar = DemoBusyCalendar(access: access, answers: answers, blocks: [BusyBlock(start: from, end: from.addingTimeInterval(6 * 3600))])
        app.busyCalendar = calendar
        return calendar
    }

    private func busyCard(_ app: AppModel) -> Notice? { app.noticeDeck().first { $0.kind == .busyDay } }

    func testTheCardComesFromTheCalendar() async throws {
        let app = makeApp()
        _ = world(app)
        XCTAssertNil(busyCard(app), "nothing read yet")
        await app.refreshBusyBlocks()
        let card = try XCTUnwrap(busyCard(app))
        guard case .busyDay(let move) = card.evidence else { return XCTFail("a long day") }
        XCTAssertEqual(move.busy.offset, 3)
        XCTAssertEqual(move.minutes, 10)
        XCTAssertEqual(move.examTitle, "Bio 101 Midterm")
    }

    func testMovingChangesThePlanAndWritesNoMemory() async throws {
        let app = makeApp()
        _ = world(app)
        await app.refreshBusyBlocks()
        let card = try XCTUnwrap(busyCard(app))
        guard case .busyDay(let move) = card.evidence else { return XCTFail("a long day") }
        let memory = try XCTUnwrap(app.courses.first?.items.first?.memory)
        let revision = app.revision
        XCTAssertNil(app.perform(.init(title: "Move them", systemImage: "", run: .moveBusyDay(move))))
        XCTAssertGreaterThan(app.revision, revision, "it saved, so the plan follows")
        XCTAssertEqual(app.courses.first?.items.first?.memory, memory, "no memory written")

        let boosts = app.planBoosts()
        XCTAssertEqual(boosts.minutes, [3: -10, 2: 5, 4: 5], "a long day's future boosts have no questions to wait for")
        XCTAssertTrue(boosts.pinned.isEmpty)
        let plan = try XCTUnwrap(app.examPlans().first)
        XCTAssertEqual(plan.days.first { $0.offset == 3 }?.sessionMinutes, 5, "the long day keeps 5")
        XCTAssertEqual(plan.days.first { $0.offset == 2 }?.sessionMinutes, 20)
        XCTAssertEqual(plan.days.first { $0.offset == 4 }?.sessionMinutes, 20)
        let strip = app.todayStrip(summary: app.todaySummary())
        XCTAssertEqual(strip.first { $0.offset == 3 }?.mark, .minutes(5))
        XCTAssertEqual(strip.first { $0.offset == 2 }?.mark, .minutes(20))

        // The slot says so, with Undo, and the card has gone for its 7 days.
        let slot = try XCTUnwrap(app.todayNotices().first)
        XCTAssertTrue(slot.isConfirmation)
        XCTAssertEqual(slot.kind, .busyDay)
        XCTAssertNil(busyCard(app))

        XCTAssertNil(app.perform(try XCTUnwrap(slot.action)))
        XCTAssertTrue(app.planBoosts().minutes.isEmpty)
        XCTAssertEqual(app.examPlans().first?.days.first { $0.offset == 3 }?.sessionMinutes, 15, "taken back")
        XCTAssertFalse(app.todayNotices().first?.isConfirmation ?? false)
        XCTAssertNotNil(busyCard(app), "the card comes back")
    }

    func testOnTheLongDayItselfTheSessionIsShortAndNotACatchUp() async throws {
        let app = makeApp()
        _ = world(app)
        await app.refreshBusyBlocks()
        guard case .busyDay(let move)? = busyCard(app)?.evidence else { return XCTFail("a long day") }
        app.applyBusyMove(move)
        let start = app.now
        // The day before took the minutes.
        app.clock = { app.calendar.adding(days: 2, to: start) }
        XCTAssertEqual(app.dailyBudgetMinutes(), 20)
        XCTAssertNil(app.backlogMinutesToday())
        app.clock = { app.calendar.adding(days: 3, to: start) }
        XCTAssertEqual(app.dailyBudgetMinutes(), 5)
        XCTAssertEqual(app.backlogMinutesToday(), 15, "a backlog is still measured against the usual day")
        let summary = app.todaySummary()
        XCTAssertEqual(summary.minutesGoal, 5)
        XCTAssertFalse(summary.catchUp)
    }

    func testAnExamThatGoesTakesItsMoveWithIt() async throws {
        let app = makeApp()
        _ = world(app)
        await app.refreshBusyBlocks()
        guard case .busyDay(let move)? = busyCard(app)?.evidence else { return XCTFail("a long day") }
        app.applyBusyMove(move)
        XCTAssertFalse(app.planBoosts().minutes.isEmpty)
        app.upcomingExams().first?.deletedAt = app.now
        app.save()
        _ = app.noticeInputs()
        XCTAssertTrue(app.planBoosts().minutes.isEmpty)
    }

    func testAskingOnceFromTheCard() async throws {
        let app = makeApp()
        let calendar = world(app, access: .notAsked)
        let card = try XCTUnwrap(busyCard(app))
        XCTAssertEqual(card.id, NoticeEngine.busyAskID)
        await app.askForCalendar()
        XCTAssertEqual(calendar.askedCount, 1)
        XCTAssertEqual(calendar.access, .granted)
        let next = try XCTUnwrap(busyCard(app), "the calendar was read at once")
        XCTAssertNotEqual(next.id, NoticeEngine.busyAskID)
        XCTAssertNil(app.router.toast)
    }

    func testAskingWithNothingLongSaysSo() async throws {
        let app = makeApp()
        _ = world(app, access: .notAsked)
        app.busyCalendar = DemoBusyCalendar(access: .notAsked, answers: .granted, blocks: [])
        await app.askForCalendar()
        XCTAssertNil(busyCard(app))
        XCTAssertEqual(app.router.toast.map { String(localized: $0.message) }, "Nothing long this week. Cap will keep an eye out.")
    }

    func testANoIsTheEndOfIt() async throws {
        let app = makeApp()
        let calendar = world(app, access: .notAsked, answers: .denied)
        await app.askForCalendar()
        XCTAssertEqual(calendar.askedCount, 1)
        XCTAssertNil(busyCard(app), "no card, and no more asking")
        XCTAssertEqual(app.router.toast.map { String(localized: $0.message) }, "Okay. Cap won't look at your calendar.")
        await app.refreshBusyBlocks()
        XCTAssertTrue(app.noticeCache.busyBlocks.isEmpty)
    }

    func testTheSwitchStopsTheReading() async throws {
        let app = makeApp()
        _ = world(app)
        await app.refreshBusyBlocks()
        XCTAssertFalse(app.noticeCache.busyBlocks.isEmpty)
        app.setNoticeKind(.busyDay, on: false)
        XCTAssertNil(busyCard(app))
        await app.refreshBusyBlocks()
        XCTAssertTrue(app.noticeCache.busyBlocks.isEmpty, "what was read goes too")
    }

    func testNoExamNearNothingIsRead() async throws {
        let app = makeApp()
        _ = world(app)
        app.upcomingExams().first?.date = app.calendar.adding(days: 30, to: app.now)
        app.save()
        await app.refreshBusyBlocks()
        XCTAssertTrue(app.noticeCache.busyBlocks.isEmpty)
    }

    func testOnlyWhatsMarkedBusyCounts() {
        XCTAssertTrue(LiveBusyCalendar.counts(availability: .busy, allDay: false))
        XCTAssertTrue(LiveBusyCalendar.counts(availability: .unavailable, allDay: true))
        XCTAssertFalse(LiveBusyCalendar.counts(availability: .free, allDay: false))
        XCTAssertFalse(LiveBusyCalendar.counts(availability: .tentative, allDay: false))
        XCTAssertTrue(LiveBusyCalendar.counts(availability: .notSupported, allDay: false))
        XCTAssertFalse(LiveBusyCalendar.counts(availability: .notSupported, allDay: true), "a holiday takes no one's time")
    }

    func testTheAppSaysWhyItAsks() throws {
        let line = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") as? String)
        XCTAssertTrue(line.contains("nothing leaves your iPhone"), line)
    }

    func testATestOrHarnessAppNeverTouchesTheRealCalendar() {
        XCTAssertTrue(makeApp().busyCalendar is NoBusyCalendar)
    }
}
