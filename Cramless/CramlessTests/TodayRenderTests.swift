import SwiftUI
import UIKit
import XCTest
@testable import Cramless

/// Draws Today's cards in every state to PNGs in build/review/s1-today/render/ (gitignored), at an iPhone SE's width (375) and a
/// 17 Pro's (402), light and dark, and at the third accessibility text size, to be looked at; and checks that on an SE the day's card,
/// button included, fits on the first screen under the band.
@MainActor
final class TodayRenderTests: XCTestCase {
    static let outputFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/review/s1-today/render", directoryHint: .isDirectory)

    private let examID = UUID()

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: Self.outputFolder, withIntermediateDirectories: true)
    }

    // MARK: The states

    private func exam(_ title: String = "Chem 110 Quiz", when: String = "Sun · in 2 days", readiness: Double = 0.42, delta: Double = 0.15,
                      days: Int = 2) -> TodayExam {
        TodayExam(id: title == "Chem 110 Quiz" ? examID : UUID(), title: title, courseName: "Chem 110", color: .tangerine,
                  date: Date(timeIntervalSince1970: 1_790_000_000), daysLeft: days, readiness: readiness, delta: delta, when: when,
                  itemsInScope: 7, deltaToday: 0.1)
    }

    private func snapshot(_ hero: TodayHero) -> TodaySnapshot {
        var summary = TodaySummary()
        summary.plannedMinutes = 15
        summary.reviews = 12
        summary.newItems = 3
        summary.weakSpots = 2
        summary.sessionReady = true
        var snap = TodaySnapshot(hero: hero, summary: summary, streak: StreakState(current: 12), answersToday: 24,
                                 exams: [exam(), exam("Bio 101 Midterm", when: "29 Nov · in 23 days", readiness: 0.53, delta: 0.04, days: 23)],
                                 firstCourseID: nil, initials: "M")
        snap.focus = TodayFocus(exam: exam(), topics: ["Limiting reagents", "Stoichiometry"], forecast: 0.52, weakCount: 2,
                                dueCount: 12, newCount: 3)
        snap.eveTopics = ["Limiting reagents", "Stoichiometry"]
        return snap
    }

    private func states() -> [(String, TodaySnapshot)] {
        var list: [(String, TodaySnapshot)] = [("plan", snapshot(.session))]
        var partway = snapshot(.session)
        partway.summary.minutesDone = 6
        partway.summary.plannedMinutes = 9
        list.append(("partway", partway))
        var catchUp = snapshot(.catchUp)
        catchUp.summary.dueTotal = 142
        catchUp.summary.catchUpDaysToClear = 4
        list.append(("catchup", catchUp))
        var noExam = snapshot(.session)
        noExam.focus = nil
        noExam.sessionTopics = ["Cell cycle", "Moles", "Learning"]
        list.append(("noExam", noExam))
        list.append(("eve", snapshot(.examEve(examID))))
        var nothingWeak = snapshot(.examEve(examID))
        nothingWeak.eveHasWork = false
        list.append(("eveNothing", nothingWeak))
        list.append(("eveDone", snapshot(.examEveDone(examID))))
        var done = snapshot(.done)
        done.summary.minutesDone = 15
        done.doneExam = TodayDoneExam(title: "Chem 110 Quiz", readiness: 0.52, deltaToday: 0.10, daysLeft: 2)
        list.append(("done", done))
        var allLit = snapshot(.caughtUp)
        allLit.practice = TodayPractice(name: "Limiting reagents", topicID: UUID(), courseID: UUID())
        list.append(("allLit", allLit))
        list.append(("noMaterial", snapshot(.noMaterial)))
        list.append(("empty", snapshot(.empty)))
        return list
    }

    /// The states whose card holds the day's session: on an SE it must fit under the band.
    private let sessionStates: Set<String> = ["plan", "partway", "catchup", "noExam", "eve"]

    // MARK: Drawing

    @discardableResult
    private func render<V: View>(_ view: V, width: CGFloat, name: String, scheme: ColorScheme,
                                 size: DynamicTypeSize = .large) throws -> CGSize {
        let framed = view
            .frame(width: width - 2 * CLSpace.gutter)
            .padding(CLSpace.gutter)
            .background(scheme == .dark ? Color(hex: 0x0B1220) : Color(hex: 0xF1F5FA))
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, size)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, name)
        let suffix = "\(Int(width))-\(scheme == .dark ? "dark" : "light")\(size.isAccessibilitySize ? "-ax3" : "")"
        try XCTUnwrap(image.pngData(), name).write(to: Self.outputFolder.appending(path: "\(name)-\(suffix).png"))
        return CGSize(width: image.size.width, height: image.size.height - 2 * CLSpace.gutter)
    }

    func testEveryDayCardStateDrawsAtBothWidthsInLightDarkAndLargeText() throws {
        for (name, snap) in states() {
            let card = TodayDayCard(content: TodayHeroContent.make(snap), perform: { _ in }, onWhy: {})
            for width in [375.0, 402.0] {
                for scheme in [ColorScheme.light, .dark] {
                    let size = try render(card, width: width, name: "card-\(name)", scheme: scheme)
                    XCTAssertGreaterThan(size.height, 80, name)
                }
                try render(card, width: width, name: "card-\(name)", scheme: .light, size: .accessibility3)
            }
        }
    }

    func testOnAnSETheDaysCardFitsTheFirstScreen() throws {
        // An SE: 667 points tall, a 20-point status bar and a 49-point tab bar. Under the band (and the page's 16-point gap) the card,
        // its button included, must end above the tab bar.
        let band = HeroWorldGeometry.band(width: 375, topInset: 20, compact: false).height
        let room = 667 - 49 - band - 16
        for (name, snap) in states() where sessionStates.contains(name) {
            let card = TodayDayCard(content: TodayHeroContent.make(snap), perform: { _ in }, onWhy: {})
            let size = try render(card, width: 375, name: "se-\(name)", scheme: .light)
            XCTAssertLessThanOrEqual(size.height, room, "\(name): \(size.height) pt tall, \(room) pt of room")
        }
    }

    /// Every kind of Cap's card, in its real words: to be looked at, at the SE's width and the largest text size too.
    func testEveryKindOfCapsCard() throws {
        let cal = EngineTest.calendar()
        let now = EngineTest.date(2026, 10, 22, 16, in: cal)
        let examDate = cal.adding(days: 6, to: now)
        let days = [0, 1].map { FadeRescue.Day(dayKey: cal.dayKey(for: cal.adding(days: $0, to: now)), offset: $0, date: cal.adding(days: $0, to: now), itemIDs: []) }
        let rescue = FadeRescue(noticeID: "fade", examID: examID, examTitle: "Bio 101 Midterm", examDate: examDate, daysLeft: 6, dimCount: 18, dimShare: 0.4,
                                days: days, minutesPerDay: 6, kept: 18, origin: .source("Lecture 3"))
        let pair = LookAlikePair(id: "pair", a: UUID(), b: UUID(), termA: "Metaphase", termB: "Telophase", courseID: nil, topicID: nil, examID: examID,
                                 examTitle: "Bio 101 Midterm", examDate: examDate, daysLeft: 6, similarity: 0.67, linked: true)
        let spotted = ConfusionNote(id: UUID(), name: "Metaphase vs telophase", missCount: 0, recentMisses: 0, recentAnswers: 0)
        let missed = ConfusionNote(id: UUID(), name: "Anaphase vs telophase", missCount: 3, recentMisses: 3, recentAnswers: 4)
        let notices: [(String, Notice)] = [
            ("mixup", Notice(id: "m", kind: .mixUp, rank: 0, evidence: .mixUp(missed))),
            ("spotted", Notice(id: "s", kind: .mixUp, rank: 0, evidence: .mixUp(spotted))),
            ("lookalike", Notice(id: "p", kind: .lookAlike, rank: 0, evidence: .lookAlike(pair), cost: .cloud)),
            ("fading", Notice(id: "f", kind: .fading, rank: 0, evidence: .fading(rescue))),
            ("back", Notice(id: "b", kind: .welcomeBack, rank: 0, evidence: .welcomeBack(best: 23))),
        ]
        var cards = notices.map { ($0.0, NoticeContent.card($0.1, firstName: "Maya", now: now, calendar: cal)) }
        let boosts = days.map { PlanBoost(noticeID: "fade", examID: examID, examTitle: "Bio 101 Midterm", origin: "Lecture 3", dayKey: $0.dayKey, minutes: 6, itemIDs: []) }
        cards.append(("updated", try XCTUnwrap(NoticeContent.confirmation(boosts: boosts, now: now, calendar: cal))))
        for (name, notice) in cards {
            let view = TodayNoticeCard(notice: notice, index: 2, total: 3, onAction: { _ in }, onLater: {}, onOpen: { _ in })
            for width in [375.0, 402.0] {
                try render(view, width: width, name: "notice-\(name)", scheme: .light)
                try render(view, width: width, name: "notice-\(name)", scheme: .dark)
                try render(view, width: width, name: "notice-\(name)", scheme: .light, size: .accessibility3)
            }
        }
    }

    func testCapsCardTheQuietLineAndTheExams() throws {
        let note = ConfusionNote(id: UUID(), name: "Anaphase vs telophase", missCount: 3, recentMisses: 3, recentAnswers: 4)
        var noticed = NoticeContent.card(for: note)
        noticed.cost = "No AI"
        let card = TodayNoticeCard(notice: noticed, index: 1, total: 2, onAction: { _ in }, onLater: {}, onOpen: { _ in })
        let quiet = TodayQuietLine(text: TodayCopy.quietLine(examTitle: "Chem 110 Quiz", others: ["Bio 101", "AP Psychology"]))
        let exams = snapshot(.session).exams
        for width in [375.0, 402.0] {
            for scheme in [ColorScheme.light, .dark] {
                try render(card, width: width, name: "notice", scheme: scheme)
                try render(quiet, width: width, name: "quiet", scheme: scheme)
                // The row scrolls sideways (which an image renderer draws empty), so its tiles are drawn side by side here.
                let tiles = HStack(alignment: .top, spacing: 12) { ForEach(exams) { TodayExamTile(exam: $0, onOpen: {}) } }
                try render(tiles, width: width, name: "exams", scheme: scheme)
                try render(TodayAddExamCard(onAdd: {}), width: width, name: "addExam", scheme: scheme)
            }
            try render(card, width: width, name: "notice", scheme: .light, size: .accessibility3)
            try render(TodayExamsRow(exams: exams, onOpen: { _ in }, onSeeAll: {}), width: width, name: "exams", scheme: .light,
                       size: .accessibility3)
        }
    }
}
