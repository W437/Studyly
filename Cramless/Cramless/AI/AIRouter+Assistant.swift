import Foundation

// Ask Cap as an assistant. The same ground rules as the tutor (the app finds the passages, the model answers only from
// them, a quote that isn't in the notes is never shown as one), plus tools. A reply is up to four rounds: the model answers
// or calls tools; the app runs each call (`AppModel+Assistant`, and the lookup and the web here) and sends the results
// back; the last round is Cap's short note. Everything the model drafts is shown to the student first.
//
// It runs only on the relay (the cloud tier of the tutor job: consent, an account that isn't under 13, within the free
// limit). Without that the tutor answers as before, and a reply that fails before anything is shown falls back to the
// tutor too, quietly. A reply that fails part way keeps what arrived and says so.

extension AIRouter {

    // MARK: Whether to try

    /// Ask Cap's assistant may answer this message: the cloud tier is open for the tutor, the relay has an assistant, and the
    /// message is not one the tutor refuses or an "explain my mistake" (those keep their own, measured, path).
    func assistantAvailable(question: String, hasContext: Bool) -> Bool {
        guard let app, !hasContext, transport != nil else { return false }
        if let retry = assistantRetryAt, retry > app.now { return false }
        if TutorPolicy.isRefused(question) || LocalTutor.isSmallTalk(question) { return false }
        return route(.tutor, content: question).usesCloud
    }

    /// Ask Cap's tools can be offered on the empty screen: the cloud is open (consent, a relay, an account that isn't a child's)
    /// and the relay has an assistant. No side effects, so a view may ask.
    var assistantReady: Bool {
        guard let app, cloudStillAllowed() else { return false }
        if let retry = assistantRetryAt, retry > app.now { return false }
        return true
    }

    // MARK: The reply

    /// Cap's reply as it happens: text and checked quotes as the tutor's, and steps that appear, work, and settle. Cancelling
    /// the consuming task cancels the request.
    func assistant(_ input: AssistantInput) -> AsyncStream<AssistantUpdate> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { continuation.finish(); return }
                await self.runAssistant(input) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole reply at once (tests).
    func assistantReply(_ input: AssistantInput) async -> AssistantOutcome? {
        var outcome: AssistantOutcome?
        for await update in assistant(input) {
            if case .finished(let o) = update { outcome = o }
        }
        return outcome
    }

    private func runAssistant(_ input: AssistantInput, emit: @escaping @MainActor (AssistantUpdate) -> Void) async {
        guard let app, let transport else { emit(.declined); return }
        let settings = app.settings
        let question = input.messages.last { $0.role == .user }?.text ?? ""
        let route = route(.tutor, content: question)
        guard route.usesCloud else { emit(.declined); return }
        let mode = route.forcedTutorMode ?? settings.effectiveTutorMode
        let material = input.material
        let retriever = await Task.detached(priority: .userInitiated) { LocalRetriever(material: material) }.value
        if Task.isCancelled { return }
        let retrieval = Self.retrieve(retriever, messages: input.messages, context: nil, limit: 6)
        let session = AssistantSession(index: app.studyIndex(currentCourseID: input.courseID), retriever: retriever,
                                       currentCourseID: input.courseID)
        session.send(retrieval.hits.map(\.passage))

        var turns: [AssistantTurn] = []
        var steps: [AssistantStep] = []
        var text = ""
        var citations: [Citation] = []
        var model = ""
        var limit: String?
        var started = false
        var reveals: [Task<Void, Never>] = []
        var failure: RelayError?
        func start() {
            if !started { emit(.started); started = true }
        }
        func upsert(_ step: AssistantStep) {
            if let i = steps.firstIndex(where: { $0.id == step.id }) { steps[i] = step } else { steps.append(step) }
            emit(.step(step))
        }

        rounds: for round in 0..<4 {
            if Task.isCancelled { return }
            let request = AssistantRequest(
                mode: mode, minor: settings.isMinor, course: input.courseName, messages: Array(input.messages.suffix(10)),
                sources: session.sources, context: nil, study: session.index.state, tools: app.assistantTools, turns: turns)
            var calls: [AssistantToolCall] = []
            var continuation: [AnyJSON] = []
            var stop = "end_turn"
            var openedText = false
            do {
                for try await event in transport.assistant(request) {
                    switch event {
                    case .start(let m):
                        if !m.isEmpty { model = m }
                    case .delta(let piece):
                        start()
                        if !openedText, round > 0, !text.isEmpty { text += "\n\n"; emit(.text("\n\n")) }
                        openedText = true
                        text += piece
                        emit(.text(piece))
                    case .citation(let sourceID, let label, let quote):
                        if let citation = Self.citation(sourceID: sourceID, label: label, quote: quote, sent: session.sent,
                                                        retriever: retriever, index: citations.count) {
                            start()
                            citations.append(citation)
                            emit(.citation(citation))
                        }
                    case .toolStart(let id, let name):
                        start()
                        if let tool = AssistantToolName(rawValue: name) {
                            upsert(Self.workingStep(id: id, tool: tool, session: session, app: app))
                        }
                    case .toolItem(let id, _, let item):
                        if let i = steps.firstIndex(where: { $0.id == id }) {
                            var step = steps[i]
                            Self.stream(item, into: &step)
                            upsert(step)
                        }
                    case .toolText(let id, let piece):
                        if let i = steps.firstIndex(where: { $0.id == id }) {
                            var step = steps[i]
                            Self.stream(text: piece, into: &step)
                            upsert(step)
                        }
                    case .toolCall(let id, let name, let arguments):
                        if let tool = AssistantToolName(rawValue: name) {
                            calls.append(AssistantToolCall(callID: id, name: tool, arguments: arguments))
                        }
                    case .done(let m, let s, let cont, let lim):
                        if !m.isEmpty { model = m }
                        stop = s
                        continuation = cont
                        limit = lim ?? limit
                    case .failure(let code, let message):
                        throw RelayError.from(code: code, message: message, quota: nil)
                    }
                }
            } catch {
                failure = HTTPRelayTransport.map(error)
                break rounds
            }
            if Task.isCancelled { return }
            guard stop == "tool_calls", !calls.isEmpty else { break rounds }

            // Do what each call asks, here, where the notes and the screens are.
            var results: [AssistantResult] = []
            for call in calls {
                let run: AssistantToolRun
                switch call.name {
                case .searchNotes:
                    run = await searchNotes(call, session: session)
                case .researchWeb:
                    run = await research(call, session: session, app: app) { upsert($0) }
                default:
                    run = app.runDraftTool(call, session: session)
                }
                results.append(AssistantResult(callId: call.callID, output: run.output))
                let frames = Self.reveal(run.step)
                if frames.isEmpty || assistantBeat == .zero {
                    upsert(run.step)
                } else {
                    // The checks play out while the next round is already on its way.
                    let beat = assistantBeat
                    let final = run.step
                    let tasks = frames
                    upsert(tasks[0])
                    reveals.append(Task { @MainActor in
                        for frame in tasks.dropFirst() {
                            try? await Task.sleep(for: beat)
                            if Task.isCancelled { return }
                            emit(.step(frame))
                        }
                        try? await Task.sleep(for: beat)
                        if Task.isCancelled { return }
                        emit(.step(final))
                    })
                    if let i = steps.firstIndex(where: { $0.id == final.id }) { steps[i] = final }
                }
            }
            turns.append(AssistantTurn(continuation: continuation, results: results))
        }
        for reveal in reveals { await reveal.value }
        if Task.isCancelled { return }

        if let failure {
            if !started {
                // Nothing reached the student. A relay with no assistant isn't asked again for a while; a free limit
                // is the tutor's to explain.
                if case .upstream(let message) = failure, message.contains("isn't set up") || message.contains("isn't available") {
                    assistantRetryAt = app.now.addingTimeInterval(600)
                }
                _ = absorbQuotaError(failure, meter: .tutor)
                emit(.declined)
                return
            }
            if failure == .cancelled { return }
            // A later round the day's limit refused (a cost cap crossed by the first round) is not a lost connection.
            var note = String(localized: "Cap lost the connection part way. This is what arrived.")
            if case .quotaExceeded = failure {
                note = String(localized: "That's all the cloud AI for today, so Cap stopped here. It starts again at midnight.")
            }
            let outcome = AssistantOutcome(text: text, citations: citations, steps: steps, model: model, interrupted: true,
                                           note: note, limit: limit)
            emit(.finished(outcome))
            return
        }
        if limit == "drafts" {
            // The model reached for a draft the day's allowance doesn't cover, and the relay stopped it there: the words are ours,
            // in the student's language (the card under them offers Pro). A lookup that began in the same round goes with it.
            steps.removeAll { $0.status == .working }
            let said = plan.isPaid ? String(localized: "That's all the drafts for today. They start again at midnight.")
                : String(localized: "I can't make anything new today.")
            start()
            if text.isEmpty { emit(.text(said)) }
            recordCloudUse(.tutor)
            emit(.finished(AssistantOutcome(text: said, citations: citations, steps: steps, model: model, limit: limit)))
            return
        }
        guard started else { emit(.declined); return }
        recordCloudUse(.tutor)
        emit(.finished(AssistantOutcome(text: text, citations: citations, steps: steps, model: model, limit: limit)))
    }

    // MARK: Steps while they are written

    /// The step for a call that has just begun: it exists as soon as the model starts writing it, so the student sees work
    /// happening.
    static func workingStep(id: String, tool: AssistantToolName, session: AssistantSession, app: AppModel) -> AssistantStep {
        let course = app.liveCourse(session.currentCourseID)
        let title: String
        let payload: AssistantPayload
        switch tool {
        case .searchNotes: (title, payload) = (String(localized: "Reading your notes"), .lookup(NotesLookup(query: "", hits: [])))
        case .createFlashcards: (title, payload) = (String(localized: "Writing flashcards"), .cards([]))
        case .createQuizQuestions: (title, payload) = (String(localized: "Writing questions"), .questions([]))
        case .createNote: (title, payload) = (String(localized: "Writing a note"), .note(NoteDraft(title: String(localized: "New note"), body: "")))
        case .createExam: (title, payload) = (String(localized: "Planning an exam"), .none)
        case .startPractice: (title, payload) = (String(localized: "Setting up practice"), .none)
        case .openScreen: (title, payload) = (String(localized: "Finding the screen"), .none)
        case .researchWeb: (title, payload) = (String(localized: "Searching the web"), .research(ResearchResult(topic: "")))
        }
        return AssistantStep(id: id, tool: tool, status: .working, courseID: course?.id, courseName: course?.name ?? "",
                             title: title, payload: payload)
    }

    /// A card or question the model has just finished writing, added to its step (not yet checked).
    static func stream(_ item: AnyJSON, into step: inout AssistantStep) {
        switch step.payload {
        case .cards(var cards):
            guard let front = item["front"]?.string, let back = item["back"]?.string else { return }
            cards.append(CardDraft(id: ModelID.make(), front: front.clTrimmed, back: back.clTrimmed, basis: .checking))
            step.payload = .cards(cards)
            step.title = String(localized: "\(CLFormat.count(cards.count, "flashcard")) so far")
        case .questions(var questions):
            guard let prompt = item["question"]?.string, let answer = item["answer"]?.string else { return }
            let kind: QuestionDraft.Kind = item["type"]?.string == "multiple_choice" ? .multipleChoice
                : item["type"]?.string == "fill_blank" ? .fillBlank : .shortAnswer
            questions.append(QuestionDraft(id: ModelID.make(), kind: kind, prompt: prompt.clTrimmed, answer: answer.clTrimmed,
                                           choices: item["options"]?.array?.compactMap(\.string) ?? [], basis: .checking))
            step.payload = .questions(questions)
            step.title = String(localized: "\(CLFormat.count(questions.count, "question")) so far")
        default:
            break
        }
    }

    /// More of a note's body.
    static func stream(text piece: String, into step: inout AssistantStep) {
        guard case .note(var note) = step.payload else { return }
        note.body += piece
        step.payload = .note(note)
    }

    /// The frames of a step being checked: the drafts' checks come in one at a time, then the step as it is. Empty when there is
    /// nothing worth staging (a lookup, one card).
    static func reveal(_ step: AssistantStep) -> [AssistantStep] {
        func frames<D>(_ drafts: [D], with make: ([D]) -> AssistantPayload, unresolved: (D) -> D) -> [AssistantStep] {
            guard drafts.count >= 2 else { return [] }
            var out: [AssistantStep] = []
            for upTo in 0..<drafts.count {
                var frame = step
                frame.status = .working
                frame.checking = true
                frame.payload = make(drafts.enumerated().map { $0.offset < upTo ? $0.element : unresolved($0.element) })
                out.append(frame)
            }
            return out
        }
        switch step.payload {
        case .cards(let drafts):
            return frames(drafts, with: { .cards($0) }, unresolved: { var d = $0; d.basis = .checking; return d })
        case .questions(let drafts):
            return frames(drafts, with: { .questions($0) }, unresolved: { var d = $0; d.basis = .checking; return d })
        default:
            return []
        }
    }

    // MARK: Looking up the notes

    private func searchNotes(_ call: AssistantToolCall, session: AssistantSession) async -> AssistantToolRun {
        // (What the model reads: the student's card says only that the lookup didn't work.)
        func fail(_ message: String) -> AssistantToolRun {
            AssistantToolRun(
                step: AssistantStep(id: call.callID, tool: call.name, status: .failed, title: String(localized: "Couldn't look that up"),
                                    detail: nil, payload: .none),
                output: AnyJSON.result(["error": .string(message)]).jsonString)
        }
        let query = call.arguments["query"]?.string?.clTrimmed ?? ""
        guard !query.isEmpty, let app else { return fail("Say what to look for.") }
        var retriever = session.retriever
        var scope = ""
        if let short = call.arguments["course_id"]?.string {
            guard let id = session.index.course(short), let course = app.liveCourse(id) else {
                return fail("That course id doesn't exist. The courses are: \(session.index.courseList).")
            }
            scope = course.name
            if id != session.currentCourseID {
                let material = app.tutorMaterial(courseID: id)
                retriever = await Task.detached(priority: .userInitiated) { LocalRetriever(material: material) }.value
            }
        } else if session.currentCourseID != nil {
            let material = app.tutorMaterial(courseID: nil)
            retriever = await Task.detached(priority: .userInitiated) { LocalRetriever(material: material) }.value
        }
        var found = retriever.search(query, limit: 6).map(\.passage)
        // A source's name finds its passages too: "Lecture 6", "the week 5 slides".
        let folded = AssistantDrafts.fold(query)
        for passage in retriever.passages where found.count < 6 && !found.contains(where: { $0.key == passage.key }) {
            let head = AssistantDrafts.fold(passage.title.split(separator: ":").first.map(String.init) ?? passage.title)
            if head.count >= 4, folded.contains(head) { found.append(passage) }
        }
        let sent = session.send(found)
        let passages: [AnyJSON] = sent.map { id, p in
            .object(["id": .string(id), "label": .string(p.label), "text": .string(String(p.text.prefix(900)))])
        }
        let hits = sent.map { NotesLookup.Hit(label: $0.passage.label, preview: String($0.passage.text.prefix(90))) }
        let title = hits.isEmpty ? String(localized: "Nothing in your notes for “\(query)”") : String(localized: "Read \(CLFormat.count(hits.count, "passage"))")
        let step = AssistantStep(id: call.callID, tool: .searchNotes, status: .done, courseName: scope, title: title,
                                 payload: .lookup(NotesLookup(query: query, hits: hits)))
        return AssistantToolRun(step: step, output: AnyJSON.result(["passages": .array(passages)]).jsonString)
    }

    // MARK: Looking things up on the web

    /// Web research from trusted study sites, shown as it happens: what is searched, the pages found, the summary writing itself,
    /// the pages it rests on. The summary becomes a note only when the student taps to save it.
    private func research(_ call: AssistantToolCall, session: AssistantSession, app: AppModel,
                          update: @escaping @MainActor (AssistantStep) -> Void) async -> AssistantToolRun {
        let topic = call.arguments["topic"]?.string?.clTrimmed ?? ""
        let course = app.liveCourse(session.currentCourseID) ?? app.liveCourse(app.defaultChatCourseID)
        var step = AssistantStep(id: call.callID, tool: .researchWeb, status: .working, courseID: course?.id,
                                 courseName: course?.name ?? "", title: topic, payload: .research(ResearchResult(topic: topic)))
        func failed(_ message: String, needsPro: Bool = false) -> AssistantToolRun {
            step.status = .failed
            step.detail = message
            step.needsPro = needsPro
            step.title = topic.isEmpty ? String(localized: "Web research") : topic
            return AssistantToolRun(step: step, output: AnyJSON.result(["error": .string(message)]).jsonString)
        }
        guard app.settings.assistantWeb else { return failed(String(localized: "Web research is off in Settings.")) }
        guard !topic.isEmpty, let transport else { return failed(String(localized: "Say what to research.")) }
        var result = ResearchResult(topic: topic)
        step.payload = .research(result)
        update(step)
        let request = ResearchRequest(minor: app.settings.isMinor, topic: topic,
                                      focus: call.arguments["focus"]?.string?.clTrimmed.clNonEmpty, course: course?.name)
        do {
            for try await event in transport.research(request) {
                switch event {
                case .start:
                    break
                case .search(_, let phase, let queries, let sources):
                    result.phase = phase == .done ? .reading : .searching
                    for q in queries where !result.queries.contains(q) { result.queries.append(q) }
                    for s in sources where !result.sources.contains(where: { $0.url == s.url }) {
                        result.sources.append(WebSource(url: s.url, domain: s.domain, title: nil))
                    }
                case .delta(let piece):
                    result.phase = .writing
                    result.text += piece
                case .citation(let url, let title, let domain):
                    let source = WebSource(url: url, domain: domain, title: title)
                    if let i = result.sources.firstIndex(where: { $0.url == url }) { result.sources[i].title = title }
                    if !result.cited.contains(where: { $0.url == url }) { result.cited.append(source) }
                case .done:
                    result.phase = .done
                case .failure(let code, let message):
                    throw RelayError.from(code: code, message: message, quota: nil)
                }
                step.payload = .research(result)
                update(step)
            }
        } catch {
            switch HTTPRelayTransport.map(error) {
            case .entitlementRequired:
                return failed(String(localized: "Web research is part of Capling Pro."), needsPro: true)
            case .quotaExceeded:
                return failed(String(localized: "That's all the web research for today. It resets at midnight."))
            case .offline:
                return failed(String(localized: "You're offline, so Cap can't look it up."))
            case .cancelled:
                return failed(String(localized: "Stopped."))
            case .upstream(let message) where message.contains("couldn't find anything"):
                return failed(message)
            default:
                return failed(String(localized: "Cap couldn't reach the web right now. Try again in a moment."))
            }
        }
        guard !result.text.clTrimmed.isEmpty else { return failed(String(localized: "Nothing came back for that.")) }
        result.phase = .done
        step.status = .proposed
        step.title = topic
        step.payload = .research(result)
        // Never saved on its own, whatever "Let Cap do it" says: a page's words are not the student's, so the student decides.
        let out: [String: AnyJSON] = ["status": .string("researched"), "sources": .number(Double(result.cited.count)),
                                        "note": .string("The student sees the cited summary and can save it as a note.")]
        return AssistantToolRun(step: step, output: AnyJSON.result(out).jsonString)
    }
}
