import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// Settings ▸ Your data: the cards as CSV and everything as JSON, from a real store. Plus the words Settings shows
/// for a backend error, a name's initials and the retention target, and the root's rows, the pages' trails and Hidden tips.
@MainActor
final class SettingsExportTests: AskTestCase {

    // MARK: CSV

    func testCSVFieldsAreQuotedAndFormulasDefused() {
        XCTAssertEqual(DataExport.field("plain"), "plain")
        XCTAssertEqual(DataExport.field("2, identical"), "\"2, identical\"")
        XCTAssertEqual(DataExport.field("the \"metaphase plate\""), "\"the \"\"metaphase plate\"\"\"")
        XCTAssertEqual(DataExport.field("line one\nline two"), "\"line one\nline two\"")
        XCTAssertEqual(DataExport.field("=SUM(A1:A2)"), "'=SUM(A1:A2)")
        XCTAssertEqual(DataExport.field("@home"), "'@home")
        XCTAssertEqual(DataExport.field("-3 is negative"), "-3 is negative", "a leading minus is ordinary text")
    }

    func testCardsAsCSVFromTheStore() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let topic = try XCTUnwrap(ItemFactory.topic(named: "Cytokinesis", in: bio.course, now: app.now))
        func add(_ item: StudyItem) { app.context.insert(item); bio.course.items.append(item) }
        add(StudyItem(course: bio.course, topicID: topic.id, kind: .flashcard, status: .active, origin: .person,
                      prompt: "Mitosis vs cytokinesis", answer: "Mitosis splits the nucleus, cytokinesis the \"rest\"."))
        add(StudyItem(course: bio.course, kind: .mcq, status: .active, origin: .cloud, prompt: "Which happens first?", answer: "Mitosis",
                      choices: [Choice(text: "Mitosis", correct: true), Choice(text: "Cytokinesis", correct: false)]))
        add(StudyItem(course: bio.course, kind: .cloze, status: .suspended, origin: .rules, prompt: "Fill in the word.", answer: "cytoplasm",
                      cloze: ClozeSpec(text: "Cytokinesis divides the {{cytoplasm}}.")))
        let trashed = StudyItem(course: bio.course, kind: .flashcard, status: .active, origin: .person, prompt: "Gone", answer: "Gone")
        trashed.deletedAt = app.now
        add(trashed)
        add(StudyItem(course: bio.course, kind: .flashcard, status: .draft, origin: .cloud, prompt: "Draft", answer: "Not approved"))
        app.save()

        let rows = DataExport.cardRows(app: app)
        XCTAssertEqual(rows.map(\.question), ["Mitosis vs cytokinesis", "Which happens first?", "Cytokinesis divides the ____."],
                       "trashed and draft cards stay out")
        XCTAssertEqual(rows[0].topic, "Cytokinesis")
        XCTAssertEqual(rows[1].options, ["Mitosis", "Cytokinesis"])
        XCTAssertEqual(rows[1].answer, "Mitosis")
        XCTAssertEqual(rows[2].answer, "cytoplasm")
        XCTAssertEqual(rows[2].status, "suspended")

        let csv = DataExport.csv(rows)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], "Course,Topic,Type,Question,Answer,Options,Explanation,Source,Status,Due,Reviews,Lapses")
        XCTAssertTrue(lines[1].hasPrefix("Bio 101,Cytokinesis,Flashcard,Mitosis vs cytokinesis,\"Mitosis splits the nucleus, cytokinesis the \"\"rest\"\".\""), lines[1])
        XCTAssertTrue(lines[2].contains(",Mitosis | Cytokinesis,"), lines[2])
    }

    // MARK: JSON

    func testEverythingAsJSONRoundTrips() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let item = StudyItem(course: bio.course, kind: .flashcard, status: .active, origin: .person, prompt: "Diffusion", answer: "High to low")
        app.context.insert(item)
        bio.course.items.append(item)
        let gone = Course(name: "Old course", now: app.now)
        gone.deletedAt = app.now
        app.context.insert(gone)
        let log = ReviewLog(itemID: item.id, courseID: bio.course.id, sessionID: nil, reviewedAt: app.now, rating: .good, score: 0.8,
                            answer: "from high to low", gradedBy: "rules", durationMs: 9000, before: .new, after: item.memory,
                            elapsedDays: 0, scheduledDays: 1)
        app.context.insert(log)
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("What happens after mitosis?", to: thread)
        app.saveAnswer(TutorOutcome(text: "Cytokinesis.", citations: [Citation(id: "c", sourceID: bio.textbook.id, pageIndex: 0, start: nil,
                                                                               quote: "After mitosis, cytokinesis takes place.", label: "Textbook p. 87")],
                                    origin: .cloud, model: "m", mode: .explain, grounded: true), to: thread)
        var s = app.settings
        s.firstName = "Maya"
        s.easyDays = [1, 7]
        app.settings = s
        app.save()

        let data = try DataExport.json(DataExport.archive(app: app))
        let archive = try DataExport.decode(data)
        XCTAssertEqual(archive.format, "capling-export")
        XCTAssertEqual(archive.profile.firstName, "Maya")
        XCTAssertEqual(archive.profile.easyDays, [1, 7])
        XCTAssertEqual(archive.courses.map(\.name), ["Bio 101"], "a course in the trash stays out")
        let course = try XCTUnwrap(archive.courses.first)
        XCTAssertEqual(course.sources.count, 2)
        XCTAssertEqual(course.sources.first { $0.kind == "lecture" }?.transcript.count, AITestSupport.lectureSegments.count)
        XCTAssertTrue(course.sources.first { $0.kind == "sample" }?.pages.first?.text.contains("cytokinesis takes place") ?? false)
        XCTAssertEqual(course.items.map(\.prompt), ["Diffusion"])
        XCTAssertEqual(archive.reviews.count, 1)
        XCTAssertEqual(archive.reviews.first?.score, 0.8)
        XCTAssertEqual(archive.chats.count, 1)
        XCTAssertEqual(archive.chats.first?.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(archive.chats.first?.messages.last?.citations.first?.label, "Textbook p. 87")
        // Readable as text, with dates a person can read.
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"exportedAt\" : \""), "ISO 8601 dates")
    }

    func testQuietModeSurvivesTheSettingsAndTheExport() throws {
        let app = makeApp()
        XCTAssertFalse(app.settings.quietMode, "off until someone turns it on")
        app.settings.quietMode = true
        XCTAssertEqual(DataExport.archive(app: app).profile.quietMode, true)
        let data = try JSONEncoder().encode(app.settings)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).quietMode)
        // Settings saved before it existed read as off.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["quietMode"] = nil
        let older = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: older).quietMode)
    }

    func testExportFileNamesAreDated() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        XCTAssertEqual(DataExport.fileName("Capling cards", ext: "csv", date: date), "Capling cards 2026-10-22.csv")
    }

    func testAnExportFileIsWrittenWhereTheShareSheetCanReadIt() throws {
        let file = ExportFile(data: Data("a,b\r\n".utf8), fileName: "Capling cards 2026-10-22.csv")
        let url = try file.write()
        XCTAssertEqual(url.lastPathComponent, "Capling cards 2026-10-22.csv")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a,b\r\n")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Words Settings shows

    func testBackendErrorsInPlainWords() {
        XCTAssertNil(RelayError.cancelled.friendlyMessage, "a cancelled call says nothing")
        XCTAssertEqual(RelayError.badRequest("That code didn't work.").friendlyMessage, "That code didn't work.")
        XCTAssertEqual(RelayError.entitlementRequired.friendlyMessage, "Inviting friends is part of the Squad plan.")
        XCTAssertTrue(RelayError.notConfigured.friendlyMessage?.hasPrefix("Accounts aren't set up in this build") ?? false)
        XCTAssertEqual(RelayError.message(for: URLError(.notConnectedToInternet)), RelayError.offline.friendlyMessage)
    }

    func testInitialsAndTheRetentionTarget() {
        XCTAssertEqual(InitialsAvatar.initials("Maya"), "M")
        XCTAssertEqual(InitialsAvatar.initials("maya rivera lopez"), "MR")
        XCTAssertEqual(InitialsAvatar.initials("  "), "")
        XCTAssertTrue(RetentionPage.retentionText(0.85).contains("Fewer reviews"))
        XCTAssertTrue(RetentionPage.retentionText(0.90).contains("sweet spot"))
        XCTAssertTrue(RetentionPage.retentionText(0.95).contains("More reviews"))
        XCTAssertTrue(RetentionPage.retentionText(0.93).hasPrefix("Each question comes back when you're about 93% likely"))
        // Its row on More names the band in words: readiness keeps the only percentage outside the slider's own page.
        XCTAssertEqual(String(localized: RetentionPage.bandName(0.9)), "The sweet spot for most people")
        XCTAssertFalse(String(localized: RetentionPage.bandName(0.86)).contains("%"))
    }

    // MARK: The Settings root and its pages

    func testTheRootIsEightRowsWithNoPlanOrSaleAtTheTop() {
        XCTAssertEqual(SettingsView.rows.flatMap { $0 },
                       [.account, .subscription, .study, .notifications, .aiPrivacy, .accessibility, .appearance, .more])
        XCTAssertEqual(SettingsView.rows.flatMap { $0 }.map { String(localized: $0.title) },
                       ["Account", "Subscription", "Study", "Notifications", "AI and privacy", "Accessibility", "Appearance", "More"])
        XCTAssertFalse(SettingsView.rows.joined().contains(.assistant), "What Cap can do is inside AI and privacy")
    }

    func testAPageDeeperDownIsReachedThroughItsParents() {
        XCTAssertEqual(SettingsPage.help.trail, [.more, .help])
        XCTAssertEqual(SettingsPage.data.trail, [.more, .data])
        XCTAssertEqual(SettingsPage.retention.trail, [.more, .retention])
        XCTAssertEqual(SettingsPage.fontLicences.trail, [.more, .about, .fontLicences])
        XCTAssertEqual(SettingsPage.hiddenTips.trail, [.study, .hiddenTips])
        XCTAssertEqual(SettingsPage.notifications.trail, [.notifications])
        XCTAssertEqual(SettingsPage.assistant.trail, [.assistant], "its own route still opens it directly")
        let app = makeApp()
        app.settings.onboardingCompleted = true
        DeepLinks.handle(CramlessLink.settings(page: "about"), app: app)
        XCTAssertEqual(app.router.paths[.today], [.settings, .settingsPage(.more), .settingsPage(.about)])
    }

    func testEachRowSaysWhereItsPageStands() {
        let app = makeApp()
        app.settings.dailyMinutes = 15
        app.settings.reminderMinutes = 19 * 60
        app.settings.easyDays = []
        app.settings.quietMode = false
        XCTAssertEqual(SettingsSummary.line(.study, app: app), "15 min a day")
        XCTAssertEqual(SettingsSummary.line(.notifications, app: app),
                       "Reminder at \(QuizContent.timeString(minutes: 19 * 60)), exam countdowns")
        app.settings.reminderMinutes = nil
        XCTAssertEqual(SettingsSummary.line(.notifications, app: app), "Exam countdowns only")
        app.settings.quietMode = true
        XCTAssertEqual(SettingsSummary.line(.study, app: app), "15 min a day, Quiet mode on")
        XCTAssertEqual(SettingsSummary.line(.more, app: app), "Help, your data and About")
        XCTAssertFalse(SettingsSummary.line(.about, app: app)?.contains(AboutInfo.version) ?? true, "the version is only on About")
    }

    func testHiddenTipsListOnlyTheKindsSwitchedOff() {
        let app = makeApp()
        app.settings.notices.off = []
        XCTAssertTrue(HiddenTipsPage.hidden(app.settings).isEmpty, "nothing hidden: Study shows no row for it")
        XCTAssertNil(SettingsSummary.line(.hiddenTips, app: app))
        app.setNoticeKind(.busyDay, on: false)
        app.setNoticeKind(.mixUp, on: false)
        XCTAssertEqual(HiddenTipsPage.hidden(app.settings), [.mixUp, .busyDay], "in the order Cap deals them")
        XCTAssertEqual(SettingsSummary.line(.hiddenTips, app: app),
                       [NoticeContent.switchTitle(.mixUp), NoticeContent.switchTitle(.busyDay)].map { String(localized: $0) }
                           .formatted(.list(type: .and)))
        app.setNoticeKind(.mixUp, on: true)
        XCTAssertEqual(HiddenTipsPage.hidden(app.settings), [.busyDay], "Show again brings a kind back")
    }

    func testHelpIsOneLineAndAWayToWrite() {
        XCTAssertEqual(String(localized: HelpCopy.intro), "Questions, a bug or a surprise charge? A real person reads every message.")
        XCTAssertEqual(String(localized: HelpCopy.writeTitle), "Write to us")
    }

    func testDeletingAllDataEmptiesTheStoreAndRestartsOnboarding() {
        let app = makeApp()
        makeBio(app)
        let thread = app.startChat(courseID: nil)
        app.addQuestion("What is diffusion?", to: thread)
        app.settings.onboardingCompleted = true
        app.wipeLocalData()
        XCTAssertTrue(app.courses.isEmpty)
        XCTAssertTrue(app.chatThreads().isEmpty)
        XCTAssertFalse(app.settings.onboardingCompleted)
        XCTAssertTrue(DataExport.cardRows(app: app).isEmpty)
    }
}
