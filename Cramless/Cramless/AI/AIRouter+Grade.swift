import Foundation

// Grading. The offline grade comes first and at once, so the person never waits; a refined grade may follow from
// this iPhone's model (short answers) or the relay (long or shaky answers, and "Grade again"). Fill-ins, choices
// and diagram labels are exact checks: the offline grade is final for them.
//
// For an answer in the person's own words the rules' verdict is only as good as it was measured to be (`SelfCheck`), so the grade
// carries a `mode`. While a model is allowed and still to answer, the rules' grade is `.provisional`. Where no model will grade it,
// the rules' verdict stands only if it can be trusted (`.verdict`); otherwise the grade is `.selfCheck`, and the person compares
// their answer with the model answer and ticks the key ideas they had. A model's grade is always `.verdict`.
//
// Marks are always the person's own words: a cloud or on-device quote becomes a range only when it is found word for word in the
// answer; when it isn't, that idea keeps the offline grader's range if it found one, else no mark.

extension AIRouter {

    /// What asking the model tiers came to.
    struct GradeRefinement {
        /// The model's grade; nil when none is allowed or none answered (the offline grade stands).
        var outcome: GradeOutcome?
        /// With no outcome: why nobody graded it, for the line that tells a person they mark it themselves.
        var why: SelfCheckReason?
        /// A free limit the relay reported on the way.
        var limit: QuotaMeter.Key?
    }

    /// One attempt to get a model's grade, as the stream below runs it: what the attempt has learned so far that the clock must not
    /// lose when it ends the attempt (a free limit the relay reported), and which of the two ends came first.
    @MainActor
    final class GradeAttempt {
        var limit: QuotaMeter.Key?
        var settled = false
    }

    /// The most words this iPhone's model is given to grade.
    static let onDeviceGradeWords = 120

    /// What a model tier's place on the route depends on, worked out once from the answer: the text the language gate reads, whether
    /// this iPhone's prompt fits its window, and whether the cloud comes first. The offline grade, the refinement, "Grade again" and
    /// its button all route with the same facts, so the screen never offers a model the refinement then won't use.
    struct GradeRouting {
        var content: String
        var promptFits: Bool
        var preferCloud: Bool
    }

    func gradeRouting(_ subject: GradeSubject, answer: String, needsSecondLook: Bool) -> GradeRouting {
        let words = answer.split(whereSeparator: \.isWhitespace).count
        var fits = words <= Self.onDeviceGradeWords
        if fits, probe.capability().availability.isAvailable {
            let call = OnDeviceGradeCall(subject: subject, answer: answer)
            fits = budget.fits(call.prompt, instructions: OnDeviceGradeCall.instructions,
                               schemaTokens: OnDeviceGradeCall.schemaTokens, responseTokens: OnDeviceGradeCall.responseTokens)
        }
        return GradeRouting(content: subject.prompt + " " + answer, promptFits: fits, preferCloud: words > 60 || needsSecondLook)
    }

    /// The offline grade, at once. Never metered. For own-words answers it carries what the UI may offer next
    /// (a second look with Cloud AI, or the paywall when today's free Cloud AI checks are used up) and its mode: provisional while
    /// a model will look at it, `.selfCheck` when none will and the rules can't be trusted.
    func instantGrade(_ subject: GradeSubject, answer: AnswerInput) -> GradeOutcome {
        var outcome = LocalGrader.grade(subject, answer: answer)
        if let text = Self.refinableText(subject, answer) {
            let routing = gradeRouting(subject, answer: text, needsSecondLook: outcome.needsSecondLook)
            let route = route(.grade, content: routing.content, promptFits: routing.promptFits, preferCloud: routing.preferCloud)
            outcome.suggestion = route.suggestion
            outcome.limitReached = route.limitReached
            outcome = SelfCheck.settled(outcome, subject: subject, answer: text, modelAllowed: !route.tiers.isEmpty,
                                        why: route.whyNoModel)
        }
        return outcome
    }

    /// The offline grade first, then a refined one when a model tier is allowed: the stream yields one or two
    /// outcomes. When no model answers after all, the second is the offline grade again, settled without a model (a self-check where
    /// the rules can't be trusted). `wait` is how long the model has: when it is up the model is let go and the answer is settled
    /// the same way, as if the model could not be reached (nil: no limit, for callers that have no one waiting). Cancelling the
    /// consuming task cancels the refinement.
    func grade(_ subject: GradeSubject, answer: AnswerInput, wait: Duration? = SelfCheck.modelWait) -> AsyncStream<GradeOutcome> {
        let instant = instantGrade(subject, answer: answer)
        let text = Self.refinableText(subject, answer)
        return AsyncStream { continuation in
            continuation.yield(instant)
            guard let text, instant.mode == .provisional else { continuation.finish(); return }
            let attempt = GradeAttempt()
            let work = Task { @MainActor [weak self] in
                guard let self else { continuation.finish(); return }
                let result = await self.refinement(subject, answer: text, local: instant, strongest: false, attempt: attempt)
                guard !attempt.settled else { return }
                attempt.settled = true
                if let refined = result.outcome {
                    continuation.yield(refined)
                } else if !Task.isCancelled {
                    continuation.yield(self.settledWithoutModel(instant, subject: subject, answer: text, result: result))
                }
                continuation.finish()
            }
            let timer = wait.map { wait in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: wait)
                    guard !Task.isCancelled, !attempt.settled else { return }
                    attempt.settled = true
                    work.cancel()
                    if let self {
                        let result = GradeRefinement(outcome: nil, why: .unreachable, limit: attempt.limit)
                        continuation.yield(self.settledWithoutModel(instant, subject: subject, answer: text, result: result))
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                work.cancel()
                timer?.cancel()
            }
        }
    }

    /// The best grade available now (awaits the refinement). For callers that don't show the instant grade.
    func gradeNow(_ subject: GradeSubject, answer: AnswerInput) async -> GradeOutcome {
        var last = instantGrade(subject, answer: answer)
        for await outcome in grade(subject, answer: answer, wait: nil) { last = outcome }
        return last
    }

    /// "Grade again": the strongest tier allowed (the cloud, else this iPhone's model, else the rules once more), and whether it
    /// agrees with the grade on screen.
    func gradeAgain(_ subject: GradeSubject, answer: AnswerInput, previous: GradeOutcome? = nil) async -> GradeOutcome {
        let local = LocalGrader.grade(subject, answer: answer)
        var outcome = local
        if let text = Self.refinableText(subject, answer) {
            let result = await refinement(subject, answer: text, local: local, strongest: true)
            if let refined = result.outcome {
                outcome = refined
            } else {
                let routing = gradeRouting(subject, answer: text, needsSecondLook: local.needsSecondLook)
                let route = route(.grade, content: routing.content, promptFits: routing.promptFits, strongest: true,
                                  preferCloud: routing.preferCloud)
                outcome.suggestion = route.suggestion
                outcome.limitReached = route.limitReached
                outcome = settledWithoutModel(outcome, subject: subject, answer: text, result: result)
            }
        }
        if let previous {
            outcome.agreesWithPrevious = outcome.verdict == previous.verdict && Set(outcome.hitIdeaIDs) == Set(previous.hitIdeaIDs)
        }
        return outcome
    }

    /// "Grade again" could get a model's grade now: a model tier is on the route, worked out from the same facts as the grade it
    /// would replace (the language and length the iPhone's model can read), so the button is never a dead one. Reads and changes
    /// nothing (safe from a view's body).
    func canGradeAgain(_ subject: GradeSubject, answer: AnswerInput) -> Bool {
        guard let text = Self.refinableText(subject, answer) else { return false }
        let routing = gradeRouting(subject, answer: text, needsSecondLook: false)
        let context = routeContext(.grade, content: routing.content, promptFits: routing.promptFits, strongest: true,
                                   preferCloud: routing.preferCloud)
        return !AIRouting.route(context).tiers.isEmpty
    }

    /// The answer text when a model could improve on the offline grade: own words (with key ideas) only.
    static func refinableText(_ subject: GradeSubject, _ answer: AnswerInput) -> String? {
        guard subject.kind.isOwnWords, !subject.keyIdeas.isEmpty, case .text(let text) = answer else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // The person's number is the model answer's: the offline grade is the whole check, and no model is asked to second-guess it
        // against key ideas that describe the method.
        if trimmed.isEmpty || NumericAnswer.agrees(modelAnswer: subject.modelAnswer, typed: trimmed) { return nil }
        return text
    }

    /// The offline grade after no model answered: final where the rules can be trusted, the person's to mark where they can't (for
    /// the reason the attempt came to). A free limit the relay reported on the way shows its paywall card, in words that say the
    /// person marks it themselves.
    func settledWithoutModel(_ rules: GradeOutcome, subject: GradeSubject, answer: String, result: GradeRefinement) -> GradeOutcome {
        var outcome = rules
        if let key = rules.limitReached ?? result.limit {
            outcome.limitReached = key
            outcome.suggestion = limitSuggestion(key)
        }
        return SelfCheck.settled(outcome, subject: subject, answer: answer, modelAllowed: false, why: result.why)
    }

    /// Asks the route's tiers in order; nil when none is allowed or none answered (the offline grade stands).
    func refine(_ subject: GradeSubject, answer: String, local: GradeOutcome, strongest: Bool) async -> GradeOutcome? {
        await refinement(subject, answer: answer, local: local, strongest: strongest).outcome
    }

    /// `refine`, with why there was no grade when there was none. `attempt` hears of a free limit the relay reports on the way.
    func refinement(_ subject: GradeSubject, answer: String, local: GradeOutcome, strongest: Bool,
                    attempt: GradeAttempt? = nil) async -> GradeRefinement {
        let call = OnDeviceGradeCall(subject: subject, answer: answer)
        let routing = gradeRouting(subject, answer: answer, needsSecondLook: local.needsSecondLook)
        let route = route(.grade, content: routing.content, promptFits: routing.promptFits, strongest: strongest,
                          preferCloud: routing.preferCloud)
        var fellBack = false
        var limit: QuotaMeter.Key?
        var cloudDenied = false, cloudOffline = false, cloudFailed = false
        // What the person is told if nobody grades it: a free limit first, then what went wrong with the cloud, then the route's own reason.
        func nobody() -> GradeRefinement {
            let why: SelfCheckReason = limit != nil ? .freeLimit : cloudOffline ? .offline : cloudFailed ? .unreachable
                : cloudDenied ? .cloudOff : (route.whyNoModel ?? .deviceUnavailable)
            return GradeRefinement(outcome: nil, why: why, limit: limit)
        }
        for tier in route.tiers {
            if Task.isCancelled { cloudFailed = true; return nobody() }
            switch tier {
            case .onDevice, .privateCloud:
                if let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget),
                   var outcome = OnDeviceGrading.outcome(from: output, subject: subject, answer: answer, local: local) {
                    recordOnDeviceUse(.grades)
                    outcome.fellBack = fellBack
                    if let limit {
                        // The relay said the free Cloud AI checks are used while this call was under way (its count runs ahead of this
                        // iPhone's): the paywall card shows with this answer, not with the next one.
                        outcome.limitReached = limit
                        outcome.suggestion = limitSuggestion(limit, deviceKeepsWorking: true)
                    } else {
                        outcome.suggestion = route.suggestion
                        outcome.limitReached = route.limitReached
                    }
                    return GradeRefinement(outcome: outcome, limit: limit)
                }
                fellBack = true
            case .cloud:
                guard cloudStillAllowed(), let transport else { cloudDenied = true; continue }
                // Built now, from the item and the answer as they are now.
                let request = GradeRequest(kind: subject.kind, level: subject.level ?? app?.settings.level?.rawValue,
                                           prompt: subject.prompt, modelAnswer: subject.modelAnswer, keyIdeas: subject.keyIdeas,
                                           response: answer, sourceExcerpt: subject.sourceExcerpt).fitted()
                do {
                    let response = try await transport.grade(request)
                    recordCloudUse(.grades)
                    var outcome = Self.outcome(from: response, subject: subject, answer: answer, local: local)
                    outcome.fellBack = fellBack
                    return GradeRefinement(outcome: outcome, limit: limit)
                } catch {
                    let relay = HTTPRelayTransport.map(error)
                    if relay == .cancelled { cloudFailed = true; return nobody() }
                    if let key = absorbQuotaError(relay, meter: .grades) {
                        // The free Cloud AI checks are used (the server says so, ahead of this iPhone's own count). The paywall card
                        // shows; this iPhone's model, if it is still on the route, goes on.
                        limit = key
                        attempt?.limit = key
                    } else if relay == .offline {
                        cloudOffline = true
                    } else {
                        cloudFailed = true
                    }
                    fellBack = true
                }
            case .rules:
                break
            }
        }
        return nobody()
    }

    /// The relay's grade as an outcome, with only verbatim quotes marked.
    static func outcome(from response: GradeResponse, subject: GradeSubject, answer: String, local: GradeOutcome) -> GradeOutcome {
        let ideaIDs = subject.keyIdeas.map(\.id)
        var marks: [GradeMark] = []
        var hit: [String] = []
        for h in response.hits where ideaIDs.contains(h.ideaId) {
            if !hit.contains(h.ideaId) { hit.append(h.ideaId) }
            if let range = HighlightMark.locate(h.quote, in: answer) {
                marks.append(GradeMark(ideaID: h.ideaId, range: range))
            } else {
                marks += local.marks.filter { $0.ideaID == h.ideaId }
            }
        }
        hit.sort { (ideaIDs.firstIndex(of: $0) ?? 0) < (ideaIDs.firstIndex(of: $1) ?? 0) }
        let missingIDs = response.missing.filter { ideaIDs.contains($0) && !hit.contains($0) }
        let missing = missingIDs.compactMap { id in subject.keyIdeas.first { $0.id == id } }
            .map { MissingIdea(id: $0.id, label: $0.label) }
        return GradeOutcome(score: min(1, max(0, response.score)), verdict: response.verdict,
                            confidence: min(1, max(0, response.confidence)), marks: marks, hitIdeaIDs: hit, missing: missing,
                            feedback: response.feedback, fix: response.fix, gradedBy: .cloud, model: response.model,
                            isRefined: true)
    }
}
