import Foundation
import SwiftData

// Ask Cap's assistant, the app's half. The relay lets the model choose a tool; everything that touches the student's study
// happens here, in AppModel, as everywhere else:
//
//  - `studyIndex` shows the model the student's courses, topics and exams with short ids (c1, t3, e1), because models
//    mangle uuids but copy short ids; the index maps them back.
//  - `runDraftTool` turns a draft tool's arguments into a step. It adds nothing by itself: a step is *proposed* and waits for
//    the student, unless they switched "Let Cap do it" on for that kind (never for an account under 18).
//  - `applyAssistantStep` adds a step's drafts through the same pipeline as every generator (`ItemFactory`,
//    `createSource`, `createExam`), `undoAssistantStep` takes them back (a soft delete), and the step records what it made.
//
// Every claim of the model is checked here: a quote counts as evidence only if it is in the student's material, a choice
// question needs a right option, a date must be a real day that hasn't passed. See `AssistantDrafts`.

// MARK: - The index

/// The student's study as the model sees it, and how to get back from its short ids.
struct StudyIndex: Sendable {
    var state: StudyState
    private var courses: [String: UUID]
    private var topics: [String: UUID]
    private var exams: [String: UUID]

    init(state: StudyState = StudyState(today: "", currentCourseId: nil, courses: [], exams: []),
         courses: [String: UUID] = [:], topics: [String: UUID] = [:], exams: [String: UUID] = [:]) {
        self.state = state
        self.courses = courses
        self.topics = topics
        self.exams = exams
    }

    func course(_ short: String?) -> UUID? { short.flatMap { courses[$0] } }
    func topic(_ short: String?) -> UUID? { short.flatMap { topics[$0] } }
    func exam(_ short: String?) -> UUID? { short.flatMap { exams[$0] } }

    /// "c1 “Bio 101”, c2 “Chem 110”": what to tell the model when it used an id that doesn't exist.
    var courseList: String {
        state.courses.map { "\($0.id) “\($0.name)”" }.joined(separator: ", ")
    }
}

/// The state of one assistant reply: what the model was shown, the passages it may cite (the first few the app found, then
/// those its lookups added), and the student's study with its short ids. Lives for the length of the reply.
@MainActor
final class AssistantSession {
    let index: StudyIndex
    let retriever: LocalRetriever
    let currentCourseID: UUID?
    private(set) var sent: [String: LocalRetriever.Passage] = [:]
    /// The most passages a request carries. The relay takes `TutorSelection.assistant.maxPassages`; a relay from before that
    /// took 24, and once it has said so (`restart`) the reply stays within it in every round, whatever the lookups add.
    private(set) var limit = AssistantSession.maxSources

    init(index: StudyIndex, retriever: LocalRetriever, currentCourseID: UUID?) {
        self.index = index
        self.retriever = retriever
        self.currentCourseID = currentCourseID
    }

    /// Gives passages the ids "s1", "s2", … the model cites them by. A passage the model already has keeps its id, also when it
    /// went inside a longer one (neighbouring passages are joined when a material has more than a request holds).
    @discardableResult
    func send(_ passages: [LocalRetriever.Passage]) -> [(id: String, passage: LocalRetriever.Passage)] {
        passages.map { passage in
            if let known = sent.first(where: { $0.value.key == passage.key || $0.value.members.contains(passage.key) }) {
                return (known.key, known.value)
            }
            let id = "s\(sent.count + 1)"
            sent[id] = passage
            return (id, passage)
        }
    }

    /// Starts again from these passages (their ids "s1", "s2", … from the top), for at most `limit` in a request from here on: a
    /// reply that has shown nothing yet, asked again of a relay that takes fewer.
    func restart(with passages: [LocalRetriever.Passage], limit: Int) {
        sent = [:]
        self.limit = limit
        send(passages)
    }

    /// The passages to send with a request, in the order of their ids: the ones the app found first, and the newest of those a
    /// lookup added, never more than the relay takes (`limit`). The ids and their order stay as they were from one round to the
    /// next, so the start of the request is the same and the provider's prompt cache can pay for it once.
    var sources: [TutorSource] {
        let ordered = sent.sorted { (Int($0.key.dropFirst()) ?? 0) < (Int($1.key.dropFirst()) ?? 0) }
        let head = min(6, limit)
        var kept = ordered.count > limit ? Array(ordered.prefix(head)) + Array(ordered.suffix(limit - head)) : ordered
        // And never more text than the relay takes in all (a language written without spaces has long passages): the oldest
        // lookups go first.
        var total = kept.reduce(0) { $0 + $1.value.text.utf16.count }
        while total > AssistantSession.maxCharacters, kept.count > head + 1 {
            total -= kept[head].value.text.utf16.count
            kept.remove(at: head)
        }
        return kept.map { id, p in TutorSource(id: id, title: p.title, label: p.label, text: p.text) }
    }

    static let maxSources = TutorSelection.assistant.maxPassages
    /// The relay takes 200,000 characters of passages in a request; this leaves room for the clipping of a long one.
    static let maxCharacters = 195_000
}

// MARK: - What the model is told

extension AppSettings {
    /// What Cap may add without asking: nothing for an account under 18.
    var assistantAuto: Set<AssistantAutoKind> { isMinor ? [] : assistant.auto }

    /// Web research is on for this account (still a Pro feature, and never under 18).
    var assistantWeb: Bool { !isMinor && assistant.webResearch }
}

extension AppModel {

    /// A research summary as a note in the course, with the pages it rests on: Ask Cap's "Save as note" and "Fill the gap". Nil when there's no text.
    func saveResearchNote(_ result: ResearchResult, course: Course) -> Source? {
        guard !result.text.clTrimmed.isEmpty else { return nil }
        let sources = (result.cited.isEmpty ? result.sources : result.cited).prefix(6)
        let footer = sources.isEmpty ? "" : "\n\nSources\n" + sources.map { "• \($0.title ?? $0.domain): \($0.url)" }.joined(separator: "\n")
        let body = CapMarkdown.plain(result.text) + footer
        return try? createSource(fromText: body, title: "From the web: \(result.topic)", course: course)
    }

    /// The tools the model may use for this student.
    var assistantTools: [AssistantToolName] {
        AssistantToolName.allCases.filter { $0 != .researchWeb || settings.assistantWeb }
    }

    /// "2026-10-22" in the student's calendar.
    func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The student's courses, topics and exams for the model, with short ids. Capped so the prompt stays small: 12 courses,
    /// 30 topics each, the next 8 exams.
    func studyIndex(currentCourseID: UUID?) -> StudyIndex {
        var courseIDs: [String: UUID] = [:]
        var topicIDs: [String: UUID] = [:]
        var examIDs: [String: UUID] = [:]
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        var topicNumber = 0
        var courseStates: [StudyCourseState] = []
        for (n, course) in courses.prefix(12).enumerated() {
            let short = "c\(n + 1)"
            courseIDs[short] = course.id
            let mastery = Dictionary(topicMastery(course: course).map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
            var topicStates: [StudyTopicState] = []
            for topic in course.liveTopics.prefix(30) {
                topicNumber += 1
                let id = "t\(topicNumber)"
                topicIDs[id] = topic.id
                let fading = (mastery[topic.id] ?? nil).map { $0 < 0.6 } ?? false
                topicStates.append(StudyTopicState(id: id, name: topic.name, weak: fading ? true : nil))
            }
            let due = course.activeItems.filter { ($0.due ?? .distantFuture) <= endOfToday }.count
            courseStates.append(StudyCourseState(id: short, name: course.name, sources: course.liveSources.count,
                                                 questions: course.activeItems.count, due: due, topics: topicStates))
        }
        var examStates: [StudyExamState] = []
        for (n, exam) in upcomingExams().prefix(8).enumerated() {
            guard let course = exam.course, let courseShort = courseIDs.first(where: { $0.value == course.id })?.key else { continue }
            let short = "e\(n + 1)"
            examIDs[short] = exam.id
            examStates.append(StudyExamState(id: short, courseId: courseShort, title: exam.title, date: dayString(exam.date),
                                             readiness: Int((readiness(for: exam).value * 100).rounded())))
        }
        let current = courseIDs.first { $0.value == currentCourseID }?.key
        let state = StudyState(today: dayString(now), currentCourseId: current, courses: courseStates, exams: examStates)
        return StudyIndex(state: state, courses: courseIDs, topics: topicIDs, exams: examIDs)
    }

    /// The request for the assistant: the chat with what each reply drafted written in, and the material of the chat's course.
    func assistantInput(for thread: ChatThread, lastQuestionAs: String? = nil) -> AssistantInput {
        var messages = thread.sortedMessages.map { TutorMessage(role: $0.role, text: $0.textForModel) }
        if let lastQuestionAs, let i = messages.lastIndex(where: { $0.role == .user }) { messages[i].text = lastQuestionAs }
        let course = liveCourse(thread.courseID)
        return AssistantInput(messages: messages, courseID: course?.id, courseName: course?.name,
                              material: tutorMaterial(courseID: course?.id))
    }
}

extension ChatMessage {
    /// What the model reads for this message: the words, and a line for each thing the reply drafted, so "make more like
    /// those" and "save that as a note" have something to refer to.
    var textForModel: String {
        let steps = self.steps.filter { $0.status != .working }
        guard role == .assistant, !steps.isEmpty else { return text }
        var lines: [String] = []
        for step in steps {
            switch step.payload {
            case .cards(let cards):
                lines.append("[Drafted \(step.title): " + cards.prefix(10).map(\.front).joined(separator: "; ") + "]")
            case .questions(let questions):
                lines.append("[Drafted \(step.title): " + questions.prefix(8).map(\.prompt).joined(separator: "; ") + "]")
            case .note(let note):
                lines.append("[Drafted the note “\(note.title)”: \(note.body.prefix(600))]")
            case .exam(let exam):
                lines.append("[Drafted the exam “\(exam.title)” on \(exam.date.formatted(date: .abbreviated, time: .omitted))]")
            case .research(let r) where !r.text.isEmpty:
                lines.append("[Researched “\(r.topic)” on the web. The summary the student saw: \(r.text.prefix(1200))]")
            default:
                break
            }
        }
        return ([text] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

// MARK: - Running a draft tool

extension AppModel {

    /// A call that couldn't be done. `message` is what the student reads on the card; `tell` is what the model reads (it may carry
    /// ids and instructions for it, and stays in English).
    private func failure(_ call: AssistantToolCall, course: String = "", _ message: String, tell: String? = nil) -> AssistantToolRun {
        AssistantToolRun(
            step: AssistantStep(id: call.callID, tool: call.name, status: .failed, courseName: course,
                                title: String(localized: "Couldn't do that"), detail: message, payload: .none),
            output: AnyJSON.result(["error": .string(tell ?? message)]).jsonString)
    }

    private func resolveCourse(_ call: AssistantToolCall, session: AssistantSession) -> Course? {
        guard let id = session.index.course(call.arguments["course_id"]?.string) else { return nil }
        return liveCourse(id)
    }

    private func unknownCourse(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        failure(call, String(localized: "Cap couldn't tell which course you meant."),
                tell: "That course id doesn't exist. The courses are: \(session.index.courseList).")
    }

    /// Runs a tool that drafts something, offers a button, or opens a screen. Lookups and web research are the router's.
    func runDraftTool(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        switch call.name {
        case .createFlashcards: return draftCards(call, session: session)
        case .createQuizQuestions: return draftQuestions(call, session: session)
        case .createNote: return draftNote(call, session: session)
        case .createExam: return draftExam(call, session: session)
        case .startPractice: return offerPractice(call, session: session)
        case .openScreen: return offerScreen(call, session: session)
        case .searchNotes, .researchWeb:
            return failure(call, String(localized: "Cap couldn't do that one."), tell: "That tool is run elsewhere.")
        }
    }

    private func countLine(_ n: Int, _ noun: String, on topic: String?) -> String {
        CLFormat.count(n, noun) + (topic.map { " on \($0)" } ?? "")
    }

    /// "5 flashcards on Mitosis"; when the course has every one of them already (they are shown, unticked), "Already in Bio 101".
    private func draftTitle(_ kept: Int, _ noun: String, topic: String?, course: Course) -> String {
        kept == 0 ? String(localized: "Already in \(course.name)") : countLine(kept, noun, on: topic)
    }

    private func draftCards(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        guard let course = resolveCourse(call, session: session) else { return unknownCourse(call, session: session) }
        let topic = call.arguments["topic"]?.string?.clTrimmed.clNonEmpty
        let existing = Set(course.liveItems.map { AssistantDrafts.key($0.prompt) })
        let made = AssistantDrafts.cards(from: call.arguments, check: evidenceChecker(session), existing: existing)
        guard !made.drafts.isEmpty else {
            return failure(call, course: course.name, String(localized: "Cap couldn't make usable cards from that. Try asking again."),
                           tell: "None of the cards could be used. Try again with clear fronts and backs.")
        }
        let step = AssistantStep(id: call.callID, tool: call.name, status: .proposed, courseID: course.id, courseName: course.name,
                                 topicName: topic, title: draftTitle(made.drafts.filter(\.kept).count, "flashcard", topic: topic, course: course),
                                 payload: .cards(made.drafts))
        let own = made.drafts.filter { !$0.basis.isFromNotes }.count
        let duplicates = made.drafts.filter(\.isDuplicate).count
        return settle(step, kind: .cards, extra: ["not_from_notes": .number(Double(own)), "already_in_course": .number(Double(duplicates))])
    }

    private func draftQuestions(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        guard let course = resolveCourse(call, session: session) else { return unknownCourse(call, session: session) }
        let topic = call.arguments["topic"]?.string?.clTrimmed.clNonEmpty
        let existing = Set(course.liveItems.map { AssistantDrafts.key($0.prompt) })
        let made = AssistantDrafts.questions(from: call.arguments, check: evidenceChecker(session), existing: existing)
        guard !made.drafts.isEmpty else {
            return failure(call, course: course.name, String(localized: "Cap couldn't make usable questions from that. Try asking again."),
                           tell: "None of the questions could be used. Check each multiple-choice question has its right option among the options.")
        }
        let step = AssistantStep(id: call.callID, tool: call.name, status: .proposed, courseID: course.id, courseName: course.name,
                                 topicName: topic, title: draftTitle(made.drafts.filter(\.kept).count, "question", topic: topic, course: course),
                                 payload: .questions(made.drafts))
        let own = made.drafts.filter { !$0.basis.isFromNotes }.count
        return settle(step, kind: .cards, extra: ["not_from_notes": .number(Double(own)), "dropped": .number(Double(made.dropped))])
    }

    private func draftNote(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        guard let course = resolveCourse(call, session: session) else { return unknownCourse(call, session: session) }
        guard let note = AssistantDrafts.note(from: call.arguments) else {
            return failure(call, course: course.name, String(localized: "The note came out empty. Try asking again."),
                           tell: "The note was empty. Write the note's text.")
        }
        let step = AssistantStep(id: call.callID, tool: call.name, status: .proposed, courseID: course.id, courseName: course.name,
                                 title: note.title, payload: .note(note))
        return settle(step, kind: .notes)
    }

    private func draftExam(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        guard let course = resolveCourse(call, session: session) else { return unknownCourse(call, session: session) }
        let when: (date: Date, hasTime: Bool)
        do {
            when = try AssistantDrafts.examDate(day: call.arguments["date"]?.string, time: call.arguments["time"]?.string,
                                                calendar: calendar, now: now)
        } catch let problem as AssistantDrafts.ExamProblem {
            return failure(call, course: course.name, problem.studentMessage, tell: problem.message)
        } catch {
            return failure(call, course: course.name, AssistantDrafts.ExamProblem.noDate.studentMessage,
                           tell: AssistantDrafts.ExamProblem.noDate.message)
        }
        let live = course.liveTopics
        var topicIDs: [UUID] = []
        for short in call.arguments["topic_ids"]?.array?.compactMap(\.string) ?? [] {
            if let id = session.index.topic(short), live.contains(where: { $0.id == id }), !topicIDs.contains(id) { topicIDs.append(id) }
        }
        let names = topicIDs.compactMap { id in live.first { $0.id == id }?.name }
        let title = (call.arguments["title"]?.string?.clTrimmed.clNonEmpty).map { String($0.prefix(80)) } ?? String(localized: "\(course.name) exam")
        let duplicate = course.liveExams.contains { calendar.isDate($0.date, inSameDayAs: when.date) }
        let plan = ExamPlanDraft(title: title, date: when.date, hasTime: when.hasTime, topicIDs: topicIDs, topicNames: names,
                                 isDuplicate: duplicate)
        let step = AssistantStep(id: call.callID, tool: call.name, status: .proposed, courseID: course.id, courseName: course.name,
                                 title: title, payload: .exam(plan))
        return settle(step, kind: .exams, extra: duplicate ? ["note": .string("The course already has an exam that day.")] : [:])
    }

    private func offerPractice(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        let course = session.index.course(call.arguments["course_id"]?.string).flatMap { liveCourse($0) }
        let topic = course.flatMap { c in session.index.topic(call.arguments["topic_id"]?.string).flatMap { id in c.liveTopics.first { $0.id == id } } }
        if let course, course.activeItems.isEmpty {
            return failure(call, course: course.name, String(localized: "There is nothing to practice in \(course.name) yet."),
                           tell: "There is nothing to practice in \(course.name) yet. Offer to make flashcards first.")
        }
        let minutes = min(30, max(5, call.arguments["minutes"]?.int ?? settings.dailyMinutes))
        let label = [CLFormat.count(minutes, "minute"), topic?.name ?? course?.name].compactMap { $0 }.joined(separator: " · ")
        let step = AssistantStep(id: call.callID, tool: call.name, status: .offered, courseID: course?.id, courseName: course?.name ?? "",
                                 topicName: topic?.name, title: label,
                                 payload: .practice(PracticeOffer(courseID: course?.id, topicID: topic?.id, minutes: minutes, label: label)))
        return AssistantToolRun(step: step, output: AnyJSON.result(["status": .string("offered")]).jsonString)
    }

    private func offerScreen(_ call: AssistantToolCall, session: AssistantSession) -> AssistantToolRun {
        guard let raw = call.arguments["screen"]?.string, let screen = OpenOffer.Screen(rawValue: raw) else {
            return failure(call, String(localized: "Cap couldn't open that screen."), tell: "Pick one of: today, library, progress, sky, course, exam.")
        }
        var id: UUID?
        var label: String
        switch screen {
        case .today: label = String(localized: "Open Today")
        case .library: label = String(localized: "Open Library")
        case .progress: label = String(localized: "Open Progress")
        case .sky: label = String(localized: "Open your memory sky")
        case .course:
            guard let course = session.index.course(call.arguments["id"]?.string).flatMap({ liveCourse($0) }) else {
                return failure(call, String(localized: "Cap couldn't tell which course to open."), tell: "Say which course: \(session.index.courseList).")
            }
            id = course.id
            label = String(localized: "Open \(course.name)")
        case .exam:
            guard let exam = session.index.exam(call.arguments["id"]?.string).flatMap({ self.exam($0) }), exam.deletedAt == nil else {
                return failure(call, String(localized: "Cap couldn't find that exam."), tell: "That exam id doesn't exist.")
            }
            id = exam.id
            label = String(localized: "Open \(exam.title)")
        }
        let step = AssistantStep(id: call.callID, tool: call.name, status: .offered, title: label,
                                 payload: .open(OpenOffer(screen: screen, id: id, label: label)))
        return AssistantToolRun(step: step, output: AnyJSON.result(["status": .string("offered")]).jsonString)
    }

    /// A drafted step is proposed, or, if the student switched on "Let Cap do it" for its kind, added at once.
    private func settle(_ step: AssistantStep, kind: AssistantAutoKind, extra: [String: AnyJSON] = [:]) -> AssistantToolRun {
        var step = step
        var out = extra
        let count = Self.count(of: step)
        out["count"] = .number(Double(count))
        if settings.assistantAuto.contains(kind) {
            step = applyAssistantStep(step, auto: true)
            if step.status == .applied {
                out["status"] = .string("added")
                return AssistantToolRun(step: step, output: AnyJSON.result(out).jsonString)
            }
            // Adding failed (the course vanished): the student still decides.
        }
        out["status"] = .string("proposed")
        return AssistantToolRun(step: step, output: AnyJSON.result(out).jsonString)
    }

    /// Items in a step's payload that would be added.
    static func count(of step: AssistantStep) -> Int {
        switch step.payload {
        case .cards(let c): c.filter(\.kept).count
        case .questions(let q): q.filter(\.kept).count
        default: 1
        }
    }

    // MARK: Evidence

    /// Checks a quote against the passages the model was shown (the one it named first), then against all the student's
    /// material. Found: the page or lecture moment, the lines it sits on. Not found: nil, and the item is Cap's own words.
    private func evidenceChecker(_ session: AssistantSession) -> AssistantDrafts.EvidenceChecker {
        { [weak self] sourceID, quote in
            guard let self else { return nil }
            // The passage the model named wins when it holds the quote; a passage sent joined from several is searched among those
            // it was made of, so the page, the moment in a lecture and the lines are the exact ones.
            guard let passage = TutorSelection.passage(named: sourceID.flatMap { session.sent[$0] }, sent: session.sent,
                                                       retriever: session.retriever,
                                                       holding: { AssistantDrafts.contains(quote, in: $0.text) }) else { return nil }
            let spaced = quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            var anchors = passage.anchorIDs
            if let source = self.source(passage.sourceID), source.deletedAt == nil {
                if let index = passage.pageIndex, let page = source.pages.first(where: { $0.pageIndex == index }) {
                    let lines = Self.lineIDs(quoting: spaced, in: page.lines)
                    if !lines.isEmpty { anchors = lines }
                } else if source.kind == .lecture {
                    let hit = source.segments.filter { AssistantDrafts.contains(spaced, in: $0.text) }.map(\.id)
                    if !hit.isEmpty { anchors = hit }
                }
            }
            return Evidence(quote: spaced, sourceID: passage.sourceID, pageIndex: passage.pageIndex, start: passage.start,
                            label: passage.label, anchorIDs: anchors)
        }
    }
}

extension String {
    /// Self, or nil when empty.
    var clNonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Adding, taking back

extension AppModel {

    /// Adds what a step drafted to the student's library. Returns the step as it is after: applied with what it made, or failed.
    @discardableResult
    func applyAssistantStep(_ step: AssistantStep, auto: Bool) -> AssistantStep {
        var step = step
        func fail(_ message: String) -> AssistantStep {
            step.status = .failed
            step.detail = message
            return step
        }
        guard step.status == .proposed || step.status == .working || step.status == .skipped || step.status == .undone else { return step }
        guard let course = liveCourse(step.courseID) else { return fail(String(localized: "That course isn't in your library anymore.")) }
        var made: [UUID] = []
        switch step.payload {
        case .cards(let drafts):
            let kept = drafts.filter(\.kept)
            guard !kept.isEmpty else { return fail(String(localized: "No card is ticked.")) }
            let topic = step.topicName.flatMap { ItemFactory.topic(named: $0, in: course, now: now) }
            for (n, d) in kept.enumerated() {
                let generated = GeneratedItem(id: "a\(n + 1)", kind: .flashcard, topic: topic?.name ?? "", prompt: d.front, answer: d.back,
                                              anchors: d.basis.evidence?.anchorIDs ?? [])
                made.append(addAssistantItem(generated, basis: d.basis, course: course, topicID: topic?.id, order: n).id)
            }
            if let topic { touch(topic) }
        case .questions(let drafts):
            let kept = drafts.filter(\.kept)
            guard !kept.isEmpty else { return fail(String(localized: "No question is ticked.")) }
            let topic = step.topicName.flatMap { ItemFactory.topic(named: $0, in: course, now: now) }
            for (n, d) in kept.enumerated() {
                let anchors = d.basis.evidence?.anchorIDs ?? []
                var generated: GeneratedItem
                switch d.kind {
                case .multipleChoice:
                    let choices = d.choices.enumerated().map { i, text in
                        Choice(text: text, correct: i == d.correctIndex, why: i == d.correctIndex && !d.explanation.isEmpty ? d.explanation : nil)
                    }
                    generated = GeneratedItem(id: "a\(n + 1)", kind: .mcq, topic: topic?.name ?? "", prompt: d.prompt, answer: d.answer,
                                              explanation: d.explanation, choices: choices, anchors: anchors)
                case .shortAnswer:
                    let ideas = d.keyIdeas.enumerated().map { i, label in KeyIdea(id: "k\(i + 1)", label: label, terms: [label.lowercased()]) }
                    generated = GeneratedItem(id: "a\(n + 1)", kind: .recall, topic: topic?.name ?? "", prompt: d.prompt, answer: d.answer,
                                              explanation: d.explanation, keyIdeas: ideas, anchors: anchors)
                case .fillBlank:
                    generated = GeneratedItem(id: "a\(n + 1)", kind: .cloze, topic: topic?.name ?? "", prompt: ItemDraft.defaultClozePrompt,
                                              answer: d.answer, explanation: d.explanation, cloze: ClozeSpec(text: d.prompt), anchors: anchors)
                }
                made.append(addAssistantItem(generated, basis: d.basis, course: course, topicID: topic?.id, order: n).id)
            }
            if let topic { touch(topic) }
        case .note(let note):
            guard let source = try? createSource(fromText: note.body, title: note.title, course: course) else { return fail(String(localized: "The note was empty.")) }
            made = [source.id]
        case .exam(let plan):
            var draft = ExamDraft.new(courseID: course.id, now: now, calendar: calendar)
            draft.title = plan.title
            draft.date = plan.date
            draft.wholeCourse = plan.topicIDs.isEmpty
            draft.scope = Set(plan.topicIDs)
            guard let exam = createExam(draft) else { return fail(String(localized: "The exam couldn't be added.")) }
            made = [exam.id]
        case .research(let result):
            guard !result.text.clTrimmed.isEmpty else { return fail(String(localized: "There is nothing to save yet.")) }
            guard let source = saveResearchNote(result, course: course) else { return fail(String(localized: "The note was empty.")) }
            made = [source.id]
            step.payload = .research({ var r = result; r.savedSourceID = source.id; return r }())
        case .none, .lookup, .practice, .open:
            return step
        }
        touch(course)
        save()
        AssistantFresh.mark(step.id)
        step.status = .applied
        step.createdIDs = made
        step.appliedAt = now
        step.auto = auto
        step.detail = nil
        return step
    }

    private func addAssistantItem(_ generated: GeneratedItem, basis: DraftBasis, course: Course, topicID: UUID?, order: Int) -> StudyItem {
        var source: Source?
        var page: SourcePage?
        // (Only a page of this course: a card never points into another course's notes.)
        if let e = basis.evidence, let id = e.sourceID, let found = self.source(id), found.deletedAt == nil, found.course?.id == course.id {
            source = found
            if let index = e.pageIndex { page = found.pages.first { $0.pageIndex == index } }
        }
        // A millisecond apart, so the course keeps the order Cap wrote them in.
        let stamp = now.addingTimeInterval(Double(order) / 1000)
        let item = ItemFactory.makeItem(from: generated, course: course, topicID: topicID, source: source, page: page,
                                        origin: .cloud, status: .active, now: stamp)
        // Only what the notes back counts as checked against them.
        if basis.isFromNotes { item.checkedAt = now }
        context.insert(item)
        course.items.append(item)
        return item
    }

    /// Takes back what a step added (everything it made goes to the trash, as if the student had deleted it).
    @discardableResult
    func undoAssistantStep(_ step: AssistantStep) -> AssistantStep {
        var step = step
        guard step.status == .applied else { return step }
        switch step.payload {
        case .cards, .questions: deleteItems(step.createdIDs)
        case .note, .research:
            for id in step.createdIDs { deleteSource(id, keepQuestions: false) }
        case .exam:
            for id in step.createdIDs { deleteExam(id) }
        default: break
        }
        if case .research(var r) = step.payload {
            r.savedSourceID = nil
            step.payload = .research(r)
        }
        step.status = .undone
        step.createdIDs = []
        return step
    }
}

// MARK: - Steps in the chat

/// Something Cap added, and the reply it is in.
struct AssistantAddition: Identifiable {
    var messageID: UUID
    var step: AssistantStep
    var id: String { "\(messageID.uuidString)#\(step.id)" }
}

extension AppModel {

    func assistantStep(messageID: UUID, stepID: String) -> AssistantStep? {
        guard let message = chatMessage(messageID), message.modelContext != nil else { return nil }
        return message.steps.first { $0.id == stepID }
    }

    func chatMessage(_ id: UUID) -> ChatMessage? {
        fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })).first
    }

    /// Changes one step of a saved reply (a tick, an edit) and saves.
    func updateAssistantStep(messageID: UUID, stepID: String, _ change: (inout AssistantStep) -> Void) {
        guard let message = chatMessage(messageID), message.modelContext != nil else { return }
        var steps = message.steps
        guard let i = steps.firstIndex(where: { $0.id == stepID }) else { return }
        change(&steps[i])
        message.steps = steps
        save()
    }

    /// The student pressed Add: the step's drafts join their course.
    @discardableResult
    func approveAssistantStep(messageID: UUID, stepID: String) -> AssistantStep? {
        guard let step = assistantStep(messageID: messageID, stepID: stepID), step.isOpen else { return nil }
        let applied = applyAssistantStep(step, auto: false)
        updateAssistantStep(messageID: messageID, stepID: stepID) { $0 = applied }
        return applied
    }

    func skipAssistantStep(messageID: UUID, stepID: String) {
        updateAssistantStep(messageID: messageID, stepID: stepID) { if $0.isOpen { $0.status = .skipped } }
    }

    /// Takes back what Cap added, from the chat or from the list in Settings.
    @discardableResult
    func undoAssistantStep(messageID: UUID, stepID: String) -> AssistantStep? {
        guard let step = assistantStep(messageID: messageID, stepID: stepID), step.status == .applied else { return nil }
        let undone = undoAssistantStep(step)
        updateAssistantStep(messageID: messageID, stepID: stepID) { $0 = undone }
        return undone
    }

    /// Cap's answer saved with what it did: the text, the checked quotes and the steps. Replaces nothing: one reply, one message.
    @discardableResult
    func saveAssistantAnswer(_ outcome: AssistantOutcome, to thread: ChatThread) -> ChatMessage? {
        let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard thread.modelContext != nil, !text.isEmpty || !outcome.steps.isEmpty else { return nil }
        let steps = outcome.steps.map { step -> AssistantStep in
            var s = step
            s.checking = nil
            guard s.status == .working else { return s }
            if !s.createdIDs.isEmpty {
                // Added (by "Let Cap do it") while the checks were still playing out when the reply was stopped: it is in the
                // library, so it stays in the chat as added, and can be taken back.
                s.status = .applied
            } else {
                // Cut off: what it had written is left for the student to add after all, and none of it was checked against the notes.
                s.status = .skipped
                s.detail = String(localized: "Cap stopped before it finished this.")
                switch s.payload {
                case .cards(var cards):
                    for i in cards.indices where cards[i].basis == .checking { cards[i].basis = .own }
                    s.payload = .cards(cards)
                case .questions(var questions):
                    for i in questions.indices where questions[i].basis == .checking { questions[i].basis = .own }
                    s.payload = .questions(questions)
                default:
                    break
                }
            }
            return s
        }
        let message = ChatMessage(thread: thread, role: .assistant, text: text, citations: outcome.citations,
                                  origin: ItemOrigin.cloud.rawValue, steps: steps, now: nextAssistantMessageTime(in: thread))
        context.insert(message)
        thread.messages.append(message)
        thread.updatedAt = now
        save()
        return message
    }

    private func nextAssistantMessageTime(in thread: ChatThread) -> Date {
        let last = thread.messages.map(\.createdAt).max() ?? .distantPast
        return max(now, last.addingTimeInterval(0.001))
    }

    /// Everything Cap has added that is still there, newest first, for Settings ▸ What Cap can do.
    func assistantAdditions() -> [AssistantAddition] {
        var out: [AssistantAddition] = []
        let withSteps = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.actionsData != nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        for message in fetch(withSteps) {
            for step in message.steps where step.status == .applied { out.append(AssistantAddition(messageID: message.id, step: step)) }
        }
        return out.sorted { ($0.step.appliedAt ?? .distantPast) > ($1.step.appliedAt ?? .distantPast) }
    }

    // MARK: Buttons

    /// A practice or screen button the student tapped.
    func perform(_ payload: AssistantPayload) {
        switch payload {
        case .practice(let offer):
            CLHaptics.tap()
            router.present(.session(SessionRequest(kind: .practice, courseID: offer.courseID, minutes: offer.minutes, topicID: offer.topicID)))
        case .open(let offer):
            CLHaptics.tap()
            switch offer.screen {
            case .today: router.tab = .today
            case .library: router.tab = .library
            case .progress: router.tab = .progress
            case .sky: router.push(.sky, on: .today)
            case .course: if let id = offer.id { router.push(.course(id), on: .library) }
            case .exam: if let id = offer.id { router.push(.exam(id), on: .library) }
            }
        default:
            break
        }
    }
}
