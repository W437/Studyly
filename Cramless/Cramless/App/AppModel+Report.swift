import Foundation
import SwiftData

/// One re-check's result on its way to the open question: `SessionQuestionHost` reads it when the sheet closes.
struct RecheckDelivery: Equatable, Sendable {
    var itemID: UUID
    var result: RecheckResult
    /// What the student answered, for the review log when the answer comes to count.
    var given: String?
}

/// The lines a question came from, read on this iPhone.
struct ReportSource: Equatable, Sendable {
    var ref: SourceRef
    /// "p. 87", "Lecture 6".
    var place: String
    var lines: [String]
    var isLecture: Bool
}

// "Looks wrong?": the student says a question looks wrong and Cap re-reads the lines it came from. A report takes the question out of
// sessions at once (`ItemSnapshot.reported`, `SessionBuilder`), and it stays in readiness: a report isn't a judgement yet. What's sent is the
// question, the lines it points at, the source's title and headings, and the report. A report is a claim to verify: the relay's prompt
// says so, and only the verdict changes anything here.
extension AppModel {
    /// The one question a re-check asks about goes by this id. (A fixture and a verdict can name it.)
    static let recheckKey = "reported"

    // MARK: The ledger

    private var reportLedger: ReportLedger {
        get {
            guard let data = defaults.data(forKey: ReportLedger.defaultsKey),
                  let ledger = try? JSONDecoder.cramless.decode(ReportLedger.self, from: data) else { return ReportLedger() }
            return ledger
        }
        set {
            if let data = try? JSONEncoder.cramless.encode(newValue) { defaults.set(data, forKey: ReportLedger.defaultsKey) }
        }
    }

    /// How many "my answer should count" today still has.
    func myAnswerReportsLeft() -> Int {
        reportLedger.myAnswerLeft(on: calendar.dayKey(for: now))
    }

    /// Takes one of today's "my answer should count" (an own-words answer spends it going back to the grader). False when they are used up.
    @discardableResult
    func spendMyAnswerReport() -> Bool {
        var ledger = reportLedger
        guard ledger.spendMyAnswer(on: calendar.dayKey(for: now)) else { return false }
        reportLedger = ledger
        return true
    }

    // MARK: Reading

    /// The item's own lines, offline, for the sheet. Nil with nothing to show (a question the student wrote, an imported card).
    func reportSource(of item: StudyItem) -> ReportSource? {
        guard let ref = item.sourceRef, !ref.anchorIDs.isEmpty, let source = source(ref.sourceID), source.deletedAt == nil else { return nil }
        let wanted = Set(ref.anchorIDs)
        if source.kind == .lecture {
            let lines = source.segments.sorted { $0.start < $1.start }.filter { wanted.contains($0.id) }.map(\.text)
            guard !lines.isEmpty else { return nil }
            let name = source.title.split(separator: ":").first.map(String.init) ?? source.title
            return ReportSource(ref: ref, place: name, lines: lines, isLecture: true)
        }
        let pages = ref.pageIndex.map { index in source.sortedPages.filter { $0.pageIndex == index } } ?? source.sortedPages
        let lines = pages.flatMap(\.lines).filter { wanted.contains($0.id) }.map(\.text)
        guard !lines.isEmpty else { return nil }
        let place = pages.first { page in page.lines.contains { wanted.contains($0.id) } }.map { String(localized: "p. \($0.label)") } ?? source.title
        return ReportSource(ref: ref, place: place, lines: lines, isLecture: false)
    }

    /// Whether Cap could re-read a question at all in this build for this person (the consent may still be to give).
    var canAskCapToCheck: Bool {
        ai.cloudAvailableInThisBuild && AIAgeGate(settings) != .child
    }

    // MARK: Reporting

    /// Files a report: the question leaves sessions at once and stays in readiness. A "my answer should count" past the day's limit is refused
    /// (false). The words go only as far as the check, cut to the relay's limits.
    @discardableResult
    func reportItem(_ id: UUID, reason: CheckReport.Reason, given: String? = nil, note: String? = nil) -> Bool {
        guard let item = item(id), item.deletedAt == nil else { return false }
        var ledger = reportLedger
        if reason == .myAnswerCounts, !ledger.spendMyAnswer(on: calendar.dayKey(for: now)) { return false }
        ledger.pending[id.uuidString] = ItemReport(reason: reason, given: Self.reportWords(given, limit: RelayLimits.reportGiven),
                                                   note: Self.reportWords(note, limit: RelayLimits.reportNote), at: now)
        reportLedger = ledger
        item.reported = true
        touch(item)
        save()
        return true
    }

    private static func reportWords(_ text: String?, limit: Int) -> String? {
        let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines).clipped(toScalars: limit) ?? ""
        return clean.isEmpty ? nil : clean
    }

    /// "Put it back in my sessions": the report is dropped unchecked.
    func withdrawReport(_ id: UUID) {
        guard let item = item(id) else { return }
        forgetReport(id)
        guard item.reported else { return }
        item.reported = false
        touch(item)
        save()
    }

    private func forgetReport(_ id: UUID) {
        var ledger = reportLedger
        guard ledger.pending.removeValue(forKey: id.uuidString) != nil else { return }
        reportLedger = ledger
    }

    // MARK: The re-check

    /// The request for one reported question: only its anchored lines (a lecture's segments, as one page), the source's title and headings, and
    /// the report. Never a photo. Nil when nothing it points at is left.
    func recheckRequest(for item: StudyItem, report: ItemReport) -> CheckRequest? {
        guard let ref = item.sourceRef, !ref.anchorIDs.isEmpty, let source = source(ref.sourceID), source.deletedAt == nil else { return nil }
        let wanted = Set(ref.anchorIDs)
        var pages: [PageInput] = []
        var headings: [String] = []
        if source.kind == .lecture {
            let lines = source.segments.sorted { $0.start < $1.start }.filter { wanted.contains($0.id) }
                .map { LineInput(id: $0.id, text: $0.text.clipped(toScalars: RelayLimits.lineText)) }
            if !lines.isEmpty { pages = [PageInput(page: 0, label: "Lecture", lines: lines, image: nil)] }
        } else {
            let candidates = ref.pageIndex.map { index in source.sortedPages.filter { $0.pageIndex == index } } ?? source.sortedPages
            pages = candidates.compactMap { page in
                let lines = page.lines.filter { wanted.contains($0.id) }
                    .map { LineInput(id: $0.id, text: $0.text.clipped(toScalars: RelayLimits.lineText)) }
                return lines.isEmpty ? nil : PageInput(page: page.pageIndex, label: page.label.clipped(toScalars: RelayLimits.label), lines: lines, image: nil)
            }
            headings = AIRouter.headings(of: candidates.map(pageText))
        }
        guard !pages.isEmpty else { return nil }
        let context = CheckRequest.context(title: source.title, headings: headings)
        let question = GeneratedItem(id: Self.recheckKey, kind: item.kind, topic: "", prompt: item.prompt.clipped(toScalars: RelayLimits.contextPrompt),
                                     answer: item.answer.clipped(toScalars: RelayLimits.contextAnswer),
                                     explanation: item.explanation.clipped(toScalars: RelayLimits.contextAnswer),
                                     keyIdeas: item.keyIdeas, choices: item.choices, cloze: item.cloze,
                                     anchors: pages.flatMap { $0.lines.map(\.id) }, difficulty: item.difficultyHint)
        return CheckRequest(pages: pages, items: [question], sourceTitle: context.title, headings: context.headings,
                            reports: [CheckReport(id: Self.recheckKey, reason: report.reason, given: report.given, note: report.note)])
    }

    /// Asks Cap about a reported question and applies the verdict. `.queued` when it can't be asked now: the report waits for `runPendingRechecks`.
    @discardableResult
    func recheck(_ id: UUID) async -> RecheckResult {
        guard let item = item(id), item.deletedAt == nil, item.reported else { return .queued }
        let report = reportLedger.report(for: id) ?? ItemReport(reason: .other, at: now)
        guard let request = recheckRequest(for: item, report: report) else { return .queued }
        guard rechecksInFlight.insert(id).inserted else { return .queued }
        defer { rechecksInFlight.remove(id) }
        guard let verdict = await ai.recheck(request, itemKey: Self.recheckKey) else { return .queued }
        // Read again after the wait: it may have been edited, deleted or put back meanwhile.
        guard let fresh = self.item(id), fresh.deletedAt == nil, fresh.reported else { return .queued }
        return apply(verdict, to: fresh)
    }

    private func apply(_ verdict: CheckVerdict, to item: StudyItem) -> RecheckResult {
        let change = RecheckChange.from(verdict, kind: item.kind, choices: item.choices)
        let result: RecheckResult
        switch change {
        case .stands:
            item.checkedAt = now
            result = .stands
        case .replace(let answer, let choices):
            item.answer = answer
            if let choices { item.choices = choices }
            if !verdict.reason.isEmpty { item.explanation = verdict.reason }
            item.checkedAt = now
            result = .fixed
        case .retire:
            item.status = .suspended
            result = .retired
        case .needsEdit:
            item.status = .suspended
            result = .needsEdit
        }
        item.reported = false
        recheckReasons[item.id] = verdict.reason
        forgetReport(item.id)
        touch(item)
        save()
        return result
    }

    /// What Cap read on the page, for the sheet that asked.
    func recheckReason(for id: UUID) -> String? { recheckReasons[id] }

    /// Asks about every report still waiting, on becoming active and after consent. A report with nothing left to check is let go, so
    /// its question comes back. Says once what came of them.
    func runPendingRechecks() async {
        guard ai.cloudStillAllowed() else { return }
        let waiting = fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.reported && $0.deletedAt == nil }))
            .filter { !rechecksInFlight.contains($0.id) }
        var ledger = reportLedger
        let live = Set(waiting.map(\.id.uuidString))
        let flying = Set(rechecksInFlight.map(\.uuidString))
        let pruned = ledger.pending.filter { live.contains($0.key) || flying.contains($0.key) }
        if pruned.count != ledger.pending.count {
            ledger.pending = pruned
            reportLedger = ledger
        }
        var results: [RecheckResult] = []
        for item in waiting {
            guard item.modelContext != nil else { continue }
            guard recheckRequest(for: item, report: ledger.report(for: item.id) ?? ItemReport(reason: .other, at: now)) != nil else {
                withdrawReport(item.id)
                continue
            }
            let result = await recheck(item.id)
            if result == .queued { break }
            results.append(result)
        }
        guard let first = results.first else { return }
        if results.count > 1 {
            router.toast("Cap checked the questions you reported.")
        } else {
            switch first {
            case .fixed: router.toast("Cap fixed a question you reported.")
            case .stands: router.toast("The page agrees with a question you reported. It's back in your sessions.")
            case .retired, .needsEdit: router.toast("Cap took a question you reported out of your sessions.", systemImage: "pause.circle.fill", tone: .neutral)
            case .queued, .regrade: break
            }
        }
    }

    // MARK: The open question

    /// The sheet closed: the open question acts on how it came out.
    func deliverRecheck(_ id: UUID, result: RecheckResult, given: String?) {
        recheckDelivery = RecheckDelivery(itemID: id, result: result, given: given)
    }

    func takeRecheckDelivery() {
        recheckDelivery = nil
    }
}
