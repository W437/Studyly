import Foundation

// Grading. The offline grade comes first and at once, so the person never waits; a refined grade may follow from
// this iPhone's model (short answers) or the relay (long or shaky answers, and "Grade again"). Fill-ins, choices
// and diagram labels are exact checks: the offline grade is final for them.
//
// Marks are always the person's own words: a cloud or on-device quote becomes a range only when it is found word
// for word in the answer; when it isn't, that idea keeps the offline grader's range if it found one, else no mark.

extension AIRouter {

    /// The offline grade, at once. Never metered. For own-words answers it carries what the UI may offer next
    /// (a second look with Cloud AI, or the paywall when today's graded answers are used up).
    func instantGrade(_ subject: GradeSubject, answer: AnswerInput) -> GradeOutcome {
        var outcome = LocalGrader.grade(subject, answer: answer)
        if let text = Self.refinableText(subject, answer) {
            let route = route(.grade, content: subject.prompt + " " + text, preferCloud: outcome.needsSecondLook)
            outcome.suggestion = route.suggestion
            outcome.limitReached = route.limitReached
        }
        return outcome
    }

    /// The offline grade first, then a refined one when a model tier is allowed: the stream yields one or two
    /// outcomes. Cancelling the consuming task cancels the refinement.
    func grade(_ subject: GradeSubject, answer: AnswerInput) -> AsyncStream<GradeOutcome> {
        let instant = instantGrade(subject, answer: answer)
        let text = Self.refinableText(subject, answer)
        return AsyncStream { continuation in
            continuation.yield(instant)
            guard let text, instant.limitReached == nil else { continuation.finish(); return }
            let task = Task { @MainActor [weak self] in
                if let self, let refined = await self.refine(subject, answer: text, local: instant, strongest: false) {
                    continuation.yield(refined)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The best grade available now (awaits the refinement). For callers that don't show the instant grade.
    func gradeNow(_ subject: GradeSubject, answer: AnswerInput) async -> GradeOutcome {
        var last = instantGrade(subject, answer: answer)
        for await outcome in grade(subject, answer: answer) { last = outcome }
        return last
    }

    /// "Grade again": the strongest tier allowed (the cloud, else this iPhone's model, else the rules once more),
    /// and whether it agrees with the grade on screen.
    func gradeAgain(_ subject: GradeSubject, answer: AnswerInput, previous: GradeOutcome? = nil) async -> GradeOutcome {
        let local = LocalGrader.grade(subject, answer: answer)
        var outcome = local
        if let text = Self.refinableText(subject, answer) {
            if let refined = await refine(subject, answer: text, local: local, strongest: true) {
                outcome = refined
            } else {
                let route = route(.grade, content: subject.prompt + " " + text, strongest: true)
                outcome.suggestion = route.suggestion
                outcome.limitReached = route.limitReached
            }
        }
        if let previous {
            outcome.agreesWithPrevious = outcome.verdict == previous.verdict && Set(outcome.hitIdeaIDs) == Set(previous.hitIdeaIDs)
        }
        return outcome
    }

    /// The answer text when a model could improve on the offline grade: own words (with key ideas) only.
    static func refinableText(_ subject: GradeSubject, _ answer: AnswerInput) -> String? {
        guard subject.kind.isOwnWords, !subject.keyIdeas.isEmpty, case .text(let text) = answer else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    /// Asks the route's tiers in order; nil when none is allowed or none answered (the offline grade stands).
    func refine(_ subject: GradeSubject, answer: String, local: GradeOutcome, strongest: Bool) async -> GradeOutcome? {
        let words = answer.split(whereSeparator: \.isWhitespace).count
        let preferCloud = words > 60 || local.needsSecondLook
        let call = OnDeviceGradeCall(subject: subject, answer: answer)
        let fits = budget.fits(call.prompt, instructions: OnDeviceGradeCall.instructions,
                               schemaTokens: OnDeviceGradeCall.schemaTokens, responseTokens: OnDeviceGradeCall.responseTokens)
        let route = route(.grade, content: subject.prompt + " " + answer, promptFits: fits && words <= 120,
                          strongest: strongest, preferCloud: preferCloud)
        var fellBack = false
        for tier in route.tiers {
            if Task.isCancelled { return nil }
            switch tier {
            case .onDevice, .privateCloud:
                if let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget),
                   var outcome = OnDeviceGrading.outcome(from: output, subject: subject, answer: answer, local: local) {
                    recordOnDeviceUse(.grades)
                    outcome.fellBack = fellBack
                    outcome.suggestion = route.suggestion
                    return outcome
                }
                fellBack = true
            case .cloud:
                guard cloudStillAllowed(), let transport else { continue }
                // Built now, from the item and the answer as they are now.
                let request = GradeRequest(kind: subject.kind, level: subject.level ?? app?.settings.level?.rawValue,
                                           prompt: subject.prompt, modelAnswer: subject.modelAnswer, keyIdeas: subject.keyIdeas,
                                           response: answer, sourceExcerpt: subject.sourceExcerpt)
                do {
                    let response = try await transport.grade(request)
                    recordCloudUse(.grades)
                    var outcome = Self.outcome(from: response, subject: subject, answer: answer, local: local)
                    outcome.fellBack = fellBack
                    return outcome
                } catch {
                    let relay = HTTPRelayTransport.map(error)
                    if relay == .cancelled { return nil }
                    if let key = absorbQuotaError(relay, meter: .grades) {
                        var outcome = local
                        outcome.limitReached = key
                        outcome.suggestion = limitSuggestion(key)
                        return outcome
                    }
                    fellBack = true
                }
            case .rules:
                break
            }
        }
        return nil
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
