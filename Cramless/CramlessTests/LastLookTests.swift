import Foundation
import XCTest
@testable import Cramless

/// The last look on an exam's eve, without the app: which ideas, when they are prepared, which sentences may be shown, and the words.
final class LastLookEngineTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 11, 6, 14, in: cal)
    let course = UUID()

    private var engine: LastLookEngine { LastLookEngine(fsrs: FSRS(), calendar: cal, now: now) }

    private func exam(hoursFromNow hours: Double = 20, scope: Set<UUID> = []) -> ExamSnapshot {
        ExamSnapshot(courseID: course, title: "Chem 110 Quiz", date: now.addingTimeInterval(hours * 3600), scope: scope)
    }

    private func item(recall: Double, topic: UUID? = nil, kind: ItemKind = .flashcard, reported: Bool = false) -> ItemSnapshot {
        var snapshot = EngineTest.studied(kind: kind, topic: topic, course: course, recall: recall, daysAgo: 10, now: now, cal: cal)
        snapshot.reported = reported
        return snapshot
    }

    func testTheShakiestComeFirst() {
        let topics = (0..<6).map { _ in UUID() }
        let items = [0.9, 0.5, 0.7, 0.6, 0.8, 0.4].enumerated().map { item(recall: $1, topic: topics[$0]) }
        let picks = engine.picks(items: items, exams: [exam()], limit: 3)
        XCTAssertEqual(picks, [items[5].id, items[1].id, items[3].id])
    }

    func testAtMostTwoFromATopicWhileOtherTopicsHaveIdeas() {
        let weak = UUID(), other = UUID()
        let items = [0.4, 0.42, 0.44, 0.46].map { item(recall: $0, topic: weak) } + [0.8, 0.85, 0.9].map { item(recall: $0, topic: other) }
        let picks = engine.picks(items: items, exams: [exam()], limit: 4)
        XCTAssertEqual(picks.prefix(4), [items[0].id, items[1].id, items[4].id, items[5].id])
    }

    func testAScopeOfOneTopicStillFillsTheScreen() {
        let only = UUID()
        let items = (0..<8).map { item(recall: 0.3 + Double($0) / 100, topic: only) }
        XCTAssertEqual(engine.picks(items: items, exams: [exam()], limit: LastLookEngine.shown).count, LastLookEngine.shown)
    }

    func testOnlyStudiedActiveQuestionsInScopeWithNoDiagramAndNothingReported() {
        let topic = UUID()
        let inScope = item(recall: 0.6, topic: topic)
        var suspended = item(recall: 0.2, topic: topic)
        suspended.status = .suspended
        let fresh = EngineTest.fresh(topic: topic, course: course)
        let diagram = item(recall: 0.2, topic: topic, kind: .diagram)
        let reported = item(recall: 0.2, topic: topic, reported: true)
        let elsewhere = EngineTest.studied(topic: UUID(), course: UUID(), recall: 0.1, daysAgo: 10, now: now, cal: cal)
        let picks = engine.picks(items: [suspended, fresh, diagram, reported, elsewhere, inScope], exams: [exam(scope: [topic])], limit: 8)
        XCTAssertEqual(picks, [inScope.id])
    }

    func testTheSameRecallAsTheEveSessionReads() {
        // A question that looks fine now and won't last until a far exam date comes before one that lasts.
        let quick = EngineTest.studied(topic: UUID(), course: course, recall: 0.9, daysAgo: 1, now: now, cal: cal)
        let lasting = EngineTest.studied(topic: UUID(), course: course, recall: 0.8, daysAgo: 30, now: now, cal: cal)
        let later = exam(hoursFromNow: 24 * 20)
        XCTAssertEqual(engine.picks(items: [lasting, quick], exams: [later], limit: 1), [quick.id])
    }

    func testTonightShowsTheLowestOfWhatWasPreparedAsTheyStandNow() {
        let items = (0..<8).map { item(recall: 0.5 + Double($0) / 20, topic: UUID()) }
        var after = items
        // Tonight's session put the two weakest right.
        for i in [0, 1] { after[i] = EngineTest.studied(items[i].id, topic: items[i].topicID, course: course, recall: 0.99, daysAgo: 1, now: now, cal: cal) }
        let worse = item(recall: 0.1, topic: UUID())
        let shown = engine.shown(items: after + [worse], exams: [exam()], prepared: items.map(\.id))
        XCTAssertEqual(shown, [items[2].id, items[3].id, items[4].id, items[5].id, items[6].id], "what wasn't prepared waits")
    }

    func testWhatRunsOutIsFilledFromTheRestAndNothingPreparedPicksAfresh() {
        let items = (0..<6).map { item(recall: 0.5 + Double($0) / 20, topic: UUID()) }
        XCTAssertEqual(engine.shown(items: items, exams: [exam()], prepared: []), items.prefix(5).map(\.id))
        let shown = engine.shown(items: items, exams: [exam()], prepared: [items[4].id, UUID()])
        XCTAssertEqual(shown, [items[4].id] + items.prefix(4).map(\.id), "a deleted question drops out")
    }

    func testTheWindowOpensTwoDaysBeforeAndClosesAtSixOnTheEve() {
        var e = ExamSnapshot(courseID: course, title: "Quiz", date: EngineTest.date(2026, 11, 8, 10, in: cal))
        func open(_ d: Int, _ h: Int) -> Bool {
            LastLookEngine(fsrs: FSRS(), calendar: cal, now: EngineTest.date(2026, 11, d, h, in: cal)).isPreparing(for: e)
        }
        XCTAssertFalse(open(6, 9), "more than 48 hours before")
        XCTAssertTrue(open(6, 11))
        XCTAssertTrue(open(7, 17))
        XCTAssertFalse(open(7, 18), "the eve from six on: nothing more is prepared")
        XCTAssertFalse(open(8, 9), "the day itself")
        e.date = EngineTest.date(2026, 11, 8, 19, in: cal)
        XCTAssertFalse(open(7, 19), "an evening exam closes at six on the day before as well")
    }

    func testASentenceIsKeptOnlyIfItsWordsAreInTheQuestionAndLines() {
        let question = "What happens in anaphase?"
        let answer = "Sister chromatids separate and move to opposite poles."
        let lines = ["Anaphase: sister chromatids separate at the centromere.", "The spindle pulls them to opposite poles of the cell."]
        func keeps(_ s: String) -> Bool { LastLookEngine.keeps(sentence: s, question: question, answer: answer, lines: lines) }
        XCTAssertTrue(keeps("In anaphase the sister chromatids separate and move to opposite poles."))
        XCTAssertFalse(keeps(""))
        XCTAssertFalse(keeps("Anaphase"), "a word says nothing without its question")
        XCTAssertFalse(keeps("Telomeres shorten during replication because telomerase stops working."), "words the notes don't have")
        XCTAssertFalse(keeps("In anaphase 46 sister chromatids separate."), "a number the notes don't have")
        XCTAssertFalse(keeps("Sister chromatids do not separate in anaphase."), "a not the notes don't have")
    }

    func testAFewMinutesOfReading() {
        XCTAssertEqual(LastLookEngine.minutes(ideas: 5), 2)
        XCTAssertEqual(LastLookEngine.minutes(ideas: 1), 1)
    }

    func testTheWords() {
        XCTAssertEqual(LastLookCopy.title, "Your last look")
        XCTAssertEqual(LastLookCopy.line(ideas: 5, minutes: 2), "5 ideas · about 2 minutes · no quiz")
        XCTAssertEqual(LastLookCopy.subtitle(ideas: 5, inSentences: true), "Your five shakiest ideas, in plain words")
        XCTAssertEqual(LastLookCopy.subtitle(ideas: 3, inSentences: true), "Your shakiest ideas, in plain words")
        XCTAssertEqual(LastLookCopy.subtitle(ideas: 5, inSentences: false), "Your five shakiest ideas", "a question and its answer aren't plain words of Cap's")
        XCTAssertEqual(LastLookCopy.subtitle(ideas: 3, inSentences: false), "Your shakiest ideas")
        XCTAssertEqual(LastLookCopy.closing, "That's enough for today. Sleep is part of studying. Good luck tomorrow.")
    }
}

/// A last look through the app: prepared ahead of the eve, kept on the phone, and the same with no connection.
@MainActor
final class LastLookAppModelTests: AskTestCase {
    /// Bio 101 with six studied questions on six topics, and an exam 40 hours from now: its window is open whatever the hour.
    private func world(_ app: AppModel) -> (exam: Exam, items: [StudyItem]) {
        let bio = makeBio(app)
        let exam = Exam(course: bio.course, title: "Bio 101 Midterm", date: app.now.addingTimeInterval(40 * 3600), now: app.now)
        app.context.insert(exam)
        var items: [StudyItem] = []
        for index in 0..<6 {
            let topic = Topic(course: bio.course, name: "Topic \(index)", sortOrder: index, now: app.now)
            app.context.insert(topic)
            let item = StudyItem(course: bio.course, topicID: topic.id, kind: .flashcard, status: .active, origin: .person,
                                 prompt: "What is chromatid \(index)?", answer: "Sister chromatid number \(index)", now: app.now)
            var memory = item.memory
            memory.state = .review
            memory.stability = 1 + Double(index)
            memory.difficulty = 5
            memory.lastReview = app.now.addingTimeInterval(-5 * 86_400)
            memory.due = app.now.addingTimeInterval(-86_400)
            memory.reps = 3
            item.memory = memory
            app.context.insert(item)
            bio.course.items.append(item)
            items.append(item)
        }
        app.save()
        return (exam, items)
    }

    private final class Spy: RelayTransport, @unchecked Sendable {
        let base = MockRelayTransport(latencyScale: 0)
        let lock = NSLock()
        private var asked: [LastLookRequest] = []
        var requests: [LastLookRequest] { lock.withLock { asked } }
        var fails = false
        /// What each idea comes back as (default: the mock's).
        var says: ((LastLookIdeaInput) -> String)?

        func generate(_ request: GenerateRequest) async throws -> GenerateResponse { try await base.generate(request) }
        func check(_ request: CheckRequest) async throws -> CheckResponse { try await base.check(request) }
        func grade(_ request: GradeRequest) async throws -> GradeResponse { try await base.grade(request) }
        func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> { base.tutor(request) }
        func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse { try await base.confusions(request) }
        func lecture(_ request: LectureRequest) async throws -> LectureResponse { try await base.lecture(request) }
        func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse { try await base.cardsFromChat(request) }
        func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse { try await base.transcribeImage(request) }
        func quota() async throws -> QuotaStatus { try await base.quota() }

        func lastLook(_ request: LastLookRequest) async throws -> LastLookResponse {
            lock.withLock { asked.append(request) }
            if fails { throw RelayError.upstream("down") }
            if let says { return LastLookResponse(model: "spy", ideas: request.ideas.map { LastLookSentence(id: $0.id, sentence: says($0)) }) }
            return try await base.lastLook(request)
        }
    }

    /// With consent off, on the relay: the mock takes consent as given.
    private func app(spy: Spy? = nil, consent: Bool = true) -> AppModel {
        let app = makeApp(mode: consent ? .mock : .relay, consent: consent)
        app.ai.transportOverride = spy
        return app
    }

    func testWithNothingPreparedItIsTheQuestionsAndAnswers() throws {
        let app = app()
        let world = world(app)
        let look = try XCTUnwrap(app.lastLook(for: world.exam.id))
        XCTAssertEqual(look.ideas.count, 5)
        XCTAssertTrue(look.ideas.allSatisfy { $0.sentence == nil })
        XCTAssertFalse(look.isWritten)
        XCTAssertEqual(look.ideas[0].question, "What is chromatid 0?", "the lowest recall first")
        XCTAssertEqual(look.ideas[0].answer, "Sister chromatid number 0")
        XCTAssertEqual(look.ideas[0].topic, "Topic 0")
        XCTAssertEqual(app.lastLookCount(for: world.exam.id), 5)
    }

    func testPreparingWritesSentencesThatAreThereWithNoConnection() async throws {
        let spy = Spy()
        spy.says = { "\($0.answer) is the idea." }
        let app = app(spy: spy)
        let world = world(app)
        await app.prepareLastLooks()
        XCTAssertEqual(spy.requests.count, 1)
        XCTAssertEqual(spy.requests[0].ideas.count, 6, "all it has, up to eight")
        XCTAssertEqual(spy.requests[0].examTitle, "Bio 101 Midterm")
        XCTAssertEqual(spy.requests[0].course, "Bio 101")
        // The connection goes.
        spy.fails = true
        app.ai.transportOverride = nil
        let look = try XCTUnwrap(app.lastLook(for: world.exam.id))
        XCTAssertTrue(look.isWritten)
        XCTAssertEqual(look.ideas[0].sentence, "Sister chromatid number 0 is the idea.")
    }

    func testAskedOnceADay() async {
        let spy = Spy()
        spy.says = { $0.answer }
        let app = app(spy: spy)
        _ = world(app)
        await app.prepareLastLooks()
        await app.prepareLastLooks()
        XCTAssertEqual(spy.requests.count, 1)
    }

    func testAFailureIsTriedAgainAndLeavesTheOfflineLines() async throws {
        let spy = Spy()
        spy.fails = true
        let app = app(spy: spy)
        let world = world(app)
        await app.prepareLastLooks()
        XCTAssertEqual(spy.requests.count, 1)
        XCTAssertFalse(try XCTUnwrap(app.lastLook(for: world.exam.id)).isWritten)
        spy.fails = false
        spy.says = { $0.answer }
        await app.prepareLastLooks()
        XCTAssertEqual(spy.requests.count, 2)
        XCTAssertTrue(try XCTUnwrap(app.lastLook(for: world.exam.id)).isWritten)
    }

    func testAStraySentenceIsNotKept() async throws {
        let spy = Spy()
        spy.says = { _ in "Mitochondria are the powerhouse of the eukaryotic organism." }
        let app = app(spy: spy)
        let world = world(app)
        await app.prepareLastLooks()
        XCTAssertFalse(try XCTUnwrap(app.lastLook(for: world.exam.id)).isWritten)
    }

    func testASentenceGoesWhenItsQuestionChanged() async throws {
        let spy = Spy()
        spy.says = { $0.answer }
        let app = app(spy: spy)
        let world = world(app)
        await app.prepareLastLooks()
        world.items[0].answer = "A corrected answer"
        app.save()
        let look = try XCTUnwrap(app.lastLook(for: world.exam.id))
        XCTAssertNil(look.ideas[0].sentence, "the old sentence would say the old thing")
        XCTAssertEqual(look.ideas[0].answer, "A corrected answer")
        XCTAssertNotNil(look.ideas[1].sentence)
    }

    func testWithoutConsentNothingIsAskedAndTheIdeasAreStillPicked() async throws {
        let spy = Spy()
        let app = app(spy: spy, consent: false)
        let world = world(app)
        await app.prepareLastLooks()
        XCTAssertTrue(spy.requests.isEmpty)
        XCTAssertEqual(try XCTUnwrap(app.lastLook(for: world.exam.id)).ideas.count, 5)
    }

    func testOutsideTheWindowNothingIsPrepared() async throws {
        let spy = Spy()
        let app = app(spy: spy)
        let world = world(app)
        world.exam.date = app.now.addingTimeInterval(72 * 3600)
        app.save()
        await app.prepareLastLooks()
        XCTAssertTrue(spy.requests.isEmpty)
    }

    func testAPackGoesWithItsExamAndALocalWipe() async {
        let spy = Spy()
        spy.says = { $0.answer }
        let app = app(spy: spy)
        let world = world(app)
        await app.prepareLastLooks()
        XCTAssertNotNil(app.defaults.data(forKey: LastLookStore.defaultsKey))
        world.exam.deletedAt = app.now
        app.save()
        await app.prepareLastLooks()
        let data = app.defaults.data(forKey: LastLookStore.defaultsKey)
        let store = data.flatMap { try? JSONDecoder.cramless.decode(LastLookStore.self, from: $0) }
        XCTAssertEqual(store?.packs.count, 0)
        app.clearLastLooks()
        XCTAssertNil(app.defaults.data(forKey: LastLookStore.defaultsKey))
    }

    func testAChipIsThereOnlyWhenItOpensSomething() throws {
        let app = app()
        let (exam, items) = world(app)
        let course = try XCTUnwrap(items[0].course)
        let deck = Source(course: course, kind: .quizlet, title: "Unit 3 terms", status: .ready, now: app.now)
        app.context.insert(deck)
        course.sources.append(deck)
        let notes = Source(course: course, kind: .text, title: "Week 5", status: .ready, now: app.now)
        app.context.insert(notes)
        course.sources.append(notes)
        let page = SourcePage(source: notes, pageIndex: 0, label: "p. 1", text: "", lines: [])
        app.context.insert(page)
        notes.pages.append(page)
        items[0].sourceRef = SourceRef(sourceID: deck.id, pageIndex: nil, label: deck.title)
        items[1].sourceRef = SourceRef(sourceID: notes.id, pageIndex: 0, label: "p. 1")
        app.save()

        let ideas = try XCTUnwrap(app.lastLook(for: exam.id)).ideas
        XCTAssertNil(try XCTUnwrap(ideas.first { $0.id == items[0].id }).ref, "a deck's card has no page")
        XCTAssertEqual(ideas.first { $0.id == items[1].id }?.ref?.label, "p. 1")
    }

    /// One rule for every chip: the session's, the mock's and the last look's.
    func testAChipOpensOnlyWhatIsThere() throws {
        let app = app()
        let (_, items) = world(app)
        let course = try XCTUnwrap(items[0].course)
        let deck = Source(course: course, kind: .quizlet, title: "Unit 3 terms", status: .ready, now: app.now)
        app.context.insert(deck)
        course.sources.append(deck)
        XCTAssertFalse(app.opens(SourceRef(sourceID: deck.id, pageIndex: nil, label: deck.title)), "a deck's card has no page")
        XCTAssertFalse(app.opens(SourceRef(sourceID: UUID(), pageIndex: 0, label: "p. 1")), "a source that's gone")
        let lecture = Source(course: course, kind: .lecture, title: "Lecture 3", status: .ready, now: app.now)
        app.context.insert(lecture)
        course.sources.append(lecture)
        XCTAssertTrue(app.opens(SourceRef(sourceID: lecture.id, pageIndex: nil, label: "Lecture 3")))
        deck.deletedAt = app.now
    }

    func testNothingStudiedNothingToLookAt() {
        let app = app()
        let bio = makeBio(app)
        let exam = Exam(course: bio.course, title: "Quiz", date: app.now.addingTimeInterval(20 * 3600), now: app.now)
        app.context.insert(exam)
        app.save()
        XCTAssertNil(app.lastLook(for: exam.id))
        XCTAssertEqual(app.lastLookCount(for: exam.id), 0)
    }

    func testTheWordsSayWhoWroteWhat() {
        func idea(_ question: String, _ answer: String, sentence: String? = nil) -> LastLookIdea {
            LastLookIdea(id: UUID(), topic: nil, question: question, answer: answer, sentence: sentence, ref: nil)
        }
        let his = idea("Q?", "A long answer here", sentence: "Cap's own sentence.")
        let theirs = idea("What is a mole?", "A count of particles")
        let fill = idea("", "A fill-in is a sentence by itself.")
        let id = UUID()
        XCTAssertNil(LastLookCopy.written(LastLook(examID: id, ideas: [theirs, fill])))
        XCTAssertEqual(LastLookCopy.written(LastLook(examID: id, ideas: [his])), "Cap wrote these from your questions and notes.")
        XCTAssertEqual(LastLookCopy.written(LastLook(examID: id, ideas: [his, theirs])), "Cap wrote the sentences from your questions and notes. The rest are your own questions.")
        XCTAssertTrue(LastLook(examID: id, ideas: [his, fill]).isAllSentences)
        XCTAssertFalse(LastLook(examID: id, ideas: [his, theirs]).isAllSentences)
    }

    func testABareAnswerReadsWithItsQuestion() {
        func idea(_ question: String, _ answer: String, sentence: String? = nil) -> LastLookIdea {
            LastLookIdea(id: UUID(), topic: nil, question: question, answer: answer, sentence: sentence, ref: nil)
        }
        XCTAssertTrue(idea("How many moles?", "4").answerIsBare)
        XCTAssertTrue(idea("Which phase?", "Metaphase").answerIsBare)
        XCTAssertFalse(idea("What does it tell you?", "The ratio of moles of each reactant").answerIsBare)
        XCTAssertFalse(idea("", "4 moles of water").answerIsBare, "no question to read it with")
        XCTAssertFalse(idea("How many?", "4", sentence: "There are four.").answerIsBare)
    }
}
