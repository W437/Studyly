import Foundation

// Reading a syllabus: the rules' answer at once, the relay's when it's allowed (on the hidden `extras` meter, free for everyone), a quiet fall back
// to the rules when it fails or the relay is older than the route. Text only: the photo stays on this iPhone and isn't kept here either.

/// What a syllabus read has to go on.
struct SyllabusInput: Sendable {
    var course: String
    var examTitle: String
    var topics: [(id: UUID, name: String)]
    var pages: [PageText]
    /// The draft the proposal starts from.
    var base: ExamDraft
    /// What the course already holds: the proposal's topics are read against it.
    var library = SyllabusLibrary.empty
}

struct SyllabusOutcome: Sendable {
    /// Nil when the pages say nothing about any exam.
    var proposal: SyllabusProposal?
    var origin: ItemOrigin
    var model: String
    /// Cloud AI would help and is off.
    var suggestion: AISuggestion?
    var fellBack = false
}

extension AIRouter {
    func readSyllabus(_ input: SyllabusInput, offlineOnly: Bool = false) async -> SyllabusOutcome {
        guard let app else { return SyllabusOutcome(proposal: nil, origin: .rules, model: LocalGrader.model) }
        let now = app.now, calendar = app.calendar
        let ids = SyllabusProposal.requestIDs(for: input.topics)
        let requestTopics = input.topics.prefix(RelayLimits.syllabusTopics).enumerated().map { SyllabusTopicInput(id: "t\($0.offset + 1)", name: $0.element.name) }
        let pages = input.pages.prefix(RelayLimits.syllabusPages).map {
            PageInput(page: $0.index, label: $0.label, lines: $0.lines.map { LineInput(id: $0.id, text: $0.text) }, image: nil)
        }
        let text = input.pages.flatMap(\.lines).map(\.text).joined(separator: "\n")
        let route = route(.syllabus)
        func proposal(_ exams: [SyllabusExam], origin: ItemOrigin) -> SyllabusProposal? {
            SyllabusProposal.make(exams: exams, examTitle: input.examTitle, topicIDs: ids, base: input.base, pageText: text, origin: origin, now: now, calendar: calendar)
        }
        var fellBack = false
        if !offlineOnly, route.usesCloud, cloudStillAllowed(), let transport, !text.clTrimmed.isEmpty {
            let request = SyllabusRequest(course: input.course, examTitle: input.examTitle.clTrimmed.clNonEmpty, today: calendar.dayKey(for: now),
                                          topics: requestTopics, pages: pages).fitted()
            do {
                let response = try await transport.syllabus(request)
                if let read = proposal(response.exams, origin: .cloud) {
                    return SyllabusOutcome(proposal: await matched(read, with: input.library), origin: .cloud, model: response.model)
                }
                // The model found nothing: the rules may still find a schedule, and they'll say so.
            } catch {
                fellBack = true
            }
        }
        // Rules, off the main thread: a date detector over six pages isn't free.
        let local = await Task.detached(priority: .userInitiated) {
            LocalSyllabus.read(pages: pages, topics: requestTopics, examTitle: input.examTitle, today: now, calendar: calendar)
        }.value
        return SyllabusOutcome(proposal: await matched(proposal(local, origin: .rules), with: input.library), origin: .rules, model: LocalGrader.model,
                               suggestion: route.usesCloud ? nil : (offlineOnly ? .allowCloud(feature: AIJob.syllabus.feature) : route.suggestion), fellBack: fellBack)
    }

    /// The topics read against the course, off the main thread: a big library's words aren't free.
    private func matched(_ proposal: SyllabusProposal?, with library: SyllabusLibrary) async -> SyllabusProposal? {
        guard var proposal else { return nil }
        return await Task.detached(priority: .userInitiated) {
            proposal.match(against: library)
            return proposal
        }.value
    }

    /// The one AI look at a date heard in a lecture, after the student's tap; on the hidden `extras` meter. Nil when it isn't allowed or doesn't answer: the rules' reading stands.
    func checkExamMention(_ mention: ExamMention, course: String, title: String, recordedAt: Date, topics: [String]) async -> ExamMentionVerdict? {
        guard let app, route(.examMention).usesCloud, cloudStillAllowed(), let transport else { return nil }
        let request = ExamMentionRequest(course: course, title: title, recordedDay: app.calendar.dayKey(for: recordedAt),
                                         language: LocalGenerator.dominantLanguage(mention.quote), topics: topics,
                                         mentions: [ExamMentionInput(id: mention.id, text: mention.quote, candidates: mention.candidates)]).fitted()
        guard let response = try? await transport.examMention(request) else { return nil }
        return response.mentions.first { $0.id == mention.id }
    }
}
