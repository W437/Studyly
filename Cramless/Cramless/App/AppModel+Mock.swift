import Foundation
import SwiftData

// Mock exams: what one can ask, whether to offer one, and the last result. A mock is a `StudySession` of kind `.mock` for its exam plus the
// `ReviewLog`s written at hand-in, so nothing here needs a table of its own: the score is read back from the log. The screen is
// `MockExamView`, its state `MockRunner`.
extension AppModel {

    /// A mock already taken.
    struct LastMock: Equatable {
        var sessionID: UUID
        var score: Double
        var date: Date
    }

    /// The questions a mock of this exam may ask, as the engine sees them: active, in its scope, of its format's kinds, not reported by the
    /// student, and either checked against their source or the student's own (written or imported).
    func mockEligibleItems(for exam: Exam) -> [ItemSnapshot] {
        guard let course = exam.course, course.deletedAt == nil else { return [] }
        let snapshot = ExamSnapshot(exam)
        let own: Set<ItemOrigin> = [.person, .quizlet, .anki, .csv, .sample]
        let items = course.items.filter { item in
            item.deletedAt == nil && item.status == .active && !item.reported && (item.checkedAt != nil || own.contains(item.origin))
        }
        return MockExamBuilder.eligible(items.map { ItemSnapshot($0, courseID: course.id) }, exam: snapshot)
    }

    /// The mock for this exam now. `seed`: a new one each day and each sitting, unless a caller pins it.
    func mockPlan(for exam: Exam, seed: UInt64? = nil, size: Int? = nil) -> MockPlan? {
        // How many options each multiple-choice question has: what a blind guess is worth in "Cap predicted".
        var choices: [UUID: Int] = [:]
        for item in exam.course?.items ?? [] where item.kind == .mcq { choices[item.id] = item.choices.count }
        return mockBuilder().build(exam: ExamSnapshot(exam), items: mockEligibleItems(for: exam), choices: choices,
                                   seed: seed ?? mockSeed(for: exam), size: size)
    }

    private func mockBuilder() -> MockExamBuilder { MockExamBuilder(fsrs: fsrs, calendar: calendar, now: now) }

    private func mockSeed(for exam: Exam) -> UInt64 {
        let sittings = mockSessions(of: exam.id).count
        return StableRandom.seed(exam.id, day: calendar.dayNumber(for: now), salt: UInt64(sittings) &* 0x9E37)
    }

    func mockOffer(for exam: Exam) -> MockOffer {
        guard case .ahead = ExamPresentation.phase(examDate: exam.date, now: now, calendar: calendar) else { return .hidden }
        // With no guesses worked out, since the page reads only its size, mix and time. The sitting's own seed, so a card's minutes are the sitting's.
        let items = mockEligibleItems(for: exam)
        if let plan = mockBuilder().build(exam: ExamSnapshot(exam), items: items, seed: mockSeed(for: exam)) { return .ready(plan) }
        return .tooFew(have: items.count)
    }

    /// Finished mocks of an exam with at least one answer, the newest first.
    private func mockSessions(of examID: UUID) -> [StudySession] {
        let mock = SessionKind.mock.rawValue
        let exam: UUID? = examID
        return fetch(FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.kindRaw == mock && $0.examID == exam && $0.endedAt != nil && $0.itemCount > 0
        }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }

    /// The newest mock of an exam, scored from its log.
    func lastMock(for examID: UUID) -> LastMock? {
        guard let session = mockSessions(of: examID).first else { return nil }
        let id: UUID? = session.id
        let scores = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.sessionID == id })).map(\.score).filter { $0 >= 0 }
        guard !scores.isEmpty else { return nil }
        return LastMock(sessionID: session.id, score: MockScorer.mean(scores), date: session.startedAt)
    }

    /// Today's card asks this: the exam is 2 to 7 days out, there are enough questions and no mock in the last few days.
    func mockIsDue(for exam: Exam) -> Bool {
        let items = mockEligibleItems(for: exam)
        return MockSuggestion.isDue(daysLeft: calendar.dayDistance(from: now, to: exam.date), eligible: items.count, studied: items.filter(\.isStudied).count,
                                    minimum: MockExamBuilder.minimum(for: exam.format), lastMockAt: lastMock(for: exam.id)?.date, now: now, calendar: calendar)
    }

    // MARK: Recording

    /// One graded answer of a mock, as a review given when the person gave it. Returns nil when the item has gone.
    @discardableResult
    func recordMockAnswer(itemID: UUID, score: Double, answer: String?, gradedBy: String, seconds: Double, sessionID: UUID?,
                          at answeredAt: Date?, rating fixed: Rating? = nil) -> ReviewOutcome? {
        guard let item = item(itemID), item.deletedAt == nil else { return nil }
        let durationMs = Int(seconds * 1000)
        let rating = fixed ?? AppModel.rating(forScore: score, kind: item.kind, durationMs: durationMs)
        return recordReview(itemID: itemID, rating: rating, score: score, answer: answer, gradedBy: gradedBy, durationMs: durationMs,
                            sessionID: sessionID, at: answeredAt)
    }
}
