import Foundation
import Observation

/// One sitting of a mock exam: what has been answered, what is flagged, the clock, and the marking at hand-in.
///
/// Nothing is graded or recorded while the person works: they can go back, change an answer and flag a question. At hand-in the exact
/// formats are checked at once and own-words answers are graded a few at a time (`SelfCheck.modelWait` each at most), then every answer with a
/// mark is recorded as a review, dated when it was given, in one `StudySession` of kind `.mock`. A question left blank isn't recorded, and neither is
/// an own-words answer no model graded until the person has marked it. A mock has no requeues: it asks each question once.
///
/// What is typed goes straight into a store nobody observes, so a keystroke reaches only the view that holds it; the views read the narrow
/// counts below.
@MainActor
@Observable
final class MockRunner: Identifiable {
    enum Phase: Equatable, Sendable {
        case intro, answering, review, timeUp, marking, summary
    }

    /// What the person has given for one question.
    struct Given: Equatable, Sendable {
        /// The option picked, as its index in the item's choices.
        var choice: Int?
        var text = ""
        var blanks: [String] = []
        /// Seconds this question has been on screen.
        var seconds = 0.0
        /// When the answer last changed.
        var answeredAt: Date?
    }

    /// One question after hand-in.
    enum Mark: Equatable, Sendable {
        case blank
        /// A grade: an exact check, a model's, or the rules' where they can be trusted.
        case graded(score: Double, verdict: GradeResponse.Verdict)
        /// No model graded it and the rules can't be trusted: the person's to mark. `reason` says why, `found` is what the rules found.
        case toMark(reason: SelfCheckReason?, found: Set<String>)
        /// Marked by the person.
        case selfMarked(score: Double)

        var credit: Double? {
            switch self {
            case .blank, .toMark: nil
            case .graded(let score, _), .selfMarked(let score): score
            }
        }
    }

    /// How many written answers are graded at once.
    static let markingAtOnce = 4

    let id = UUID()
    let examID: UUID
    let examTitle: String
    let courseID: UUID?
    let plan: MockPlan
    /// The real exam's format: what the intro compares this mock with.
    let format: ExamFormat

    private(set) var phase: Phase = .intro
    /// The question on screen, as an index of `plan.entries`.
    private(set) var position = 0
    private(set) var answeredCount = 0
    private(set) var flagged: Set<UUID> = []
    /// When the time limit runs out; nil when the clock isn't running.
    private(set) var deadline: Date?
    /// How many were answered when the clock ran out, once it has.
    private(set) var answeredInTime: Int?
    private(set) var markingDone = 0
    private(set) var markingTotal = 0
    private(set) var result: MockResult?
    private(set) var summary: SessionSummary?
    private(set) var marks: [UUID: Mark] = [:]
    /// What the game loop made of this sitting (a badge earned).
    private(set) var game = GameOutcome()

    @ObservationIgnored private var given: [UUID: Given] = [:]
    @ObservationIgnored private var session: StudySession?
    @ObservationIgnored private var shownAt: Date?
    @ObservationIgnored private let app: AppModel
    /// The wall clock (the app's own may be frozen by the harness); tests set it.
    @ObservationIgnored private let clock: () -> Date
    #if DEBUG
    /// `CRAMLESS_MOCK=marking` stays on the marking screen.
    @ObservationIgnored var debugHoldsMarking = false
    #endif

    init?(app: AppModel, examID: UUID, seed: UInt64? = nil, clock: @escaping () -> Date = Date.init) {
        guard let exam = app.exam(examID), exam.deletedAt == nil, let plan = app.mockPlan(for: exam, seed: seed) else { return nil }
        self.app = app
        self.examID = examID
        self.examTitle = exam.title
        self.courseID = exam.course?.id
        self.plan = plan
        self.format = exam.format
        self.clock = clock
    }

    // MARK: Reading

    var total: Int { plan.entries.count }
    var current: SessionEntry? { plan.entries.indices.contains(position) ? plan.entries[position] : nil }
    var isTimed: Bool { deadline != nil }
    var isFirst: Bool { position == 0 }
    var isLast: Bool { position >= total - 1 }
    var flaggedCount: Int { flagged.count }
    /// Questions left blank.
    var blankCount: Int { total - answeredCount }
    var isFlagged: Bool { current.map { flagged.contains($0.itemID) } ?? false }

    func item(_ entry: SessionEntry) -> StudyItem? {
        guard let item = app.item(entry.itemID), item.deletedAt == nil, item.modelContext != nil else { return nil }
        return item
    }

    func given(for itemID: UUID) -> Given { given[itemID] ?? Given() }

    func isAnswered(_ entry: SessionEntry) -> Bool {
        let g = given(for: entry.itemID)
        switch entry.kind {
        case .mcq: return g.choice != nil
        case .cloze: return g.blanks.contains { !$0.clTrimmed.isEmpty }
        default: return !g.text.clTrimmed.isEmpty
        }
    }

    /// What the person gave, in words, for the log and "See your answers".
    func answerText(for entry: SessionEntry) -> String? {
        let g = given(for: entry.itemID)
        switch entry.kind {
        case .mcq:
            guard let choice = g.choice, let choices = item(entry)?.choices, choices.indices.contains(choice) else { return nil }
            return choices[choice].text
        case .cloze:
            let words = g.blanks.map(\.clTrimmed)
            return words.contains { !$0.isEmpty } ? words.joined(separator: " / ") : nil
        default:
            let words = g.text.clTrimmed
            return words.isEmpty ? nil : words
        }
    }

    /// Own-words answers waiting for the person's mark.
    var toMark: [SessionEntry] {
        plan.entries.filter { if case .toMark = marks[$0.itemID] { true } else { false } }
    }

    // MARK: Sitting

    /// Starts the clock (`timed`) and the `StudySession` with readiness before. `elapsed`: seconds already gone (a DEBUG hook).
    func start(timed: Bool, elapsed: TimeInterval = 0) {
        guard phase == .intro else { return }
        session = app.startSession(plan.built())
        let now = clock()
        deadline = timed ? now.addingTimeInterval(Double(plan.minutes) * 60 - elapsed) : nil
        shownAt = now
        phase = .answering
        checkTime()
    }

    func setChoice(_ choice: Int?, for itemID: UUID) {
        update(itemID) { $0.choice = choice }
    }

    func setText(_ text: String, for itemID: UUID) {
        update(itemID) { $0.text = text }
    }

    func setBlanks(_ blanks: [String], for itemID: UUID) {
        update(itemID) { $0.blanks = blanks }
    }

    private func update(_ itemID: UUID, _ change: (inout Given) -> Void) {
        var g = given(for: itemID)
        change(&g)
        g.answeredAt = app.now
        given[itemID] = g
        let answered = plan.entries.reduce(0) { $0 + (isAnswered($1) ? 1 : 0) }
        if answered != answeredCount { answeredCount = answered }
    }

    func next() { go(to: position + 1) }
    func back() { go(to: position - 1) }

    /// Moves to a question (from the review grid too), counting the time spent on the one before.
    func go(to index: Int) {
        guard plan.entries.indices.contains(index) else { return }
        noteTime()
        position = index
        if phase == .review { phase = .answering }
    }

    func toggleFlag() {
        guard let id = current?.itemID else { return }
        if flagged.contains(id) { flagged.remove(id) } else { flagged.insert(id) }
    }

    func openReview() {
        guard phase == .answering else { return }
        noteTime()
        phase = .review
    }

    func closeReview() {
        guard phase == .review else { return }
        shownAt = clock()
        phase = .answering
    }

    private func noteTime() {
        let now = clock()
        if let shownAt, let id = current?.itemID, phase == .answering {
            var g = given(for: id)
            g.seconds += max(0, now.timeIntervalSince(shownAt))
            given[id] = g
        }
        shownAt = now
    }

    // MARK: The clock

    /// The time limit has run out: stops and asks (idempotent). The view calls this when its timer fires and when the app comes back.
    func checkTime() {
        guard let deadline, clock() >= deadline, phase == .answering || phase == .review else { return }
        noteTime()
        answeredInTime = answeredCount
        phase = .timeUp
    }

    /// "Finish untimed": the clock is gone and the rest can be answered. The score says how many were in time.
    func finishUntimed() {
        guard phase == .timeUp else { return }
        deadline = nil
        shownAt = clock()
        phase = .answering
        if let firstBlank = plan.entries.firstIndex(where: { !isAnswered($0) }) { position = firstBlank }
    }

    // MARK: Handing in

    /// Marks what has been answered, records it and finishes the session. Idempotent.
    func handIn() async {
        guard phase == .answering || phase == .review || phase == .timeUp else { return }
        if phase == .answering { noteTime() }
        phase = .marking
        app.stopReadingAloud()
        let answered = plan.entries.filter(isAnswered)
        var grades: [UUID: GradeOutcome] = [:]
        var written: [SessionEntry] = []
        for entry in answered {
            guard let item = item(entry) else { continue }
            let g = given(for: entry.itemID)
            switch entry.kind {
            case .mcq:
                grades[entry.itemID] = app.ai.instantGrade(app.gradeSubject(for: item), answer: .choice(g.choice ?? -1))
            case .cloze:
                grades[entry.itemID] = app.ai.instantGrade(app.gradeSubject(for: item), answer: .blanks(g.blanks.map(\.clTrimmed)))
            default:
                written.append(entry)
            }
        }
        markingTotal = written.count
        markingDone = 0
        // The written answers, up to four at a time.
        let ai = app.ai
        let jobs = written.compactMap { entry in
            item(entry).map { (id: entry.itemID, subject: app.gradeSubject(for: $0), text: given(for: entry.itemID).text.clTrimmed) }
        }
        await withTaskGroup(of: (UUID, GradeOutcome?).self) { group in
            var nextJob = 0
            var running = 0
            while nextJob < jobs.count || running > 0 {
                while running < Self.markingAtOnce, nextJob < jobs.count {
                    let job = jobs[nextJob]
                    nextJob += 1
                    running += 1
                    group.addTask { @MainActor in
                        var last: GradeOutcome?
                        for await outcome in ai.grade(job.subject, answer: .text(job.text), wait: SelfCheck.modelWait) { last = outcome }
                        return (job.id, last)
                    }
                }
                guard let (id, outcome) = await group.next() else { break }
                running -= 1
                if let outcome { grades[id] = outcome }
                markingDone += 1
            }
        }
        #if DEBUG
        if debugHoldsMarking { return }
        #endif

        // Every answer with a mark is a review, dated when it was given.
        var marks: [UUID: Mark] = [:]
        let order = plan.entries.enumerated().sorted { a, b in
            let da = given(for: a.element.itemID).answeredAt ?? .distantFuture
            let db = given(for: b.element.itemID).answeredAt ?? .distantFuture
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        for entry in order {
            guard isAnswered(entry), let grade = grades[entry.itemID] else {
                marks[entry.itemID] = .blank
                continue
            }
            if grade.mode != .verdict {
                let ideas = item(entry)?.keyIdeas ?? []
                marks[entry.itemID] = .toMark(reason: grade.selfCheckReason, found: SelfCheck.startingTicks(of: grade, ideas: ideas))
                continue
            }
            let g = given(for: entry.itemID)
            app.recordMockAnswer(itemID: entry.itemID, score: grade.score, answer: answerText(for: entry), gradedBy: grade.gradedBy.rawValue,
                                 seconds: g.seconds, sessionID: session?.id, at: g.answeredAt)
            marks[entry.itemID] = .graded(score: grade.score, verdict: grade.verdict)
            await Task.yield()
        }
        self.marks = marks
        finish()
    }

    /// Records the person's mark on an own-words answer no model graded: the ticks' share of the key ideas, counted as marked by them.
    func mark(_ itemID: UUID, ticked: Set<String>) {
        guard case .toMark = marks[itemID], let item = app.item(itemID), item.deletedAt == nil else { return }
        let ticks = SelfCheck.score(ticked: ticked, of: item.keyIdeas)
        let g = given(for: itemID)
        let rating = AppModel.rating(forScore: ticks, kind: item.kind, durationMs: Int(g.seconds * 1000))
        let score = Grading.score(standingFor: rating, near: ticks)
        app.recordMockAnswer(itemID: itemID, score: score, answer: g.text.clTrimmed, gradedBy: "self", seconds: g.seconds,
                             sessionID: session?.id, at: g.answeredAt, rating: rating)
        marks[itemID] = .selfMarked(score: score)
        rescore()
        let outcome = app.settleGame()
        game.badges += outcome.badges
    }

    /// The screen went away before hand-in: what has been answered is marked, and with nothing answered the session simply ends.
    func abandon() {
        guard phase == .answering || phase == .review || phase == .timeUp else { return }
        if answeredCount > 0 {
            Task { await handIn() }
        } else if let session, session.endedAt == nil {
            summary = app.finishSession(session)
        }
    }

    private func finish() {
        if let session { summary = app.finishSession(session) }
        rescore()
        game = app.settleGame()
        phase = .summary
    }

    private func rescore() {
        let lines = plan.entries.map { entry in
            MockLine(itemID: entry.itemID, topicID: entry.topicID, expected: plan.expectedByItem[entry.itemID] ?? 0,
                     credit: marks[entry.itemID]?.credit)
        }
        result = MockScorer.score(lines, topicNames: app.topicNames())
    }

    // MARK: DEBUG

    #if DEBUG
    /// Gives answers by a pattern, as the person would: `r` right, `p` partly right, `w` wrong, `k` left blank, one letter per question.
    func debugAnswer(pattern: [Character], through limit: Int? = nil) {
        guard !pattern.isEmpty else { return }
        for (index, entry) in plan.entries.enumerated() where index < limit ?? total {
            debugAnswer(entry, step: pattern[index % pattern.count])
        }
    }

    func debugAnswer(_ entry: SessionEntry, step: Character) {
        guard let item = item(entry), step != "k" else { return }
        switch entry.kind {
        case .mcq:
            let correct = item.choices.firstIndex(where: \.correct)
            setChoice(step == "r" ? correct : item.choices.indices.first { !item.choices[$0].correct }, for: entry.itemID)
        case .cloze:
            let answers = (item.cloze ?? ClozeSpec(text: "{{\(item.answer)}}")).answers
            setBlanks(step == "r" ? answers : answers.map { _ in "anaphase" }, for: entry.itemID)
        default:
            let subject = app.gradeSubject(for: item)
            switch step {
            case "r": setText(SessionQuestionHost.rightAnswer(to: item, subject: subject), for: entry.itemID)
            case "p": setText(item.keyIdeas.first.map { $0.terms.first ?? $0.label } ?? item.answer, for: entry.itemID)
            default: setText("It has something to do with the cell, I think.", for: entry.itemID)
            }
        }
    }

    /// The clock has just run out.
    func debugRunOutTheClock() {
        deadline = clock().addingTimeInterval(-1)
        checkTime()
    }

    func debugFlag(_ index: Int) {
        guard plan.entries.indices.contains(index) else { return }
        flagged.insert(plan.entries[index].itemID)
    }
    #endif
}
