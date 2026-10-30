import Foundation

// The tutor. The app finds the passages (`LocalRetriever`); every tier answers only from them, and a citation
// becomes a `Citation` only if its quote is really in the person's material. With nothing in the notes to answer
// from, no model is asked: Cap says the notes don't cover it. Under-18 accounts are always on hints first and the
// relay is told `minor: true`. Order: the relay, then this iPhone's model (short questions), then the offline tutor.
// A cloud answer that breaks off part way keeps what arrived and says so; it never restarts on another tier.

extension AIRouter {

    /// Cap's answer as it arrives: `.started` with the first words (once), then text pieces and citations, then
    /// `.finished` with the whole answer. Cancelling the consuming task cancels the request.
    func tutor(_ input: TutorInput) -> AsyncStream<TutorUpdate> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { continuation.finish(); return }
                await self.runTutor(input) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole answer at once.
    func tutorReply(_ input: TutorInput) async -> TutorOutcome? {
        var outcome: TutorOutcome?
        for await update in tutor(input) {
            if case .finished(let o) = update { outcome = o }
        }
        return outcome
    }

    private func runTutor(_ input: TutorInput, emit: @escaping @MainActor (TutorUpdate) -> Void) async {
        let userTurns = input.messages.filter { $0.role == .user }.map(\.text)
        let question = userTurns.last ?? ""
        let asked = input.context.map { "\($0.itemPrompt) \($0.expected) \(question)" } ?? question
        let material = input.material
        let retriever = await Task.detached(priority: .userInitiated) { LocalRetriever(material: material) }.value
        let retrieval = Self.retrieve(retriever, messages: input.messages, context: input.context, limit: 4)
        let hits = retrieval.hits
        let searchText = retrieval.searchText
        let terms = retriever.weightedTerms(searchText)
        let sources = hits.enumerated().map { n, hit in
            TutorSource(id: "s\(n + 1)", title: hit.passage.title, label: hit.passage.label, text: hit.passage.text)
        }
        let sent = Dictionary(uniqueKeysWithValues: zip(sources.map(\.id), hits.map(\.passage)))

        // Read after the retrieval wait: who is asking, and how Cap may answer.
        let settings = app?.settings ?? AppSettings()
        let route = route(.tutor, content: asked)
        let mode = route.forcedTutorMode ?? settings.effectiveTutorMode
        let local = LocalTutor.reply(question: question, mode: mode, hits: hits, context: input.context, terms: terms)

        var fellBack = false
        var cloudFailed = false
        var limitReached = route.limitReached
        // Grounded or silent: a refused request, small talk, or notes that don't cover it never reach a model.
        if local.grounded {
            tiers: for tier in route.tiers {
                if Task.isCancelled { return }
                switch tier {
                case .cloud:
                    cloudFailed = true
                    cloudRefused = false
                    switch await cloudTutor(input, mode: mode, minor: settings.isMinor, sources: sources, sent: sent,
                                            retriever: retriever, fellBack: fellBack, emit: emit) {
                    case .success: return
                    case .limit(let key):
                        limitReached = key
                        fellBack = true
                        cloudFailed = false   // not a failure: the free limit, which the suggestion explains
                        break tiers
                    case .failed:
                        fellBack = true
                    }
                case .onDevice, .privateCloud:
                    if await onDeviceTutor(question, mode: mode, sources: Array(sources.prefix(3)), sent: sent,
                                           retriever: retriever, context: input.context, tier: tier, fellBack: fellBack,
                                           suggestion: route.suggestion, emit: emit) {
                        return
                    }
                    fellBack = true
                case .rules:
                    break
                }
            }
        }

        // The offline tutor.
        emit(.started(origin: .rules))
        for piece in Self.pieces(of: local.text) {
            if Task.isCancelled { return }
            emit(.text(piece))
            await pause()
        }
        var citations: [Citation] = []
        for quote in local.quotes {
            guard let passage = hits.first(where: { $0.passage.key == quote.passageKey })?.passage else { continue }
            let citation = Citation(id: "r\(citations.count + 1)", sourceID: passage.sourceID, pageIndex: passage.pageIndex,
                                    start: passage.start, quote: quote.text, label: passage.label)
            citations.append(citation)
            emit(.citation(citation))
        }
        let suggestion = route.suggestion ?? limitReached.map(limitSuggestion)
        emit(.finished(TutorOutcome(text: local.text, citations: citations, origin: .rules, model: LocalGrader.model, mode: mode,
                                    grounded: local.grounded,
                                    note: cloudFailed && local.grounded ? failureNote(refused: cloudRefused) : nil,
                                    suggestion: local.grounded ? suggestion : nil, limitReached: limitReached, fellBack: fellBack)))
    }

    /// What the note under an offline answer says when the cloud was tried and didn't answer: the relay's refusal for the day (a paid
    /// plan's fair use, or the day's cost cap, which every plan has) or, otherwise, that it couldn't be reached.
    private func failureNote(refused: Bool) -> String {
        refused
            ? String(localized: "That's all the cloud AI for today, so Cap answered from your notes on this iPhone. It starts again at midnight.")
            : "Cloud AI couldn't be reached, so Cap answered from your notes on this iPhone."
    }

    /// The passages for a chat's last question. A follow-up ("why?", "and in plants?") carries few topic words of its own:
    /// when the question alone finds nothing, or is a few words long, the last two questions and Cap's last answer are
    /// searched with it.
    struct Retrieval {
        var hits: [LocalRetriever.Hit]
        var searchText: String
    }

    static func retrieve(_ retriever: LocalRetriever, messages: [TutorMessage], context: TutorContext?, limit: Int) -> Retrieval {
        let userTurns = messages.filter { $0.role == .user }.map(\.text)
        let question = userTurns.last ?? ""
        let asked = context.map { "\($0.itemPrompt) \($0.expected) \(question)" } ?? question
        var searchText = asked
        var hits = retriever.search(asked, limit: limit)
        let wordCount = question.split(whereSeparator: { $0.isWhitespace }).count
        if userTurns.count > 1, hits.isEmpty || wordCount <= 4 {
            let earlier = userTurns.dropLast().suffix(2).joined(separator: " ")
            let lastAnswer = String((messages.last { $0.role == .assistant }?.text ?? "").prefix(400))
            searchText = [asked, earlier, lastAnswer].filter { !$0.isEmpty }.joined(separator: " ")
            let widened = retriever.search(searchText, limit: limit)
            if !widened.isEmpty { hits = widened }
        }
        return Retrieval(hits: hits, searchText: searchText)
    }

    // MARK: Cloud

    private func cloudTutor(_ input: TutorInput, mode: TutorMode, minor: Bool, sources: [TutorSource],
                            sent: [String: LocalRetriever.Passage], retriever: LocalRetriever, fellBack: Bool,
                            emit: @MainActor (TutorUpdate) -> Void) async -> Attempt<Void> {
        guard cloudStillAllowed(), let transport else { return .failed }
        let request = TutorRequest(mode: mode, minor: minor, course: input.course, messages: Array(input.messages.suffix(8)),
                                   sources: sources, context: input.context)
        var text = ""
        var citations: [Citation] = []
        var model = ""
        var started = false
        func start() {
            if !started { emit(.started(origin: .cloud)); started = true }
        }
        func finish(interrupted: Bool, note: String?) {
            emit(.finished(TutorOutcome(text: text, citations: citations, origin: .cloud, model: model, mode: mode,
                                        grounded: !citations.isEmpty, interrupted: interrupted, note: note, fellBack: fellBack)))
        }
        do {
            for try await event in transport.tutor(request) {
                switch event {
                case .start(let m):
                    model = m
                case .delta(let piece):
                    start()
                    text += piece
                    emit(.text(piece))
                case .citation(let sourceID, let label, let quote):
                    if let citation = Self.citation(sourceID: sourceID, label: label, quote: quote, sent: sent,
                                                    retriever: retriever, index: citations.count) {
                        start()
                        citations.append(citation)
                        emit(.citation(citation))
                    }
                case .done(let m):
                    if !m.isEmpty { model = m }
                    guard started else { return .failed }
                    recordCloudUse(.tutor)
                    finish(interrupted: false, note: nil)
                    return .success(())
                case .failure(let code, let message):
                    let error = RelayError.from(code: code, message: message, quota: nil)
                    guard started else {
                        if let key = absorbQuotaError(error, meter: .tutor) { return .limit(key) }
                        return .failed
                    }
                    finish(interrupted: true, note: "Cap lost the connection part way. This is what arrived.")
                    return .success(())
                }
            }
            guard started else { return .failed }
            finish(interrupted: true, note: "Cap lost the connection part way. This is what arrived.")
            return .success(())
        } catch {
            let relay = HTTPRelayTransport.map(error)
            if relay == .cancelled {
                if started { finish(interrupted: true, note: nil) }
                return .success(())
            }
            guard started else {
                if let key = absorbQuotaError(relay, meter: .tutor) { return .limit(key) }
                return .failed
            }
            finish(interrupted: true, note: "Cap lost the connection part way. This is what arrived.")
            return .success(())
        }
    }

    /// A tier's citation as the app's `Citation`, through the passages sent: the quote must be in the passage the
    /// model named, or else somewhere in the person's material (then that passage is credited). Otherwise it is
    /// dropped: a quote that isn't in their notes is never shown as one.
    static func citation(sourceID: String, label: String, quote: String, sent: [String: LocalRetriever.Passage],
                         retriever: LocalRetriever, index: Int) -> Citation? {
        let q = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 4 else { return nil }
        let named = sent[sourceID]
        let candidates = (named.map { [$0] } ?? []) + sent.values.sorted { $0.key < $1.key } + retriever.passages
        guard let passage = candidates.first(where: { HighlightMark.locate(q, in: $0.text) != nil }) else { return nil }
        return Citation(id: "\(sourceID)-\(index + 1)", sourceID: passage.sourceID, pageIndex: passage.pageIndex,
                        start: passage.start, quote: q, label: passage.label)
    }

    // MARK: On device

    private func onDeviceTutor(_ question: String, mode: TutorMode, sources: [TutorSource], sent: [String: LocalRetriever.Passage],
                               retriever: LocalRetriever, context: TutorContext?, tier: AITier, fellBack: Bool,
                               suggestion: AISuggestion?, emit: @MainActor (TutorUpdate) -> Void) async -> Bool {
        // Short help only: a long question goes to the offline tutor rather than a cramped prompt.
        guard question.split(whereSeparator: \.isWhitespace).count <= 40, !sources.isEmpty else { return false }
        let call = OnDeviceTutorCall(question: question, mode: mode, passages: sources, context: context)
        guard let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget),
              let reply = OnDeviceTutoring.reply(from: output, passages: sources) else { return false }
        // Hints first means a question back, never the answer: measured, the small model often states the answer
        // in hints mode. Then the offline tutor's hint (a guiding question with the citation) answers instead.
        if mode == .hints, !reply.text.contains("?") { return false }
        recordOnDeviceUse(.tutor)
        emit(.started(origin: .onDevice))
        for piece in Self.pieces(of: reply.text) {
            if Task.isCancelled { return true }
            emit(.text(piece))
            await pause()
        }
        var citations: [Citation] = []
        for quote in reply.quotes {
            if let citation = Self.citation(sourceID: quote.source.id, label: quote.source.label, quote: quote.quote,
                                            sent: sent, retriever: retriever, index: citations.count) {
                citations.append(citation)
                emit(.citation(citation))
            }
        }
        emit(.finished(TutorOutcome(text: reply.text, citations: citations, origin: .onDevice, model: "on-device", mode: mode,
                                    grounded: !citations.isEmpty, suggestion: suggestion, fellBack: fellBack)))
        return true
    }
}
