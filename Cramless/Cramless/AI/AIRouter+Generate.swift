import Foundation

// Generating a set from pages. The processing screen follows the phases (reading → finding the key ideas →
// writing questions → checking against the page); every run passes through all four whichever tier answers.
//
//   cloud:            generate → anchors must be real lines → the relay's check (fixed answers applied,
//                     unsupported items dropped with the reason) → drafts. A reading longer than the plan's pages
//                     per scan goes in parts, one scan each (`GenerationPlan`), cut by the scans the week has left; a check
//                     that rejects nearly everything is asked again leniently and, failing that, replaced by this
//                     iPhone's (`CheckPolicy`)
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
                                    formats: Set(input.formats), courseLanguage: input.courseLanguage)
        }.value
        let pageText = input.pages.flatMap { $0.lines.map(\.text) }.joined(separator: "\n")
        let route = route(.generate, content: pageText)

        var fellBack = false
        var triedCloud = false
        var limitReached = route.limitReached
        var cloudFailure: CloudFailure?
        tiers: for tier in route.tiers {
            if Task.isCancelled { break }
            switch tier {
            case .cloud:
                triedCloud = true
                switch await cloudGeneration(input, progress: &progress, onProgress: onProgress) {
                case .success(var outcome):
                    outcome.fellBack = fellBack
                    return outcome
                case .limit(let key):
                    limitReached = key
                    fellBack = true
                    // The free limit removes the cloud only: this iPhone's model is still tried next (AIRouting rule 1).
                case .failed(let why):
                    cloudFailure = why
                    fellBack = true
                }
            case .onDevice, .privateCloud:
                if var outcome = await onDeviceGeneration(input, texts: texts, rules: rules, tier: tier, progress: &progress,
                                                          onProgress: onProgress) {
                    outcome.fellBack = fellBack
                    outcome.cloudFailure = triedCloud && limitReached == nil ? cloudFailure : nil
                    // A limit the relay reported mid-job keeps its paywall card; the iPhone's model still wrote the set.
                    outcome.suggestion = limitReached.map(limitSuggestion) ?? route.suggestion
                    outcome.limitReached = limitReached
                    // Cloud was tried first and didn't answer: the review says why this iPhone wrote the set.
                    if fellBack, triedCloud {
                        outcome.note = limitReached != nil
                            ? "You've used this week's free Cloud AI scans, so your iPhone's AI wrote these."
                            : Self.deviceNote(cloudFailure)
                    }
                    return outcome
                }
                fellBack = true
            case .rules:
                break
            }
        }
        return rulesOutcome(rules, texts: texts, route: route, limitReached: limitReached, fellBack: fellBack,
                            triedCloud: triedCloud, cloudFailure: cloudFailure, progress: &progress, onProgress: onProgress)
    }

    // MARK: Cloud

    enum Attempt<Value> {
        case success(Value)
        case limit(QuotaMeter.Key)
        case failed
    }

    /// Why Cloud AI gave no set, for the note that says so (`basicNote`, `deviceNote`).
    enum CloudFailure: Equatable, Sendable {
        /// Offline, timed out, a server error.
        case unreachable
        /// The anonymous account isn't made yet (sign-ups are rate limited); it is retried in the background.
        case gettingReady
        /// The relay refused for a limit that isn't a free meter (the day's cost cap, fair use), in its own words.
        case refused(String)
        /// Cloud AI answered, but nothing it wrote was on the page.
        case nothingUsable
        /// The relay still found a part too long after it was halved.
        case tooLong

        /// A sentence that says what happened.
        var sentence: String {
            switch self {
            case .unreachable: "Cloud AI couldn't be reached."
            case .gettingReady: "Cloud AI is getting ready."
            case .refused(let message): message
            case .nothingUsable: "Cloud AI's questions didn't match your page."
            case .tooLong: "Cloud AI couldn't take a reading this long."
            }
        }
    }

    private enum CloudRun {
        case success(GenerationOutcome)
        case limit(QuotaMeter.Key)
        case failed(CloudFailure)
    }

    private enum PartRun {
        case done(PartResult)
        case limit(QuotaMeter.Key)
        /// `entitlement_required`: the relay found the part longer than the plan's scan.
        case tooManyPages
        case failed(CloudFailure)
    }

    private struct PartResult {
        var response: GenerateResponse
        var items: [GeneratedItem]
        var dropped: [DroppedItem]
        var checkedByRules: Bool
        var note: String?
    }

    /// A long reading goes to Cloud AI in the fewest parts the plan allows (slices of consecutive pages with similar word
    /// counts, none asking for more than 20 questions), one after another; each part is a normal generate and check, and
    /// each counts as one scan for the student (the relay's rule). When the week's free scans run out between parts, or a
    /// later part fails, what the finished parts wrote is kept and a note names the pages left out. If the first part
    /// fails, the next tier answers and the note says why.
    private func cloudGeneration(_ input: GenerationInput, progress: inout GenerationProgress,
                                 onProgress: @MainActor (GenerationProgress) -> Void) async -> CloudRun {
        guard cloudStillAllowed(), let transport else { return .failed(.unreachable) }
        progress.phase = .findingKeyIdeas
        progress.origin = .cloud
        progress.detail = "With Cloud AI"
        onProgress(progress)

        let plan = self.plan
        let labels = input.pages.map(\.label)
        let pageWords = input.pages.map { GenerationPlan.wordCount(of: $0) }
        let language = LocalGenerator.dominantLanguage(input.pages.flatMap { $0.lines.map(\.text) }.joined(separator: " "),
                                                       courseLanguage: input.courseLanguage)
        var cap = AIFreeLimits.pagesPerScan(plan)
        var halved = false

        planning: while true {
            let parts = GenerationPlan.parts(pageWords: pageWords, pageCap: cap, questions: input.maxItems, plan: plan,
                                             runnable: runnableScans())
            var done = RunAccumulator(parts: parts)
            progress.parts = parts.filter(\.affordable).count

            for part in parts {
                if Task.isCancelled { break }
                // Pages the scans left can't pay for wait; that was decided from the scans meter when the parts were cut, never from a
                // part's number of questions.
                if !part.affordable {
                    done.leftOut(part, because: .scans)
                    continue
                }
                if part.number > 1 {
                    // Consent may have been withdrawn, or the week's free scans run out (on another device, say), while the earlier
                    // parts were read.
                    if !cloudStillAllowed() {
                        done.fail(part, .unreachable)
                        done.stop(after: part)
                        break
                    }
                    if isExhausted(.generate) {
                        done.leftOut(part, because: .scans)
                        continue
                    }
                }
                progress.part = part.number
                switch await runPart(part, of: input, language: language, transport: transport, progress: &progress,
                                     onProgress: onProgress) {
                case .done(let result):
                    done.add(part, result)
                case .limit(let key):
                    done.leftOut(part, because: key)
                    done.stop(after: part)
                case .tooManyPages:
                    // The relay counts pages differently from this app (a purchase it hasn't heard of yet): halve the
                    // parts once and start again.
                    if part.number == 1, !halved, part.pages.count > 1 {
                        cap = max(1, cap / 2)
                        halved = true
                        continue planning
                    }
                    done.fail(part, .tooLong)
                    done.stop(after: part)
                case .failed(let why):
                    done.fail(part, why)
                    // Offline, rate limited or refused: the next part would meet the same wait. A part whose questions
                    // didn't match the page says nothing about the others.
                    if why != .nothingUsable { done.stop(after: part) }
                }
                if done.stopped { break }
            }
            return finish(done, input: input, labels: labels, plan: plan)
        }
    }

    /// How many more parts the plan can pay for (nil: no limit): the week's scans left, and one more when a page reading just opened a
    /// scan window the first part can ride on for nothing (`ScanWindow`).
    private func runnableScans() -> Int? {
        switch quotaState(for: .generate) {
        case .unmetered: nil
        case .available(let remaining): remaining + (canRideOpenScanWindow ? 1 : 0)
        case .exhausted: 0
        }
    }

    private func isExhausted(_ job: AIJob) -> Bool { quotaState(for: job) == .exhausted }

    /// The outcome of a run, from what its parts wrote.
    private func finish(_ done: RunAccumulator, input: GenerationInput, labels: [String], plan: Plan) -> CloudRun {
        guard !done.items.isEmpty else {
            if let key = done.limit { return .limit(key) }
            return .failed(done.firstFailure ?? .nothingUsable)
        }
        var notes: [String?] = []
        var suggestion: AISuggestion?
        if let key = done.limit {
            suggestion = limitSuggestion(key)
            notes.append(GenerationPlan.limitNote(read: done.read, left: done.notRead, labels: labels))
        } else if !done.notRead.isEmpty {
            notes.append(GenerationPlan.skippedNote(read: done.read, skipped: done.notRead, labels: labels))
        } else if done.parts.count > 1 {
            notes.append(GenerationPlan.partsNote(parts: done.parts.count, plan: plan))
        }
        notes.append(contentsOf: done.notes)
        let used = Set(done.items.map(\.topic))
        let outcome = GenerationOutcome(title: done.title, topics: done.topics.filter { used.contains($0.name) },
                                        items: done.items, dropped: done.dropped, origin: .cloud, model: done.model,
                                        checkedBy: done.checkedByRules ? .rules : .cloud, note: GenerationPlan.joined(notes),
                                        suggestion: suggestion, limitReached: done.limit, fellBack: false,
                                        parts: done.reports(labels: labels, indexes: input.pages.map(\.index)))
        return .success(outcome)
    }

    /// One part: generate, the anchor check, the relay's check (asked again leniently when it rejects nearly everything,
    /// and replaced by this iPhone's when it still does).
    private func runPart(_ part: GenerationPlan.Part, of input: GenerationInput, language: String,
                         transport: any RelayTransport, progress: inout GenerationProgress,
                         onProgress: @MainActor (GenerationProgress) -> Void) async -> PartRun {
        let pages = Array(input.pages[part.pages])
        let texts = GroundingCheck.texts(of: pages)
        let multi = progress.parts > 1
        if multi { progress.detail = "Part \(part.number) of \(progress.parts)"; onProgress(progress) }

        // Built now, from what is true now: page photos go along only if that switch is on at this moment.
        let request = await makeGenerateRequest(input, pages: pages, maxItems: part.maxItems, language: language)
        let response: GenerateResponse
        do {
            response = try await transport.generate(request)
        } catch {
            let relay = HTTPRelayTransport.map(error)
            if let key = absorbQuotaError(relay, meter: .scans) { return .limit(key) }
            if relay == .entitlementRequired { return .tooManyPages }
            return .failed(Self.cloudFailure(for: relay))
        }
        // One scan unless this rides on a window a page reading opened (`ScanWindow`).
        recordScanRequest(.generate, pages: part.pages.count)
        progress.phase = max(progress.phase, .writingQuestions)
        for topic in response.topics.map(\.name) where !progress.topics.contains(topic) { progress.topics.append(topic) }
        progress.written += response.items.count
        if !multi { progress.detail = "\(response.items.count) questions" }
        onProgress(progress)

        // Every anchor must be a line of the part's pages, whoever wrote the item.
        var (items, dropped) = GroundingCheck.apply(response.items, texts: texts, anchorsOnly: true)
        progress.phase = .checking
        if !multi { progress.detail = "So nothing made up gets through" }
        onProgress(progress)

        var checkedByRules = false
        var note: String?
        // After the wait: consent may have been withdrawn while the questions were being written.
        if cloudStillAllowed(), !Task.isCancelled, !items.isEmpty {
            do {
                let checked = try await checkWithRelay(items, pages: pages, title: input.sourceTitle, transport: transport)
                switch checked {
                case .verdicts(let verdicts):
                    let applied = Self.applyCheck(verdicts, to: items)
                    items = applied.kept
                    dropped += applied.dropped
                case .rejectedEverything:
                    // Palsgraf: the cited lines never name the judge, so the check called every question unsupported.
                    let local = GroundingCheck.apply(items, texts: texts, minimumOverlap: 0.34)
                    items = local.kept
                    dropped += local.dropped
                    checkedByRules = true
                    note = GenerationPlan.checkedOnThisIPhoneNote
                }
            } catch {
                let local = GroundingCheck.apply(items, texts: texts, minimumOverlap: 0.34)
                items = local.kept
                dropped += local.dropped
                checkedByRules = true
            }
        } else {
            let local = GroundingCheck.apply(items, texts: texts, minimumOverlap: 0.34)
            items = local.kept
            dropped += local.dropped
            checkedByRules = true
        }
        guard !items.isEmpty else { return .failed(.nothingUsable) }
        progress.checked += response.items.count
        progress.kept += items.count
        if !multi { progress.detail = "\(items.count) of \(response.items.count) match the page" }
        onProgress(progress)
        return .done(PartResult(response: response, items: items, dropped: dropped, checkedByRules: checkedByRules, note: note))
    }

    private enum RelayCheck {
        case verdicts([CheckVerdict])
        case rejectedEverything
    }

    /// The relay's check, with the source's title and headings; asked once more with `lenient: true` when it rejects
    /// nearly everything (`CheckPolicy`).
    private func checkWithRelay(_ items: [GeneratedItem], pages: [PageText], title: String,
                                transport: any RelayTransport) async throws -> RelayCheck {
        let checkPages = pages.map {
            PageInput(page: $0.index, label: $0.label.clipped(toScalars: RelayLimits.label),
                      lines: $0.lines.prefix(RelayLimits.pageLines).map { LineInput(id: $0.id, text: $0.text.clipped(toScalars: RelayLimits.lineText)) },
                      image: nil)
        }
        let context = CheckRequest.context(title: title, headings: Self.headings(of: pages))
        let ids = items.map(\.id)
        var request = CheckRequest(pages: checkPages, items: items, sourceTitle: context.title, headings: context.headings)
        var verdicts = try await transport.check(request).verdicts
        var step = CheckPolicy.step(after: verdicts, itemIDs: ids, lenient: false)
        if step == .retryLenient, cloudStillAllowed(), !Task.isCancelled {
            request.lenient = true
            verdicts = try await transport.check(request).verdicts
            step = CheckPolicy.step(after: verdicts, itemIDs: ids, lenient: true)
        }
        return step == .accept ? .verdicts(verdicts) : .rejectedEverything
    }

    /// The title and section headings of the pages, as the check takes them: what a question about a court opinion or a
    /// chapter names that its cited lines don't.
    static func headings(of pages: [PageText]) -> [String] {
        var out: [String] = []
        for page in pages {
            let structure = PageStructure.read(page.lines)
            if let title = structure.title?.text { out.append(title) }
            out += structure.sections.compactMap { $0.heading?.text }
            out += structure.groups.flatMap { $0.siblings.map(\.name.text) }
        }
        return out
    }

    static func cloudFailure(for relay: RelayError) -> CloudFailure {
        if relay == .accountPending { return .gettingReady }
        switch relay {
        case .quotaExceeded(_, let message): return .refused(message)
        case .entitlementRequired: return .tooLong
        default: return .unreachable
        }
    }

    /// What the parts of a run have written so far.
    private struct RunAccumulator {
        let parts: [GenerationPlan.Part]
        var title = ""
        var model = ""
        var topics: [GeneratedTopic] = []
        var items: [GeneratedItem] = []
        var dropped: [DroppedItem] = []
        var checkedByRules = false
        var notes: [String] = []
        var read: [Range<Int>] = []
        var notRead: [Range<Int>] = []
        var limit: QuotaMeter.Key?
        var firstFailure: CloudFailure?
        var stopped = false
        private var status: [Int: GenerationPartReport.Status] = [:]
        private var kept: [Int: Int] = [:]

        init(parts: [GenerationPlan.Part]) { self.parts = parts }

        mutating func add(_ part: GenerationPlan.Part, _ result: PartResult) {
            if title.isEmpty { title = result.response.title }
            if model.isEmpty { model = result.response.model }
            // A name seen before keeps its first spelling; ids stay unique across parts.
            for topic in result.response.topics where !topics.contains(where: { $0.name.caseInsensitiveCompare(topic.name) == .orderedSame }) {
                topics.append(topic)
            }
            let prefix = part.number == 1 ? "" : "s\(part.number)-"
            for var item in result.items {
                item.id = prefix + item.id
                if let known = topics.first(where: { $0.name.caseInsensitiveCompare(item.topic) == .orderedSame }) { item.topic = known.name }
                items.append(item)
            }
            for var drop in result.dropped {
                drop.item.id = prefix + drop.item.id
                dropped.append(drop)
            }
            checkedByRules = checkedByRules || result.checkedByRules
            if let note = result.note, !notes.contains(note) { notes.append(note) }
            read.append(part.pages)
            status[part.number] = .read
            kept[part.number] = result.items.count
        }

        mutating func fail(_ part: GenerationPlan.Part, _ why: CloudFailure) {
            if firstFailure == nil { firstFailure = why }
            notRead.append(part.pages)
            status[part.number] = .failed
        }

        /// The week's free scans ran out before this part.
        mutating func leftOut(_ part: GenerationPlan.Part, because key: QuotaMeter.Key) {
            limit = limit ?? key
            notRead.append(part.pages)
            status[part.number] = status[part.number] ?? .notStarted
        }

        mutating func stop(after part: GenerationPlan.Part) {
            stopped = true
            for later in parts where later.number > part.number {
                notRead.append(later.pages)
                status[later.number] = .notStarted
            }
        }

        func reports(labels: [String], indexes: [Int]) -> [GenerationPartReport] {
            parts.map { part in
                GenerationPartReport(number: part.number, firstPage: labels[part.pages.lowerBound],
                                     lastPage: labels[part.pages.upperBound - 1], pageCount: part.pages.count,
                                     pageIndexes: part.pages.map { indexes[$0] },
                                     status: status[part.number] ?? .notStarted, kept: kept[part.number] ?? 0)
            }
        }
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

    private func makeGenerateRequest(_ input: GenerationInput, pages source: [PageText], maxItems: Int,
                                     language: String) async -> GenerateRequest {
        let photos = app.map { AIConsent.photosGranted($0.settings) } ?? false
        var pages: [PageInput] = []
        for page in source {
            var image: String?
            if photos, let url = page.imageURL { image = await AIImagePrep.base64JPEG(at: url) }
            pages.append(PageInput(page: page.index, label: page.label.clipped(toScalars: RelayLimits.label),
                                   lines: page.lines.prefix(RelayLimits.pageLines).map {
                                       LineInput(id: $0.id, text: $0.text.clipped(toScalars: RelayLimits.lineText))
                                   },
                                   image: image))
        }
        // Preparing photos takes a moment per page: if the switch went off meanwhile, none go.
        if photos, !(app.map { AIConsent.photosGranted($0.settings) } ?? false) {
            pages = pages.map { PageInput(page: $0.page, label: $0.label, lines: $0.lines, image: nil) }
        }
        // The relay counts code points, so a name that is short to read can still be too long to send: cut by scalars.
        return GenerateRequest(course: input.course.clipped(toScalars: RelayLimits.course),
                               sourceTitle: input.sourceTitle.clipped(toScalars: RelayLimits.title),
                               level: input.level?.clipped(toScalars: RelayLimits.level), language: language, formats: input.formats,
                               maxItems: maxItems, pages: pages)
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

        // One page at a time, cut into pieces that fit the model's window. This iPhone's model keeps a target of 16
        // questions however long the source is (it is slow and less sure on long readings); the rules fill in the rest.
        let target = min(input.maxItems, AIFreeLimits.onDeviceQuestions)
        let limit = budget.promptTokens(instructions: OnDevicePageCall.instructions, schemaTokens: OnDevicePageCall.schemaTokens,
                                        responseTokens: OnDevicePageCall.responseTokens) - 30
        var topics: [String] = []
        var items: [GeneratedItem] = []
        var next = 1
        for page in input.pages {
            let lines = page.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            for chunk in budget.chunks(lines, limit: max(1, limit), render: OnDevicePageCall.render) {
                if Task.isCancelled { return nil }
                guard items.count < target else { break }
                let call = OnDevicePageCall(lines: chunk, maxQuestions: min(8, target - items.count))
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

    /// The model's items first, then the rules' items that add a different question (another prompt, other lines, not the same fact in
    /// other words) up to `limit`; multiple choice from the rules is preferred because the model doesn't write it.
    static func merge(_ model: [GeneratedItem], with rules: [GeneratedItem], limit: Int) -> [GeneratedItem] {
        var out = Array(model.prefix(limit))
        var prompts = Set(out.map { Lexicon.normalizedAnswer($0.prompt) })
        var anchorSets = Set(out.map { $0.anchors.sorted().joined(separator: ",") + "#" + $0.kind.rawValue })
        let ordered = rules.filter { $0.kind == .mcq } + rules.filter { $0.kind != .mcq }
        for item in ordered where out.count < limit {
            let prompt = Lexicon.normalizedAnswer(item.prompt)
            let key = item.anchors.sorted().joined(separator: ",") + "#" + item.kind.rawValue
            guard !prompts.contains(prompt), !anchorSets.contains(key) else { continue }
            // Nor the same fact the model already asked in other words (its card and the rules' fill-in of one definition).
            guard !out.contains(where: { QuestionQuality.isNearDuplicate($0, item) }) else { continue }
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
                              limitReached: QuotaMeter.Key?, fellBack: Bool, triedCloud: Bool, cloudFailure: CloudFailure?,
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
        // The check can empty a set the generator thought basic: the note then says so instead of "basic questions".
        let quality: LocalGenerator.Result.Quality = kept.isEmpty && rules.quality != .unsupportedLanguage ? .empty : rules.quality
        var outcome = GenerationOutcome(title: rules.title, topics: rules.topics.filter { used.contains($0.name) }, items: kept,
                                        dropped: dropped, origin: .rules, model: LocalGrader.model, checkedBy: .rules,
                                        note: basicNote(quality, route: route, limitReached: limitReached, fellBack: fellBack,
                                                        triedCloud: triedCloud, cloudFailure: cloudFailure, hasItems: !kept.isEmpty),
                                        suggestion: suggestion, limitReached: limitReached, fellBack: fellBack)
        outcome.cloudFailure = triedCloud && limitReached == nil ? cloudFailure : nil
        return outcome
    }

    /// The review screen's honest line about an offline set. It always says something: an empty set, or one that is only
    /// term cards, says why (a page that isn't English, a free limit, Cloud AI not reachable) and what would help.
    func basicNote(_ quality: LocalGenerator.Result.Quality, route: AIRoute, limitReached: QuotaMeter.Key?, fellBack: Bool,
                   triedCloud: Bool, cloudFailure: CloudFailure? = nil, hasItems: Bool = true) -> String {
        switch quality {
        case .unsupportedLanguage:
            return languageNote(route: route, limitReached: limitReached, fellBack: fellBack, triedCloud: triedCloud,
                                cloudFailure: cloudFailure, hasItems: hasItems)
        case .empty:
            if limitReached != nil { return "You've used this week's free AI scans, and the offline rules couldn't find questions on this page." }
            if fellBack, triedCloud { return "\((cloudFailure ?? .unreachable).sentence) The offline rules couldn't find questions on this page either." }
            return "The offline rules couldn't find questions on this page."
        default:
            break
        }
        if limitReached != nil {
            return "You've used this week's free AI scans, so these are basic questions from the offline rules."
        }
        if fellBack {
            guard triedCloud else { return "Your iPhone's AI couldn't write these, so they're basic questions from the offline rules." }
            switch cloudFailure ?? .unreachable {
            case .unreachable: return "Cloud AI couldn't be reached, so these are basic questions from the offline rules."
            case .gettingReady: return "Cloud AI is getting ready, so these are basic questions from the offline rules. Try again in a minute."
            case .refused(let message): return "\(message) These are basic questions from the offline rules."
            case .nothingUsable: return "Cloud AI's questions didn't match your page, so these are basic questions from the offline rules."
            case .tooLong: return "Cloud AI couldn't take a reading this long, so these are basic questions from the offline rules."
            }
        }
        if case .allowCloud = route.suggestion {
            return "Basic questions from the offline rules. Turn on Cloud AI for better ones."
        }
        return "Basic questions from the offline rules."
    }

    /// A page that isn't English: the offline rules write questions for English only (and, on any other language, term
    /// cards at most), so the note says so in plain words, and what would write questions for it.
    private func languageNote(route: AIRoute, limitReached: QuotaMeter.Key?, fellBack: Bool, triedCloud: Bool,
                              cloudFailure: CloudFailure?, hasItems: Bool) -> String {
        var note = "This page doesn't look like English, and the offline rules only write questions for English pages"
        note += hasItems ? ", so these are just the term cards on it." : "."
        if limitReached != nil {
            note += " This week's free AI scans are used up. Cloud AI can write questions for it once they reset, or with Capling Pro."
        } else if triedCloud, fellBack {
            note += " \((cloudFailure ?? .unreachable).sentence) Try again later."
        } else if case .allowCloud = route.suggestion {
            note += " Cloud AI can write questions for it."
        }
        return note
    }

    /// The line on a review whose set was written again and came out weaker than the one in it (Cloud AI didn't answer this time, so
    /// this iPhone's model or the rules wrote it): the earlier questions stay, and this says why.
    static func keptNote(_ failure: CloudFailure?, limitReached: QuotaMeter.Key?, earlier: ItemOrigin) -> String {
        if limitReached != nil { return "You've used this week's free Cloud AI scans, so your earlier questions are kept." }
        guard earlier == .cloud else { return "Your iPhone's AI couldn't write them again, so your earlier questions are kept." }
        switch failure ?? .unreachable {
        case .unreachable: return "Cloud AI couldn't be reached, so your earlier questions are kept."
        case .gettingReady: return "Cloud AI is getting ready, so your earlier questions are kept. Try again in a minute."
        case .refused(let message): return "\(message) Your earlier questions are kept."
        case .nothingUsable: return "Cloud AI's questions didn't match your page, so your earlier questions are kept."
        case .tooLong: return "Cloud AI couldn't take a reading this long, so your earlier questions are kept."
        }
    }

    /// The line on a set this iPhone's AI wrote because Cloud AI, tried first, didn't answer.
    static func deviceNote(_ failure: CloudFailure?) -> String {
        switch failure ?? .unreachable {
        case .unreachable: "Cloud AI couldn't be reached, so your iPhone's AI wrote these."
        case .gettingReady: "Cloud AI is getting ready, so your iPhone's AI wrote these. Try Cloud AI again in a minute."
        case .refused(let message): "\(message) Your iPhone's AI wrote these."
        case .nothingUsable: "Cloud AI's questions didn't match your page, so your iPhone's AI wrote these."
        case .tooLong: "Cloud AI couldn't take a reading this long, so your iPhone's AI wrote these."
        }
    }
}
