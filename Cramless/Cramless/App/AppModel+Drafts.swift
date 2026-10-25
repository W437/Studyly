import Foundation
import SwiftData

// Drafts: a generated set becomes draft items (status `.draft`) in a course, the person approves or rejects them in
// review, and the approved ones join the course. Every mutation stamps with `touch` and ends in `save()`.
//
// A draft set always lives in a course, so its topics exist from the start (made once: an existing topic with the same
// name is reused). When nothing chose a course (onboarding, an empty library, a file opened from another app with no
// course yet), the set goes to the course with the soonest exam, or, with no courses at all, to a provisional course
// named from the page ("Biology"). A provisional course is renamed by the class question, or removed again when the
// set goes elsewhere or is thrown away.
//
// What the generator and the check said about the set (who wrote it, who checked it, the honest note, the better-AI
// suggestion, the items the check left out with their reasons) is kept beside the source in
// `sources/<id>/draft.json` until the set is approved or thrown away, so a review opened later says the same.

/// A generated set, from a page set or a lecture, as the drafts code takes it.
struct DraftInput: Sendable {
    var title: String
    var topics: [GeneratedTopic]
    var items: [GeneratedItem]
    var dropped: [DroppedItem]
    var origin: ItemOrigin
    var checkedBy: ItemOrigin
    var model: String
    var note: String?
    var suggestion: AISuggestion?
    var fellBack: Bool

    init(_ outcome: GenerationOutcome) {
        title = outcome.title
        topics = outcome.topics
        items = outcome.items
        dropped = outcome.dropped
        origin = outcome.origin
        checkedBy = outcome.checkedBy
        model = outcome.model
        note = outcome.note
        suggestion = outcome.suggestion
        fellBack = outcome.fellBack
    }

    init(_ outcome: LectureOutcome) {
        title = outcome.title
        var names: [String] = []
        for item in outcome.items where !item.topic.isEmpty && !names.contains(item.topic) { names.append(item.topic) }
        topics = names.map { GeneratedTopic(name: $0, summary: "") }
        items = outcome.items
        dropped = outcome.dropped
        origin = outcome.origin
        // Lecture items are checked on this iPhone against the transcript's segments, whoever wrote them.
        checkedBy = .rules
        model = outcome.model
        note = outcome.note
        suggestion = outcome.suggestion
        fellBack = outcome.fellBack
    }
}

/// What the generator and the check said about a draft set, kept beside its source until the set is decided.
struct DraftReport: Codable, Hashable, Sendable {
    /// A question the check took out, with the reason the person reads in review.
    struct LeftOut: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var kind: ItemKind
        var topic: String
        var prompt: String
        var answer: String
        var reason: String
    }

    /// `AISuggestion`, stored.
    enum Suggestion: Codable, Hashable, Sendable {
        case allowCloud(feature: String)
        case allowPhotos
        case upgrade(QuotaMeter.Key, message: String)

        init(_ suggestion: AISuggestion) {
            switch suggestion {
            case .allowCloud(let feature): self = .allowCloud(feature: feature)
            case .allowPhotos: self = .allowPhotos
            case .upgrade(let key, let message): self = .upgrade(key, message: message)
            }
        }

        var aiSuggestion: AISuggestion {
            switch self {
            case .allowCloud(let feature): .allowCloud(feature: feature)
            case .allowPhotos: .allowPhotos
            case .upgrade(let key, let message): .upgrade(key, message: message)
            }
        }
    }

    var title: String
    var origin: ItemOrigin
    var checkedBy: ItemOrigin
    var model: String
    var note: String?
    var suggestion: Suggestion?
    var fellBack: Bool
    var leftOut: [LeftOut]
    /// Topic names in the generator's order; the review groups by them.
    var topics: [String]
    /// A course made for this set because none was chosen.
    var provisionalCourseID: UUID?
    /// Topics this set created, removed again if the set leaves their course before they hold anything else.
    var createdTopicIDs: [UUID]
    var createdAt: Date

    static let fileName = "draft.json"

    static func path(_ sourceID: UUID) -> String { "\(PageImageStore.sourceFolder(sourceID))/\(fileName)" }
}

extension AppModel {

    // MARK: - Reading

    /// The draft items of a source, in the generator's order.
    func draftItems(sourceID: UUID) -> [StudyItem] {
        let draft = ItemStatus.draft.rawValue
        let drafts = fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.statusRaw == draft && $0.deletedAt == nil },
                                                      sortBy: [SortDescriptor(\.createdAt)]))
        return drafts.filter { $0.sourceRef?.sourceID == sourceID }
    }

    /// The live items made from a source (approved, or suspended), in the order they were made.
    func items(fromSource sourceID: UUID) -> [StudyItem] {
        let rejected = ItemStatus.rejected.rawValue
        let draft = ItemStatus.draft.rawValue
        let items = fetch(FetchDescriptor<StudyItem>(predicate: #Predicate {
            $0.deletedAt == nil && $0.statusRaw != rejected && $0.statusRaw != draft
        }, sortBy: [SortDescriptor(\.createdAt)]))
        return items.filter { $0.sourceRef?.sourceID == sourceID }
    }

    func draftReport(sourceID: UUID) -> DraftReport? {
        guard let data = try? Data(contentsOf: FileStore.url(for: DraftReport.path(sourceID))) else { return nil }
        return try? JSONDecoder.cramless.decode(DraftReport.self, from: data)
    }

    /// The course new material goes to when the person hasn't picked one: `preferred` when it exists, else the
    /// course with the soonest exam, else the first course.
    func defaultCourseID(preferring preferred: UUID? = nil) -> UUID? {
        if let preferred, let course = course(preferred), course.deletedAt == nil { return course.id }
        return upcomingExams().first(where: { $0.course?.deletedAt == nil })?.course?.id ?? courses.first?.id
    }

    // MARK: - Making drafts

    /// Turns a generated page set into draft items for `source`, in `course` (or the source's course, or the default
    /// course, or a provisional one). A set made before for the same source is replaced. Returns the drafts.
    @discardableResult
    func makeDrafts(from outcome: GenerationOutcome, source: Source, course: Course? = nil) -> [StudyItem] {
        makeDrafts(DraftInput(outcome), source: source, course: course)
    }

    /// A lecture's notes and its draft questions: the notes are saved on the source, the questions become drafts.
    @discardableResult
    func saveLectureNotes(_ outcome: LectureOutcome, lecture: Source, course: Course? = nil) -> [StudyItem] {
        lecture.notes = outcome.notes
        // "Lecture 7" becomes "Lecture 7: Cell division" when the notes found a name for it.
        if let colon = outcome.title.range(of: ": "), !lecture.title.contains(":") {
            let name = outcome.title[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { lecture.title = "\(lecture.title): \(name)" }
        }
        touch(lecture)
        guard !outcome.items.isEmpty else {
            if lecture.status == .read { lecture.status = .ready }
            save()
            return []
        }
        return makeDrafts(DraftInput(outcome), source: lecture, course: course)
    }

    @discardableResult
    func makeDrafts(_ input: DraftInput, source: Source, course: Course? = nil) -> [StudyItem] {
        var report = draftReport(sourceID: source.id)
        // A set made again (with Cloud AI, say) replaces the one before it.
        for old in draftItems(sourceID: source.id) { removeItem(old) }

        let target: Course
        if let course {
            target = course
        } else if let current = source.course, current.deletedAt == nil {
            target = current
        } else if let id = defaultCourseID(), let existing = self.course(id) {
            target = existing
        } else {
            let names = suggestedCourseNames(for: source, title: input.title, topics: input.topics.map(\.name))
            target = makeCourse(named: names.first ?? "My class")
            report?.provisionalCourseID = target.id
            if report == nil { report = emptyReport(provisional: target.id) }
        }
        if source.course?.id != target.id {
            source.course = target
            if !target.sources.contains(where: { $0.id == source.id }) { target.sources.append(source) }
        }

        // Topics, made once: an existing topic with the same name is reused.
        var topicIDs: [String: UUID] = [:]
        var created = report?.createdTopicIDs ?? []
        var order: [String] = []
        let named = input.topics + input.items.map { GeneratedTopic(name: $0.topic, summary: "") }
        for topic in named {
            let key = topic.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, topicIDs[key] == nil else { continue }
            let existed = target.topics.contains { $0.deletedAt == nil && $0.name.lowercased() == key }
            guard let made = ItemFactory.topic(named: topic.name, in: target, summary: topic.summary, now: now) else { continue }
            if !existed { created.append(made.id) }
            topicIDs[key] = made.id
            order.append(made.name)
        }

        var drafts: [StudyItem] = []
        for (index, generated) in input.items.enumerated() {
            let page = page(for: generated.anchors, in: source)
            // A millisecond apart, so the review keeps the generator's order.
            let stamp = now.addingTimeInterval(Double(index) / 1000)
            let item = ItemFactory.makeItem(from: generated, course: target,
                                            topicID: topicIDs[generated.topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()],
                                            source: source, page: page, origin: input.origin, status: .draft, now: stamp)
            // Every item here passed a check against its source (the cloud's, or the grounding check on this iPhone).
            item.checkedAt = now
            context.insert(item)
            target.items.append(item)
            drafts.append(item)
        }
        source.status = .drafted
        touch(source)
        touch(target)
        save()

        let leftOut = input.dropped.map {
            DraftReport.LeftOut(id: $0.item.id, kind: $0.item.kind, topic: $0.item.topic, prompt: $0.item.prompt,
                                answer: $0.item.answer, reason: $0.reason)
        }
        writeDraftReport(DraftReport(title: input.title, origin: input.origin, checkedBy: input.checkedBy, model: input.model,
                                     note: input.note, suggestion: input.suggestion.map(DraftReport.Suggestion.init),
                                     fellBack: input.fellBack, leftOut: leftOut, topics: order,
                                     provisionalCourseID: report?.provisionalCourseID, createdTopicIDs: created, createdAt: now),
                         sourceID: source.id)
        return drafts
    }

    // MARK: - Deciding

    /// Approves a draft set: the kept drafts become active in `course` (the set's own course when nil), the others
    /// are rejected (kept for the check's statistics, never shown). The source is ready. Returns how many were added.
    @discardableResult
    func approveDrafts(sourceID: UUID, keeping kept: Set<UUID>, in course: Course? = nil) -> Int {
        guard let source = source(sourceID) else { return 0 }
        if let course { moveDrafts(sourceID: sourceID, to: course) }
        var added = 0
        for item in draftItems(sourceID: sourceID) {
            if kept.contains(item.id) {
                item.status = .active
                added += 1
            } else {
                item.status = .rejected
            }
            touch(item)
        }
        source.status = .ready
        touch(source)
        if let target = source.course { touch(target) }
        // A provisional course the set ended up in is a real course now; one it left is cleaned up by the move.
        removeDraftReport(sourceID: sourceID)
        save()
        return added
    }

    /// Throws a draft set away. With `keepSource`, the source stays (read, without questions); otherwise it goes too.
    /// Topics and a provisional course made for the set go with it when nothing else uses them.
    func discardDrafts(sourceID: UUID, keepSource: Bool = false) {
        let report = draftReport(sourceID: sourceID)
        for item in draftItems(sourceID: sourceID) { removeItem(item) }
        let course = source(sourceID)?.course
        if let source = source(sourceID) {
            if keepSource {
                source.status = source.kind == .lecture ? .ready : .read
                touch(source)
                removeDraftReport(sourceID: sourceID)
            } else {
                course?.sources.removeAll { $0.id == sourceID }
                discardSource(source)
            }
        }
        if let report, let course { cleanUp(report, leaving: course) }
        save()
    }

    /// Moves a draft set (its source, drafts and their topics) to another course.
    func moveDrafts(sourceID: UUID, to course: Course) {
        guard let source = source(sourceID), source.course?.id != course.id else { return }
        let old = source.course
        var report = draftReport(sourceID: sourceID)
        let names = Dictionary((old?.topics ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var created = report?.createdTopicIDs ?? []
        for item in draftItems(sourceID: sourceID) {
            let name = item.topicID.flatMap { names[$0] }
            if let old { old.items.removeAll { $0.id == item.id } }
            item.course = course
            if !course.items.contains(where: { $0.id == item.id }) { course.items.append(item) }
            if let name {
                let existed = course.topics.contains { $0.deletedAt == nil && $0.name.lowercased() == name.lowercased() }
                let topic = ItemFactory.topic(named: name, in: course, now: now)
                if let topic, !existed { created.append(topic.id) }
                item.topicID = topic?.id
            } else {
                item.topicID = nil
            }
            touch(item)
        }
        old?.sources.removeAll { $0.id == sourceID }
        source.course = course
        if !course.sources.contains(where: { $0.id == sourceID }) { course.sources.append(source) }
        touch(source)
        touch(course)
        if var kept = report, let old {
            kept.createdTopicIDs = created
            kept = cleanUp(kept, leaving: old)
            report = kept
        }
        if let report { writeDraftReport(report, sourceID: sourceID) }
        save()
    }

    /// Edits a draft before it's approved. Multiple-choice options keep which one is right; a fill-in's blanks are the
    /// words between `{{` and `}}` in `clozeText`.
    func updateDraft(_ itemID: UUID, prompt: String, answer: String, choices: [Choice]? = nil, clozeText: String? = nil) {
        guard let item = item(itemID), item.modelContext != nil else { return }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPrompt.isEmpty { item.prompt = cleanPrompt }
        if let choices, choices.filter(\.correct).count == 1, choices.allSatisfy({ !$0.text.isEmpty }) {
            item.choices = choices
            item.answer = choices.first(where: \.correct)?.text ?? item.answer
        } else if let clozeText, !clozeText.isEmpty {
            var spec = item.cloze ?? ClozeSpec(text: clozeText)
            spec.text = clozeText
            if spec.alternates.count != spec.answers.count { spec.alternates = [] }
            item.cloze = spec
            item.answer = spec.answers.joined(separator: ", ")
        } else if !cleanAnswer.isEmpty {
            item.answer = cleanAnswer
        }
        touch(item)
        save()
    }

    // MARK: - Courses

    /// A new course, or the live course with that name (case doesn't matter).
    @discardableResult
    func createCourse(named name: String) -> Course {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = courses.first(where: { $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
            return existing
        }
        let course = makeCourse(named: clean.isEmpty ? "My class" : clean)
        save()
        return course
    }

    /// The class question's answer for a draft set: the live course with that name, or the set's provisional course
    /// renamed, or a new course. The drafts are moved there.
    @discardableResult
    func assignDrafts(sourceID: UUID, toCourseNamed name: String) -> Course? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return source(sourceID)?.course }
        if let existing = courses.first(where: { $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
            moveDrafts(sourceID: sourceID, to: existing)
            return existing
        }
        if let report = draftReport(sourceID: sourceID), let id = report.provisionalCourseID, let provisional = course(id),
           source(sourceID)?.course?.id == id {
            provisional.name = clean
            provisional.symbol = CourseGuess.symbol(for: clean)
            touch(provisional)
            save()
            return provisional
        }
        let course = createCourse(named: clean)
        moveDrafts(sourceID: sourceID, to: course)
        return course
    }

    /// Class names to suggest for a source: subjects its words point at (a guess made on this iPhone from the page),
    /// then the person's own courses.
    func suggestedCourseNames(sourceID: UUID) -> [String] {
        guard let source = source(sourceID) else { return courses.map(\.name) }
        let report = draftReport(sourceID: sourceID)
        return suggestedCourseNames(for: source, title: report?.title ?? "", topics: report?.topics ?? [])
    }

    func suggestedCourseNames(for source: Source, title: String, topics: [String]) -> [String] {
        var text = [source.title, title] + topics
        for page in source.sortedPages { text.append(contentsOf: page.lines.prefix(80).map(\.text)) }
        text.append(contentsOf: source.segments.prefix(80).map(\.text))
        let subjects = CourseGuess.subjects(in: text, headline: [source.title, title] + topics)
        var names: [String] = []
        // The strongest subject, then how a class in it is usually named at the person's level ("Bio 101",
        // "AP Biology"), then the other subjects.
        if let first = subjects.first {
            names = [first] + CourseGuess.variants(of: first, level: settings.level) + subjects.dropFirst()
        }
        for course in courses where !names.contains(where: { $0.compare(course.name, options: .caseInsensitive) == .orderedSame }) {
            names.append(course.name)
        }
        return names
    }

    // MARK: - A better read

    enum CloudReadResult: Equatable {
        /// Every page that needed it was read; the source is ready to write questions from.
        case read
        /// Not allowed right now; the suggestion's sheet would allow it (nil when nothing can, like no relay).
        case notAllowed(AISuggestion?)
        case failed(String)
        /// Cloud AI read the photos and found no text either.
        case nothingFound
    }

    /// Reads the pages the iPhone couldn't (handwriting, math, an alphabet it doesn't read) with Cloud AI, from their
    /// photos. The router checks consent and the photos switch again right before each photo goes.
    func readPagesWithCloud(sourceID: UUID) async -> CloudReadResult {
        guard let source = source(sourceID) else { return .failed("This page is gone.") }
        let pages = source.sortedPages.filter { $0.imageFileName != nil && ($0.wantsBetterRead || $0.lines.isEmpty) }
        for page in pages {
            guard page.modelContext != nil, let image = page.imageFileName else { continue }
            switch await ai.transcribeImage(at: FileStore.url(for: image), page: page.pageIndex, label: page.label) {
            case .lines(let lines, _):
                guard !lines.isEmpty, page.modelContext != nil else { continue }
                replaceLines(of: page, with: lines)
            case .notAllowed(let suggestion):
                return .notAllowed(suggestion)
            case .failed(let message):
                return .failed(message)
            }
        }
        return self.source(sourceID)?.pages.contains(where: { !$0.lines.isEmpty }) == true ? .read : .nothingFound
    }

    // MARK: - Helpers

    /// The page an item's anchors point at: "p3.l12" is page 3; otherwise the page holding the first anchor.
    func page(for anchors: [String], in source: Source) -> SourcePage? {
        guard source.kind != .lecture, let first = anchors.first else { return nil }
        let pages = source.sortedPages
        if first.hasPrefix("p"), let dot = first.firstIndex(of: "."), let index = Int(first[first.index(after: first.startIndex)..<dot]),
           let page = pages.first(where: { $0.pageIndex == index }) {
            return page
        }
        return pages.first { page in page.lines.contains { $0.id == first } } ?? (pages.count == 1 ? pages.first : nil)
    }

    private func makeCourse(named name: String) -> Course {
        let used = Set(courses.map(\.color))
        let color = CourseColor.allCases.first { !used.contains($0) } ?? CourseColor.allCases[courses.count % CourseColor.allCases.count]
        let course = Course(name: name, color: color, symbol: CourseGuess.symbol(for: name),
                            sortOrder: (courses.map(\.sortOrder).max() ?? -1) + 1, now: now)
        context.insert(course)
        touch(course)
        return course
    }

    /// Deletes an item outright when it never reached the server, soft-deletes it when it did.
    private func removeItem(_ item: StudyItem) {
        if item.syncedAt == nil {
            item.course?.items.removeAll { $0.id == item.id }
            context.delete(item)
        } else {
            item.deletedAt = now
            touch(item)
        }
    }

    /// After a set left `course`: removes the topics it made there that hold nothing now, and the course itself when
    /// it was the set's provisional course and holds nothing now.
    @discardableResult
    private func cleanUp(_ report: DraftReport, leaving course: Course) -> DraftReport {
        var report = report
        let used = Set(course.items.filter { $0.deletedAt == nil && $0.modelContext != nil }.compactMap(\.topicID))
        for topic in course.topics where report.createdTopicIDs.contains(topic.id) && !used.contains(topic.id) {
            report.createdTopicIDs.removeAll { $0 == topic.id }
            course.topics.removeAll { $0.id == topic.id }
            if topic.syncedAt == nil { context.delete(topic) } else { topic.deletedAt = now; touch(topic) }
        }
        if report.provisionalCourseID == course.id {
            let holdsNothing = course.items.allSatisfy { $0.deletedAt != nil || $0.modelContext == nil }
                && course.sources.allSatisfy { $0.deletedAt != nil || $0.modelContext == nil }
                && course.exams.allSatisfy { $0.deletedAt != nil }
            if holdsNothing {
                if course.syncedAt == nil { context.delete(course) } else { course.deletedAt = now; touch(course) }
                report.provisionalCourseID = nil
            }
        }
        return report
    }

    private func emptyReport(provisional: UUID?) -> DraftReport {
        DraftReport(title: "", origin: .rules, checkedBy: .rules, model: "", note: nil, suggestion: nil, fellBack: false,
                    leftOut: [], topics: [], provisionalCourseID: provisional, createdTopicIDs: [], createdAt: now)
    }

    private func writeDraftReport(_ report: DraftReport, sourceID: UUID) {
        guard let data = try? JSONEncoder.cramless.encode(report) else { return }
        _ = try? FileStore.write(data, folder: PageImageStore.sourceFolder(sourceID), name: DraftReport.fileName)
    }

    private func removeDraftReport(sourceID: UUID) {
        try? FileManager.default.removeItem(at: FileStore.url(for: DraftReport.path(sourceID)))
    }
}

/// Guesses which class a page is for from its words, on this iPhone: a short keyword list per subject, headings and
/// titles counting triple. A guess to suggest, never a decision: the person picks the class.
enum CourseGuess {
    struct Subject: Sendable {
        var name: String
        var symbol: String
        var words: Set<String>
    }

    static let subjects: [Subject] = [
        Subject(name: "Biology", symbol: "leaf", words: ["biology", "cell", "cells", "mitosis", "meiosis", "dna", "gene", "genes",
                "protein", "organism", "organisms", "enzyme", "photosynthesis", "chromosome", "chromosomes", "species",
                "evolution", "membrane", "tissue", "tissues", "nucleus", "cytoplasm", "bacteria", "ecosystem", "cytokinesis"]),
        Subject(name: "Chemistry", symbol: "flask", words: ["chemistry", "mole", "moles", "atom", "atoms", "molecule", "molecules",
                "reaction", "reactions", "acid", "acids", "bond", "bonds", "electron", "electrons", "ion", "ions", "compound",
                "periodic", "stoichiometry", "oxidation", "reagent", "molar"]),
        Subject(name: "Physics", symbol: "atom", words: ["physics", "force", "forces", "velocity", "acceleration", "momentum",
                "newton", "gravity", "wave", "waves", "frequency", "circuit", "voltage", "friction", "kinetic", "quantum"]),
        Subject(name: "Psychology", symbol: "brain.head.profile", words: ["psychology", "memory", "conditioning", "behavior",
                "behaviour", "cognitive", "neuron", "neurons", "perception", "stimulus", "reinforcement", "personality",
                "emotion", "freud", "pavlov"]),
        Subject(name: "History", symbol: "building.columns", words: ["history", "war", "empire", "revolution", "treaty", "century",
                "king", "colonial", "dynasty", "independence", "civilization", "monarchy"]),
        Subject(name: "Economics", symbol: "chart.line.uptrend.xyaxis", words: ["economics", "supply", "demand", "market",
                "markets", "inflation", "gdp", "trade", "elasticity", "monetary", "fiscal", "tariff"]),
        Subject(name: "Math", symbol: "function", words: ["math", "equation", "equations", "derivative", "integral", "theorem",
                "proof", "matrix", "vector", "algebra", "calculus", "polynomial", "probability", "geometry"]),
        Subject(name: "English", symbol: "text.book.closed", words: ["poem", "poetry", "novel", "author", "metaphor", "essay",
                "narrator", "literature", "shakespeare", "stanza"]),
        Subject(name: "Computer science", symbol: "chevron.left.forwardslash.chevron.right", words: ["algorithm", "algorithms",
                "array", "compiler", "recursion", "database", "programming", "binary", "function", "loop"]),
    ]

    /// Subject names the text points at, strongest first (at most three).
    static func subjects(in text: [String], headline: [String] = []) -> [String] {
        var scores: [String: Int] = [:]
        func count(_ line: String, weight: Int) {
            let words = line.lowercased().split { !$0.isLetter }.map(String.init)
            for word in words {
                for subject in subjects where subject.words.contains(word) { scores[subject.name, default: 0] += weight }
            }
        }
        for line in text { count(line, weight: 1) }
        for line in headline { count(line, weight: 3) }
        return scores.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map(\.key)
    }

    /// Usual names of a class in a subject at a level: "AP Biology" in high school, "Bio 101" at college.
    static func variants(of subject: String, level: AppSettings.Level?) -> [String] {
        let short: [String: String] = ["Biology": "Bio", "Chemistry": "Chem", "Psychology": "Psych", "Economics": "Econ",
                                       "Physics": "Physics", "History": "History"]
        let ap: Set<String> = ["Biology", "Chemistry", "Psychology", "Physics", "Economics"]
        let college = short[subject].map { "\($0) 101" }
        let highSchool = ap.contains(subject) ? "AP \(subject)" : nil
        switch level {
        case .highSchool: return [highSchool].compactMap { $0 }
        case .college, .grad: return [college].compactMap { $0 }
        default: return [college, highSchool].compactMap { $0 }
        }
    }

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if let subject = subjects.first(where: { lower.contains($0.name.lowercased()) }) { return subject.symbol }
        let hints: [(String, String)] = [("bio", "leaf"), ("chem", "flask"), ("phys", "atom"), ("psych", "brain.head.profile"),
                                        ("hist", "building.columns"), ("econ", "chart.line.uptrend.xyaxis"), ("calc", "function"),
                                        ("math", "function"), ("spanish", "character.bubble"), ("french", "character.bubble"),
                                        ("german", "character.bubble"), ("lang", "character.bubble"), ("lit", "text.book.closed")]
        return hints.first { lower.contains($0.0) }?.1 ?? "book.closed"
    }
}
