import XCTest
@testable import Cramless

/// "Fill the gap": what counts as a gap, Cap's card about it, the words, a capture aimed at a topic, and the research note.
@MainActor
final class ExamGapTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 11, 6, 14, in: cal)
    let course = UUID()

    private func snapshot(days: Int = 12) -> ExamSnapshot {
        ExamSnapshot(courseID: course, title: "Bio 101 Midterm", date: cal.adding(days: days, to: now))
    }

    private func topic(_ name: String, _ value: Double?, items: Int = 0) -> TopicReadiness {
        TopicReadiness(id: UUID(), name: name, value: value, itemCount: items)
    }

    // MARK: What a gap is

    func testAGapIsATopicWithNothingOnIt() throws {
        let draft = topic("Genetics", nil)
        let list = [topic("Mitosis", 0.6, items: 4), topic("Meiosis", nil), draft, topic("New but unstudied", 0, items: 3)]
        let gap = try XCTUnwrap(ExamGaps.find(exam: snapshot(), topicReadiness: list, draftTopicIDs: [draft.id], daysLeft: 12))
        XCTAssertEqual(gap.topics.map(\.name), ["Meiosis"], "a topic with questions, studied or not, isn't one")
        XCTAssertEqual(gap.waiting.map(\.name), ["Genetics"], "drafts waiting only need a look")
        XCTAssertEqual(gap.examTitle, "Bio 101 Midterm")
        XCTAssertEqual(gap.daysLeft, 12)
    }

    func testNoGapsNoCard() {
        XCTAssertNil(ExamGaps.find(exam: snapshot(), topicReadiness: [topic("Mitosis", 0.6, items: 4)], draftTopicIDs: [], daysLeft: 12))
        XCTAssertNil(ExamGaps.find(exam: snapshot(), topicReadiness: [], draftTopicIDs: [], daysLeft: 12))
    }

    func testTheWindow() {
        let gaps = [topic("Meiosis", nil)]
        XCTAssertNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 29), "too far off for Cap to bring up")
        XCTAssertNotNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 28))
        XCTAssertNotNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 2))
        XCTAssertNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 1), "the eve is too late")
        XCTAssertNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 0))
        XCTAssertNotNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 90, within: nil), "the exam page shows it at any distance")
        XCTAssertNil(ExamGaps.find(exam: snapshot(), topicReadiness: gaps, draftTopicIDs: [], daysLeft: 1, within: nil))
    }

    // MARK: The words

    func testTheWords() {
        XCTAssertEqual(ExamGapCopy.title(count: 2, examTitle: "Midterm"), "2 topics on your Midterm have no notes")
        XCTAssertEqual(ExamGapCopy.title(count: 1, examTitle: "Midterm"), "1 topic on your Midterm has no notes")
        XCTAssertEqual(ExamGapCopy.detail(["Meiosis"]), "Meiosis. Want help filling it in?")
        XCTAssertEqual(ExamGapCopy.detail(["Meiosis", "Genetics"]), "Meiosis and Genetics. Want help filling them in?")
        XCTAssertEqual(ExamGapCopy.detail(["A", "B", "C", "D", "E"]), "A, B, C and 2 more. Want help filling them in?")
        XCTAssertEqual(ExamGapCopy.waiting(["Meiosis"]), "Questions for Meiosis are waiting for your review.")
    }

    // MARK: Aimed captures

    private func makeApp() throws -> (AppModel, Course) {
        let app = AITestSupport.makeApp()
        app.calendar = cal
        let frozen = now
        app.clock = { frozen }
        return (app, try XCTUnwrap(app.createCourse(name: "Bio 101", color: .sky, symbol: "leaf")))
    }

    private func draftInput() -> DraftInput {
        DraftInput(GenerationOutcome(title: "Chapter", topics: [GeneratedTopic(name: "Whatever it thinks", summary: "")], items: [
            GeneratedItem(id: "a", kind: .flashcard, topic: "Whatever it thinks", prompt: "What is meiosis?", answer: "Division into four cells."),
            GeneratedItem(id: "b", kind: .flashcard, topic: "Something else", prompt: "How many cells?", answer: "Four."),
        ], dropped: [], origin: .cloud, model: "mock", checkedBy: .cloud, note: nil, suggestion: nil, limitReached: nil, fellBack: false))
    }

    func testACaptureAimedAtATopicPutsEveryQuestionThereAndMakesNoOther() throws {
        let (app, course) = try makeApp()
        let meiosis = try XCTUnwrap(ItemFactory.topic(named: "Meiosis", in: course, now: now))
        let source = try app.createSource(fromText: "Meiosis makes four cells.", title: "Chapter 9", course: course)
        let drafts = app.makeDrafts(draftInput(), source: source, course: course, topicID: meiosis.id)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.topicID == meiosis.id })
        XCTAssertEqual(course.liveTopics.map(\.name), ["Meiosis"], "the generator's own names made nothing")
        XCTAssertTrue(drafts.allSatisfy { $0.status == .draft }, "they still go through review")
    }

    func testWithoutAnAimTheGeneratorsTopicsAreMadeAsAlways() throws {
        let (app, course) = try makeApp()
        let source = try app.createSource(fromText: "Meiosis makes four cells.", title: "Chapter 9", course: course)
        let drafts = app.makeDrafts(draftInput(), source: source, course: course)
        XCTAssertEqual(Set(course.liveTopics.map(\.name)), ["Whatever it thinks", "Something else"])
        XCTAssertEqual(drafts.compactMap(\.topicID).count, 2)
    }

    func testAnAimAtAnotherCoursesTopicIsIgnored() throws {
        let (app, course) = try makeApp()
        let other = try XCTUnwrap(app.createCourse(name: "Chem", color: .mint, symbol: "flask"))
        let elsewhere = try XCTUnwrap(ItemFactory.topic(named: "Moles", in: other, now: now))
        let source = try app.createSource(fromText: "Meiosis makes four cells.", title: "Chapter 9", course: course)
        let drafts = app.makeDrafts(draftInput(), source: source, course: course, topicID: elsewhere.id)
        XCTAssertFalse(drafts.contains { $0.topicID == elsewhere.id })
    }

    func testTheRequestCarriesItsAim() {
        let topic = UUID()
        let plan = Coverage.Rest(sourceID: UUID(), anchorIDs: [], pages: [], sections: 1, startsOver: false)
        XCTAssertEqual(CaptureRequest.rest(plan, in: nil, topicID: topic).topicID, topic)
        XCTAssertNil(CaptureRequest.rest(plan, in: nil).topicID)
        XCTAssertEqual(AppCover.scanner(courseID: nil, isOnboarding: false, topicID: topic), .scanner(courseID: nil, isOnboarding: false, topicID: topic))
        XCTAssertNotEqual(AppCover.scanner(courseID: nil, isOnboarding: false), .scanner(courseID: nil, isOnboarding: false, topicID: topic))
    }

    // MARK: On the page, and on Cap's card

    func testTheAppReadsAGapFromAnEmptyTopicAndNotFromOneWithDrafts() throws {
        let (app, course) = try makeApp()
        let meiosis = try XCTUnwrap(ItemFactory.topic(named: "Meiosis", in: course, now: now))
        let genetics = try XCTUnwrap(ItemFactory.topic(named: "Genetics", in: course, now: now))
        let exam = try XCTUnwrap(app.createExam(ExamDraft(title: "Midterm", courseID: course.id, date: cal.adding(days: 12, to: now), wholeCourse: false,
                                                          scope: [meiosis.id, genetics.id])))
        let source = try app.createSource(fromText: "Some genetics.", title: "Chapter 9", course: course)
        _ = app.makeDrafts(draftInput(), source: source, course: course, topicID: genetics.id)
        let gap = try XCTUnwrap(app.examGap(for: exam))
        XCTAssertEqual(gap.topics.map(\.name), ["Meiosis"])
        XCTAssertEqual(gap.waiting.map(\.name), ["Genetics"])
        XCTAssertEqual(app.draftSource(forTopics: [genetics.id], in: course.id), source.id)
        XCTAssertFalse(app.gapIsPutOff(exam.id))
        app.snoozeNotice(NoticeEngine.gapID(exam.id))
        XCTAssertTrue(app.gapIsPutOff(exam.id), "Later on the page is Later on Cap's card")
    }

    func testAResearchNoteIsSavedThenWrittenOnThatTopic() throws {
        let (app, course) = try makeApp()
        let meiosis = try XCTUnwrap(ItemFactory.topic(named: "Meiosis", in: course, now: now))
        var result = ResearchResult(topic: "Meiosis")
        XCTAssertNil(app.saveResearchNote(result, course: course), "nothing to save")
        XCTAssertNil(app.saveResearch(result, forGap: meiosis.id, courseID: course.id))
        XCTAssertTrue(course.liveSources.isEmpty)
        result.text = String(repeating: "Meiosis makes four cells with half the chromosomes each. ", count: 12)
        result.cited = [WebSource(url: "https://openstax.org/meiosis", domain: "openstax.org", title: "Meiosis")]
        let request = try XCTUnwrap(app.saveResearch(result, forGap: meiosis.id, courseID: course.id))
        XCTAssertEqual(request.topicID, meiosis.id)
        XCTAssertEqual(request.courseID, course.id)
        let source = try XCTUnwrap(course.liveSources.first)
        XCTAssertEqual(source.title, "From the web: Meiosis")
        XCTAssertEqual(request.restOf, source.id)
        XCTAssertTrue(source.sortedPages.flatMap(\.lines).map(\.text).joined(separator: " ").contains("openstax.org"), "the note says where it came from")
    }

    /// The router reads consent itself, so a caller that forgets can't send anything.
    func testResearchSendsNothingWithoutConsentWhoeverAsks() async throws {
        let (app, _) = try makeApp()
        let spy = AssistantSpyTransport()
        app.ai.transportOverride = spy
        let off = String(localized: "Web research needs Cloud AI, which is off.")

        app.withdrawCloudAI()
        var steps = 0
        let withdrawn = await app.ai.research(topic: "Meiosis", focus: nil, course: "Bio 101") { _ in steps += 1 }
        XCTAssertEqual(withdrawn, .failed(message: off, needsPro: false))
        XCTAssertEqual(steps, 0)

        app.allowCloudAI()
        app.settings.ageBand = .under13
        let child = await app.ai.research(topic: "Meiosis", focus: nil, course: "Bio 101") { _ in steps += 1 }
        XCTAssertEqual(child, .failed(message: off, needsPro: false), "consent given, but never under 13")
        XCTAssertTrue(spy.researchRequests.isEmpty, "nothing went out")

        app.settings.ageBand = .adult
        guard case .done = await app.ai.research(topic: "Meiosis", focus: nil, course: "Bio 101", update: { _ in }) else {
            return XCTFail("allowed again, it runs")
        }
        XCTAssertEqual(spy.researchRequests.count, 1)
    }

    func testResearchRunsOutsideTheChatAndSaysWhyItCant() async throws {
        let (app, _) = try makeApp()
        let spy = AssistantSpyTransport()
        app.ai.transportOverride = spy
        app.allowCloudAI()
        var steps = 0
        let done = await app.ai.research(topic: "Meiosis", focus: nil, course: "Bio 101") { _ in steps += 1 }
        guard case .done(let result) = done else { return XCTFail("\(done)") }
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(steps, 1, "it's reported as it happens")
        XCTAssertEqual(spy.researchRequests.first?.minor, false)

        spy.researchError = .entitlementRequired
        let refused = await app.ai.research(topic: "Meiosis", focus: nil, course: nil) { _ in }
        XCTAssertEqual(refused, .failed(message: "Web research is part of Capling Pro.", needsPro: true))
        spy.researchError = .offline
        let offline = await app.ai.research(topic: "Meiosis", focus: nil, course: nil) { _ in }
        XCTAssertEqual(offline, .failed(message: "You're offline, so Cap can't look it up.", needsPro: false))
    }

    func testTheSheetsRoutes() {
        let exam = UUID(), topic = UUID()
        XCTAssertEqual(AppSheet.fillGap(examID: exam, topicID: topic).id, AppSheet.fillGap(examID: exam, topicID: topic).id)
        XCTAssertNotEqual(AppSheet.fillGap(examID: exam, topicID: nil), AppSheet.fillGap(examID: exam, topicID: topic))
    }
}
