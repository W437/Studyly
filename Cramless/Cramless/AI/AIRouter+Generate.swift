import Foundation

// Generating a set from pages. The processing screen follows the phases (reading → finding the key ideas →
// writing questions → checking against the page); every run passes through all four whichever tier answers.
//
//   cloud:            generate → anchors must be real lines → the relay's check (fixed answers applied,
//                     unsupported items dropped with the reason) → drafts
//   on-device, rules: generate → grounding check (anchors exist, the answer is on its lines) → drafts
//
// The result is always a draft set for review; nothing is saved here.

extension AIRouter {

    /// The run as a stream for the processing screen: progress updates, then the outcome. Cancelling the consuming
    /// task cancels the run.
    func generateSet(_ input: GenerationInput) -> AsyncStream<GenerationUpdate> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { continuation.finish(); return }
                let outcome = await self.generateSet(input) { continuation.yield(.progress($0)) }
                continuation.yield(.finished(outcome))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The run, with progress reported through `onProgress`.
    func generateSet(_ input: GenerationInput,
                     onProgress: @escaping @MainActor (GenerationProgress) -> Void = { _ in }) async -> GenerationOutcome {
        var progress = GenerationProgress(phase: .reading, origin: .rules, detail: "Text and layout, on your iPhone")
        onProgress(progress)
        let texts = GroundingCheck.texts(of: input.pages)

        // T0 first: the rules' answer is always made, and it is what the person gets if nothing better is allowed.
        let rules = await Task.detached(priority: .userInitiated) {
            LocalGenerator.generate(pages: input.pages, sourceTitle: input.sourceTitle, maxItems: input.maxItems,
                                    formats: Set(input.formats))
        }.value
        let pageText = input.pages.flatMap { $0.lines.map(\.text) }.joined(separator: "\n")
        let route = route(.generate, content: pageText)

        var fellBack = false
        var triedCloud = false
        var limitReached = route.limitReached
        tiers: for tier in route.tiers {
            if Task.isCancelled { break }
            switch tier {
            case .cloud:
                triedCloud = true
                switch await cloudGeneration(input, texts: texts, progress: &progress, onProgress: onProgress) {
                case .success(var outcome):
                    outcome.fellBack = fellBack
                    return outcome
                case .limit(let key):
                    limitReached = key
                    fellBack = true
                    break tiers   // the free limit counts every model tier
                case .failed:
                    fellBack = true
                }
            case .onDevice, .privateCloud:
                if var outcome = await onDeviceGeneration(input, texts: texts, rules: rules, tier: tier, progress: &progress,
                                                          onProgress: onProgress) {
                    outcome.fellBack = fellBack
                    outcome.suggestion = route.suggestion
                    return outcome
                }
                fellBack = true
            case .rules:
                break
            }
        }
        return rulesOutcome(rules, texts: texts, route: route, limitReached: limitReached, fellBack: fellBack,
                            triedCloud: triedCloud, progress: &progress, onProgress: onProgress)
    }

    // MARK: Cloud

    enum Attempt<Value> {
        case success(Value)
        case limit(QuotaMeter.Key)
        case failed
    }

    private func cloudGeneration(_ input: GenerationInput, texts: [String: String], progress: inout GenerationProgress,
                                 onProgress: @MainActor (GenerationProgress) -> Void) async -> Attempt<GenerationOutcome> {
        guard cloudStillAllowed(), let transport else { return .failed }
        progress.phase = .findingKeyIdeas
        progress.origin = .cloud
        progress.detail = "With Cloud AI"
        onProgress(progress)

        // Built now, from what is true now: page photos go along only if that switch is on at this moment.
        let request = await makeGenerateRequest(input)
        let response: GenerateResponse
        do {
            response = try await transport.generate(request)
        } catch {
            let relay = HTTPRelayTransport.map(error)
            if let key = absorbQuotaError(relay, meter: .scans) { return .limit(key) }
            return .failed
        }
        recordCloudUse(.scans)
        progress.phase = .writingQuestions
        progress.topics = response.topics.map(\.name)
        progress.written = response.items.count
        progress.detail = "\(response.items.count) questions"
        onProgress(progress)

        // Every anchor must be a line of the page, whoever wrote the item.
        var (items, dropped) = GroundingCheck.apply(response.items, texts: texts, anchorsOnly: true)
        progress.phase = .checking
        progress.detail = "So nothing made up gets through"
        onProgress(progress)

        var checkedBy = ItemOrigin.cloud
        // After the wait: consent may have been withdrawn while the questions were being written.
        if cloudStillAllowed(), !Task.isCancelled {
            let checkPages = request.pages.map { PageInput(page: $0.page, label: $0.label, lines: $0.lines, image: nil) }
            do {
                let check = try await transport.check(CheckRequest(pages: checkPages, items: items))
                let applied = Self.applyCheck(check.verdicts, to: items)
                items = applied.kept
                dropped += applied.dropped
            } catch {
                let local = GroundingCheck.apply(items, texts: texts, minimumOverlap: 0.34)
                items = local.kept
                dropped += local.dropped
                checkedBy = .rules
            }
        } else {
            let local = GroundingCheck.apply(items, texts: texts, minimumOverlap: 0.34)
            items = local.kept
            dropped += local.dropped
            checkedBy = .rules
        }
        guard !items.isEmpty else { return .failed }
        progress.checked = response.items.count
        progress.kept = items.count
        progress.detail = "\(items.count) of \(response.items.count) match the page"
        onProgress(progress)
        let used = Set(items.map(\.topic))
        return .success(GenerationOutcome(title: response.title, topics: response.topics.filter { used.contains($0.name) },
                                          items: items, dropped: dropped, origin: .cloud, model: response.model,
                                          checkedBy: checkedBy, note: nil, suggestion: nil, limitReached: nil, fellBack: false))
    }

    /// The check's verdicts on the items: supported kept, fixed kept with the fixed answer (and options), unsupported
    /// dropped with the reason. An item the check didn't mention is kept, as `SamplePage.checkedItems` does.
    static func applyCheck(_ verdicts: [CheckVerdict], to items: [GeneratedItem]) -> (kept: [GeneratedItem], dropped: [DroppedItem]) {
        let byID = Dictionary(verdicts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [GeneratedItem] = []
        var dropped: [DroppedItem] = []
        for var item in items {
            guard let verdict = byID[item.id] else { kept.append(item); continue }
            switch verdict.verdict {
            case .supported:
                kept.append(item)
            case .fixed:
                if let answer = verdict.fixedAnswer, !answer.isEmpty { item.answer = answer }
                if let choices = verdict.fixedChoices {
                    guard choices.filter(\.correct).count == 1, choices.count >= 2 else {
                        dropped.append(DroppedItem(item: item, reason: verdict.reason))
                        continue
                    }
                    item.choices = choices
                }
                kept.append(item)
            case .unsupported:
                dropped.append(DroppedItem(item: item, reason: verdict.reason))
            }
        }
        return (kept, dropped)
    }

    private func makeGenerateRequest(_ input: GenerationInput) async -> GenerateRequest {
        let photos = app.map { AIConsent.photosGranted($0.settings) } ?? false
        var pages: [PageInput] = []
        for page in input.pages {
            var image: String?
            if photos, let url = page.imageURL { image = await AIImagePrep.base64JPEG(at: url) }
            pages.append(PageInput(page: page.index, label: page.label,
                                   lines: page.lines.map { LineInput(id: $0.id, text: $0.text) }, image: image))
        }
        // Preparing photos takes a moment per page: if the switch went off meanwhile, none go.
        if photos, !(app.map { AIConsent.photosGranted($0.settings) } ?? false) {
            pages = pages.map { PageInput(page: $0.page, label: $0.label, lines: $0.lines, image: nil) }
        }
        let text = input.pages.flatMap { $0.lines.map(\.text) }.joined(separator: " ")
        return GenerateRequest(course: input.course, sourceTitle: input.sourceTitle, level: input.level,
                               language: LocalGenerator.dominantLanguage(text), formats: input.formats,
                               maxItems: input.maxItems, pages: pages)
    }

    // MARK: On device

    private func onDeviceGeneration(_ input: GenerationInput, texts: [String: String], rules: LocalGenerator.Result,
                                    tier: AITier, progress: inout GenerationProgress,
                                    onProgress: @MainActor (GenerationProgress) -> Void) async -> GenerationOutcome? {
        let backend = backend(for: tier)
        let budget = self.budget
        progress.phase = max(progress.phase, .findingKeyIdeas)
        progress.origin = .onDevice
        progress.detail = "On your iPhone"
        onProgress(progress)

        // One page at a time, cut into pieces that fit the model's window.
        let limit = budget.promptTokens(instructions: OnDevicePageCall.instructions, schemaTokens: OnDevicePageCall.schemaTokens,
                                        responseTokens: OnDevicePageCall.responseTokens) - 30
        var topics: [String] = []
        var items: [GeneratedItem] = []
        var next = 1
        for page in input.pages {
            let lines = page.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            for chunk in budget.chunks(lines, limit: max(1, limit), render: OnDevicePageCall.render) {
                if Task.isCancelled { return nil }
                guard items.count < input.maxItems else { break }
                let call = OnDevicePageCall(lines: chunk, maxQuestions: min(8, input.maxItems - items.count))
                guard let output = await OnDeviceRunner.run(call, on: backend, budget: budget) else { continue }
                let mapped = OnDeviceGeneration.items(from: output, call: call, startingAt: next)
                next += mapped.items.count
                for topic in mapped.topics where !topics.contains(topic) { topics.append(topic) }
                items += mapped.items.filter { input.formats.contains($0.kind) }
                progress.phase = max(progress.phase, .writingQuestions)
                progress.topics = topics
                progress.written = items.count
                progress.detail = "\(items.count) questions"
                onProgress(progress)
            }
        }
        guard !items.isEmpty else { return nil }
        progress.phase = max(progress.phase, .checking)
        progress.detail = "So nothing made up gets through"
        onProgress(progress)
        let (kept, dropped) = GroundingCheck.apply(items, texts: texts)
        // Nothing usable survived: the rules' set is the draft.
        guard !kept.isEmpty else { return nil }
        recordOnDeviceUse(.scans)
        progress.checked = items.count
        progress.kept = kept.count
        progress.detail = "\(kept.count) of \(items.count) match the page"
        onProgress(progress)
        // The model writes the own-words questions; the rules add what they do reliably (choices from parallel
        // headings, fill-ins from definitions), grounded the same way, without repeating a question or its lines.
        let ruleItems = GroundingCheck.apply(rules.items, texts: texts, minimumOverlap: 0.34).kept
        var finalItems = Self.merge(kept, with: ruleItems, limit: input.maxItems)
        for topic in rules.topics.map(\.name) where !topics.contains(topic)
            && finalItems.contains(where: { $0.topic == topic }) { topics.append(topic) }
        let names = topics.isEmpty ? [input.sourceTitle] : topics
        for i in finalItems.indices where !names.contains(finalItems[i].topic) { finalItems[i].topic = names[0] }
        let used = Set(finalItems.map(\.topic))
        return GenerationOutcome(title: names[0], topics: names.filter { used.contains($0) }.map { GeneratedTopic(name: $0, summary: "") },
                                 items: finalItems, dropped: dropped, origin: .onDevice, model: "on-device",
                                 checkedBy: .onDevice, note: nil, suggestion: nil, limitReached: nil, fellBack: false)
    }

    /// The model's items first, then the rules' items that add a different question (another prompt, other lines)
    /// up to `limit`; multiple choice from the rules is preferred because the model doesn't write it.
    static func merge(_ model: [GeneratedItem], with rules: [GeneratedItem], limit: Int) -> [GeneratedItem] {
        var out = Array(model.prefix(limit))
        var prompts = Set(out.map { Lexicon.normalizedAnswer($0.prompt) })
        var anchorSets = Set(out.map { $0.anchors.sorted().joined(separator: ",") + "#" + $0.kind.rawValue })
        let ordered = rules.filter { $0.kind == .mcq } + rules.filter { $0.kind != .mcq }
        for item in ordered where out.count < limit {
            let prompt = Lexicon.normalizedAnswer(item.prompt)
            let key = item.anchors.sorted().joined(separator: ",") + "#" + item.kind.rawValue
            guard !prompts.contains(prompt), !anchorSets.contains(key) else { continue }
            var copy = item
            copy.id = "r\(out.count + 1)-" + item.id
            out.append(copy)
            prompts.insert(prompt)
            anchorSets.insert(key)
        }
        return out
    }

    // MARK: Rules

    private func rulesOutcome(_ rules: LocalGenerator.Result, texts: [String: String], route: AIRoute,
                              limitReached: QuotaMeter.Key?, fellBack: Bool, triedCloud: Bool,
                              progress: inout GenerationProgress,
                              onProgress: @MainActor (GenerationProgress) -> Void) -> GenerationOutcome {
        progress.origin = .rules
        progress.detail = "On your iPhone"
        progress.phase = max(progress.phase, .findingKeyIdeas)
        progress.topics = rules.topics.map(\.name)
        onProgress(progress)
        progress.phase = max(progress.phase, .writingQuestions)
        progress.written = rules.items.count
        progress.detail = "\(rules.items.count) questions"
        onProgress(progress)
        progress.phase = max(progress.phase, .checking)
        progress.detail = "So nothing made up gets through"
        onProgress(progress)
        let (kept, dropped) = GroundingCheck.apply(rules.items, texts: texts)
        progress.checked = rules.items.count
        progress.kept = kept.count
        progress.detail = "\(kept.count) of \(rules.items.count) match the page"
        onProgress(progress)

        let used = Set(kept.map(\.topic))
        let suggestion = route.suggestion ?? limitReached.map(limitSuggestion)
        return GenerationOutcome(title: rules.title, topics: rules.topics.filter { used.contains($0.name) }, items: kept,
                                 dropped: dropped, origin: .rules, model: LocalGrader.model, checkedBy: .rules,
                                 note: basicNote(rules.quality, route: route, limitReached: limitReached,
                                                 fellBack: fellBack, triedCloud: triedCloud),
                                 suggestion: suggestion, limitReached: limitReached, fellBack: fellBack)
    }

    /// The review screen's honest line about an offline set.
    func basicNote(_ quality: LocalGenerator.Result.Quality, route: AIRoute, limitReached: QuotaMeter.Key?, fellBack: Bool,
                   triedCloud: Bool) -> String {
        switch quality {
        case .unsupportedLanguage:
            return "The offline rules only write questions for English pages, so these are just the term cards on it."
        case .empty:
            return "The offline rules couldn't find questions on this page."
        default:
            break
        }
        if limitReached != nil {
            return "You've used this week's free AI scans, so these are basic questions from the offline rules."
        }
        if fellBack {
            return triedCloud
                ? "Cloud AI couldn't be reached, so these are basic questions from the offline rules."
                : "Your iPhone's AI couldn't write these, so they're basic questions from the offline rules."
        }
        if case .allowCloud = route.suggestion {
            return "Basic questions from the offline rules. Turn on Cloud AI for better ones."
        }
        return "Basic questions from the offline rules."
    }
}
