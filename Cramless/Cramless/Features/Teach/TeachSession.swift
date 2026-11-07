import Foundation
import Observation

/// What Teach Cap is built from, so tests and demos swap the microphone.
@MainActor
struct TeachPorts {
    var makeListener: @MainActor () -> SpokenListening
    /// Teach mode: the explanation runs until Done or two minutes.
    static func system(vocabulary: [String], language: String?) -> TeachPorts {
        TeachPorts(makeListener: { SpokenAnswerListener(vocabulary: vocabulary, language: language) })
    }
}

/// One go at explaining a topic to Cap.
///
/// Say it or type it; the notes fill in as the rules find each idea in the words. Done runs the normal grade path over the plan's ideas (the rules at once, then Cloud
/// AI if it's allowed), and shows what was covered. Where no model will grade it and the rules can't be trusted, the person ticks what they said, as with any own-words answer.
/// One follow-up comes from the first missed idea, answered aloud or by typing, and records one review. The missing idea can be added as a question.
///
/// Nothing the person said is kept: the audio is never stored, and the words stay in this object until it goes. It works with Cloud AI off, and with
/// no microphone or speech model it falls back to typing.
@MainActor
@Observable
final class TeachSession {
    enum Phase: Equatable, Sendable {
        case prompt
        /// Getting the microphone, or downloading the speech model.
        case gettingReady(progress: Double?)
        case listening
        case typing
        case check
        /// The follow-up's question, before an answer.
        case followUp
        case followUpListening
        case followUpTyping
        /// How the follow-up went.
        case followUpDone
    }

    let plan: TeachPlan
    private(set) var phase: Phase = .prompt
    /// The words so far: heard, or typed.
    private(set) var words = ""
    /// The ideas found in the words so far, in the order they turned up.
    private(set) var liveHits: [String] = []
    /// Bumps with each new idea, so Cap nods.
    private(set) var nods = 0
    private(set) var grade: GradeOutcome?
    private(set) var isRefining = false
    /// With a self-check: the ideas the person says they covered.
    private(set) var ticked: Set<String> = []
    private(set) var followUp: TeachFollowUp?
    private(set) var followUpGrade: GradeOutcome?
    private(set) var followUpRefining = false
    private(set) var followUpWords = ""
    /// The rating the follow-up was recorded with.
    private(set) var followUpRating: Rating?
    private(set) var addedIdea: String?
    /// Why it's typing instead of listening, or that nothing was heard.
    private(set) var note: LocalizedStringResource?
    /// Recent levels, oldest first, for the meter.
    private(set) var levels: [Float] = Array(repeating: 0, count: 24)
    private(set) var listenStartedAt = Date()

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let ports: TeachPorts?
    @ObservationIgnored private let subject: GradeSubject
    @ObservationIgnored private var listener: SpokenListening?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var grading: Task<Void, Never>?
    @ObservationIgnored private var typedCheck: Task<Void, Never>?
    @ObservationIgnored private var lastHitCheck = ContinuousClock.now - .seconds(10)

    /// How often the rules read the words while they are arriving. A final phrase is read at once.
    private static let hitCheckEvery: Duration = .milliseconds(600)

    init(app: AppModel, plan: TeachPlan, ports: TeachPorts? = nil) {
        self.app = app
        self.plan = plan
        self.ports = ports
        subject = plan.subject(level: app.settings.level?.rawValue)
    }

    // MARK: Reading

    /// The ideas counted as covered right now: the grade's, or the person's ticks.
    var covered: Set<String> {
        guard let grade else { return Set(liveHits) }
        return grade.mode == .selfCheck ? ticked : Set(grade.hitIdeaIDs)
    }

    var coveredCount: Int { plan.ideas.filter { covered.contains($0.id) }.count }
    var isSelfCheck: Bool { grade?.mode == .selfCheck }
    var firstMissing: TeachIdea? { plan.firstMissing(covered: covered) }
    /// The labels the notes show, in the order they turned up.
    var liveHitLabels: [String] { liveHits.compactMap { id in plan.ideas.first { $0.id == id }?.label } }

    // MARK: Saying it

    /// The microphone: the explanation runs until Done or two minutes. Without one, typing, with why.
    func sayIt() {
        guard phase == .prompt else { return }
        note = nil
        phase = .gettingReady(progress: nil)
        listen(endpoint: .teaching, terms: plan.ideas.flatMap(\.hearingTerms), phase: .listening) { [weak self] heard in
            self?.heard(heard)
        } finished: { [weak self] hearing in
            self?.finishedListening(hearing)
        } unavailable: { [weak self] error in
            self?.note = TeachCopy.reason(error)
            self?.phase = .typing
        }
    }

    func typeIt() {
        guard phase == .prompt else { return }
        phase = .typing
    }

    func typed(_ text: String) {
        words = text
        typedCheck?.cancel()
        typedCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.readHits()
        }
    }

    /// Done: what was said goes to be checked.
    func done() {
        switch phase {
        case .listening:
            listener?.stopListening()
        case .typing:
            typedCheck?.cancel()
            let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            check(text)
        default:
            break
        }
    }

    private func heard(_ text: String) {
        words = text
        let now = ContinuousClock.now
        guard now - lastHitCheck >= Self.hitCheckEvery else { return }
        lastHitCheck = now
        readHits()
    }

    /// The notes fill in from the rules, as the words arrive.
    private func readHits() {
        guard !words.isEmpty else { return }
        let found = LocalGrader.gradeOwnWords(subject, words).hitIdeaIDs
        let new = found.filter { !liveHits.contains($0) }
        guard !new.isEmpty else { return }
        liveHits += new
        nods += 1
    }

    private func finishedListening(_ hearing: SpokenHearing) {
        let text = hearing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        closeListener()
        guard !text.isEmpty else {
            note = TeachCopy.heardNothing
            phase = .prompt
            return
        }
        words = text
        readHits()
        check(text)
    }

    private func check(_ text: String) {
        phase = .check
        app.noteTopicTaught(plan.topicID)
        isRefining = true
        grading?.cancel()
        grading = Task { [weak self] in
            guard let self else { return }
            for await outcome in self.app.ai.grade(self.subject, answer: .text(text)) {
                if Task.isCancelled { return }
                self.grade = outcome
                self.isRefining = outcome.mode == .provisional
                if outcome.mode == .selfCheck { self.ticked = Set(outcome.hitIdeaIDs) }
            }
            self.isRefining = false
        }
    }

    /// A self-check: an idea the person says they did, or didn't, cover.
    func toggle(_ idea: TeachIdea) {
        guard isSelfCheck else { return }
        if ticked.contains(idea.id) { ticked.remove(idea.id) } else { ticked.insert(idea.id) }
    }

    // MARK: The follow-up

    /// One question, from the first missed idea.
    func askFollowUp() {
        guard phase == .check, !isRefining, let idea = firstMissing, let made = app.teachFollowUp(for: idea) else { return }
        followUp = made
        note = nil
        phase = .followUp
    }

    func sayFollowUp() {
        guard phase == .followUp else { return }
        phase = .gettingReady(progress: nil)
        listen(endpoint: .answer, terms: followUp?.idea.hearingTerms ?? [], phase: .followUpListening) { [weak self] heard in
            self?.followUpWords = heard
        } finished: { [weak self] hearing in
            guard let self else { return }
            self.closeListener()
            let text = hearing.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                self.note = TeachCopy.heardNothing
                self.phase = .followUp
                return
            }
            self.followUpWords = text
            self.gradeFollowUp(text, seconds: hearing.seconds)
        } unavailable: { [weak self] error in
            self?.note = TeachCopy.reason(error)
            self?.phase = .followUpTyping
        }
    }

    func typeFollowUp() {
        guard phase == .followUp else { return }
        phase = .followUpTyping
    }

    func typedFollowUp(_ text: String) { followUpWords = text }

    func doneFollowUp() {
        switch phase {
        case .followUpListening:
            listener?.stopListening()
        case .followUpTyping:
            let text = followUpWords.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            gradeFollowUp(text, seconds: 0)
        default:
            break
        }
    }

    private func gradeFollowUp(_ text: String, seconds: Double) {
        guard let followUp else { return }
        phase = .followUpDone
        followUpRefining = true
        grading?.cancel()
        grading = Task { [weak self] in
            guard let self else { return }
            var last: GradeOutcome?
            for await outcome in self.app.ai.grade(followUp.subject, answer: .text(text)) {
                if Task.isCancelled { return }
                last = outcome
                self.followUpGrade = outcome
                self.followUpRefining = outcome.mode == .provisional
            }
            self.followUpRefining = false
            guard let last, last.mode != .selfCheck else { return }
            let ms = Int(seconds * 1000)
            let rating = AppModel.rating(forScore: last.score, kind: followUp.subject.kind, durationMs: ms)
            self.app.recordTeachFollowUp(followUp, rating: rating, score: last.score, gradedBy: last.gradedBy.rawValue, durationMs: ms)
            self.followUpRating = rating
        }
    }

    /// A follow-up no model graded: how it went is the person's to say. Recorded once.
    func markFollowUp(hadIt: Bool) {
        guard let followUp, followUpRating == nil, let grade = followUpGrade, grade.mode == .selfCheck else { return }
        let rating: Rating = hadIt ? .good : .again
        app.recordTeachFollowUp(followUp, rating: rating, score: Grading.score(standingFor: rating, near: grade.score), gradedBy: "self", durationMs: 0)
        followUpRating = rating
    }

    /// The missing idea as a question. Once.
    func addMissingIdea() {
        guard addedIdea == nil, let idea = followUp?.idea, let made = app.addMissingIdea(idea, topicID: plan.topicID) else { return }
        addedIdea = made.prompt
    }

    // MARK: The microphone

    private func listen(endpoint: SpeechEndpoint.Config, terms: [String], phase next: Phase, onWords: @escaping @MainActor (String) -> Void,
                        finished: @escaping @MainActor (SpokenHearing) -> Void, unavailable: @escaping @MainActor (Error) -> Void) {
        let ports = ports ?? app.teachPorts(courseID: plan.courseID)
        let listener = ports.makeListener()
        self.listener = listener
        listener.onLevel = { [weak self] level in self?.noteLevel(level) }
        listener.onInterruption = { [weak self] interruption in
            // A call ends the turn with what was said.
            if case .began = interruption { self?.listener?.stopListening() }
        }
        listening = Task { [weak self] in
            do {
                try await listener.prepare { fraction in
                    guard let self, case .gettingReady = self.phase else { return }
                    self.phase = .gettingReady(progress: fraction)
                }
            } catch {
                self?.closeListener()
                unavailable(error)
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.listenStartedAt = Date()
            self.phase = next
            let hearing = await listener.listen(SpokenTurn(endpoint: endpoint, terms: Array(terms.prefix(40))), onWords: onWords)
            guard !Task.isCancelled else { return }
            finished(hearing)
        }
    }

    private func noteLevel(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    private func closeListener() {
        listener?.close()
        listener = nil
    }

    /// The person left: the microphone goes off at once.
    func close() {
        listening?.cancel()
        grading?.cancel()
        typedCheck?.cancel()
        closeListener()
    }
}
