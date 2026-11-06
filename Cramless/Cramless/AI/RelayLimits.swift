import Foundation

// What the relay takes in a tutor or an assistant request, as `supabase/functions/_shared/schemas/requests.json` has it, and
// the one place that makes a request fit. The relay counts Unicode code points, not characters (`TextClip.swift`), and
// refuses the WHOLE request when one string is over its limit: with the student's material in every request, one source
// with a long file name for a title would otherwise make every cloud answer fail.

enum RelayLimits {
    // The strings of the request bodies that are not the tutor's or the assistant's (generate, check, lecture, confusions, cards, photos).
    /// `GenerateRequest.sourceTitle` and `LectureRequest.title`.
    static let title = 300
    /// `CheckRequest.sourceTitle`.
    static let checkTitle = 200
    /// One of `CheckRequest.headings`, and how many.
    static let heading = 120
    static let headings = 60
    /// `PageInput.label` and `TranscribeImageRequest.label`.
    static let label = 40
    /// `LineInput.text` and a lecture segment's text.
    static let lineText = 4000
    /// A lecture flag's words.
    static let flagText = 2000
    /// `CheckReport.given` and `.note`.
    static let reportGiven = 2000
    static let reportNote = 280
    /// `RungRequest.prompt` and `.answer`.
    static let rungText = 2000
    /// A harder question's page (`GenerateRequest.rung`).
    static let rungLines = 60

    // The tutor's and the assistant's.
    static let sourceID = 80
    static let sourceTitle = 300
    static let sourceLabel = 120
    static let sourceText = 20_000
    /// `GenerateRequest.course`, `LectureRequest.course` and the tutor's and assistant's.
    static let course = 200
    static let messageText = 8_000
    static let contextPrompt = 4_000
    static let contextAnswer = 8_000
    static let materialLines = 20
    static let materialLine = 120
    static let studyCourseName = 200
    static let studyTopicName = 120
    static let studyExamTitle = 200
    /// What a tool's result may say to the model (`AssistantResult.output`).
    static let toolOutput = 12_000

    // Grading, the mix-ups, cards from a chat and web research.
    /// `GradeRequest.level`, and `GenerateRequest.level`.
    static let level = 40
    /// `GradeRequest.response` and `.sourceExcerpt`.
    static let gradeResponse = 12_000
    static let gradeExcerpt = 12_000
    /// `GradeRequest.keyIdeas`: at most 12, each with an id of at most 80, a label of at most 300 and at most 40 terms of at most 300.
    static let keyIdeas = 12
    static let keyIdeaID = 80
    static let keyIdeaLabel = 300
    static let keyIdeaTerms = 40
    static let keyIdeaTerm = 300
    /// `ConfusionsRequest.mistakes`: at most 40, with a topic of at most 300.
    static let mistakes = 40
    static let mistakeTopic = 300
    /// `CardsFromChatRequest.messages`: at most 60 (the last ones), and the most it asks for.
    static let chatMessages = 60
    static let chatCards = 20
    /// `ResearchRequest.topic` and `.focus`.
    static let researchTopic = 200
    static let researchFocus = 300
    /// The lines of one page of a generate or check request.
    static let pageLines = 800

    // Reading a syllabus and checking a date heard in a lecture.
    /// `SyllabusRequest.pages`, `.topics` (each name at most 120, like a mention's topics).
    static let syllabusPages = 6
    static let syllabusTopics = 60
    /// `ExamMentionRequest.mentions`: at most 5, each a sentence of at most 2,000 with at most 4 candidate days; at most 30 topics.
    static let mentions = 5
    static let mentionText = 2000
    static let mentionCandidates = 4
    static let mentionTopics = 30
    /// `ExamMentionRequest.title` and `.course` are the lecture's (`title`, `course`).

    /// How much of the end of a label that has to be cut is kept ("p. 87", "· 07:40", "· card 7"): it says which one it is.
    static let labelTail = 24

    /// Messages within the limits: each cut to its limit, and one with no text at all (a reply that was only cards, say) left
    /// out, because the relay refuses an empty one.
    static func fit(_ messages: [TutorMessage]) -> [TutorMessage] {
        messages.compactMap { message in
            let text = message.text.clipped(toScalars: messageText)
            return text.isEmpty ? nil : TutorMessage(role: message.role, text: text)
        }
    }

    static func fit(_ context: TutorContext) -> TutorContext {
        TutorContext(itemPrompt: context.itemPrompt.clipped(toScalars: contextPrompt),
                     expected: context.expected.clipped(toScalars: contextAnswer),
                     given: context.given.clipped(toScalars: contextAnswer))
    }

    /// The last `limit` messages within the limits (the relay takes at most 60 for cards from a chat, 40 for the tutor): each cut to its
    /// length, and the ones with no text left out first, so the empty reply of a thread (one that only drafted cards) doesn't take
    /// the place of a message that says something.
    static func fit(_ messages: [TutorMessage], last limit: Int) -> [TutorMessage] {
        Array(fit(messages).suffix(max(0, limit)))
    }

    /// The lines of `TutorRequest.materials`: at most 20, each at most 120 code points.
    static func fit(materials: [String]) -> [String] {
        Array(materials.prefix(materialLines)).map { $0.clipped(toScalars: materialLine) }
    }
}

extension String {
    /// At most `limit` Unicode scalars: the start, a "…", and the last `tail` scalars, all cut between characters. For a label
    /// whose end ("p. 87", "· card 7") is what tells two of them apart.
    func clipped(toScalars limit: Int, keepingEnd tail: Int) -> String {
        guard unicodeScalars.count > limit else { return self }
        guard tail > 0, limit > tail + 2 else { return clipped(toScalars: limit) }
        var count = 0
        var start = endIndex
        for index in indices.reversed() {
            let n = unicodeScalars.distance(from: index, to: self.index(after: index))
            if count + n > tail { break }
            count += n
            start = index
        }
        let head = clipped(toScalars: limit - 1 - count).trimmingCharacters(in: .whitespaces)
        return head + "…" + String(self[start...])
    }
}

extension TutorSource {
    /// The passages of a request within the relay's limits. Titles and passages are cut to theirs, and a label keeps its end.
    /// Two labels that were different and are the same once cut (two sources whose long names start alike) are told apart by a
    /// number, so the model can still say which is which.
    static func fitting(_ sources: [TutorSource]) -> [TutorSource] {
        // A label that fits is what it is, however many passages share it ("Textbook p. 87").
        var used = Set(sources.map(\.label).filter { $0.unicodeScalars.count <= RelayLimits.sourceLabel })
        var cut: [String: String] = [:]   // an original label that had to be cut, and what it became
        return sources.map { source in
            var fitted = source
            fitted.id = source.id.clipped(toScalars: RelayLimits.sourceID)
            fitted.title = source.title.clipped(toScalars: RelayLimits.sourceTitle)
            fitted.text = source.text.clipped(toScalars: RelayLimits.sourceText)
            if source.label.unicodeScalars.count > RelayLimits.sourceLabel {
                if let known = cut[source.label] {
                    fitted.label = known
                } else {
                    var label = source.label.clipped(toScalars: RelayLimits.sourceLabel, keepingEnd: RelayLimits.labelTail)
                    var n = 1
                    while used.contains(label) {
                        n += 1
                        let mark = " (\(n))"
                        label = source.label.clipped(toScalars: RelayLimits.sourceLabel - mark.unicodeScalars.count,
                                                     keepingEnd: RelayLimits.labelTail) + mark
                    }
                    used.insert(label)
                    cut[source.label] = label
                    fitted.label = label
                }
            }
            return fitted
        }
    }
}

extension GradeRequest {
    /// The request within the relay's limits. The answer is the person's own words and the excerpt the lines the question came from:
    /// either can be longer than the relay takes (a pasted page, a question anchored on a whole passage), and one string over its
    /// limit makes the relay refuse the whole request, so the grade would silently come from the offline rules instead.
    func fitted() -> GradeRequest {
        var request = self
        request.level = level?.clipped(toScalars: RelayLimits.level)
        request.prompt = prompt.clipped(toScalars: RelayLimits.contextPrompt)
        request.modelAnswer = modelAnswer.clipped(toScalars: RelayLimits.contextAnswer)
        request.keyIdeas = keyIdeas.prefix(RelayLimits.keyIdeas).map { idea in
            KeyIdea(id: idea.id.clipped(toScalars: RelayLimits.keyIdeaID), label: idea.label.clipped(toScalars: RelayLimits.keyIdeaLabel),
                    terms: idea.terms.prefix(RelayLimits.keyIdeaTerms).map { $0.clipped(toScalars: RelayLimits.keyIdeaTerm) })
        }
        request.response = response.clipped(toScalars: RelayLimits.gradeResponse)
        request.sourceExcerpt = sourceExcerpt?.clipped(toScalars: RelayLimits.gradeExcerpt)
        return request
    }
}

extension ConfusionsRequest {
    /// The request within the relay's limits: the course, and for each mistake the question and the two answers.
    func fitted() -> ConfusionsRequest {
        var request = self
        request.course = course.clipped(toScalars: RelayLimits.course)
        request.mistakes = mistakes.prefix(RelayLimits.mistakes).map { mistake in
            MistakeInput(itemId: mistake.itemId.clipped(toScalars: RelayLimits.sourceID),
                         topic: mistake.topic.clipped(toScalars: RelayLimits.mistakeTopic),
                         prompt: mistake.prompt.clipped(toScalars: RelayLimits.contextPrompt),
                         expected: mistake.expected.clipped(toScalars: RelayLimits.contextAnswer),
                         given: mistake.given.clipped(toScalars: RelayLimits.contextAnswer), misses: min(10_000, max(0, mistake.misses)))
        }
        return request
    }
}

extension CardsFromChatRequest {
    /// The request within the relay's limits: the last 60 messages that say something, each cut to 8,000 code points. A reply that
    /// only drafted cards has no text and the relay refuses an empty message; a long thread has more than it takes.
    func fitted() -> CardsFromChatRequest {
        var request = self
        request.course = course?.clipped(toScalars: RelayLimits.course)
        request.messages = RelayLimits.fit(messages, last: RelayLimits.chatMessages)
        request.maxItems = min(RelayLimits.chatCards, max(1, maxItems))
        return request
    }
}

extension ResearchRequest {
    /// The request within the relay's limits.
    func fitted() -> ResearchRequest {
        var request = self
        request.topic = topic.clipped(toScalars: RelayLimits.researchTopic)
        request.focus = focus?.clipped(toScalars: RelayLimits.researchFocus)
        request.course = course?.clipped(toScalars: RelayLimits.course)
        return request
    }
}

extension SyllabusRequest {
    /// The request within the relay's limits: its first 6 pages, a body of text only, each line within its length.
    func fitted() -> SyllabusRequest {
        var request = self
        request.course = course.clipped(toScalars: RelayLimits.course)
        request.examTitle = examTitle?.clipped(toScalars: RelayLimits.studyExamTitle)
        request.topics = topics.prefix(RelayLimits.syllabusTopics).map {
            SyllabusTopicInput(id: $0.id, name: $0.name.clipped(toScalars: RelayLimits.studyTopicName))
        }
        request.pages = pages.prefix(RelayLimits.syllabusPages).map { page in
            PageInput(page: page.page, label: page.label.clipped(toScalars: RelayLimits.label),
                      lines: page.lines.prefix(RelayLimits.pageLines).map { LineInput(id: $0.id, text: $0.text.clipped(toScalars: RelayLimits.lineText)) },
                      image: nil)
        }
        return request
    }
}

extension ExamMentionRequest {
    /// The request within the relay's limits.
    func fitted() -> ExamMentionRequest {
        var request = self
        request.course = course.clipped(toScalars: RelayLimits.course)
        request.title = title.clipped(toScalars: RelayLimits.title)
        request.topics = topics.prefix(RelayLimits.mentionTopics).map { $0.clipped(toScalars: RelayLimits.studyTopicName) }
        request.mentions = mentions.prefix(RelayLimits.mentions).map {
            ExamMentionInput(id: $0.id.clipped(toScalars: RelayLimits.sourceID), text: $0.text.clipped(toScalars: RelayLimits.mentionText),
                             candidates: Array($0.candidates.prefix(RelayLimits.mentionCandidates)))
        }
        return request
    }
}

extension TutorRequest {
    /// The request within the relay's limits.
    func fitted() -> TutorRequest {
        var request = self
        request.course = course?.clipped(toScalars: RelayLimits.course)
        request.messages = RelayLimits.fit(messages)
        request.sources = TutorSource.fitting(sources)
        request.context = context.map(RelayLimits.fit)
        request.materials = materials.map(RelayLimits.fit(materials:))
        return request
    }
}

extension StudyState {
    /// The names of courses, topics and exams within the relay's limits. (Their short ids are what the model passes back, so the
    /// names are only for it to read.)
    func fitted() -> StudyState {
        var state = self
        state.courses = courses.map { course in
            var fitted = course
            fitted.name = course.name.clipped(toScalars: RelayLimits.studyCourseName)
            fitted.topics = course.topics.map { topic in
                var t = topic
                t.name = topic.name.clipped(toScalars: RelayLimits.studyTopicName)
                return t
            }
            return fitted
        }
        state.exams = exams.map { exam in
            var fitted = exam
            fitted.title = exam.title.clipped(toScalars: RelayLimits.studyExamTitle)
            return fitted
        }
        return state
    }
}

extension AssistantRequest {
    /// The request within the relay's limits: its passages, messages, course, the names in the study overview, and what the tools
    /// told the model in the rounds so far.
    func fitted() -> AssistantRequest {
        var request = self
        request.course = course?.clipped(toScalars: RelayLimits.course)
        request.messages = RelayLimits.fit(messages)
        request.sources = TutorSource.fitting(sources)
        request.context = context.map(RelayLimits.fit)
        request.study = study.fitted()
        request.turns = turns.map { turn in
            AssistantTurn(continuation: turn.continuation,
                          results: turn.results.map { AssistantResult(callId: $0.callId, output: $0.output.clipped(toScalars: RelayLimits.toolOutput)) })
        }
        return request
    }
}
