import Foundation
import Observation

/// What Study out loud is built from, so tests and demos swap the microphone and the voice.
@MainActor
struct OutLoudPorts {
    var makeListener: @MainActor () -> SpokenListening
    var makeSpeaker: @MainActor () -> SpokenSpeaking
    /// Where the Live Activity's line goes (`LiveActivityController.updateOutLoud`).
    var publish: @MainActor (_ prompt: String?, _ voice: StudySessionAttributes.ContentState.Voice?) -> Void = { _, _ in }

    /// The microphone and the on-device speech engine, primed with the course's words, and Cap's voice.
    static func system(vocabulary: [String], language: String?) -> OutLoudPorts {
        OutLoudPorts(makeListener: { SpokenAnswerListener(vocabulary: vocabulary, language: language) },
                     makeSpeaker: { ReadAloudSpeaker() })
    }
}

/// One out-loud session: Cap asks, the person answers with their voice, Cap says how it went, with the screen on or off.
///
/// It drives a `SessionRunner`, as the question views do on screen: the same queue, the same `record` and `advance`, the same summary.
/// Speak, then listen: the microphone's engine keeps running throughout, which is what keeps the session alive on a locked phone (the app's audio
/// background mode), and nothing is taken from it between turns. What was said is read by `SpokenAnswer`, own words are graded through
/// `app.ai.grade` like typed ones, and `SpokenVerdict` says how it went.
///
/// **Nothing the person said is kept.** The audio is never stored, and the review log gets the rating and the score but not the words
/// (a typed answer's words are kept and sync; a spoken one's aren't, which is what `docs/privacy-wording.md` promises). A multiple choice logs
/// the option's own words, as on screen.
///
/// A call or an alarm pauses it (the same question is asked again afterwards); Repeat and Skip also come from the Live Activity
/// (`OutLoudRemote`). Two silences in a row and Cap waits; after `Timing.waitsForReturn` of that the session ends, so a forgotten phone doesn't
/// keep its microphone open.
@MainActor
@Observable
final class OutLoudController: Identifiable {
    enum Phase: Equatable, Sendable {
        case intro
        /// Asking for the microphone, or downloading the speech model (with how far it has got).
        case gettingReady(progress: Double?)
        case blocked(OutLoudBlock)
        /// Cap is reading the question.
        case asking
        /// The microphone is open. `reply`: for "got it" or "again", not an answer.
        case listening(reply: Bool)
        case checking
        /// Cap is saying how it went.
        case verdict
        case paused(OutLoudPause)
        case finished
    }

    /// What's on screen while Cap says how it went.
    struct Verdict: Equatable, Sendable {
        var line: String
        var tone: FeedbackTone
        var moment: CapMoment
        /// A multiple choice: the place picked.
        var pickedPlace: Int? = nil
    }

    struct Timing: Sendable {
        /// How long a session waits on its own after no answer came, twice, before it ends.
        var waitsForReturn: Duration = .seconds(300)
        var poll: Duration = .milliseconds(200)
        static let standard = Timing()
    }

    /// Commands from the screen and the Live Activity.
    enum Action: Equatable, Sendable {
        case repeatQuestion, skip, stop, pause, resume
    }

    let id = UUID()
    let runner: SessionRunner
    private(set) var phase: Phase = .intro
    private(set) var question: OutLoudQuestion?
    /// The words heard so far in this turn.
    private(set) var heard = ""
    private(set) var verdict: Verdict?
    /// Recent levels, oldest first, for the meter.
    private(set) var levels: [Float] = Array(repeating: 0, count: OutLoudController.levelCount)
    /// Nothing on screen needs the meter while the app is away.
    @ObservationIgnored var isOnScreen = true

    static let levelCount = 24

    @ObservationIgnored private let app: AppModel
    /// Nil: the microphone and the speech engine, worked out when the session starts (`AppModel.outLoudPorts`).
    @ObservationIgnored private let givenPorts: OutLoudPorts?
    @ObservationIgnored private var ports: OutLoudPorts?
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var listener: SpokenListening?
    @ObservationIgnored private var speaker: SpokenSpeaking?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pending: Action?
    @ObservationIgnored private var pauseReason: OutLoudPause?
    /// A pause cut in, however short: the question is asked again.
    @ObservationIgnored private var wasPaused = false
    @ObservationIgnored private var closed = false

    /// `SessionRunner.Options`: no Undo window here, because there is nothing to press; a rating is what was said.
    init(app: AppModel, request: SessionRequest, ports: OutLoudPorts? = nil, timing: Timing = .standard) {
        self.app = app
        givenPorts = ports
        self.timing = timing
        var spoken = request
        spoken.spokenOnly = true
        runner = SessionRunner(app: app, request: spoken, options: SessionRunner.Options(outLoud: true))
    }

    // MARK: Reading

    var questionCount: Int { Set(runner.built.entries.map(\.itemID)).count }
    var minutes: Int { runner.built.plannedMinutes }
    var hasQuestions: Bool { !runner.built.isEmpty }

    var isListening: Bool {
        if case .listening = phase { true } else { false }
    }

    var isPaused: Bool {
        if case .paused = phase { true } else { false }
    }

    // MARK: Running

    /// Asks for what it needs, then goes through the questions. Also "Try again" from a block.
    func start() {
        guard loop == nil, hasQuestions else { return }
        switch phase {
        case .intro, .blocked: break
        default: return
        }
        loop = Task { [weak self] in await self?.run() }
    }

    func perform(_ action: Action) {
        switch action {
        case .pause:
            guard !isPaused, phase != .finished else { return }
            pauseReason = .person
            wasPaused = true
            listener?.suspend()
            speaker?.stop()
            phase = .paused(.person)
            publish()
        case .resume:
            guard pauseReason != nil else { return }
            try? listener?.resume()
            pauseReason = nil
        case .repeatQuestion where pauseReason != nil:
            // The Live Activity's way back from "Cap is waiting".
            perform(.resume)
        case .repeatQuestion, .skip, .stop:
            pending = action
            speaker?.stop()
            listener?.stopListening()
        }
    }

    /// The person left the screen: what was answered stays recorded, and the microphone goes off at once.
    func close() {
        guard !closed else { return }
        closed = true
        loop?.cancel()
        loop = nil
        speaker?.stop()
        closeAudio()
        runner.close()
    }

    private func run() async {
        phase = .gettingReady(progress: nil)
        let ports = givenPorts ?? app.outLoudPorts(for: runner.built)
        self.ports = ports
        let listener = ports.makeListener()
        self.listener = listener
        speaker = ports.makeSpeaker()
        listener.onLevel = { [weak self] level in self?.noteLevel(level) }
        listener.onInterruption = { [weak self] interruption in self?.handle(interruption) }
        do {
            try await listener.prepare { [weak self] fraction in
                if case .gettingReady = self?.phase { self?.phase = .gettingReady(progress: fraction) }
            }
        } catch {
            closeAudio()
            phase = .blocked(OutLoudBlock(error))
            loop = nil
            return
        }
        guard !Task.isCancelled else { return }
        runner.start()
        OutLoudRemote.handler = { [weak self] command in
            switch command {
            case .repeatQuestion: self?.perform(.repeatQuestion)
            case .skip: self?.perform(.skip)
            }
        }
        var stopping = false
        while !stopping, !Task.isCancelled, runner.phase == .question, let entry = runner.current {
            guard let item = runner.item(for: entry) else {
                runner.skipWithoutRecording()
                continue
            }
            switch await play(entry, item) {
            case .answered: runner.advance()
            case .skipped: runner.skipWithoutRecording()
            case .stop: stopping = true
            }
        }
        guard !Task.isCancelled else { return }
        await wrapUp()
    }

    /// The last word, then the microphone goes off (so the summary's sounds can play), then the summary.
    private func wrapUp() async {
        question = nil
        verdict = nil
        heard = ""
        let line = SpokenVerdict.summary(answered: runner.distinctAnswered, right: runner.rightFirstTime)
        phase = .verdict
        await speaker?.say(line, language: nil)
        closeAudio()
        runner.finish()
        phase = .finished
    }

    private func closeAudio() {
        if OutLoudRemote.handler != nil { OutLoudRemote.handler = nil }
        listener?.close()
        listener = nil
    }

    // MARK: One question

    private enum Turn { case answered, skipped, stop }

    /// What came of waiting for Cap's voice or an answer.
    private enum Gate { case go, reask, skip, stop }

    private func play(_ entry: SessionEntry, _ item: StudyItem) async -> Turn {
        let question = OutLoudQuestion.make(id: entry.id, itemID: item.id, kind: item.kind, prompt: item.prompt, answer: item.answer,
                                            ideas: item.keyIdeas, choices: item.choices, cloze: item.cloze,
                                            day: app.calendar.dayNumber(for: app.now))
        self.question = question
        heard = ""
        verdict = nil
        var silences = 0
        var failures = 0
        asking: while !Task.isCancelled {
            switch await say(question.spoken, as: .asking) {
            case .go: break
            case .reask: continue asking
            case .skip: return .skipped
            case .stop: return .stop
            }
            var unclear = 0
            while !Task.isCancelled {
                let turn = SpokenTurn(endpoint: .answer, terms: question.terms, question: question)
                let (hearing, gate) = await hear(turn)
                switch gate {
                case .go: break
                case .reask: continue asking
                case .skip: return .skipped
                case .stop: return .stop
                }
                if hearing.ending == .failed {
                    failures += 1
                    if failures >= 2 { return .stop }
                    await say(OutLoudCopy.cantHear, as: .asking)
                    continue asking
                }
                if hearing.text.isEmpty {
                    silences += 1
                    if silences >= 2 {
                        switch await waitForReturn() {
                        case .go, .reask:
                            silences = 0
                            continue asking
                        case .skip: return .skipped
                        case .stop: return .stop
                        }
                    }
                    switch await say(OutLoudCopy.takeYourTime, as: .asking) {
                    case .go, .reask: continue
                    case .skip: return .skipped
                    case .stop: return .stop
                    }
                }
                silences = 0
                switch await respond(to: SpokenAnswer.read(hearing.text, expecting: question.expecting), hearing: hearing,
                                     question: question, item: item) {
                case .done(let turn): return turn
                case .reask: continue asking
                case .unclear:
                    unclear += 1
                    if unclear >= 2 { continue asking }
                    let line = question.kind == .mcq ? OutLoudCopy.sayALetter : OutLoudCopy.didntCatch
                    switch await say(line, as: .asking) {
                    case .go, .reask: continue
                    case .skip: return .skipped
                    case .stop: return .stop
                    }
                }
            }
        }
        return .stop
    }

    private enum Response {
        case done(Turn)
        case reask
        case unclear
    }

    private func respond(to reading: SpokenAnswer.Reading, hearing: SpokenHearing, question: OutLoudQuestion, item: StudyItem) async -> Response {
        switch reading {
        case .command(.repeatQuestion): return .reask
        case .command(.skip): return .done(.skipped)
        case .command(.stop): return .done(.stop)
        case .dontKnow: return .done(await dontKnow(question, item: item))
        case .nothing, .rating: return .unclear
        case .choice(let place):
            guard question.optionIndexes.indices.contains(place) else { return .unclear }
            return .done(await answerChoice(place, hearing: hearing, question: question, item: item))
        case .words(let words):
            switch question.kind {
            case .mcq: return .unclear
            case .cloze: return .done(await answerBlank(words, hearing: hearing, question: question, item: item))
            case .flashcard: return .done(await rateFlashcard(question, item: item, hearing: hearing))
            case .recall, .apply, .diagram: return .done(await answerOwnWords(words, hearing: hearing, question: question, item: item))
            }
        }
    }

    /// "I don't know": the answer, and it comes back sooner, as on screen.
    private func dontKnow(_ question: OutLoudQuestion, item: StudyItem) async -> Turn {
        let isFlashcard = question.kind == .flashcard
        record(rating: .again, score: isFlashcard ? -1 : 0, answer: nil, gradedBy: isFlashcard ? "person" : LocalGrader.model, durationMs: 0,
               outcome: .wrong)
        return await deliver(Verdict(line: SpokenVerdict.dontKnow(answer: question.rightAnswer), tone: .neutral, moment: .answerShown))
    }

    private func answerChoice(_ place: Int, hearing: SpokenHearing, question: OutLoudQuestion, item: StudyItem) async -> Turn {
        let index = question.optionIndexes[place]
        let grade = app.ai.instantGrade(app.gradeSubject(for: item), answer: .choice(index))
        let ms = milliseconds(hearing)
        let score: Double = grade.isCorrect ? 1 : 0
        let review = record(rating: AppModel.rating(forScore: score, kind: .mcq, durationMs: ms), score: score, answer: question.options[place],
                            gradedBy: grade.gradedBy.rawValue, durationMs: ms, outcome: grade.isCorrect ? .right : .wrong)
        return await deliverExact(grade, review: review, question: question, item: item, pickedPlace: place)
    }

    private func answerBlank(_ words: String, hearing: SpokenHearing, question: OutLoudQuestion, item: StudyItem) async -> Turn {
        let grade = app.ai.instantGrade(app.gradeSubject(for: item), answer: .blanks([SpokenAnswer.bareAnswer(words)]))
        let ms = milliseconds(hearing)
        let review = record(rating: AppModel.rating(forScore: grade.score, kind: .cloze, durationMs: ms), score: grade.score, answer: nil,
                            gradedBy: grade.gradedBy.rawValue, durationMs: ms, outcome: SessionRunner.Outcome(grade.verdict))
        return await deliverExact(grade, review: review, question: question, item: item, pickedPlace: nil)
    }

    private func deliverExact(_ grade: GradeOutcome, review: ReviewOutcome?, question: OutLoudQuestion, item: StudyItem, pickedPlace: Int?) async -> Turn {
        let saved = review?.isSave == true
        if saved { runner.flareSave(of: item) }
        let moment: CapMoment = grade.isCorrect ? (saved ? .saved : .nice) : .notYet
        return await deliver(Verdict(line: SpokenVerdict.exact(grade, rightAnswer: question.rightAnswer, saved: saved),
                                     tone: FeedbackTone(grade.verdict), moment: moment, pickedPlace: pickedPlace))
    }

    /// A flashcard: whatever was said, the answer, then how it went is the person's to say.
    private func rateFlashcard(_ question: OutLoudQuestion, item: StudyItem, hearing: SpokenHearing) async -> Turn {
        switch await howDidItGo(question) {
        case .skipped: return .skipped
        case .stop: return .stop
        case .rated(let rating):
            return await recordRating(rating, score: -1, gradedBy: "person", durationMs: milliseconds(hearing), item: item)
        }
    }

    /// A rating the person said out loud: recorded, and Cap says he heard it.
    private func recordRating(_ rating: Rating, score: Double, gradedBy: String, durationMs: Int, item: StudyItem) async -> Turn {
        let review = record(rating: rating, score: score, answer: nil, gradedBy: gradedBy, durationMs: durationMs,
                            outcome: SessionRunner.Outcome(rating: rating))
        let saved = review?.isSave == true
        if saved { runner.flareSave(of: item) }
        return await deliver(Verdict(line: SpokenVerdict.rated(rating, saved: saved), tone: rating == .again ? .neutral : .mint,
                                     moment: saved ? .saved : (rating == .again ? .answerShown : .nice)))
    }

    /// Own words: through the same grade path as typed ones (the rules at once, then a model where one is allowed). What the rules can't
    /// judge alone becomes the person's to say, as with a flashcard.
    private func answerOwnWords(_ words: String, hearing: SpokenHearing, question: OutLoudQuestion, item: StudyItem) async -> Turn {
        phase = .checking
        publish()
        let subject = app.gradeSubject(for: item)
        var outcome: GradeOutcome?
        for await grade in app.ai.grade(subject, answer: .text(words)) {
            outcome = grade
            if Task.isCancelled { break }
        }
        switch takePending() {
        case .go, .reask: break
        case .skip: return .skipped
        case .stop: return .stop
        }
        guard let outcome else { return .skipped }
        let ms = milliseconds(hearing)
        if outcome.mode == .selfCheck {
            switch await howDidItGo(question) {
            case .skipped: return .skipped
            case .stop: return .stop
            case .rated(let rating):
                return await recordRating(rating, score: Grading.score(standingFor: rating, near: outcome.score), gradedBy: "self", durationMs: ms, item: item)
            }
        }
        let review = record(rating: AppModel.rating(forScore: outcome.score, kind: item.kind, durationMs: ms), score: outcome.score, answer: nil,
                            gradedBy: outcome.gradedBy.rawValue, durationMs: ms, outcome: SessionRunner.Outcome(outcome.verdict))
        let saved = review?.isSave == true
        if saved { runner.flareSave(of: item) }
        let moment: CapMoment
        switch outcome.verdict {
        case .correct: moment = saved ? .saved : .nice
        case .partial: moment = .almost
        case .incorrect: moment = .notYet
        }
        return await deliver(Verdict(line: SpokenVerdict.ownWords(outcome, ideas: question.ideas, modelAnswer: question.rightAnswer, saved: saved),
                                     tone: FeedbackTone(outcome.verdict), moment: moment))
    }

    private enum Reply {
        case rated(Rating)
        case skipped
        case stop
    }

    /// The answer, then "did you have it?", until a rating is heard. Two tries with nothing usable and the question moves on unrecorded.
    private func howDidItGo(_ question: OutLoudQuestion) async -> Reply {
        var line = SpokenVerdict.howDidItGo(answer: question.rightAnswer)
        verdict = Verdict(line: line, tone: .neutral, moment: .answerShown)
        var tries = 0
        while !Task.isCancelled {
            switch await say(line, as: .verdict) {
            case .go, .reask: break
            case .skip: return .skipped
            case .stop: return .stop
            }
            let turn = SpokenTurn(endpoint: .reply, terms: ["got it", "again", "hard", "easy", "skip", "stop"], question: question, isReply: true)
            let (hearing, gate) = await hear(turn, reply: true)
            switch gate {
            case .go: break
            case .reask: continue
            case .skip: return .skipped
            case .stop: return .stop
            }
            switch SpokenAnswer.read(hearing.text, expecting: .rating) {
            case .rating(let rating): return .rated(rating)
            case .dontKnow: return .rated(.again)
            case .command(.repeatQuestion): line = SpokenVerdict.howDidItGo(answer: question.rightAnswer)
            case .command(.skip): return .skipped
            case .command(.stop): return .stop
            case .choice, .words, .nothing:
                tries += 1
                if tries >= 2 { return .skipped }
                line = OutLoudCopy.sayHowItWent
            }
        }
        return .stop
    }

    /// Says how it went. An answer is already recorded by now: nothing but Stop changes what follows.
    private func deliver(_ verdict: Verdict) async -> Turn {
        self.verdict = verdict
        return await say(verdict.line, as: .verdict) == .stop ? .stop : .answered
    }

    @discardableResult
    private func record(rating: Rating, score: Double, answer: String?, gradedBy: String, durationMs: Int, outcome: SessionRunner.Outcome) -> ReviewOutcome? {
        runner.record(rating: rating, score: score, answer: answer, gradedBy: gradedBy, durationMs: durationMs, outcome: outcome)
    }

    private func milliseconds(_ hearing: SpokenHearing) -> Int { max(0, Int(hearing.seconds * 1000)) }

    // MARK: Voice and ears

    /// Cap says a line. What comes back is what happened meanwhile.
    @discardableResult
    private func say(_ line: String, as phase: Phase) async -> Gate {
        if let held = await holdIfPaused() { return held }
        self.phase = phase
        publish()
        await speaker?.say(line, language: nil)
        return await afterWaiting()
    }

    /// The microphone is open for one turn.
    private func hear(_ turn: SpokenTurn, reply: Bool = false) async -> (SpokenHearing, Gate) {
        if let held = await holdIfPaused() { return (SpokenHearing(text: "", ending: .stopped), held) }
        heard = ""
        phase = .listening(reply: reply)
        publish()
        guard let listener else { return (SpokenHearing(text: "", ending: .failed), .stop) }
        let hearing = await listener.listen(turn) { [weak self] words in self?.heard = words }
        return (hearing, await afterWaiting())
    }

    /// A pause came, or a command, while waiting.
    private func afterWaiting() async -> Gate {
        if let held = await holdIfPaused() { return held }
        guard wasPaused else { return takePending() }
        // It paused and picked up again before this got to look.
        wasPaused = false
        let taken = takePending()
        return taken == .go ? .reask : taken
    }

    private func takePending() -> Gate {
        if Task.isCancelled { return .stop }
        guard let action = pending else { return .go }
        pending = nil
        switch action {
        case .repeatQuestion: return .reask
        case .skip: return .skip
        case .stop: return .stop
        case .pause, .resume: return .go
        }
    }

    /// While paused nothing happens; afterwards the question is asked again. Nil when it wasn't paused.
    private func holdIfPaused() async -> Gate? {
        guard pauseReason != nil else { return nil }
        while pauseReason != nil, !Task.isCancelled {
            if pending == .stop { pauseReason = nil; break }
            try? await Task.sleep(for: timing.poll)
        }
        wasPaused = false
        let taken = takePending()
        return taken == .go ? .reask : taken
    }

    /// No answer, twice. Cap says he'll wait; the microphone stays on but takes nothing. Repeat (on screen or on the Live Activity) brings him
    /// back; if nobody does, the session ends.
    private func waitForReturn() async -> Gate {
        phase = .verdict
        await speaker?.say(OutLoudCopy.waiting, language: nil)
        pauseReason = .noAnswer
        phase = .paused(.noAnswer)
        publish()
        let started = ContinuousClock.now
        while pauseReason != nil, !Task.isCancelled {
            if pending == .stop { pauseReason = nil; break }
            if ContinuousClock.now - started >= timing.waitsForReturn {
                pauseReason = nil
                return .stop
            }
            try? await Task.sleep(for: timing.poll)
        }
        let taken = takePending()
        return taken == .go ? .reask : taken
    }

    private func handle(_ interruption: LectureInterruption) {
        switch interruption {
        case .began:
            pauseReason = .interruption
            wasPaused = true
            speaker?.stop()
            listener?.stopListening()
            phase = .paused(.interruption)
            publish()
        case .ended(let shouldResume):
            guard pauseReason == .interruption, shouldResume else { return }
            perform(.resume)
        case .lostInput:
            pauseReason = .lostInput
            wasPaused = true
            speaker?.stop()
            listener?.stopListening()
            phase = .paused(.lostInput)
            publish()
        }
    }

    private func noteLevel(_ level: Float) {
        guard isOnScreen else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func publish() {
        typealias Voice = StudySessionAttributes.ContentState.Voice
        let voice: Voice?
        switch phase {
        case .asking, .verdict: voice = .asking
        case .listening: voice = .listening
        case .checking: voice = .checking
        case .paused: voice = .paused
        default: voice = nil
        }
        let prompt = question?.prompt
        ports?.publish(prompt, voice)
        app.liveActivities.updateOutLoud(prompt: prompt, voice: voice)
    }
}
