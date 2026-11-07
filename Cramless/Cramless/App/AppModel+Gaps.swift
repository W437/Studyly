import Foundation

// An exam's topics with no notes: what the exam page and Cap's card say, read from the engines. Filling one is a capture aimed at the topic, or web research saved as a
// note; both go through the usual review, so nothing is added until the student says so.
extension AppModel {
    /// This exam's gaps, for its page: at any distance, while there's time to fill them. `topics`: its topics' readiness, when the caller has read them.
    func examGap(for exam: Exam, topics: [TopicReadiness]? = nil) -> ExamGap? {
        gap(of: ExamSnapshot(exam), course: exam.course, items: topics == nil ? itemSnapshots(in: exam.course) : [], within: nil, topics: topics)
    }

    /// The gaps of the exams in Cap's window, for his card.
    func noticeGaps(items: [ItemSnapshot]) -> [ExamGap] {
        upcomingExams().compactMap { exam in
            gap(of: ExamSnapshot(exam), course: exam.course, items: items, within: ExamGaps.noticeDays)
        }
    }

    private func gap(of exam: ExamSnapshot, course: Course?, items: [ItemSnapshot], within: ClosedRange<Int>?, topics known: [TopicReadiness]? = nil) -> ExamGap? {
        guard let course, course.deletedAt == nil else { return nil }
        let days = calendar.dayDistance(from: now, to: exam.date)
        guard within?.contains(days) ?? (days >= ExamGaps.noticeDays.lowerBound) else { return nil }
        let topics = known ?? ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).topicReadiness(for: exam, items: items, topics: topicSnapshots(in: course))
        guard topics.contains(where: { $0.value == nil }) else { return nil }
        let drafts = Set(course.items.filter { $0.deletedAt == nil && $0.status == .draft }.compactMap(\.topicID))
        return ExamGaps.find(exam: exam, topicReadiness: topics, draftTopicIDs: drafts, covered: coveredTopics(in: course), daysLeft: days, within: within)
    }

    /// What a course already holds, for a syllabus to be read against and for telling a true gap from a topic its questions already cover.
    func syllabusLibrary(courseID: UUID?, withNotes: Bool = true) -> SyllabusLibrary {
        guard let course = course(courseID), course.deletedAt == nil else { return .empty }
        let names = Dictionary(course.liveTopics.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let questions = course.items.filter { $0.deletedAt == nil && $0.status == .active }.map { item in
            let words = [item.topicID.flatMap { names[$0] } ?? "", item.prompt, item.answer] + item.keyIdeas.map(\.label)
            return SyllabusLibrary.Question(topicID: item.topicID, text: words.joined(separator: " "))
        }
        return SyllabusLibrary(questions: questions, topics: course.liveTopics.map { .init(id: $0.id, name: $0.name) }, noteLines: withNotes ? noteLines(of: course) : [])
    }

    /// The course's notes, a line each: pages as stored, and what lectures said.
    private func noteLines(of course: Course) -> [String] {
        course.liveSources.flatMap { source -> [String] in
            source.kind == .lecture ? source.segments.map(\.text) : source.sortedPages.flatMap { $0.text.components(separatedBy: .newlines) }
        }.filter { !$0.isEmpty }
    }

    /// The course's empty topics whose words its questions or notes already speak of: a syllabus named them, and what's there is filed under other names. They aren't gaps.
    /// Read once per shape of the course (answering a question doesn't change it), and only when it has an empty topic: the questions at once, the notes off the main thread (a
    /// long PDF takes a noticeable moment), and the screens hear of it if that changes anything.
    func coveredTopics(in course: Course) -> Set<UUID> {
        let live = course.items.filter { $0.deletedAt == nil && $0.status == .active }
        let filled = Set(live.compactMap(\.topicID))
        let empty = course.liveTopics.filter { !filled.contains($0.id) }
        guard !empty.isEmpty, !live.isEmpty || !course.liveSources.isEmpty else { return [] }
        let key = CoveredTopicsCache.Key(questions: live.count, sources: course.liveSources.count, empty: Set(empty.map(\.id)))
        if let cached = coveredCache.values[course.id], cached.key == key { return cached.covered }
        let library = syllabusLibrary(courseID: course.id, withNotes: false)
        let names = empty.map { (id: $0.id, name: $0.name) }
        let covered = CoveredTopicsCache.covered(names, by: SyllabusMatcher(library))
        coveredCache.values[course.id] = (key, covered)
        let lines = noteLines(of: course)
        guard !lines.isEmpty else { return covered }
        let courseID = course.id
        Task.detached(priority: .utility) { [weak self] in
            var full = library
            full.noteLines = lines
            let read = CoveredTopicsCache.covered(names, by: SyllabusMatcher(full))
            guard read != covered else { return }
            await MainActor.run {
                guard let self, self.coveredCache.values[courseID]?.key == key else { return }
                self.coveredCache.values[courseID] = (key, read)
                self.save()
            }
        }
        return covered
    }

    /// Each topic with drafts waiting, and the set they came from.
    func draftSources(in course: Course) -> [UUID: UUID] {
        var sources: [UUID: UUID] = [:]
        for item in course.items where item.deletedAt == nil && item.status == .draft {
            if let topic = item.topicID, let source = item.sourceRef?.sourceID, sources[topic] == nil { sources[topic] = source }
        }
        return sources
    }

    /// The set of drafts waiting for review on these topics.
    func draftSource(forTopics topicIDs: [UUID], in courseID: UUID) -> UUID? {
        guard let course = course(courseID) else { return nil }
        let wanted = Set(topicIDs)
        return course.items.first { $0.deletedAt == nil && $0.status == .draft && $0.topicID.map(wanted.contains) == true }?.sourceRef?.sourceID
    }

    /// What to say beside "Added 15 questions to Bio 101" when they hold an exam's readiness down: the same words as its page and Today's card. Nil when no exam moved
    /// by a point, or with nothing added. Read after the questions are in.
    func newQuestionsNote(added: Int, in course: Course?) -> String? {
        guard added > 0, let course else { return nil }
        let engine = ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now)
        let items = itemSnapshots(in: course)
        for exam in upcomingExams() where exam.course?.id == course.id {
            if engine.newQuestionsShown(of: ExamSnapshot(exam), in: items) > 0 {
                return ExamPresentation.newQuestionsLine(added, inPlan: plan(for: exam).days.contains { $0.newItems > 0 })
            }
        }
        return nil
    }

    /// "Later" on the exam page's card: the same as on Cap's.
    func gapIsPutOff(_ examID: UUID) -> Bool { noticeLedger.snoozed.contains(NoticeEngine.gapID(examID)) }

    /// A research summary saved for a gap, then the usual flow: questions written from it, on that topic, into the usual review. Nil when nothing could be saved.
    func saveResearch(_ result: ResearchResult, forGap topicID: UUID, courseID: UUID) -> CaptureRequest? {
        guard let course = course(courseID), let source = saveResearchNote(result, course: course) else { return nil }
        touch(course)
        save()
        guard let coverage = coverage(of: source), let plan = restPlan(for: coverage) else { return nil }
        return .rest(plan, in: courseID, topicID: topicID)
    }
}

/// Each course's covered topics (`AppModel.coveredTopics(in:)`), for the shape of the course they were read from.
final class CoveredTopicsCache {
    struct Key: Equatable, Sendable {
        var questions: Int
        var sources: Int
        var empty: Set<UUID>
    }

    var values: [UUID: (key: Key, covered: Set<UUID>)] = [:]

    nonisolated static func covered(_ topics: [(id: UUID, name: String)], by matcher: SyllabusMatcher) -> Set<UUID> {
        Set(topics.filter { let found = matcher.match($0.name); return found.questions > 0 || found.inNotes }.map(\.id))
    }
}
