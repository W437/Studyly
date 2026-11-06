import Foundation

// The tutor. The app finds the passages (`LocalRetriever`, `TutorSelection`); every tier answers only from them, and a
// citation becomes a `Citation` only if its quote is really in the person's material. Order: the relay, then this iPhone's
// model (short questions), then the offline tutor.
//
// Who is asked what:
//   - A request Cap declines (an essay, an exam), small talk, an everyday question and an empty library are answered here, at
//     once, and no model is asked.
//   - The relay is handed the person's material (all of it when it is not much, else the best of it: `TutorSelection`) and
//     decides whether it covers the question: the keywords can't, and said "your notes don't cover that" when they did.
//     Its answer is still only from those passages, and a quote that isn't in the notes is dropped. When a line of the notes
//     talks to an assistant, the relay's prompt has the model say so itself (once, in its own words), so the app adds nothing.
//   - This iPhone's model and the offline tutor have no way to judge, so they answer only what the keywords find
//     (`LocalTutor.Reply.grounded`), and a quote from this iPhone's model must come from a passage that is about the question.
//     They have no model to say it either, so they add the app's own sentence about such a line.
// Under-18 accounts are always on hints first and the relay is told `minor: true`. A cloud answer that breaks off part way
// keeps what arrived and says so; it never restarts on another tier.

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
        let terms = retriever.weightedTerms(retrieval.searchText)
        // The nearest passages: for this iPhone's model (a small window), for the offline tutor, and to credit a quote.
        let near = hits.enumerated().map { n, hit in
            TutorSource(id: "s\(n + 1)", title: hit.passage.title, label: hit.passage.label, text: hit.passage.text)
        }
        let nearSent = Dictionary(uniqueKeysWithValues: zip(near.map(\.id), hits.map(\.passage)))

        // Read after the retrieval wait: who is asking, and how Cap may answer.
        let settings = app?.settings ?? AppSettings()
        let route = route(.tutor, content: asked)
        let mode = route.forcedTutorMode ?? settings.effectiveTutorMode
        let topic = Self.redirectTopic(course: input.course, hits: hits, retriever: retriever)
        func offline(limit: Bool, ranking: OfflineRanking? = nil) -> LocalTutor.Reply {
            LocalTutor.reply(question: question, mode: mode, hits: hits, context: input.context, terms: terms,
                             hasMaterial: !retriever.passages.isEmpty, topic: topic, limitReached: limit, ranking: ranking)
        }
        var local = offline(limit: route.limitReached == .tutor)
        // What the relay is handed. Nothing for a question no model is asked, and nothing for a large material the question
        // shares no word with.
        let selection = local.asksAModel
            ? TutorSelection.select(retriever: retriever, searchText: retrieval.searchText, titleText: retrieval.studentText,
                                    earlier: retrieval.earlier)
            : TutorSelection.Selection.none
        // A line of the notes written to an assistant, among the passages this answer rests on: this iPhone's model and the offline
        // tutor say so, once, first. (The cloud's model says it itself, so its answers get no second sentence.)
        let notice = local.asksAModel && hits.contains { TutorPolicy.looksLikeInstruction($0.passage.text) }
            ? TutorPolicy.instructionNotice : nil

        // The sentence search (`OfflineSearch`) reads the whole library, so it is made once, when the first tier that needs it asks, off the
        // main thread since the first search of a launch loads a model. It picks what this iPhone's model reads and what the offline tutor shows.
        var ranking: OfflineRanking?
        func rankOnce() async -> OfflineRanking {
            if let ranking { return ranking }
            let earlier = Array(userTurns.dropLast())
            let options = offlineSearch
            let made = await Task.detached(priority: .userInitiated) { retriever.rankSentences(for: asked, earlier: earlier, options: options) }.value
            ranking = made
            return made
        }

        // This iPhone's model chooses, among the search's best sentences, the one that answers (`OnDevicePickCall`); that sentence is shown first, by this
        // tier's window and by the offline tutor behind it. Once per question, and only when the search is convinced the notes cover it (the model
        // cannot say that they do not).
        var pickedOnce = false
        func choosing(_ base: OfflineRanking, tier: AITier) async -> OfflineRanking {
            if pickedOnce { return ranking ?? base }
            pickedOnce = true
            let shown = Array(base.candidates.prefix(OnDeviceWindow.pickAmong))
            guard OnDeviceWindow.useModelPick, base.isConvincing, shown.count >= 2 else { return base }
            let earlier = LocalTutor.isFollowUp(question) ? userTurns.dropLast().last : nil
            let call = OnDevicePickCall(question: question, earlier: earlier, sentences: shown.map(\.sentence))
            guard let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget),
                  (2...shown.count).contains(output.number) else { return base }
            var better = base
            better.candidates.insert(better.candidates.remove(at: output.number - 1), at: 0)
            better.alsoClose = nil
            ranking = better
            return better
        }

        var fellBack = false
        var cloudFailed = false
        var limitReached = route.limitReached
        tiers: for tier in route.tiers {
            if Task.isCancelled { return }
            switch tier {
            case .cloud:
                guard !selection.isEmpty else { continue }
                cloudFailed = true
                cloudRefused = false
                switch await cloudTutor(input, mode: mode, minor: settings.isMinor, selection: selection, retriever: retriever,
                                        fellBack: fellBack, emit: emit) {
                case .success: return
                case .limit(let key):
                    limitReached = key
                    fellBack = true
                    cloudFailed = false   // not a failure: the free limit, which the suggestion explains; this iPhone's model is tried next
                case .failed:
                    fellBack = true
                }
            case .onDevice, .privateCloud:
                // Grounded or silent: this iPhone's model has no way to tell that the notes don't cover a question.
                var window = Array(near.prefix(3))
                var windowSent = nearSent
                var grounded = local.grounded
                var closest: [String] = []
                // The passages it reads are the ones that hold the sentences answering best (the sentence search found the line the question
                // meant for far more questions than the first keyword hits did), and a sentence the search is convincing about is grounding.
                if OnDeviceWindow.useSentenceSearch, local.asksAModel {
                    var ranked = await rankOnce()
                    if Task.isCancelled { return }
                    ranked = await choosing(ranked, tier: tier)
                    if Task.isCancelled { return }
                    if ranked.isConvincing {
                        let picked = OnDeviceWindow.passages(ranking: ranked, keyword: hits.map(\.passage))
                        if !picked.isEmpty {
                            window = picked.enumerated().map { n, p in TutorSource(id: "s\(n + 1)", title: p.title, label: p.label, text: p.text) }
                            windowSent = Dictionary(uniqueKeysWithValues: zip(window.map(\.id), picked))
                            closest = OnDeviceWindow.closest(in: ranked)
                            grounded = true
                        }
                    }
                }
                guard grounded else { continue }
                // A line written to an assistant among the passages it reads is said once, whichever passages those are.
                let windowNotice = window.contains { TutorPolicy.looksLikeInstruction($0.text) } ? TutorPolicy.instructionNotice : notice
                if await onDeviceTutor(question, mode: mode, sources: window, sent: windowSent, retriever: retriever,
                                       context: input.context, terms: terms, closest: closest, tier: tier, fellBack: fellBack,
                                       suggestion: limitReached.map(limitSuggestion) ?? route.suggestion, limitReached: limitReached,
                                       notice: windowNotice, emit: emit) {
                    return
                }
                fellBack = true
            case .rules:
                break
            }
        }

        // The offline tutor. Until now the keyword hits only decided whom to ask; here the whole library is searched sentence by
        // sentence for the one that answers (`OfflineSearch`), off the main thread, since the first search of a launch loads a model.
        // When the relay is what said the free limit is reached, its words are the limit's too.
        if local.asksAModel {
            _ = await rankOnce()
            if Task.isCancelled { return }
        }
        if ranking != nil || (limitReached == .tutor && route.limitReached == nil) {
            local = offline(limit: limitReached == .tutor, ranking: ranking)
        }
        // A line written to an assistant in the passages the answer comes from is said once, as for the tiers above.
        let answered = ranking.flatMap { $0.isConvincing ? Array($0.candidates.prefix(3)) : nil } ?? []
        let rulesNotice = notice ?? (local.asksAModel && answered.contains { TutorPolicy.looksLikeInstruction($0.passage.text) }
                                     ? TutorPolicy.instructionNotice : nil)
        let text = (rulesNotice.map { $0 + "\n\n" } ?? "") + local.text
        emit(.started(origin: .rules))
        for piece in Self.pieces(of: text) {
            if Task.isCancelled { return }
            emit(.text(piece))
            await pause()
        }
        var citations: [Citation] = []
        for quote in local.quotes {
            guard let passage = hits.first(where: { $0.passage.key == quote.passageKey })?.passage
                    ?? retriever.passage(forKey: quote.passageKey) else { continue }
            let citation = Citation(id: "r\(citations.count + 1)", sourceID: passage.sourceID, pageIndex: passage.pageIndex,
                                    start: passage.start, quote: quote.text, label: passage.label)
            citations.append(citation)
            emit(.citation(citation))
        }
        // A question the keywords couldn't place is still worth the cloud's second look, so the offer (consent, or the paywall
        // when the free limit is what stopped it) goes with "not covered" too, when there is something to hand the cloud; not
        // with a decline, small talk or a redirect.
        let suggestion = route.suggestion ?? limitReached.map(limitSuggestion)
        let offersMore = local.kind == .answer || (local.kind == .notCovered && (!selection.isEmpty || limitReached != nil))
        emit(.finished(TutorOutcome(text: text, citations: citations, origin: .rules, model: LocalGrader.model, mode: mode,
                                    grounded: local.grounded,
                                    note: cloudFailed && local.asksAModel ? failureNote(refused: cloudRefused) : nil,
                                    suggestion: offersMore ? suggestion : nil, limitReached: limitReached, fellBack: fellBack)))
    }

    /// What an everyday question is pointed back to: the course, else the name of the nearest source, else the first.
    static func redirectTopic(course: String?, hits: [LocalRetriever.Hit], retriever: LocalRetriever) -> String? {
        if let course = course?.trimmingCharacters(in: .whitespacesAndNewlines), !course.isEmpty { return course }
        let title = hits.first?.passage.title ?? retriever.passages.first?.title
        return title.map(ItemFactory.shortTitle)
    }

    /// What the note under an offline answer says when the cloud was tried and didn't answer: the relay's refusal for the day (a paid
    /// plan's fair use, or the day's cost cap, which every plan has) or, otherwise, that it couldn't be reached.
    private func failureNote(refused: Bool) -> String {
        refused
            ? AIFreeLimits.costCapTutorNote
            : "Cloud AI couldn't be reached, so Cap answered from your notes on this iPhone."
    }

    /// The passages for a chat's last question. A follow-up ("why?", "and in plants?") carries few topic words of its own:
    /// when the question alone finds nothing, or is a few words long, the last two questions and Cap's last answer are
    /// searched with it.
    struct Retrieval {
        var hits: [LocalRetriever.Hit]
        var searchText: String
        /// The student's own words in `searchText`: this question, and the ones before it when it leans on them, never Cap's
        /// last answer. What a source's title is compared with (`TutorSelection.select`).
        var studentText: String
        /// What the chat said before this question, apart: the last two questions before it, the latest first, then Cap's last
        /// answer (its start). A material too long to go whole keeps the best passages of each in the request
        /// (`TutorSelection.select`), so a follow-up does not lose the passages the answer before it stood on.
        var earlier: [String] = []
    }

    static func retrieve(_ retriever: LocalRetriever, messages: [TutorMessage], context: TutorContext?, limit: Int) -> Retrieval {
        let userTurns = messages.filter { $0.role == .user }.map(\.text)
        let question = userTurns.last ?? ""
        let asked = context.map { "\($0.itemPrompt) \($0.expected) \(question)" } ?? question
        var searchText = asked
        var studentText = asked
        var hits = retriever.search(asked, limit: limit)
        let wordCount = question.split(whereSeparator: { $0.isWhitespace }).count + Lexicon.cjkWords(in: question)
        if userTurns.count > 1, hits.isEmpty || wordCount <= 4 {
            let earlier = userTurns.dropLast().suffix(2).joined(separator: " ")
            let lastAnswer = String((messages.last { $0.role == .assistant }?.text ?? "").prefix(400))
            searchText = [asked, earlier, lastAnswer].filter { !$0.isEmpty }.joined(separator: " ")
            studentText = [asked, earlier].filter { !$0.isEmpty }.joined(separator: " ")
            let widened = retriever.search(searchText, limit: limit)
            if !widened.isEmpty { hits = widened }
        }
        var before = Array(userTurns.dropLast().suffix(2).reversed())
        if let answer = messages.last(where: { $0.role == .assistant })?.text.prefix(400), !answer.isEmpty {
            before.append(String(answer))
        }
        return Retrieval(hits: hits, searchText: searchText, studentText: studentText, earlier: before)
    }

    // MARK: Cloud

    /// What one pass at the relay came to: an answer or a failure, or the relay turning the request down for its size.
    private enum CloudStep {
        case finished(Attempt<Void>)
        /// `bad_request` before anything arrived, for a request with more passages than a relay that doesn't yet take the new
        /// limit allows: ask again with fewer.
        case tooManySources
    }

    private func cloudTutor(_ input: TutorInput, mode: TutorMode, minor: Bool, selection: TutorSelection.Selection,
                            retriever: LocalRetriever, fellBack: Bool,
                            emit: @MainActor (TutorUpdate) -> Void) async -> Attempt<Void> {
        guard cloudStillAllowed(), let transport else { return .failed }
        let materials = TutorMaterial.listing(input.material)
        var chosen = selection
        for _ in 0..<2 {
            // Within the relay's limits (code points): one source with a long name must not make every answer fail.
            let request = TutorRequest(mode: mode, minor: minor, course: input.course, messages: Array(input.messages.suffix(8)),
                                       sources: chosen.sources, context: input.context,
                                       materials: materials.isEmpty ? nil : materials).fitted()
            switch await streamTutor(request, to: transport, sent: chosen.sent, retriever: retriever, mode: mode, fellBack: fellBack,
                                     emit: emit) {
            case .finished(let attempt):
                return attempt
            case .tooManySources:
                chosen = chosen.reduced(to: TutorSelection.legacyTutorLimit)
            }
        }
        return .failed
    }

    /// The relay turned a request down for holding more passages than it takes ("The request isn't valid: /sources has more than
    /// 12 items."), as against anything else wrong with it: only then is it asked again with fewer.
    static func refusesSourceCount(_ error: RelayError, sources: Int, legacyLimit: Int) -> Bool {
        guard case .badRequest(let message) = error, sources > legacyLimit else { return false }
        return message.contains("/sources") && message.contains("more than")
    }

    private func streamTutor(_ request: TutorRequest, to transport: any RelayTransport, sent: [String: LocalRetriever.Passage],
                             retriever: LocalRetriever, mode: TutorMode, fellBack: Bool,
                             emit: @MainActor (TutorUpdate) -> Void) async -> CloudStep {
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
        /// Before anything arrived: too many passages for the relay, or a free limit, or a plain failure.
        func beforeAnyText(_ error: RelayError) -> CloudStep {
            if Self.refusesSourceCount(error, sources: request.sources.count, legacyLimit: TutorSelection.legacyTutorLimit) {
                return .tooManySources
            }
            if let key = absorbQuotaError(error, meter: .tutor) { return .finished(.limit(key)) }
            return .finished(.failed)
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
                    guard started else { return .finished(.failed) }
                    recordCloudUse(.tutor)
                    finish(interrupted: false, note: nil)
                    return .finished(.success(()))
                case .failure(let code, let message):
                    let error = RelayError.from(code: code, message: message, quota: nil)
                    guard started else { return beforeAnyText(error) }
                    finish(interrupted: true, note: "Cap lost the connection part way. This is what arrived.")
                    return .finished(.success(()))
                }
            }
            guard started else { return .finished(.failed) }
            finish(interrupted: true, note: "Cap lost the connection part way. This is what arrived.")
            return .finished(.success(()))
        } catch {
            let relay = HTTPRelayTransport.map(error)
            if relay == .cancelled {
                if started { finish(interrupted: true, note: nil) }
                return .finished(.success(()))
            }
            guard started else { return beforeAnyText(relay) }
            finish(interrupted: true, note: "Cap lost the connection part way. This is what arrived.")
            return .finished(.success(()))
        }
    }

    /// A tier's citation as the app's `Citation`, through the passages sent: the quote must be in the passage the model named,
    /// which wins when it holds it, or else in another passage sent or somewhere in the person's material (then that passage is
    /// credited). A passage sent joined from several (`TutorSelection.joined`) is searched among the ones it was made of, so the
    /// card, the page or the moment in a lecture is the exact one, and a quote that straddles the seam between two is dropped.
    /// A quote that isn't in their notes is never shown as one.
    static func citation(sourceID: String, label: String, quote: String, sent: [String: LocalRetriever.Passage],
                         retriever: LocalRetriever, index: Int) -> Citation? {
        let q = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 4 else { return nil }
        guard let passage = TutorSelection.passage(named: sent[sourceID], sent: sent, retriever: retriever,
                                                   holding: { HighlightMark.locate(q, in: $0.text) != nil }) else { return nil }
        return Citation(id: "\(sourceID)-\(index + 1)", sourceID: passage.sourceID, pageIndex: passage.pageIndex,
                        start: passage.start, quote: q, label: passage.label)
    }

    // MARK: On device

    private func onDeviceTutor(_ question: String, mode: TutorMode, sources: [TutorSource], sent: [String: LocalRetriever.Passage],
                               retriever: LocalRetriever, context: TutorContext?, terms: [String: Double], closest: [String], tier: AITier,
                               fellBack: Bool, suggestion: AISuggestion?, limitReached: QuotaMeter.Key?, notice: String?,
                               emit: @MainActor (TutorUpdate) -> Void) async -> Bool {
        // Short help only: a long question goes to the offline tutor rather than a cramped prompt.
        guard question.split(whereSeparator: \.isWhitespace).count <= 40, !sources.isEmpty else { return false }
        let call = OnDeviceTutorCall(question: question, mode: mode, passages: sources, context: context)
        // A quote must come from a passage that is about the question; otherwise the offline answer stands in.
        guard let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget),
              let reply = OnDeviceTutoring.reply(from: output, passages: sources, terms: terms, closest: closest) else { return false }
        // Hints first means a question back, never the answer: measured, the small model often states the answer
        // in hints mode. Then the offline tutor's hint (a guiding question with the citation) answers instead.
        if mode == .hints, !reply.text.contains("?") { return false }
        recordOnDeviceUse(.tutor)
        let text = (notice.map { $0 + "\n\n" } ?? "") + reply.text
        emit(.started(origin: .onDevice))
        for piece in Self.pieces(of: text) {
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
        emit(.finished(TutorOutcome(text: text, citations: citations, origin: .onDevice, model: "on-device", mode: mode,
                                    grounded: !citations.isEmpty, suggestion: suggestion, limitReached: limitReached, fellBack: fellBack)))
        return true
    }
}

/// What this iPhone's model is handed for a tutor question. (`var` so that the tuning bench can try other sizes; nothing in the app changes them.)
enum OnDeviceWindow {
    /// Off: the first three keyword hits, as before.
    nonisolated(unsafe) static var useSentenceSearch = true
    /// The most passages handed over. Measured on 155 questions with the answering line known, with this Mac's model: the three passages of the
    /// best sentences were the best window (it answered 22 and was right on 12, against 20 and 7 with the keyword hits); adding the keyword search's
    /// nearest passages made it worse (22 and 7), a bigger window too (16 and 8): a small model reads a few passages well.
    nonisolated(unsafe) static var limit = 3
    /// How many of them are the sentence search's, the rest being the keyword search's nearest.
    nonisolated(unsafe) static var fromSentenceSearch = 3
    /// The model chooses the answering sentence among the search's best this many (`OnDevicePickCall`). Off: the search's first stays first.
    nonisolated(unsafe) static var useModelPick = true
    nonisolated(unsafe) static var pickAmong = 8

    /// A quote of the model's that is one of these is about the question whatever words it uses (`OnDeviceTutoring.reply`): the sentence the search
    /// itself takes for the answer, and the second when it is within `closeBy` of it. Measured on the quotes the share of words alone threw out: the
    /// right ones were the best or second-best sentence by 0.7 or less; the unrelated ones ranked lower or further behind.
    nonisolated(unsafe) static var closeBy = 0.7

    static func closest(in ranking: OfflineRanking) -> [String] {
        guard let best = ranking.candidates.first else { return [] }
        return ranking.candidates.prefix(2).filter { best.score - $0.score <= closeBy }.map(\.sentence)
    }

    /// The passages holding the sentences that answer best, best first, then the keyword search's nearest, each passage once.
    static func passages(ranking: OfflineRanking, keyword: [LocalRetriever.Passage]) -> [LocalRetriever.Passage] {
        var out: [LocalRetriever.Passage] = []
        for candidate in ranking.candidates where out.count < fromSentenceSearch {
            if !out.contains(where: { $0.key == candidate.passage.key }) { out.append(candidate.passage) }
        }
        for passage in keyword where out.count < limit {
            if !out.contains(where: { $0.key == passage.key }) { out.append(passage) }
        }
        return out
    }
}
