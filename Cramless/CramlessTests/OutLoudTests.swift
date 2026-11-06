import SwiftData
import XCTest
@testable import Cramless

/// A voice that does as it's told: says lines at once, and can hold on one until it is stopped.
@MainActor
final class FakeSpeaker: SpokenSpeaking {
    private(set) var said: [String] = []
    var holdOn: ((String) -> Bool)?
    private var stopped = false

    func say(_ text: String, language: String?) async {
        said.append(text)
        stopped = false
        if holdOn?(text) == true {
            while !stopped, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        }
    }

    func stop() { stopped = true }
}

/// A microphone that "hears" the next line of `lines`. With none left it waits until stopped (or says nothing, with `silentAtEnd`).
@MainActor
final class FakeListener: SpokenListening {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?
    var lines: [String]
    var failure: SpokenListenerFailure?
    private(set) var turns: [SpokenTurn] = []
    private(set) var closed = false
    private(set) var suspended = false
    /// An answer that doesn't come: the line is "…", heard as no speech.
    static let silence = "…"
    /// Holds the turn open until it's stopped.
    static let wait = "WAIT"
    private var stopped = false

    init(_ lines: [String] = []) { self.lines = lines }

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        if let failure { throw failure }
    }

    func listen(_ turn: SpokenTurn, onWords: @escaping @MainActor (String) -> Void) async -> SpokenHearing {
        turns.append(turn)
        stopped = false
        guard !lines.isEmpty else {
            while !stopped, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return SpokenHearing(text: "", ending: .stopped)
        }
        let line = lines.removeFirst()
        if line == Self.wait {
            while !stopped, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return SpokenHearing(text: "", ending: .stopped)
        }
        if line == Self.silence { return SpokenHearing(text: "", ending: .noSpeech) }
        onWords(line)
        return SpokenHearing(text: line, ending: .silence, seconds: 2)
    }

    func stopListening() { stopped = true }
    func suspend() { suspended = true; stopped = true }
    func resume() throws { suspended = false }
    func close() { closed = true; stopped = true }
}

@MainActor
final class OutLoudQuestionTests: XCTestCase {
    func testAMultipleChoiceIsReadInTheOrderTheScreenShows() {
        let choices = [Choice(text: "Prophase", correct: false), Choice(text: "Anaphase", correct: true),
                       Choice(text: "Metaphase", correct: false), Choice(text: "Telophase", correct: false)]
        let id = UUID()
        let question = OutLoudQuestion.make(id: "x#0", itemID: id, kind: .mcq, prompt: "Which phase?", answer: "Anaphase", ideas: [], choices: choices,
                                            cloze: nil, day: 100)
        let order = ChoiceOrder.order(texts: choices.map(\.text), itemID: id, day: 100)
        XCTAssertEqual(question.optionIndexes, order)
        XCTAssertEqual(question.options, order.map { choices[$0].text })
        XCTAssertEqual(question.rightAnswer, "Anaphase")
        XCTAssertEqual(question.options[question.rightPlace!], "Anaphase")
        XCTAssertTrue(question.spoken.hasPrefix("Which phase? A: \(question.options[0])."), question.spoken)
        XCTAssertTrue(question.spoken.contains("D: \(question.options[3])."), question.spoken)
        XCTAssertEqual(question.expecting, .choice(options: question.options))
    }

    func testAFillInSaysBlank() {
        let question = OutLoudQuestion.make(id: "x#0", itemID: UUID(), kind: .cloze, prompt: "Fill in the blank", answer: "x", ideas: [], choices: [],
                                            cloze: ClozeSpec(text: "During {{anaphase}}, chromatids separate."), day: 1)
        XCTAssertTrue(question.spoken.contains("During blank, chromatids separate."), question.spoken)
        XCTAssertEqual(question.rightAnswer, "anaphase")
        XCTAssertEqual(question.expecting, .words)
    }

    func testWhichQuestionsCanBeAsked() {
        XCTAssertTrue(OutLoudPolicy.canAsk(kind: .recall, options: 0, blanks: 0))
        XCTAssertTrue(OutLoudPolicy.canAsk(kind: .apply, options: 0, blanks: 0))
        XCTAssertTrue(OutLoudPolicy.canAsk(kind: .flashcard, options: 0, blanks: 0))
        XCTAssertTrue(OutLoudPolicy.canAsk(kind: .mcq, options: 4, blanks: 0))
        XCTAssertFalse(OutLoudPolicy.canAsk(kind: .mcq, options: 5, blanks: 0), "more than can be held in the head")
        XCTAssertTrue(OutLoudPolicy.canAsk(kind: .cloze, options: 0, blanks: 1))
        XCTAssertFalse(OutLoudPolicy.canAsk(kind: .cloze, options: 0, blanks: 2))
        XCTAssertFalse(OutLoudPolicy.canAsk(kind: .diagram, options: 0, blanks: 0), "something to look at")
    }

    func testTheMinutes() {
        XCTAssertEqual(OutLoudPolicy.minutes(for: []), 0)
        XCTAssertEqual(OutLoudPolicy.minutes(for: [.flashcard]), 1)
        XCTAssertEqual(OutLoudPolicy.minutes(for: [.recall, .recall, .mcq]), 3)
    }

    func testTheCopy() {
        XCTAssertEqual(OutLoudCopy.size(questions: 12, minutes: 9), "12 questions · about 9 minutes")
        XCTAssertEqual(StudySessionAttributes.ContentState.clipped(prompt: "  Short  "), "Short")
        XCTAssertNil(StudySessionAttributes.ContentState.clipped(prompt: "   "))
        let long = String(repeating: "word ", count: 80)
        let clipped = StudySessionAttributes.ContentState.clipped(prompt: long)!
        XCTAssertLessThanOrEqual(clipped.count, StudySessionAttributes.ContentState.promptLimit)
        XCTAssertTrue(clipped.hasSuffix("…"))
    }
}

@MainActor
final class OutLoudControllerTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var course: Course!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
        course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
    }

    override func tearDown() async throws {
        OutLoudRemote.handler = nil
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    private let phases = [Choice(text: "Prophase", correct: false), Choice(text: "Anaphase", correct: true),
                          Choice(text: "Metaphase", correct: false), Choice(text: "Telophase", correct: false)]
    private let ideas = [KeyIdea(id: "k1", label: "Chromatids separate", terms: ["chromatids separate"]),
                         KeyIdea(id: "k2", label: "Spindle fibres pull", terms: ["spindle fibres pull"])]

    @discardableResult
    private func add(_ kind: ItemKind, prompt: String = "Question?", answer: String = "Answer", choices: [Choice] = [], keyIdeas: [KeyIdea] = [],
                     cloze: ClozeSpec? = nil) -> StudyItem {
        let item = StudyItem(course: course, kind: kind, status: .active, origin: .rules, prompt: prompt, answer: answer, keyIdeas: keyIdeas,
                             choices: choices, cloze: cloze, now: clock.now)
        app.context.insert(item)
        course.items.append(item)
        app.save()
        return item
    }

    private func make(_ listener: FakeListener, speaker: FakeSpeaker? = nil, timing: OutLoudController.Timing = .init(poll: .milliseconds(5)),
                      publish: @escaping @MainActor (String?, StudySessionAttributes.ContentState.Voice?) -> Void = { _, _ in }) -> OutLoudController {
        let voice = speaker ?? FakeSpeaker()
        return OutLoudController(app: app, request: SessionRequest(kind: .practice, courseID: course.id),
                                 ports: OutLoudPorts(makeListener: { listener }, makeSpeaker: { voice }, publish: publish), timing: timing)
    }

    /// Waits for a condition, on the main actor.
    private func until(_ what: String = "condition", _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now >= deadline { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func finished(_ controller: OutLoudController) async throws {
        try await until("the session to finish") { controller.phase == .finished }
    }

    private func logs() -> [ReviewLog] { app.fetch(FetchDescriptor<ReviewLog>()) }

    private func letter(of text: String, in item: StudyItem) -> String {
        let order = ChoiceOrder.order(texts: item.choices.map(\.text), itemID: item.id, day: app.calendar.dayNumber(for: app.now))
        let place = order.firstIndex { item.choices[$0].text == text }!
        return ChoiceOrder.letters[place]
    }

    // MARK: Answers

    func testARightChoiceByLetterLogsTheOptionsOwnWords() async throws {
        let item = add(.mcq, prompt: "Which phase?", answer: "Anaphase", choices: phases)
        let speaker = FakeSpeaker()
        let listener = FakeListener(["It's \(letter(of: "Anaphase", in: item))."])
        let controller = make(listener, speaker: speaker)
        controller.start()
        try await finished(controller)
        let log = try XCTUnwrap(logs().first)
        XCTAssertEqual(log.answer, "Anaphase")
        XCTAssertEqual(log.gradedBy, "rules")
        XCTAssertTrue(log.wasCorrect)
        XCTAssertTrue(speaker.said.first?.contains("Which phase?") == true)
        XCTAssertTrue(speaker.said.contains("Nice!"), "\(speaker.said)")
        XCTAssertEqual(speaker.said.last, "That's it. 1 of 1 right the first time.")
        XCTAssertTrue(listener.closed)
        XCTAssertNotNil(controller.runner.summary)
    }

    func testAWrongChoiceSaysTheAnswer() async throws {
        let item = add(.mcq, prompt: "Which phase?", answer: "Anaphase", choices: phases)
        let speaker = FakeSpeaker()
        // It comes back later in the session (a learning step): the second time, right.
        let controller = make(FakeListener(["Option \(letter(of: "Telophase", in: item))", letter(of: "Anaphase", in: item)]), speaker: speaker)
        controller.start()
        try await finished(controller)
        XCTAssertTrue(speaker.said.contains("Not yet. The answer is Anaphase."), "\(speaker.said)")
        XCTAssertEqual(logs().sorted { $0.reviewedAt < $1.reviewedAt }.first?.answer, "Telophase")
    }

    func testAnOptionsWordsAndAPlaceAreAnswers() async throws {
        add(.mcq, prompt: "Which phase?", answer: "Anaphase", choices: phases)
        let controller = make(FakeListener(["I think it's anaphase"]))
        controller.start()
        try await finished(controller)
        XCTAssertEqual(logs().first?.answer, "Anaphase")
        XCTAssertTrue(logs().first?.wasCorrect == true)
    }

    func testNotCatchingAChoiceAsksForALetterThenAsksAgain() async throws {
        let item = add(.mcq, prompt: "Which phase?", answer: "Anaphase", choices: phases)
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["purple monkey", "purple monkey", letter(of: "Anaphase", in: item)]), speaker: speaker)
        controller.start()
        try await finished(controller)
        XCTAssertEqual(speaker.said.filter { $0 == OutLoudCopy.sayALetter }.count, 1)
        XCTAssertEqual(speaker.said.filter { $0.contains("Which phase?") }.count, 2, "after two tries, the question again")
        XCTAssertEqual(logs().count, 1)
    }

    func testAFillInIsCheckedExactlyAndItsWordsAreNotKept() async throws {
        add(.cloze, prompt: "Fill in", answer: "anaphase", cloze: ClozeSpec(text: "During {{anaphase}}, chromatids separate."))
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["I think it's anaphase."]), speaker: speaker)
        controller.start()
        try await finished(controller)
        let log = try XCTUnwrap(logs().first)
        XCTAssertTrue(log.wasCorrect)
        XCTAssertNil(log.answer, "what was said isn't kept")
        XCTAssertTrue(speaker.said.contains("Nice!"))
    }

    func testAFlashcardAsksHowItWent() async throws {
        add(.flashcard, prompt: "Capital of France?", answer: "Paris")
        let speaker = FakeSpeaker()
        let listener = FakeListener(["Paris I think", "got it"])
        let controller = make(listener, speaker: speaker)
        controller.start()
        try await finished(controller)
        let log = try XCTUnwrap(logs().first)
        XCTAssertEqual(log.rating, .good)
        XCTAssertEqual(log.gradedBy, "person")
        XCTAssertNil(log.answer)
        XCTAssertTrue(speaker.said.contains(SpokenVerdict.howDidItGo(answer: "Paris")), "\(speaker.said)")
        XCTAssertTrue(listener.turns[1].isReply)
        XCTAssertEqual(listener.turns[1].endpoint, .reply)
    }

    func testAFlashcardRepliesThatDontCountAskOnceMoreThenMoveOn() async throws {
        add(.flashcard, prompt: "Capital of France?", answer: "Paris")
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["Paris", "purple monkey", "banana"]), speaker: speaker)
        controller.start()
        try await finished(controller)
        XCTAssertTrue(speaker.said.contains(OutLoudCopy.sayHowItWent))
        XCTAssertTrue(logs().isEmpty, "nobody said how it went: nothing is recorded")
    }

    func testIDontKnowGivesTheAnswerAndCountsAsAgain() async throws {
        add(.flashcard, prompt: "Capital of France?", answer: "Paris")
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["I don't know", "Paris", "got it"]), speaker: speaker)
        controller.start()
        try await finished(controller)
        let first = try XCTUnwrap(logs().sorted { $0.reviewedAt < $1.reviewedAt }.first)
        XCTAssertEqual(first.rating, .again)
        XCTAssertNil(first.answer)
        XCTAssertTrue(speaker.said.contains("Here's the answer: Paris."), "\(speaker.said)")
    }

    // MARK: Own words

    func testWithoutAModelTheRulesRightAnswerStandsAndTheWordsAreNotKept() async throws {
        add(.recall, prompt: "What happens in anaphase?", answer: "Chromatids separate and spindle fibres pull.", keyIdeas: ideas)
        let speaker = FakeSpeaker()
        let words = "The chromatids separate and the spindle fibres pull them"
        let controller = make(FakeListener([words]), speaker: speaker)
        controller.start()
        try await finished(controller)
        let log = try XCTUnwrap(logs().first)
        XCTAssertTrue(log.wasCorrect)
        XCTAssertNil(log.answer, "a spoken answer's words go no further than the grade")
        XCTAssertTrue(speaker.said.contains("Nice! You got every key idea."), "\(speaker.said)")
    }

    func testWithoutAModelAPartAnswerIsThePersonsToSay() async throws {
        add(.recall, prompt: "What happens in anaphase?", answer: "Chromatids separate and spindle fibres pull.", keyIdeas: ideas)
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["Something happens to the chromatids separate", "almost"]), speaker: speaker)
        controller.start()
        try await finished(controller)
        let log = try XCTUnwrap(logs().first)
        XCTAssertEqual(log.gradedBy, "self")
        XCTAssertEqual(log.rating, .hard)
        XCTAssertGreaterThanOrEqual(log.score, 0.6, "a score that agrees with the rating")
        XCTAssertTrue(speaker.said.contains { $0.hasPrefix("Here's the answer:") && $0.hasSuffix("Say got it, or again.") }, "\(speaker.said)")
    }

    func testCloudAIGradesTheWordsAndNothingElse() async throws {
        let cloud = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        cloud.ai.transportOverride = transport
        let course = Course(name: "Bio 101", now: cloud.now)
        cloud.context.insert(course)
        let item = StudyItem(course: course, kind: .recall, status: .active, origin: .rules, prompt: "What happens in anaphase?",
                             answer: "Chromatids separate.", keyIdeas: ideas, now: cloud.now)
        cloud.context.insert(item)
        course.items.append(item)
        cloud.save()
        let speaker = FakeSpeaker()
        let words = "They get pulled apart towards the poles by the spindle"
        let listener = FakeListener([words, "again", "again", "again", "again"])
        let controller = OutLoudController(app: cloud, request: SessionRequest(kind: .practice, courseID: course.id),
                                           ports: OutLoudPorts(makeListener: { listener }, makeSpeaker: { speaker }))
        controller.start()
        try await until("the first grade") { !transport.gradeRequests.isEmpty }
        XCTAssertEqual(transport.gradeRequests.first?.response, words)
        try await until("an answer") { !cloud.fetch(FetchDescriptor<ReviewLog>()).isEmpty }
        let log = try XCTUnwrap(cloud.fetch(FetchDescriptor<ReviewLog>()).first)
        XCTAssertEqual(log.gradedBy, "cloud")
        XCTAssertNil(log.answer)
        controller.close()
    }

    // MARK: Commands

    func testRepeatAsksAgainAndSkipRecordsNothing() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["say that again", "skip"]), speaker: speaker)
        controller.start()
        try await finished(controller)
        XCTAssertEqual(speaker.said.filter { $0.contains("One?") }.count, 2)
        XCTAssertTrue(logs().isEmpty)
        XCTAssertEqual(speaker.said.last, "Okay. We'll stop here.")
    }

    func testStopEndsTheSessionAndKeepsWhatWasAnswered() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        add(.flashcard, prompt: "Two?", answer: "2")
        add(.flashcard, prompt: "Three?", answer: "3")
        let speaker = FakeSpeaker()
        let controller = make(FakeListener(["a guess", "got it", "stop"]), speaker: speaker)
        controller.start()
        try await finished(controller)
        XCTAssertEqual(logs().count, 1)
        XCTAssertEqual(controller.runner.phase, .finished)
        XCTAssertEqual(speaker.said.last, "That's it. 1 of 1 right the first time.")
    }

    func testTheScreensButtonsDoTheSame() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        add(.flashcard, prompt: "Two?", answer: "2")
        let speaker = FakeSpeaker()
        let listener = FakeListener([FakeListener.wait, FakeListener.wait, FakeListener.wait])
        let controller = make(listener, speaker: speaker)
        controller.start()
        try await until("the first turn") { listener.turns.count == 1 }
        controller.perform(.repeatQuestion)
        try await until("the second turn") { listener.turns.count == 2 }
        let first = try XCTUnwrap(listener.turns[0].question?.id)
        XCTAssertEqual(listener.turns[1].question?.id, first, "the same question")
        controller.perform(.skip)
        try await until("the next question") { listener.turns.count == 3 }
        XCTAssertNotEqual(listener.turns[2].question?.id, first)
        controller.perform(.stop)
        try await finished(controller)
        XCTAssertTrue(logs().isEmpty)
    }

    func testTheLiveActivitysButtonsReachTheSession() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        add(.flashcard, prompt: "Two?", answer: "2")
        let listener = FakeListener([FakeListener.wait, FakeListener.wait, FakeListener.wait])
        let controller = make(listener)
        controller.start()
        try await until("the first turn") { listener.turns.count == 1 }
        _ = try await OutLoudRepeatIntent().perform()
        try await until("the second turn") { listener.turns.count == 2 }
        XCTAssertEqual(listener.turns[1].question?.id, listener.turns[0].question?.id)
        _ = try await OutLoudSkipIntent().perform()
        try await until("the next question") { listener.turns.count == 3 }
        XCTAssertNotEqual(listener.turns[2].question?.id, listener.turns[0].question?.id)
        controller.close()
        XCTAssertNil(OutLoudRemote.handler, "nothing left for a stale button to reach")
    }

    func testTheButtonsDoNothingWithNoSession() async throws {
        OutLoudRemote.handler = nil
        _ = try await OutLoudRepeatIntent().perform()
        _ = try await OutLoudSkipIntent().perform()
    }

    // MARK: Silence, calls

    func testOneSilenceGetsAWordTwoAndCapWaitsUntilRepeat() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let speaker = FakeSpeaker()
        let listener = FakeListener([FakeListener.silence, FakeListener.silence, "stop"])
        let controller = make(listener, speaker: speaker)
        controller.start()
        try await until("Cap to wait") { controller.phase == .paused(.noAnswer) }
        XCTAssertTrue(speaker.said.contains(OutLoudCopy.takeYourTime))
        XCTAssertTrue(speaker.said.contains(OutLoudCopy.waiting))
        XCTAssertFalse(listener.closed, "the microphone's engine stays on, so a locked phone can come back")
        controller.perform(.repeatQuestion)
        try await finished(controller)
        XCTAssertEqual(speaker.said.filter { $0.contains("One?") }.count, 2)
    }

    func testWaitingTooLongEndsTheSessionAndTheMicrophone() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let listener = FakeListener([FakeListener.silence, FakeListener.silence])
        let controller = make(listener, timing: .init(waitsForReturn: .milliseconds(30), poll: .milliseconds(5)))
        controller.start()
        try await finished(controller)
        XCTAssertTrue(listener.closed)
    }

    func testACallPausesAndTheSameQuestionIsAskedAgain() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let speaker = FakeSpeaker()
        let listener = FakeListener([FakeListener.wait, "a guess", "got it"])
        let controller = make(listener, speaker: speaker)
        controller.start()
        try await until("the turn") { listener.turns.count == 1 }
        listener.onInterruption?(.began)
        try await until("the pause") { controller.phase == .paused(.interruption) }
        listener.onInterruption?(.ended(shouldResume: true))
        try await finished(controller)
        XCTAssertEqual(speaker.said.filter { $0.contains("One?") }.count, 2)
        XCTAssertEqual(logs().count, 1)
    }

    func testACallThatEndsWithoutLeaveToResumeWaitsForThePerson() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let listener = FakeListener([FakeListener.wait, "stop"])
        let controller = make(listener)
        controller.start()
        try await until("the turn") { listener.turns.count == 1 }
        listener.onInterruption?(.began)
        try await until("the pause") { controller.phase == .paused(.interruption) }
        listener.onInterruption?(.ended(shouldResume: false))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(controller.phase, .paused(.interruption))
        controller.perform(.resume)
        try await finished(controller)
    }

    func testThePersonsPauseTurnsTheMicrophoneOffAndResumeAsksAgain() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let speaker = FakeSpeaker()
        let listener = FakeListener([FakeListener.wait, "stop"])
        let controller = make(listener, speaker: speaker)
        controller.start()
        try await until("the turn") { listener.turns.count == 1 }
        controller.perform(.pause)
        XCTAssertEqual(controller.phase, .paused(.person))
        XCTAssertTrue(listener.suspended)
        controller.perform(.resume)
        XCTAssertFalse(listener.suspended)
        try await finished(controller)
        XCTAssertEqual(speaker.said.filter { $0.contains("One?") }.count, 2)
    }

    func testASpeechFailureTriesOnceThenEnds() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        final class Failing: FakeListenerBase {}
        let speaker = FakeSpeaker()
        let controller = OutLoudController(app: app, request: SessionRequest(kind: .practice, courseID: course.id),
                                           ports: OutLoudPorts(makeListener: { Failing() }, makeSpeaker: { speaker }),
                                           timing: .init(poll: .milliseconds(5)))
        controller.start()
        try await finished(controller)
        XCTAssertTrue(speaker.said.contains(OutLoudCopy.cantHear))
    }

    // MARK: Getting ready

    func testNoSpeechModelBlocksWithTheLanguageAndCanTryAgain() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        let listener = FakeListener(["stop"])
        listener.failure = .noSpeechModel(language: "Hebrew")
        let controller = make(listener)
        controller.start()
        try await until("the block") { if case .blocked = controller.phase { true } else { false } }
        XCTAssertEqual(controller.phase, .blocked(.noModel(language: "Hebrew")))
        XCTAssertEqual(String(localized: OutLoudBlock.noModel(language: "Hebrew").title), "Out loud needs Apple's speech model for Hebrew.")
        XCTAssertNil(controller.runner.session, "nothing has started")
        listener.failure = nil
        controller.start()
        try await finished(controller)
    }

    func testTheMicrophoneOffSaysSo() {
        XCTAssertEqual(OutLoudBlock(SpokenListenerFailure.microphoneDenied), .microphoneOff)
        XCTAssertEqual(OutLoudBlock(SpokenListenerFailure.microphoneUnavailable), .microphoneBusy)
        XCTAssertEqual(OutLoudBlock(SpokenListenerFailure.noSpeechModel(language: nil)), .noSpeechHere)
        XCTAssertTrue(OutLoudBlock.microphoneOff.opensSettings)
        XCTAssertTrue(OutLoudBlock.microphoneBusy.canRetry)
        XCTAssertTrue(OutLoudBlock.noModel(language: "x").canRetry)
        XCTAssertFalse(OutLoudBlock.noSpeechHere.canRetry)
    }

    // MARK: The session

    func testOnlyWhatCanBeSaidIsAsked() throws {
        let said = add(.flashcard, prompt: "One?", answer: "1")
        let four = add(.mcq, prompt: "Four?", answer: "Anaphase", choices: phases)
        let five = add(.mcq, prompt: "Five?", answer: "Anaphase", choices: phases + [Choice(text: "Interphase", correct: false)])
        let one = add(.cloze, prompt: "One blank", answer: "a", cloze: ClozeSpec(text: "The {{a}} word."))
        let two = add(.cloze, prompt: "Two blanks", answer: "a", cloze: ClozeSpec(text: "The {{a}} and {{b}} words."))
        let page = add(.diagram, prompt: "Label it", answer: "x")
        let built = OutLoudController(app: app, request: SessionRequest(kind: .practice, courseID: course.id),
                                      ports: OutLoudPorts(makeListener: { FakeListener() }, makeSpeaker: { FakeSpeaker() })).runner.built
        let ids = Set(built.entries.map(\.itemID))
        XCTAssertEqual(ids, [said.id, four.id, one.id])
        XCTAssertFalse(ids.contains(five.id))
        XCTAssertFalse(ids.contains(two.id))
        XCTAssertFalse(ids.contains(page.id))
    }

    func testNothingToAsk() {
        add(.diagram, prompt: "Label it", answer: "x")
        let controller = make(FakeListener())
        XCTAssertFalse(controller.hasQuestions)
        controller.start()
        XCTAssertEqual(controller.phase, .intro)
    }

    func testTheLiveActivitySaysWhoseTurnItIs() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        var seen: [StudySessionAttributes.ContentState.Voice?] = []
        var prompts: Set<String> = []
        let controller = make(FakeListener(["a guess", "got it"]), publish: { prompt, voice in
            seen.append(voice)
            if let prompt { prompts.insert(prompt) }
        })
        controller.start()
        try await finished(controller)
        XCTAssertEqual(Array(seen.prefix(2)), [.asking, .listening])
        XCTAssertEqual(prompts, ["One?"])
    }

    func testClosingTurnsEverythingOffAndKeepsTheAnswers() async throws {
        add(.flashcard, prompt: "One?", answer: "1")
        add(.flashcard, prompt: "Two?", answer: "2")
        let listener = FakeListener(["a guess", "got it", FakeListener.wait])
        let controller = make(listener)
        controller.start()
        try await until("the second question") { listener.turns.count == 3 }
        controller.close()
        XCTAssertTrue(listener.closed)
        XCTAssertEqual(logs().count, 1)
        XCTAssertEqual(controller.runner.phase, .finished)
    }

    func testPrimingNeverGivesTheRightAnswerAlone() async throws {
        add(.flashcard, prompt: "Capital?", answer: "Paris")
        let listener = FakeListener(["stop"])
        let controller = make(listener)
        controller.start()
        try await finished(controller)
        XCTAssertFalse(listener.turns.first?.terms.contains("Paris") == true)
    }

    // MARK: Read aloud

    func testTheVoiceThatEndsSaysSo() {
        // With nothing to say, what waits doesn't wait.
        var finished = false
        ReadAloud.shared.speak("   ", enabled: true) { finished = true }
        XCTAssertTrue(finished)
        finished = false
        ReadAloud.shared.speak("Words", enabled: false) { finished = true }
        XCTAssertTrue(finished)
    }
}

/// A listener whose every turn fails.
@MainActor
class FakeListenerBase: SpokenListening {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {}
    func listen(_ turn: SpokenTurn, onWords: @escaping @MainActor (String) -> Void) async -> SpokenHearing {
        SpokenHearing(text: "", ending: .failed)
    }
    func stopListening() {}
    func suspend() {}
    func resume() throws {}
    func close() {}
}
