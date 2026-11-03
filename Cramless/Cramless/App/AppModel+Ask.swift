import Foundation
import SwiftData

// The tutor chat: threads and messages (chats never sync; they stay on this iPhone), the inputs `ai.tutor` takes,
// saving an answer once it is complete, and adding the cards the person kept from a chat to a course.
//
// The answer as it streams lives in `AskStreams` (view state that outlives a screen); only the finished answer, or
// what arrived before the person stopped it, becomes a `ChatMessage` here.
extension AppModel {

    // MARK: Reading

    /// Every chat, most recent first.
    func chatThreads() -> [ChatThread] {
        fetch(FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    /// A course that hasn't been moved to the trash.
    func liveCourse(_ id: UUID?) -> Course? {
        guard let course = course(id), course.deletedAt == nil else { return nil }
        return course
    }

    /// The course a new chat starts in: the soonest exam's course that has notes Cap can read, else the first course
    /// with any, else the next exam's course or the first course.
    var defaultChatCourseID: UUID? {
        let examCourses = upcomingExams().compactMap(\.course).filter { $0.deletedAt == nil }
        let ordered = examCourses + courses.filter { c in !examCourses.contains { $0.id == c.id } }
        return ordered.first { !readableSources(courseID: $0.id).isEmpty }?.id ?? ordered.first?.id
    }

    /// The sources Cap can read in a course (nil: every course): pages with text, a lecture's transcript, or the cards of an
    /// imported Quizlet, Anki or CSV deck (the tutor reads a card as a passage, `tutorMaterial`).
    func readableSources(courseID: UUID?) -> [Source] {
        let sources = liveCourse(courseID).map(\.liveSources) ?? courses.flatMap(\.liveSources)
        return sources.filter { source in
            if source.kind == .lecture { return !source.segments.isEmpty }
            if source.kind.isDeck { return hasCards(source) }
            return source.pages.contains { !$0.text.isEmpty }
        }
    }

    /// A deck has something to read while one of its cards is still in the course (the same cards `deckCards` lists). Stops at
    /// the first, because a screen asks this every time it draws.
    private func hasCards(_ source: Source) -> Bool {
        guard let course = source.course else { return false }
        return course.items.contains { item in
            item.deletedAt == nil && (item.status == .active || item.status == .suspended) && item.sourceRef?.sourceID == source.id
        }
    }

    // MARK: Threads

    /// A new, empty chat. The first question names it.
    @discardableResult
    func startChat(courseID: UUID?, title: String = "") -> ChatThread {
        let thread = ChatThread(courseID: liveCourse(courseID)?.id, title: title, mode: settings.effectiveTutorMode, now: now)
        context.insert(thread)
        save()
        return thread
    }

    /// The course (and so the material) a chat answers from; nil means every course.
    func setChatCourse(_ thread: ChatThread, to courseID: UUID?) {
        guard thread.modelContext != nil, thread.courseID != courseID else { return }
        thread.courseID = courseID
        thread.updatedAt = now
        save()
    }

    func renameChat(_ thread: ChatThread, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard thread.modelContext != nil, !clean.isEmpty, clean != thread.title else { return }
        thread.title = String(clean.prefix(80))
        save()
    }

    /// Hints first or Just explain, for every answer from now on. An under-18 account stays on hints first. The open
    /// chat records the mode too.
    func setTutorMode(_ mode: TutorMode, in thread: ChatThread? = nil) {
        guard !settings.isMinor || mode == .hints else { return }
        if settings.tutorMode != mode { settings.tutorMode = mode }
        if let thread, thread.modelContext != nil, thread.mode != mode {
            thread.mode = mode
            save()
        }
    }

    /// Deletes a chat and its messages for good (chats aren't synced, so there is no tombstone to keep).
    func deleteChat(_ thread: ChatThread) {
        guard thread.modelContext != nil else { return }
        for message in thread.messages { context.delete(message) }
        context.delete(thread)
        save()
    }

    func deleteAllChats() {
        for message in fetch(FetchDescriptor<ChatMessage>()) { context.delete(message) }
        for thread in fetch(FetchDescriptor<ChatThread>()) { context.delete(thread) }
        save()
    }

    // MARK: Messages

    /// The person's question, added to the chat (which takes its name from the first one).
    @discardableResult
    func addQuestion(_ text: String, to thread: ChatThread, contextItemID: UUID? = nil) -> ChatMessage? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, thread.modelContext != nil else { return nil }
        let message = ChatMessage(thread: thread, role: .user, text: clean, contextItemID: contextItemID,
                                  now: nextMessageTime(in: thread))
        context.insert(message)
        thread.messages.append(message)
        if thread.title.trimmingCharacters(in: .whitespaces).isEmpty { thread.title = Self.chatTitle(for: clean) }
        thread.updatedAt = now
        save()
        return message
    }

    /// Cap's answer, saved once it is complete (or as far as it got): the text, the citations that were checked
    /// against the person's material, and who answered (`cloud`, `onDevice` or `rules`).
    @discardableResult
    func saveAnswer(_ outcome: TutorOutcome, to thread: ChatThread, contextItemID: UUID? = nil) -> ChatMessage? {
        let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, thread.modelContext != nil else { return nil }
        let message = ChatMessage(thread: thread, role: .assistant, text: text, citations: outcome.citations,
                                  origin: outcome.origin.rawValue, contextItemID: contextItemID,
                                  now: nextMessageTime(in: thread))
        context.insert(message)
        thread.messages.append(message)
        thread.updatedAt = now
        save()
        return message
    }

    /// After the chat's last message, so the order holds even with a frozen clock.
    private func nextMessageTime(in thread: ChatThread) -> Date {
        let last = thread.messages.map(\.createdAt).max() ?? .distantPast
        return max(now, last.addingTimeInterval(0.001))
    }

    // MARK: Inputs for the tutor

    /// What `ai.tutor` needs for a chat: its messages (the last one the question), the course, and the material
    /// Cap may answer from. `lastQuestionAs` replaces the last question's words for the tutor only: the tutor finds
    /// its passages from the last question alone, so a reply that leans on the chat ("4", "Explain with an analogy")
    /// is sent in words that name what it's about.
    func tutorInput(for thread: ChatThread, context: TutorContext? = nil, preferring sourceID: UUID? = nil,
                    lastQuestionAs: String? = nil) -> TutorInput {
        var messages = thread.sortedMessages.map { TutorMessage(role: $0.role, text: $0.text) }
        if let lastQuestionAs, let i = messages.lastIndex(where: { $0.role == .user }) {
            messages[i].text = lastQuestionAs
        }
        let course = liveCourse(thread.courseID)
        return TutorInput(messages: messages, course: course?.name,
                          material: tutorMaterial(courseID: course?.id, preferring: sourceID), context: context)
    }

    /// "Explain my mistake": the question, the answer it expects and what the person gave.
    func mistakeContext(itemID: UUID, given: String) -> TutorContext? {
        guard let item = item(itemID), item.modelContext != nil else { return nil }
        return TutorContext(itemPrompt: item.prompt, expected: item.answer, given: given)
    }

    /// The question an "Explain my mistake" chat opens with. The sheet shows the mistake instead; the chat's history
    /// keeps this line.
    static func mistakeQuestion(given: String) -> String {
        let answer = given.trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? "I didn't know this one. What's the answer?" : "I answered “\(answer)”. What did I miss?"
    }

    /// A chat's name from its first question: "Mitosis vs cytokinesis" for a "difference between" question,
    /// otherwise the question itself, cut at a word.
    static func chatTitle(for question: String) -> String {
        var text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)difference between (.+?) and (.+?)[?.!]*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) {
            let first = String(text[a]).trimmingCharacters(in: .whitespaces)
            let second = String(text[b]).trimmingCharacters(in: .whitespaces)
            if first.split(separator: " ").count <= 4, second.split(separator: " ").count <= 4 {
                return Lexicon.capitalizedFirst("\(first) vs \(second)")
            }
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        let limit = 44
        guard text.count > limit else { return Lexicon.capitalizedFirst(text) }
        var cut = ""
        for word in text.split(separator: " ") {
            if cut.count + word.count + 1 > limit { break }
            cut += (cut.isEmpty ? "" : " ") + word
        }
        if cut.isEmpty { cut = String(text.prefix(limit)) }
        while let last = cut.last, ",;:".contains(last) { cut.removeLast() }
        return Lexicon.capitalizedFirst(cut) + "…"
    }

    // MARK: Citations

    /// The lines of a cited page that hold the quote, for the source page's highlight. Empty when the page is gone or
    /// the quote can't be placed on it: the page then opens unmarked rather than marked in the wrong place.
    func anchorIDs(for citation: Citation) -> [String] {
        guard let id = citation.sourceID, let source = source(id), source.deletedAt == nil,
              let index = citation.pageIndex, let page = source.pages.first(where: { $0.pageIndex == index })
        else { return [] }
        return Self.lineIDs(quoting: citation.quote, in: page.lines)
    }

    /// The lines that hold `quote`. In reading order first (the lines joined, the quote's span picks them); when the
    /// page is laid out in columns or wrapped bullets, the lines whose words are (nearly) all in the quote.
    nonisolated static func lineIDs(quoting quote: String, in lines: [TextLine]) -> [String] {
        var joined = ""
        var spans: [(id: String, range: Range<Int>)] = []
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if !joined.isEmpty { joined += " " }
            let start = joined.count
            joined += text
            spans.append((line.id, start..<joined.count))
        }
        if let range = HighlightMark.locate(quote, in: joined) {
            return spans.filter { $0.range.overlaps(range) }.map(\.id)
        }
        let quoteText = quote.lowercased()
        let quoteStems = Set(Lexicon.contentStems(quote))
        let punctuation = CharacterSet(charactersIn: "•-–—.,;:()").union(.whitespaces)
        return lines.filter { line in
            let stems = Set(Lexicon.contentStems(line.text))
            guard !stems.isEmpty else { return false }
            let shared = stems.intersection(quoteStems).count
            if stems.count >= 2 { return Double(shared) / Double(stems.count) >= 0.75 }
            // A one-word line counts only when all of it is in the quote ("of the cell.").
            let bare = line.text.lowercased().trimmingCharacters(in: punctuation)
            return shared == 1 && bare.count >= 3 && quoteText.contains(bare)
        }.map(\.id)
    }

    /// The cited passage a card rests on: the page (or lecture) whose quotes in the chat share the most of the
    /// card's words, when they share at least `threshold` of them. Nil: the card isn't linked to a source.
    nonisolated static func bestCitation(for card: GeneratedItem, in citations: [Citation],
                                         threshold: Double = 0.4) -> [Citation]? {
        let cardText = [card.prompt, card.answer, card.explanation].joined(separator: " ")
        var groups: [String: [Citation]] = [:]
        var order: [String] = []
        for citation in citations where citation.sourceID != nil {
            let key = "\(citation.sourceID?.uuidString ?? "")#\(citation.pageIndex.map(String.init) ?? "t\(Int(citation.start ?? 0))")"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(citation)
        }
        var best: (key: String, score: Double)?
        for key in order {
            let quotes = groups[key, default: []].map(\.quote).joined(separator: " ")
            let score = Lexicon.overlap(of: cardText, with: quotes)
            if score >= threshold, score > (best?.score ?? 0) { best = (key, score) }
        }
        return best.flatMap { groups[$0.key] }
    }

    // MARK: Cards from a chat

    /// Adds the cards the person kept in Make cards to a course, through `ItemFactory`. They go straight into the
    /// course (the person approved each one) and link back to the cited page or lecture moment they rest on, if any.
    @discardableResult
    func addCardsFromChat(_ cards: [GeneratedItem], origin: ItemOrigin, to courseID: UUID, from thread: ChatThread?) -> [StudyItem] {
        guard let course = liveCourse(courseID) else { return [] }
        let citations = (thread?.modelContext != nil ? thread?.sortedMessages.flatMap(\.citations) : nil) ?? []
        var made: [StudyItem] = []
        for var card in cards {
            card.prompt = card.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            card.answer = card.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !card.prompt.isEmpty, !card.answer.isEmpty else { continue }
            card.anchors = []
            var source: Source?
            var page: SourcePage?
            if let cited = Self.bestCitation(for: card, in: citations), let first = cited.first,
               let id = first.sourceID, let found = self.source(id), found.deletedAt == nil {
                source = found
                if let index = first.pageIndex, let p = found.pages.first(where: { $0.pageIndex == index }) {
                    page = p
                    var anchors: [String] = []
                    for c in cited { anchors += Self.lineIDs(quoting: c.quote, in: p.lines).filter { !anchors.contains($0) } }
                    card.anchors = anchors
                } else if found.kind == .lecture {
                    let segments = found.segments
                    var ids = segments.filter { s in cited.contains { HighlightMark.locate(s.text, in: $0.quote) != nil || HighlightMark.locate($0.quote, in: s.text) != nil } }.map(\.id)
                    if ids.isEmpty, let start = first.start, let s = segments.first(where: { $0.start <= start && start < $0.end + 1 }) {
                        ids = [s.id]
                    }
                    card.anchors = ids
                }
            }
            let topic = ItemFactory.topic(named: card.topic, in: course, now: now)
            let item = ItemFactory.makeItem(from: card, course: course, topicID: topic?.id, source: source, page: page,
                                            origin: origin, status: .active, now: now)
            context.insert(item)
            course.items.append(item)
            made.append(item)
        }
        guard !made.isEmpty else { return [] }
        save()
        return made
    }

    // MARK: Starters

    /// Three questions to start a chat with, drawn from the material Cap can read in the course (each one checked:
    /// the notes cover it). Off the main thread.
    func chatStarters(courseID: UUID?, limit: Int = 3) async -> [String] {
        let course = liveCourse(courseID)
        let scope = course.map { [$0] } ?? courses
        let material = tutorMaterial(courseID: course?.id)
        let confusions = scope.flatMap(\.confusions).filter { $0.deletedAt == nil && $0.status == .open }.map(\.name)
        return await Task.detached(priority: .userInitiated) {
            AskStarters.make(material: material, confusions: confusions, limit: limit)
        }.value
    }
}
