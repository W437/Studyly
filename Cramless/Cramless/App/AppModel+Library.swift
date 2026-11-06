import Foundation
import SwiftData

// The Library, exam and editor mutations: courses, topics, exams, grades, sources and the questions a person writes
// or edits. Every mutation stamps with `touch` and ends in `save()`. Deletes are soft (`deletedAt`), so sync carries
// them; a course's deletion carries to everything in it, so nothing of it shows on Today, in sessions or in widgets.
//
// Nothing here calls AI: cards the person makes are free and unlimited.
extension AppModel {
    // MARK: - Courses

    /// A new course at the end of the list. Nil for a blank name.
    @discardableResult
    func createCourse(name: String, color: CourseColor, symbol: String) -> Course? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let order = (courses.map(\.sortOrder).max() ?? -1) + 1
        let course = Course(name: clean, color: color, symbol: symbol, sortOrder: order, now: now)
        context.insert(course)
        touch(course)
        save()
        return course
    }

    /// Renames and restyles a course. A blank name keeps the old one.
    func updateCourse(_ id: UUID, name: String, color: CourseColor, symbol: String) {
        guard let course = course(id), course.deletedAt == nil else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        if !clean.isEmpty, clean != course.name { course.name = clean; changed = true }
        if course.color != color { course.color = color; changed = true }
        if !symbol.isEmpty, course.symbol != symbol { course.symbol = symbol; changed = true }
        guard changed else { return }
        touch(course)
        save()
    }

    /// Soft-deletes a course and everything in it: exams, topics, questions, sources (their page images and
    /// recordings are removed from this iPhone) and confusions.
    func deleteCourse(_ id: UUID) {
        guard let course = course(id), course.deletedAt == nil else { return }
        let stamp = now
        for exam in course.exams where exam.deletedAt == nil { exam.deletedAt = stamp; touch(exam) }
        for topic in course.topics where topic.deletedAt == nil { topic.deletedAt = stamp; touch(topic) }
        for item in course.items where item.deletedAt == nil { item.deletedAt = stamp; touch(item) }
        for confusion in course.confusions where confusion.deletedAt == nil { confusion.deletedAt = stamp; touch(confusion) }
        for source in course.sources where source.deletedAt == nil {
            source.deletedAt = stamp
            touch(source)
            FileStore.removeFolder(PageImageStore.sourceFolder(source.id))
        }
        course.deletedAt = stamp
        touch(course)
        save()
    }

    // MARK: - Topics

    /// Adds a topic to a course (or returns the course's topic with that name, ignoring case). Nil for a blank name.
    @discardableResult
    func addTopic(named name: String, to courseID: UUID) -> Topic? {
        guard let course = course(courseID), course.deletedAt == nil else { return nil }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let existing = course.liveTopics.first(where: { $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
            return existing
        }
        let order = (course.topics.map(\.sortOrder).max() ?? -1) + 1
        let topic = Topic(course: course, name: clean, sortOrder: order, now: now)
        context.insert(topic)
        course.topics.append(topic)
        touch(topic)
        save()
        return topic
    }

    func renameTopic(_ id: UUID, to name: String) {
        guard let topic = topicModel(id), topic.deletedAt == nil else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != topic.name else { return }
        topic.name = clean
        touch(topic)
        save()
    }

    /// Soft-deletes a topic. Its questions stay (without a topic) and exams stop listing it in their scope; an exam
    /// whose whole scope was this topic covers the whole course again.
    func deleteTopic(_ id: UUID) {
        guard let topic = topicModel(id), topic.deletedAt == nil else { return }
        topic.deletedAt = now
        touch(topic)
        if let course = topic.course {
            for item in course.items where item.topicID == id {
                item.topicID = nil
                touch(item)
            }
            for exam in course.exams where exam.deletedAt == nil && exam.scope.contains(id) {
                exam.scope = exam.scope.filter { $0 != id }
                touch(exam)
            }
        }
        save()
    }

    // MARK: - Exams

    /// A new exam from the editor. Nil when the draft has no live course.
    @discardableResult
    func createExam(_ draft: ExamDraft) -> Exam? {
        var target = course(draft.courseID)
        // No course picked and a name typed (the editor asks when there are no courses): the course is made with the exam.
        if target == nil, !draft.newCourseName.clTrimmed.isEmpty {
            target = createCourse(name: draft.newCourseName, color: .sky, symbol: CourseGuess.symbol(for: draft.newCourseName))
        }
        guard let course = target, course.deletedAt == nil else { return nil }
        let liveTopics = Set(course.liveTopics.map(\.id))
        let exam = Exam(course: course, title: draft.resolvedTitle(courseName: course.name), date: draft.date,
                        scope: draft.scopeIDs.filter(liveTopics.contains), format: draft.cleanFormat,
                        targetReadiness: draft.clampedTarget, now: now)
        context.insert(exam)
        course.exams.append(exam)
        touch(exam)
        save()
        return exam
    }

    /// Writes the editor's draft into an exam. Moving the date into the future forgets the readiness kept for the
    /// old date; moving the exam to another course keeps only scope topics of that course.
    func updateExam(_ id: UUID, with draft: ExamDraft) {
        guard let exam = exam(id), exam.deletedAt == nil else { return }
        let target = course(draft.courseID).flatMap { $0.deletedAt == nil ? $0 : nil } ?? exam.course
        if let target, target.id != exam.course?.id {
            exam.course = target
        }
        let liveTopics = Set(exam.course?.liveTopics.map(\.id) ?? [])
        exam.title = draft.resolvedTitle(courseName: exam.course?.name ?? "")
        if exam.date != draft.date {
            exam.date = draft.date
            if draft.date > now {
                exam.readinessAtExam = nil
                exam.coverageAtExam = nil
            }
        }
        exam.scope = draft.scopeIDs.filter(liveTopics.contains)
        exam.format = draft.cleanFormat
        exam.targetReadiness = draft.clampedTarget
        touch(exam)
        save()
    }

    func deleteExam(_ id: UUID) {
        guard let exam = exam(id), exam.deletedAt == nil else { return }
        exam.deletedAt = now
        touch(exam)
        save()
    }

    /// Logs the grade the person got (0…1). Readiness on exam morning is kept first if it wasn't yet, so the
    /// grade can calibrate later projections.
    func logGrade(examID: UUID, score: Double) {
        guard let exam = exam(examID), exam.deletedAt == nil else { return }
        if exam.readinessAtExam == nil, exam.date <= now { applyDailyRollover() }
        exam.resultScore = min(1, max(0, score))
        exam.resultLoggedAt = now
        touch(exam)
        save()
    }

    /// The grade Capling projected for an exam, 0…1: from readiness on exam morning once the exam has started (with the coverage kept
    /// with it, so it is the grade the exam-morning card showed), else from the plan's projection. Uses only other exams' grades, so
    /// logging this one doesn't move it.
    func projectedGrade(for exam: Exam) -> ProjectedGrade {
        let snapshot = ExamSnapshot(exam)
        if let atExam = snapshot.readinessAtExam {
            return gradeModel(for: snapshot).grade(atExam, coverage: snapshot.coverageAtExam)
        }
        return readiness(for: exam).projectedGrade
    }

    /// Exams with both readiness on exam morning and a logged grade: two or more calibrate projections.
    var calibratingExamCount: Int {
        fetch(FetchDescriptor<Exam>(predicate: #Predicate {
            $0.deletedAt == nil && $0.resultScore != nil && $0.readinessAtExam != nil
        })).count
    }

    // MARK: - Questions

    /// A question the person wrote. Free and unlimited: no AI involved. Nil when the draft isn't ready or the
    /// course is gone.
    @discardableResult
    func createItem(in courseID: UUID, from draft: ItemDraft) -> StudyItem? {
        guard draft.problem == nil, let course = course(courseID), course.deletedAt == nil else { return nil }
        let n = draft.normalized
        let topicID = draft.topicID.flatMap { id in course.liveTopics.contains { $0.id == id } ? id : nil }
        let item = StudyItem(course: course, topicID: topicID, kind: draft.kind,
                             status: draft.suspended ? .suspended : .active, origin: .person, prompt: n.prompt,
                             answer: n.answer, explanation: n.explanation, keyIdeas: n.keyIdeas, choices: n.choices,
                             cloze: n.cloze, difficultyHint: 0.5, now: now)
        context.insert(item)
        course.items.append(item)
        touch(item)
        save()
        return item
    }

    /// Writes the editor's draft into a question. Its memory (FSRS) is kept; a diagram keeps its labels and page.
    func updateItem(_ id: UUID, from draft: ItemDraft) {
        guard draft.problem == nil, let item = item(id), item.deletedAt == nil else { return }
        let n = draft.normalized
        if item.kind != .diagram, draft.kind != .diagram { item.kind = draft.kind }
        item.prompt = n.prompt
        item.explanation = n.explanation
        if item.kind != .diagram {
            item.answer = n.answer
            item.keyIdeas = item.kind.isOwnWords ? n.keyIdeas : []
            item.choices = item.kind == .mcq ? n.choices : []
            item.cloze = item.kind == .cloze ? n.cloze : nil
        }
        let liveTopics = Set(item.course?.liveTopics.map(\.id) ?? [])
        item.topicID = draft.topicID.flatMap { liveTopics.contains($0) ? $0 : nil }
        if item.status == .active || item.status == .suspended {
            item.status = draft.suspended ? .suspended : .active
        }
        touch(item)
        save()
    }

    /// Soft-deletes questions.
    func deleteItems(_ ids: [UUID]) {
        var changed = false
        for id in ids {
            guard let item = item(id), item.deletedAt == nil else { continue }
            item.deletedAt = now
            touch(item)
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Sources

    /// Soft-deletes a source and removes its files from this iPhone. Its questions go too, unless
    /// `keepQuestions`, which keeps them without their link to the source.
    func deleteSource(_ id: UUID, keepQuestions: Bool) {
        guard let source = source(id), source.deletedAt == nil else { return }
        let stamp = now
        for item in questions(from: source) {
            if keepQuestions {
                item.sourceRef = nil
                if item.kind == .diagram { item.deletedAt = stamp }
            } else {
                item.deletedAt = stamp
            }
            touch(item)
        }
        source.deletedAt = stamp
        touch(source)
        FileStore.removeFolder(PageImageStore.sourceFolder(source.id))
        save()
    }

    // MARK: - Reads

    /// The live questions made from a source (any status but rejected), or from one of its pages.
    func questions(from source: Source, pageIndex: Int? = nil) -> [StudyItem] {
        guard let course = source.course else { return [] }
        let id = source.id
        return course.items.filter { item in
            guard item.deletedAt == nil, item.status != .rejected, let ref = item.sourceRef, ref.sourceID == id else { return false }
            guard let pageIndex else { return true }
            return ref.pageIndex == pageIndex || item.diagram?.pageIndex == pageIndex
        }
        .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.prompt < $1.prompt }
    }

    /// Everything the Library's search reads, as plain values (built once per change of the store).
    func librarySearchEntries() -> [LibrarySearch.Entry] {
        var entries: [LibrarySearch.Entry] = []
        for course in courses {
            let topicNames = Dictionary(uniqueKeysWithValues: course.liveTopics.map { ($0.id, $0.name) })
            for item in course.items where item.deletedAt == nil && (item.status == .active || item.status == .suspended) {
                var extra = item.choices.map(\.text)
                if let cloze = item.cloze { extra.append(cloze.text) }
                entries.append(LibrarySearch.Entry(
                    kind: .question, id: item.id, courseID: course.id, courseName: course.name, color: course.color,
                    title: item.cloze?.text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "") ?? item.prompt,
                    detail: item.topicID.flatMap { topicNames[$0] } ?? item.kind.displayName,
                    body: ([item.prompt, item.answer, item.explanation] + extra).joined(separator: "\n"),
                    systemImage: item.kind.libraryIcon, date: item.createdAt))
            }
            for source in course.liveSources {
                let isLecture = source.kind == .lecture
                let body: String
                if isLecture {
                    var parts = source.segments.map(\.text)
                    if let notes = source.notes { parts.append(notes.summary); parts += notes.sections.flatMap(\.bullets) }
                    body = parts.joined(separator: "\n")
                } else {
                    body = source.sortedPages.map(\.text).joined(separator: "\n")
                }
                entries.append(LibrarySearch.Entry(
                    kind: isLecture ? .lecture : .source, id: source.id, courseID: course.id, courseName: course.name,
                    color: course.color, title: source.title, detail: LibraryFormat.sourceKindName(source.kind),
                    body: body, systemImage: source.kind.systemImage, date: source.createdAt))
            }
        }
        return entries
    }

    private func topicModel(_ id: UUID) -> Topic? {
        fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.id == id })).first
    }
}

#if DEBUG
// MARK: - Harness scenarios

@MainActor
private var appliedHarnessScenarios: Set<String> = []

extension AppModel {
    /// Applies `CRAMLESS_SCENARIO` once per launch (harness only). Called by the exam and progress screens.
    func applyHarnessScenarioOnce(examID: UUID?) {
        guard config.isHarness, let scenario = TestHarness.value("CRAMLESS_SCENARIO"),
              appliedHarnessScenarios.insert(scenario).inserted else { return }
        applyHarnessScenario(scenario, examID: examID)
    }

    /// States of the exam and progress screens the demo world doesn't start in, for screenshots
    /// (`CRAMLESS_SCENARIO=<name>`, applied by `ExamDetailView` and `ProgressTabView` when they appear):
    /// - `eve`: the exam on screen is tomorrow (the exam-eve session is offered);
    /// - `past`: it was three days ago and no grade is logged (readiness on exam morning kept);
    /// - `graded`: the same, with a grade logged;
    /// - `missed`: yesterday wasn't studied (a held freeze covers it; the exam plan absorbs its reviews);
    /// - `repair`: yesterday wasn't studied and no freeze was held (a day earlier broke the run), so the streak
    ///   offers a repair;
    /// - `thin`: the exam's course has a long reading (about 5,800 words) with 16 well-remembered questions on its first stretch,
    ///   so its questions cover about a sixth of that reading and the exam says so.
    func applyHarnessScenario(_ scenario: String, examID: UUID?) {
        let exam = exam(examID)
        func clear(daysAgo: Int) {
            guard let record = dayRecord(key: calendar.dayKey(for: calendar.adding(days: -daysAgo, to: now))) else { return }
            record.sessions = 0
            record.studySeconds = 0
            record.itemsReviewed = 0
            record.frozen = false
            record.syncedAt = nil
        }
        switch scenario {
        case "eve":
            guard let exam else { return }
            exam.date = calendar.adding(days: 1, to: calendar.startOfDay(for: now)).addingTimeInterval(9 * 3600)
            touch(exam)
        case "past", "graded":
            guard let exam else { return }
            exam.date = calendar.adding(days: -3, to: calendar.startOfDay(for: now)).addingTimeInterval(9 * 3600)
            exam.readinessAtExam = nil
            exam.coverageAtExam = nil
            touch(exam)
            save()
            applyDailyRollover()
            if scenario == "graded" {
                exam.resultScore = min(1, (exam.readinessAtExam ?? 0.8) + 0.06)
                exam.resultLoggedAt = now
                touch(exam)
            }
        case "missed":
            clear(daysAgo: 1)
        case "repair":
            clear(daysAgo: 1)
            clear(daysAgo: 8)
        case "thin":
            guard let course = exam?.course else { return }
            addThinReading(to: course)
        default:
            return
        }
        save()
    }

    /// A long reading with sixteen well-remembered questions, two to a passage, on its first eight passages (`thin`).
    private func addThinReading(to course: Course) {
        let subjects = ["The plaintiff", "The guard", "The railroad", "A passenger", "The court", "The package", "The scales", "The jury"]
        let verbs = ["carried", "pushed", "considered", "dropped", "observed", "owed", "held", "answered"]
        let objects = ["a small package wrapped in newspaper", "a duty of reasonable care to everyone nearby",
                       "the risk that a stranger could be hurt far away", "the explosion on the crowded platform",
                       "the question of negligence the jury had decided", "a wrong to the person standing at the scales"]
        var text = ""
        var n = 0
        while text.split(whereSeparator: \.isWhitespace).count < 5800 {
            text += "\(subjects[n % subjects.count]) \(verbs[(n / 3) % verbs.count]) \(objects[(n / 2) % objects.count]) "
                + "before the train left the station in event \(n)." + (n % 7 == 6 ? "\n\n" : " ")
            n += 1
        }
        let source = Source(course: course, kind: .text, title: "Palsgraf v. Long Island Railroad", status: .ready, now: now)
        context.insert(source)
        course.sources.append(source)
        for page in TextPaginator.pages(from: text) {
            let model = SourcePage(source: source, pageIndex: page.pageIndex, label: page.label,
                                   text: page.lines.map(\.text).joined(separator: "\n"), lines: page.lines)
            context.insert(model)
            source.pages.append(model)
        }
        let studied = MemoryState(state: .review, stability: 60, difficulty: 4, due: calendar.adding(days: 50, to: now),
                                  lastReview: calendar.adding(days: -1, to: now), reps: 5)
        for section in Coverage.sections(of: coverageReading(of: source)).prefix(8) {
            for id in section.anchorIDs.prefix(2) {
                let ref = SourceRef(sourceID: source.id, pageIndex: 0, anchorIDs: [id], label: "p. 1")
                let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person,
                                     prompt: "What did the court say? (\(id))", answer: "It weighed the duty of care.", sourceRef: ref, now: now)
                item.memory = studied
                context.insert(item)
                course.items.append(item)
            }
        }
    }
}
#endif
