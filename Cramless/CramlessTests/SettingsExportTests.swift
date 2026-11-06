import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// Settings ▸ Your data: the cards as CSV and everything as JSON, from a real store. Plus the words Settings shows
/// for a backend error, a name's initials and the retention target.
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
        XCTAssertTrue(StudyPage.retentionText(0.85).contains("Fewer reviews"))
        XCTAssertTrue(StudyPage.retentionText(0.90).contains("sweet spot"))
        XCTAssertTrue(StudyPage.retentionText(0.95).contains("More reviews"))
        XCTAssertTrue(StudyPage.retentionText(0.93).hasPrefix("Each card comes back when you're about 93% likely"))
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
