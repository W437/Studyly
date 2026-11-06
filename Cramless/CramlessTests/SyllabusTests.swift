import XCTest
@testable import Cramless

/// "Snap the syllabus": dates read from text, the offline reader, the proposal's checks and what "Looks right" does, the router's ladder, and the exam made from a draft with new topics.
@MainActor
final class SyllabusTests: XCTestCase {
    let cal: Calendar = {
        var c = EngineTest.calendar()
        c.locale = Locale(identifier: "en_US")
        return c
    }()
    /// A Friday.
    lazy var now = EngineTest.date(2026, 11, 6, 14, in: cal)

    private func page(_ lines: [String]) -> [PageInput] {
        [PageInput(page: 0, label: "1", lines: lines.enumerated().map { LineInput(id: "p0.l\($0.offset)", text: $0.element) })]
    }

    private let topics = [SyllabusTopicInput(id: "t1", name: "Phases of mitosis"), SyllabusTopicInput(id: "t2", name: "Cytokinesis")]

    private func read(_ lines: [String], title: String? = nil) -> [SyllabusExam] {
        LocalSyllabus.read(pages: page(lines), topics: topics, examTitle: title, today: now, calendar: cal)
    }

    // MARK: Dates in text

    private func dates(_ text: String, from anchor: Date? = nil) -> [TextDates.Hit] {
        TextDates.find(in: text, from: anchor ?? now, calendar: cal)
    }

    func testAMonthAndDayIsTheNextTimeItComesRound() {
        XCTAssertEqual(dates("Midterm: Nov 20").first?.day, "2026-11-20")
        XCTAssertEqual(dates("Monday Oct 3").first?.day, "2027-10-03", "this year's has gone by")
        XCTAssertEqual(dates("the midterm is October 12th, 2026").first?.day, "2026-10-12", "a year that's named stays")
        XCTAssertEqual(dates("Midterm 11/14").first?.day, "2026-11-14")
        // Counted from the day it was said, not the day it's read.
        let recorded = EngineTest.date(2026, 2, 1, 10, in: cal)
        XCTAssertEqual(dates("the quiz is on March 3rd", from: recorded).first?.day, "2026-03-03")
    }

    func testAWeekdayCountsFromTheRecordingNotTheClock() {
        // A Wednesday.
        let recorded = EngineTest.date(2026, 2, 4, 10, in: cal)
        XCTAssertEqual(dates("the final is Friday", from: recorded).first?.day, "2026-02-06")
        XCTAssertEqual(dates("We'll have the quiz in class this Friday.", from: recorded).first?.day, "2026-02-06")
        XCTAssertEqual(dates("quiz next Friday at 2pm", from: recorded).first?.day, "2026-02-13", "next Friday, said midweek, is after this week's")
        XCTAssertEqual(dates("quiz next Friday at 2pm", from: recorded).first?.time, "14:00")
        XCTAssertEqual(dates("exam tomorrow", from: recorded).first?.day, "2026-02-05")
        XCTAssertEqual(dates("the exam is in two weeks", from: recorded).first?.day, "2026-02-18")
        XCTAssertEqual(dates("el examen es el viernes", from: recorded).first?.day, "2026-02-06", "a weekday in the detector's other languages")
        XCTAssertTrue(dates("the quiz was last Friday", from: recorded).isEmpty)
    }

    func testATimeIsOnlyWhatTheWordsSay() {
        XCTAssertNil(dates("Midterm: Nov 20").first?.time, "the detector says noon when none is given")
        XCTAssertEqual(dates("Friday, November 20, 10:00 AM").first?.time, "10:00")
        XCTAssertEqual(dates("Friday, November 20, 10:00 AM").first?.day, "2026-11-20", "the time's digits aren't the date's")
    }

    func testADayThatDoesNotExistIsNoDate() {
        XCTAssertNil(TextDates.date(day: "2027-02-30", calendar: cal))
        XCTAssertNil(TextDates.date(day: "soon", calendar: cal))
        XCTAssertEqual(cal.component(.hour, from: TextDates.date(day: "2027-02-20", calendar: cal)!), 9)
        XCTAssertEqual(cal.component(.hour, from: TextDates.date(day: "2027-02-20", time: "14:30", calendar: cal)!), 14)
    }

    // MARK: Exam words

    func testWhatIsAndIsNotAnExamWord() {
        XCTAssertEqual(ExamWords.first(in: "The midterm is soon")?.title, "Midterm")
        XCTAssertEqual(ExamWords.first(in: "the mid-term")?.title, "Midterm")
        XCTAssertEqual(ExamWords.first(in: "our final exam")?.title, "Final exam")
        XCTAssertEqual(ExamWords.first(in: "the finals")?.title, "Final")
        XCTAssertEqual(ExamWords.first(in: "Quiz 2 on Friday")?.title, "Quiz 2")
        XCTAssertEqual(ExamWords.first(in: "EXAMS")?.title, "Exam")
        for no in ["Your final paper", "a test tube", "the final answer", "a t-test", "final project", "the latest", "contest", "finally", "test results"] {
            XCTAssertNil(ExamWords.first(in: no), no)
        }
        XCTAssertNotNil(ExamWords.first(in: "el examen"))
        XCTAssertNotNil(ExamWords.first(in: "die Klausur"))
        XCTAssertNotNil(ExamWords.first(in: "מבחן ביום שישי"))
        XCTAssertTrue(ExamWords.sameExam("Bio 101 Midterm", "Midterm"))
        XCTAssertTrue(ExamWords.sameExam("Final", "Final exam"))
        XCTAssertFalse(ExamWords.sameExam("Midterm", "Final"))
        XCTAssertFalse(ExamWords.sameExam("Lab", "Lab"), "no exam word in them")
    }

    // MARK: The offline reader

    func testAHeadingWithItsTopicsUnderIt() throws {
        let exams = read(SyllabusSample.lines)
        XCTAssertEqual(exams.map(\.title), ["Midterm", "Final exam"], "the grading line names no exam")
        let midterm = try XCTUnwrap(exams.first)
        XCTAssertEqual(midterm.date, "2026-11-20", "from the line under the heading")
        XCTAssertEqual(midterm.time, "10:00")
        XCTAssertEqual(midterm.dateQuote, "Friday, November 20, 10:00 AM")
        XCTAssertEqual(midterm.topics.map(\.name), ["Phases of mitosis", "Cytokinesis", "Meiosis", "Genetics basics"])
        XCTAssertEqual(midterm.topics.map(\.topicId), ["t1", "t2", nil, nil])
        XCTAssertEqual(midterm.topics[0].lineIds, ["p0.l6"])
        XCTAssertEqual(midterm.format.multipleChoice, true)
        XCTAssertEqual(midterm.format.shortAnswer, true)
        XCTAssertEqual(midterm.format.questionCount, 40)
        XCTAssertEqual(midterm.format.minutes, 90)
        XCTAssertEqual(midterm.format.notes, "One page of notes")
        XCTAssertEqual(exams[1].date, "2026-12-14")
    }

    func testARowInASchedule() throws {
        let exams = read(["Week 1: Cells", "Week 2 - Mitosis (Nov 9)", "Lecture 3: Meiosis", "Week 4: Midterm (Dec 1)", "Wk 5: Genetics", "Week 6: Final (Dec 15)", "Week 7", "Spring break", "Homework 3 due"])
        XCTAssertEqual(exams.map(\.title), ["Midterm", "Final"])
        XCTAssertEqual(exams[0].date, "2026-12-01")
        XCTAssertEqual(exams[0].topics.map(\.name), ["Cells", "Mitosis", "Meiosis"], "a row is given what came before it, without the dates")
        XCTAssertEqual(exams[1].topics.map(\.name), ["Genetics"], "since the last exam")
    }

    func testChaptersAreNamedWhenThatIsAllThePageSays() throws {
        let exams = read(["Quiz 1: Nov 30", "Chapters 3 to 5", "Chapter 9: Enzymes"])
        XCTAssertEqual(exams.first?.title, "Quiz 1")
        XCTAssertEqual(exams.first?.topics.map(\.name), ["Chapter 3", "Chapter 4", "Chapter 5", "Enzymes"])
    }

    func testAPageWithOnlyASchedule() throws {
        let exams = read(["Week 1: Cells", "Week 2: Mitosis"], title: "Midterm")
        XCTAssertEqual(exams.map(\.title), ["Midterm"])
        XCTAssertNil(exams.first?.date)
        XCTAssertEqual(exams.first?.topics.count, 2)
    }

    func testAPageWithNothingOnIt() {
        XCTAssertTrue(read(["Office hours are on Tuesdays.", "Please read the policy on plagiarism."]).isEmpty)
        XCTAssertTrue(read(["Grading: midterm 30%, final 40%"]).isEmpty, "no exam is announced by its share of the grade")
        XCTAssertTrue(read(["Make-up exams are only given with a note from a doctor."]).isEmpty)
    }

    func testAFormatLineSaysOnlyWhatItSays() throws {
        let exam = try XCTUnwrap(read(["Final exam: Dec 14", "2 essays and 20 multiple choice. Two hours, open book."]).first)
        XCTAssertEqual(exam.format.essay, true)
        XCTAssertEqual(exam.format.multipleChoice, true)
        XCTAssertNil(exam.format.shortAnswer)
        XCTAssertEqual(exam.format.minutes, 120)
        XCTAssertEqual(exam.format.questionCount, 22, "the parts add up to the count")
        XCTAssertEqual(exam.format.notes, "Open book")
        XCTAssertEqual(exam.formatQuote, "2 essays and 20 multiple choice. Two hours, open book.")
    }

    func testATopicNearlyNamedIsTheCoursesOwn() {
        XCTAssertEqual(LocalSyllabus.match("phases of Mitosis", in: topics), "t1")
        XCTAssertEqual(LocalSyllabus.match("Mitosis phases", in: topics), "t1")
        XCTAssertNil(LocalSyllabus.match("Meiosis", in: topics))
    }

    // MARK: The proposal

    private let ids: [String: (id: UUID, name: String)] = ["t1": (UUID(), "Phases of mitosis"), "t2": (UUID(), "Cytokinesis")]

    private func exam(title: String = "Midterm", date: String? = "2026-11-20", time: String? = "10:00", quote: String? = "Friday, November 20, 10:00 AM",
                      topics: [SyllabusTopic] = [], format: SyllabusFormat = SyllabusFormat()) -> SyllabusExam {
        SyllabusExam(title: title, date: date, time: time, dateQuote: quote, topics: topics, format: format)
    }

    private func proposal(_ exams: [SyllabusExam], title: String = "", base: ExamDraft? = nil, text: String? = nil) -> SyllabusProposal? {
        SyllabusProposal.make(exams: exams, examTitle: title, topicIDs: ids, base: base ?? ExamDraft(date: now), pageText: text ?? SyllabusSample.text,
                              origin: .cloud, now: now, calendar: cal)
    }

    func testADateNeedsItsWordsOnThePage() throws {
        let topic = [SyllabusTopic(name: "Meiosis", lineIds: [])]
        XCTAssertNotNil(try XCTUnwrap(proposal([exam(topics: topic)])).date)
        let made = try XCTUnwrap(proposal([exam(quote: "Friday, November 27", topics: topic)]))
        XCTAssertNil(made.date, "the model's date isn't on the page")
        XCTAssertNil(made.dateQuote)
        XCTAssertNil(try XCTUnwrap(proposal([exam(quote: nil, topics: topic)])).date, "a date with no words behind it")
        // Line breaks and capitals don't change the words.
        XCTAssertNotNil(proposal([exam(topics: topic)], text: "FRIDAY, NOVEMBER 20,\n10:00 AM")?.date)
    }

    func testADateHasToBeWithinReach() throws {
        let topic = [SyllabusTopic(name: "Meiosis", lineIds: [])]
        XCTAssertNil(try XCTUnwrap(proposal([exam(date: "2026-11-05", topics: topic)])).date, "gone by")
        XCTAssertNil(try XCTUnwrap(proposal([exam(date: "2028-01-01", topics: topic)])).date, "over 400 days off")
        XCTAssertNotNil(proposal([exam(date: "2026-11-06", topics: topic)])?.date, "today")
    }

    func testNothingToSayIsNoProposal() {
        XCTAssertNil(proposal([]))
        XCTAssertNil(proposal([exam(date: nil, quote: nil)]))
        XCTAssertNil(proposal([exam(quote: "Not on the page")]), "its only claim didn't check out")
    }

    func testTheExamBeingEditedIsChosenElseTheSoonest() throws {
        let midterm = exam(topics: [SyllabusTopic(name: "A", lineIds: [])])
        let final = exam(title: "Final exam", date: "2026-12-14", time: nil, quote: "December 14", topics: [SyllabusTopic(name: "B", lineIds: [])])
        XCTAssertEqual(proposal([final, midterm])?.title, "Midterm", "the soonest")
        let picked = try XCTUnwrap(proposal([midterm, final], title: "Bio 101 Final"))
        XCTAssertEqual(picked.title, "Final exam")
        XCTAssertEqual(picked.others, [SyllabusProposal.OtherExam(title: "Midterm", date: TextDates.date(day: "2026-11-20", time: "10:00", calendar: cal))])
        XCTAssertEqual(SyllabusCopy.alsoOnIt(picked.others, calendar: cal), "Also on this syllabus: Midterm, Nov 20")
        XCTAssertNil(SyllabusCopy.alsoOnIt([], calendar: cal))
    }

    func testTopicsAreTheCoursesByIdAndTheNewOnesCapped() throws {
        var named = [SyllabusTopic(name: "Whatever the model called it", topicId: "t1", lineIds: []),
                     SyllabusTopic(name: "Unknown id", topicId: "t99", lineIds: []),
                     SyllabusTopic(name: "unknown ID", lineIds: []), SyllabusTopic(name: "  ", lineIds: [])]
        named += (0..<30).map { SyllabusTopic(name: "New \($0)", lineIds: []) }
        let made = try XCTUnwrap(proposal([exam(topics: named)]))
        XCTAssertEqual(made.topics[0].name, "Phases of mitosis", "the course's own name")
        XCTAssertEqual(made.topics[0].existingID, ids["t1"]?.id)
        XCTAssertEqual(made.topics[1].name, "Unknown id")
        XCTAssertTrue(made.topics[1].isNew)
        XCTAssertEqual(made.topics.filter { $0.name.lowercased() == "unknown id" }.count, 1, "the same name once")
        XCTAssertEqual(made.topics.filter(\.isNew).count, SyllabusProposal.maxNewTopics)
        XCTAssertEqual(SyllabusProposal.requestIDs(for: [(UUID(), "A"), (UUID(), "B")]).keys.sorted(), ["t1", "t2"])
    }

    func testTheFormatOnlyChangesWhatIsSaid() throws {
        let topic = [SyllabusTopic(name: "A", lineIds: [])]
        var base = ExamDraft(date: now)
        base.format.notes = "Bring a pencil"
        base.format.minutes = 45
        let nothing = try XCTUnwrap(proposal([exam(topics: topic)], base: base))
        XCTAssertFalse(nothing.formatKnown)
        XCTAssertEqual(nothing.format, base.format)

        let said = SyllabusFormat(multipleChoice: true, questionCount: 40, notes: "Open book")
        let made = try XCTUnwrap(proposal([exam(topics: topic, format: said)], base: base))
        XCTAssertTrue(made.formatKnown)
        XCTAssertEqual(made.format.multipleChoice, true)
        XCTAssertEqual(made.format.shortAnswer, false, "\"multiple choice\" rules out what it doesn't name")
        XCTAssertEqual(made.format.essay, false)
        XCTAssertEqual(made.format.questionCount, 40)
        XCTAssertEqual(made.format.minutes, 45, "not said, so kept")
        XCTAssertEqual(made.format.notes, "Bring a pencil", "the person's own words stay")
    }

    func testLooksRightFillsTheDraftAndStoresNothing() throws {
        let topics = [SyllabusTopic(name: "x", topicId: "t2", lineIds: []), SyllabusTopic(name: "Meiosis", lineIds: []), SyllabusTopic(name: "Genetics", lineIds: [])]
        var made = try XCTUnwrap(proposal([exam(topics: topics, format: SyllabusFormat(minutes: 90))]))
        made.topics[2].included = false
        var draft = ExamDraft(courseID: UUID(), date: EngineTest.date(2026, 12, 1, 15, in: cal))
        made.apply(to: &draft, courseName: "Bio 101", calendar: cal)
        XCTAssertEqual(draft.title, "Bio 101 Midterm")
        XCTAssertEqual(draft.date, EngineTest.date(2026, 11, 20, 10, in: cal), "a time from the page")
        XCTAssertFalse(draft.wholeCourse)
        XCTAssertEqual(draft.scope, [ids["t2"]!.id])
        XCTAssertEqual(draft.newTopics, ["Meiosis"], "unticked stays out")
        XCTAssertEqual(draft.format.minutes, 90)
        XCTAssertTrue(draft.fromSyllabus)
        XCTAssertNil(draft.problem)

        var titled = ExamDraft(title: "My midterm", date: EngineTest.date(2026, 12, 1, 15, in: cal))
        made.hasTime = false
        made.apply(to: &titled, courseName: "Bio 101", calendar: cal)
        XCTAssertEqual(titled.title, "My midterm", "a name already typed stays")
        XCTAssertEqual(titled.date, EngineTest.date(2026, 11, 20, 15, in: cal), "no time on the page: the draft keeps its hour")
    }

    func testWithNoTopicsWhatsOnItStaysAsItWas() throws {
        let made = try XCTUnwrap(proposal([exam()]))
        var draft = ExamDraft(date: now)
        made.apply(to: &draft, courseName: "", calendar: cal)
        XCTAssertTrue(draft.wholeCourse)
        XCTAssertEqual(draft.title, "Midterm")
        XCTAssertTrue(draft.fromSyllabus)
    }

    func testADraftWithOnlyNewTopicsCanBeSaved() {
        var draft = ExamDraft(courseID: UUID(), date: now, wholeCourse: false)
        XCTAssertNotNil(draft.problem)
        draft.newTopics = ["Meiosis"]
        XCTAssertNil(draft.problem)
    }

    // MARK: The router's ladder

    private func input(_ base: ExamDraft? = nil) -> SyllabusInput {
        SyllabusInput(course: "Bio 101", examTitle: "", topics: [(UUID(), "Cytokinesis")],
                      pages: SyllabusSample.pages, base: base ?? ExamDraft(date: now))
    }

    private func makeApp(mode: AppConfig.AIMode, consent: Bool) -> AppModel {
        let app = AITestSupport.makeApp(mode: mode, consent: consent)
        let frozen = now
        app.clock = { frozen }
        app.calendar = cal
        return app
    }

    func testCloudAIReadsItWhenAllowedWithTheCoursesTopicsAndNoPhoto() async throws {
        let app = makeApp(mode: .mock, consent: true)
        let spy = SyllabusSpy()
        app.ai.transportOverride = spy
        let outcome = await app.ai.readSyllabus(input())
        XCTAssertEqual(outcome.origin, .cloud)
        let made = try XCTUnwrap(outcome.proposal)
        XCTAssertEqual(made.title, "Midterm")
        XCTAssertEqual(made.date, EngineTest.date(2026, 11, 20, 10, in: cal))
        XCTAssertEqual(made.topics.first { $0.name == "Cytokinesis" }?.isNew, false)
        XCTAssertEqual(made.topics.first { $0.name == "Meiosis" }?.isNew, true)
        XCTAssertEqual(made.others.first?.title, "Final exam")
        let sent = try XCTUnwrap(spy.requests.first)
        XCTAssertEqual(sent.today, "2026-11-06")
        XCTAssertEqual(sent.topics, [SyllabusTopicInput(id: "t1", name: "Cytokinesis")])
        XCTAssertTrue(sent.pages.allSatisfy { $0.image == nil }, "only the words")
        XCTAssertNil(sent.examTitle, "no name yet")
    }

    func testWithoutConsentTheRulesAnswerAndCloudAIIsOffered() async throws {
        let app = makeApp(mode: .relay, consent: false)
        let spy = SyllabusSpy()
        app.ai.transportOverride = spy
        let outcome = await app.ai.readSyllabus(input())
        XCTAssertTrue(spy.requests.isEmpty, "nothing leaves")
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertEqual(outcome.proposal?.origin, .rules)
        XCTAssertEqual(outcome.proposal?.title, "Midterm")
        XCTAssertEqual(outcome.suggestion, .allowCloud(feature: AIJob.syllabus.feature))
    }

    func testAFailureOrAnOlderRelayFallsBackQuietly() async throws {
        let app = makeApp(mode: .mock, consent: true)
        // A relay older than the route answers 404, which reaches here as an error.
        let spy = SyllabusSpy()
        spy.syllabusError = .upstream("Not found.")
        app.ai.transportOverride = spy
        let outcome = await app.ai.readSyllabus(input())
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertNotNil(outcome.proposal)
        XCTAssertNil(outcome.suggestion, "Cloud AI is on: there's nothing to ask for")
    }

    func testUnder13NothingIsSent() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: true, age: .under13)
        app.clock = { [now] in now }
        app.calendar = cal
        let spy = SyllabusSpy()
        app.ai.transportOverride = spy
        _ = await app.ai.readSyllabus(input())
        XCTAssertTrue(spy.requests.isEmpty)
    }

    // MARK: The exam made from it

    func testCreateAndUpdateMakeTheNewTopicsInOneSave() throws {
        let app = makeApp(mode: .local, consent: false)
        let course = try XCTUnwrap(app.createCourse(name: "Bio 101", color: .sky, symbol: "leaf"))
        let known = try XCTUnwrap(ItemFactory.topic(named: "Cytokinesis", in: course, now: now))
        let before = app.revision
        var draft = ExamDraft(title: "Midterm", courseID: course.id, date: cal.adding(days: 14, to: now), wholeCourse: false, scope: [known.id])
        draft.newTopics = ["Meiosis", "cytokinesis"]
        let exam = try XCTUnwrap(app.createExam(draft))
        XCTAssertEqual(app.revision, before + 1, "one save")
        let meiosis = try XCTUnwrap(course.liveTopics.first { $0.name == "Meiosis" })
        XCTAssertEqual(Set(exam.scope), [known.id, meiosis.id])
        XCTAssertEqual(course.liveTopics.count, 2, "a topic the course has is reused")

        var edit = ExamDraft(exam: exam)
        edit.newTopics = ["Genetics"]
        app.updateExam(exam.id, with: edit)
        let genetics = try XCTUnwrap(course.liveTopics.first { $0.name == "Genetics" })
        XCTAssertTrue(exam.scope.contains(genetics.id))

        // A whole-course exam takes the new topic in by being the course's.
        var whole = ExamDraft(title: "Final", courseID: course.id, date: cal.adding(days: 30, to: now))
        whole.newTopics = ["DNA"]
        let final = try XCTUnwrap(app.createExam(whole))
        XCTAssertTrue(final.scope.isEmpty)
        XCTAssertNotNil(course.liveTopics.first { $0.name == "DNA" })
    }

    func testAnOldExamFormatStillDecodes() throws {
        // A new topic with nothing on it is a gap for the exam (`ExamGapTests`); the draft's own fields aren't stored.
        let format = try JSONDecoder.cramless.decode(ExamFormat.self, from: Data(#"{"multipleChoice":true,"shortAnswer":false,"essay":false,"notes":""}"#.utf8))
        XCTAssertNil(format.questionCount)
    }
}

/// A transport that records syllabus requests and answers like the mock.
final class SyllabusSpy: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let base = MockRelayTransport(latencyScale: 0)
    private var asked: [SyllabusRequest] = []
    private var askedMentions: [ExamMentionRequest] = []
    var mentionVerdict: ExamMentionVerdict?
    var syllabusError: RelayError?

    var requests: [SyllabusRequest] { lock.withLock { asked } }
    var mentionRequests: [ExamMentionRequest] { lock.withLock { askedMentions } }

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse { try await base.generate(request) }
    func check(_ request: CheckRequest) async throws -> CheckResponse { try await base.check(request) }
    func grade(_ request: GradeRequest) async throws -> GradeResponse { try await base.grade(request) }
    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> { base.tutor(request) }
    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse { try await base.confusions(request) }
    func lecture(_ request: LectureRequest) async throws -> LectureResponse { try await base.lecture(request) }
    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse { try await base.cardsFromChat(request) }
    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse { try await base.transcribeImage(request) }
    func quota() async throws -> QuotaStatus { try await base.quota() }

    func syllabus(_ request: SyllabusRequest) async throws -> SyllabusResponse {
        lock.withLock { asked.append(request) }
        if let syllabusError { throw syllabusError }
        return try await base.syllabus(request)
    }

    func examMention(_ request: ExamMentionRequest) async throws -> ExamMentionResponse {
        lock.withLock { askedMentions.append(request) }
        if let mentionVerdict { return ExamMentionResponse(model: "mock", mentions: [mentionVerdict]) }
        return try await base.examMention(request)
    }
}
