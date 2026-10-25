import Foundation

// The other jobs: mistake patterns, lecture notes, cards from a chat, and reading a page photo. Same ladder: the
// rules' answer first, a model tier only when the route allows, quiet fallback.

extension AIRouter {

    // MARK: Confusions

    /// Named mix-ups from repeated wrong answers. The relay explains them (when allowed); the rules find swaps and
    /// weak topics. A cloud confusion is kept only for items it was given; with `anchorTexts`, its fix questions
    /// must point at real lines.
    func confusions(course: String, mistakes: [MistakeInput], anchorTexts: [String: String]? = nil) async -> ConfusionsOutcome {
        let local = LocalConfusions.find(mistakes)
        guard !mistakes.isEmpty else { return ConfusionsOutcome(confusions: [], origin: .rules, model: LocalGrader.model) }
        let route = route(.confusions)
        var fellBack = false
        if route.usesCloud, cloudStillAllowed(), let transport {
            do {
                let response = try await transport.confusions(ConfusionsRequest(course: course, mistakes: mistakes))
                let known = Set(mistakes.map(\.itemId))
                let valid = response.confusions.compactMap { confusion -> ConfusionOut? in
                    var c = confusion
                    c.itemIds = c.itemIds.filter { known.contains($0) }
                    guard !c.itemIds.isEmpty else { return nil }
                    if let anchorTexts {
                        c.questions = GroundingCheck.apply(c.questions, texts: anchorTexts, anchorsOnly: true).kept
                    }
                    return c
                }
                if !valid.isEmpty {
                    return ConfusionsOutcome(confusions: valid, origin: .cloud, model: response.model)
                }
            } catch {
                fellBack = true
            }
        }
        return ConfusionsOutcome(confusions: local, origin: .rules, model: LocalGrader.model, suggestion: route.suggestion,
                                 fellBack: fellBack)
    }

    // MARK: Lecture notes

    /// Notes, flagged moments and draft questions for a recorded lecture. The relay writes them when allowed; on
    /// this iPhone the rules make the sections and the model may rewrite each section's title and notes; offline,
    /// the rules alone. Items always point at real segment ids.
    func lectureNotes(_ input: LectureInput) async -> LectureOutcome {
        let local = await Task.detached(priority: .userInitiated) {
            LocalLectureNotes.make(title: input.title, segments: input.segments, flags: input.flags, maxItems: input.maxItems)
        }.value
        let texts = GroundingCheck.texts(of: input.segments)
        let transcript = input.segments.map(\.text).joined(separator: " ")
        let route = route(.lecture, content: String(transcript.prefix(4000)))
        var fellBack = false
        var limitReached = route.limitReached

        tiers: for tier in route.tiers {
            if Task.isCancelled { break }
            switch tier {
            case .cloud:
                guard cloudStillAllowed(), let transport else { continue }
                let request = LectureRequest(course: input.course, title: input.title,
                                             segments: input.segments.map { SegmentInput(id: $0.id, start: $0.start, end: $0.end, text: $0.text) },
                                             flags: input.flags.map { FlagInput(time: $0.time, text: $0.text) },
                                             maxItems: input.maxItems)
                do {
                    let response = try await transport.lecture(request)
                    recordCloudUse(.lectures)
                    let (kept, dropped) = GroundingCheck.apply(response.items, texts: texts, anchorsOnly: true)
                    let notes = LectureNotes(summary: response.summary, sections: response.sections, keyTerms: response.keyTerms,
                                             origin: ItemOrigin.cloud.rawValue)
                    return LectureOutcome(title: response.title, notes: notes, examFlags: response.examFlags, items: kept,
                                          dropped: dropped, origin: .cloud, model: response.model, fellBack: fellBack)
                } catch {
                    let relay = HTTPRelayTransport.map(error)
                    if let key = absorbQuotaError(relay, meter: .lectures) {
                        limitReached = key
                        fellBack = true
                        break tiers
                    }
                    fellBack = true
                }
            case .onDevice, .privateCloud:
                if var outcome = await onDeviceLecture(local, texts: texts, tier: tier) {
                    outcome.fellBack = fellBack
                    outcome.suggestion = route.suggestion
                    return outcome
                }
                fellBack = true
            case .rules:
                break
            }
        }
        let (kept, dropped) = GroundingCheck.apply(local.items, texts: texts)
        let suggestion = route.suggestion ?? limitReached.map(limitSuggestion)
        let note: String? = local.sections.isEmpty ? "There's no transcript to make notes from yet."
            : "Notes from the offline rules: sections, flagged moments and key terms from the transcript."
        return LectureOutcome(title: local.title, notes: local.notes, examFlags: local.examFlags, items: kept, dropped: dropped,
                              origin: .rules, model: LocalGrader.model, note: note, suggestion: suggestion,
                              limitReached: limitReached, fellBack: fellBack)
    }

    private func onDeviceLecture(_ local: LocalLectureNotes.Result, texts: [String: String], tier: AITier) async -> LectureOutcome? {
        guard !local.sections.isEmpty else { return nil }
        let budget = self.budget
        let limit = budget.promptTokens(instructions: OnDeviceLectureSectionCall.instructions,
                                        schemaTokens: OnDeviceLectureSectionCall.schemaTokens,
                                        responseTokens: OnDeviceLectureSectionCall.responseTokens) - 20
        var sections = local.sections
        var improved = 0
        for i in sections.indices {
            if Task.isCancelled { return nil }
            // A long section is read from its start, cut at a sentence, to fit the window.
            var text = sections[i].text
            if OnDeviceBudget.estimateTokens(text) > limit {
                var kept = ""
                for sentence in Lexicon.sentences(text) {
                    if OnDeviceBudget.estimateTokens(kept + " " + sentence) > limit { break }
                    kept += (kept.isEmpty ? "" : " ") + sentence
                }
                text = kept
            }
            guard !text.isEmpty else { continue }
            let call = OnDeviceLectureSectionCall(text: text)
            guard let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget),
                  let section = OnDeviceLectureNotes.section(from: output, transcript: sections[i].text) else { continue }
            if !section.title.isEmpty { sections[i].title = section.title }
            sections[i].bullets = section.bullets
            improved += 1
        }
        guard improved > 0 else { return nil }
        recordOnDeviceUse(.lectures)
        let titles = sections.map(\.title)
        var summary = "Covers \(LocalGrader.list(titles.map { LocalGrader.lowerFirst($0) }))."
        if let flagLine = local.summary.range(of: "Flagged for the ") {
            summary += " " + local.summary[flagLine.lowerBound...]
        }
        let notes = LectureNotes(summary: summary,
                                 sections: sections.map { .init(id: $0.id, title: $0.title, start: $0.start, end: $0.end, bullets: $0.bullets) },
                                 keyTerms: local.keyTerms, origin: ItemOrigin.onDevice.rawValue)
        let (kept, dropped) = GroundingCheck.apply(local.items, texts: texts)
        return LectureOutcome(title: local.title, notes: notes, examFlags: local.examFlags, items: kept, dropped: dropped,
                              origin: .onDevice, model: "on-device",
                              note: "Notes written on your iPhone; the questions come from the offline rules.")
    }

    // MARK: Cards from a chat

    /// Draft flashcards from a tutor chat, for the person to pick from.
    func cardsFromChat(course: String?, messages: [TutorMessage], maxItems: Int = 6) async -> CardsOutcome {
        let local = LocalCardsFromChat.cards(messages: messages, maxItems: maxItems)
        let transcript = messages.map { "\($0.role == .user ? "Student" : "Cap"): \($0.text)" }.joined(separator: "\n")
        let route = route(.cardsFromChat, content: transcript)
        var fellBack = false
        for tier in route.tiers {
            if Task.isCancelled { break }
            switch tier {
            case .cloud:
                guard cloudStillAllowed(), let transport else { continue }
                do {
                    let response = try await transport.cardsFromChat(CardsFromChatRequest(course: course, messages: messages,
                                                                                          maxItems: maxItems))
                    let items = response.items.filter { !$0.prompt.isEmpty && !$0.answer.isEmpty }.prefix(maxItems)
                    if !items.isEmpty { return CardsOutcome(items: Array(items), origin: .cloud, model: response.model, fellBack: fellBack) }
                } catch {
                    fellBack = true
                }
            case .onDevice, .privateCloud:
                let call = OnDeviceCardsCall(transcript: transcript, maxCards: maxItems)
                if let output = await OnDeviceRunner.run(call, on: backend(for: tier), budget: budget) {
                    let items = OnDeviceCards.items(from: output, transcript: transcript, maxItems: maxItems)
                    if !items.isEmpty {
                        return CardsOutcome(items: items, origin: .onDevice, model: "on-device", suggestion: route.suggestion,
                                            fellBack: fellBack)
                    }
                }
                fellBack = true
            case .rules:
                break
            }
        }
        return CardsOutcome(items: local, origin: .rules, model: LocalGrader.model, suggestion: route.suggestion, fellBack: fellBack)
    }

    // MARK: Page photos

    /// Reads a page photo with cloud vision (handwriting, math, diagrams): only with Cloud AI allowed **and** the
    /// photos switch on, both read right before sending. The lines have no boxes.
    func transcribeImage(at url: URL, page: Int, label: String) async -> TranscriptionResult {
        let route = route(.transcribeImage)
        guard route.usesCloud else { return .notAllowed(route.suggestion) }
        guard let base64 = await AIImagePrep.base64JPEG(at: url) else { return .failed("The photo couldn't be read.") }
        return await transcribeImage(base64JPEG: base64, page: page, label: label)
    }

    func transcribeImage(base64JPEG: String, page: Int, label: String) async -> TranscriptionResult {
        let route = route(.transcribeImage)
        guard route.usesCloud, let transport else { return .notAllowed(route.suggestion) }
        guard let app, app.settings.sendPhotos, cloudStillAllowed() else { return .notAllowed(.allowPhotos) }
        do {
            let response = try await transport.transcribeImage(TranscribeImageRequest(image: base64JPEG, page: page, label: label))
            return .lines(response.lines.map { TextLine(id: $0.id, text: $0.text, box: nil) }, model: response.model)
        } catch {
            let relay = HTTPRelayTransport.map(error)
            switch relay {
            case .offline: return .failed("You're offline. The photo is kept, so it can be read later.")
            case .quotaExceeded(_, let message): return .failed(message)
            default: return .failed("Cloud AI couldn't read the photo this time.")
            }
        }
    }
}
