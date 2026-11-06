import Foundation
import SwiftData

/// A question that has become too easy, ready to be moved up.
struct LadderOffer: Identifiable, Equatable, Sendable {
    var itemID: UUID
    var next: ItemKind
    /// The idea's name for the card's title.
    var topicName: String?
    var id: UUID { itemID }
}

/// Where writing a harder question came to.
enum RungWriting: Equatable, Sendable {
    case proposal(UUID)
    case failed(String)
}

// Harder questions (`Ladder`): the store's side. A harder question arrives as a draft the student adds; adding it starts it with a seeded
// memory and rests the easy one (Undo takes that back), so one idea stays one review and readiness holds. Deleting an added one
// wakes the easy one. The harder question points at the easy one with `rungOf`, which syncs.
extension AppModel {
    private static let snoozeKey = "capling.ladder.snoozed"
    private static let declineDays = 30

    /// Questions worth moving up, the strongest first, only those whose swap keeps every exam's readiness within `Ladder.maxReadinessDrop`.
    func ladderOffers(items given: [ItemSnapshot]? = nil, exams givenExams: [ExamSnapshot]? = nil) -> [LadderOffer] {
        guard ai.cloudStillAllowed() else { return [] }
        let items = given ?? itemSnapshots()
        let strong = items.filter { $0.memory.state == .review && $0.memory.stability >= Ladder.strongStability && !$0.reported }
            .sorted { $0.memory.stability > $1.memory.stability }.prefix(30)
        guard !strong.isEmpty else { return [] }
        let exams = givenExams ?? examSnapshots(upcomingOnly: true)
        // A draft still waiting doesn't count: the card comes back for it, and writing finds the same draft, so nothing is spent twice.
        let climbed = Set(fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.rungOf != nil && $0.deletedAt == nil }))
            .filter { $0.status != .draft }.compactMap(\.rungOf))
        let snoozed = ladderSnoozes()
        let candidates = strong.compactMap { snapshot -> Ladder.Candidate? in
            guard let item = item(snapshot.id) else { return nil }
            return Ladder.Candidate(id: snapshot.id, kind: snapshot.kind, memory: snapshot.memory,
                                    reviews: recentAnswers(itemIDs: [snapshot.id], limit: Ladder.strongRun),
                                    hasAnchors: reportSource(of: item) != nil, climbed: climbed.contains(snapshot.id),
                                    snoozed: snoozed[snapshot.id.uuidString].map { $0 > now.timeIntervalSince1970 } ?? false,
                                    soonestExam: exams.filter { $0.covers(snapshot) }.map(\.date).min())
        }
        let names = topicNames()
        return Ladder.offers(candidates, cloudUsable: true, now: now, calendar: calendar).compactMap { offer in
            guard let parent = items.first(where: { $0.id == offer.itemID }),
                  readinessDrop(ifRaising: parent, items: items, exams: exams) < Ladder.maxReadinessDrop else { return nil }
            return LadderOffer(itemID: offer.itemID, next: offer.next, topicName: parent.topicID.flatMap { names[$0] })
        }
    }

    /// The most any exam's readiness would fall, in points, if a harder question took this one's place.
    func readinessDrop(ifRaising parent: ItemSnapshot, items: [ItemSnapshot], exams: [ExamSnapshot]) -> Double {
        var rung = parent
        rung.id = UUID()
        rung.memory = Ladder.seedMemory(parent: parent.memory, now: now, calendar: calendar)
        let swapped = items.filter { $0.id != parent.id } + [rung]
        let engine = ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now)
        return exams.filter { $0.covers(parent) }
            .map { (engine.value(of: $0, items: items) - engine.value(of: $0, items: swapped)) * 100 }
            .max() ?? 0
    }

    /// The draft waiting for this question, if one was written and not decided.
    func rungDraft(of parentID: UUID) -> StudyItem? {
        let draft = ItemStatus.draft.rawValue
        return fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.statusRaw == draft && $0.deletedAt == nil && $0.rungOf == parentID })).first
    }

    /// What the writer gets for this question. Nil when its lines are gone or nothing harder exists.
    func rungInput(for parent: StudyItem) -> RungInput? {
        guard let next = Ladder.next(after: parent.kind), let ref = parent.sourceRef, !ref.anchorIDs.isEmpty,
              let source = source(ref.sourceID), source.deletedAt == nil else { return nil }
        let all: [TextLine]
        let index: Int
        let label: String
        var headings: [String] = []
        if source.kind == .lecture {
            all = source.segments.sorted { $0.start < $1.start }.map { TextLine(id: $0.id, text: $0.text, box: nil) }
            index = 0
            label = "Lecture"
        } else {
            guard let page = source.sortedPages.first(where: { candidate in
                (ref.pageIndex == nil || candidate.pageIndex == ref.pageIndex) && candidate.lines.contains { ref.anchorIDs.contains($0.id) }
            }) else { return nil }
            all = page.lines
            index = page.pageIndex
            label = page.label
            headings = AIRouter.headings(of: [pageText(page)])
        }
        let lines = Ladder.neighbourhood(of: ref.anchorIDs, in: all, limit: RelayLimits.rungLines)
        guard !lines.isEmpty else { return nil }
        let language = LocalGenerator.dominantLanguage(String(lines.map(\.text).joined(separator: " ").prefix(4000)))
        return RungInput(course: parent.course?.name ?? "", sourceTitle: source.title, level: settings.level?.rawValue, language: language,
                         next: next, parentKind: parent.kind, prompt: parent.prompt, answer: parent.answer,
                         page: PageText(index: index, label: label, lines: lines), headings: headings)
    }

    /// Writes the harder question (or finds the one already written) as a draft. It joins nothing until the student adds it.
    func writeRung(for parentID: UUID) async -> RungWriting {
        if let waiting = rungDraft(of: parentID) { return .proposal(waiting.id) }
        guard let parent = item(parentID), parent.deletedAt == nil, let input = rungInput(for: parent) else {
            return .failed(LadderCopy.couldNotWrite)
        }
        switch await ai.writeRung(input) {
        case .written(var generated):
            // Read again after the wait.
            guard let fresh = item(parentID), fresh.deletedAt == nil, let course = fresh.course, let ref = fresh.sourceRef else {
                return .failed(LadderCopy.couldNotWrite)
            }
            let known = Set(input.page.lines.map(\.id))
            let anchors = generated.anchors.filter(known.contains)
            generated.anchors = anchors.isEmpty ? ref.anchorIDs : anchors
            let source = source(ref.sourceID)
            let page = source?.kind == .lecture ? nil : source?.sortedPages.first { $0.pageIndex == input.page.index }
            let draft = ItemFactory.makeItem(from: generated, course: course, topicID: fresh.topicID, source: source, page: page,
                                             origin: .cloud, status: .draft, now: now)
            draft.rungOf = parentID
            draft.checkedAt = now
            context.insert(draft)
            course.items.append(draft)
            touch(draft)
            save()
            return .proposal(draft.id)
        case .nothing:
            return .failed(LadderCopy.couldNotWrite)
        case .limit(let message):
            return .failed(message)
        case .unreachable:
            return .failed(LadderCopy.needsConnection)
        }
    }

    /// "Add it": the harder question starts, with a seeded memory, and the easy one rests.
    @discardableResult
    func adoptRung(_ draftID: UUID) -> Bool {
        guard let rung = item(draftID), rung.deletedAt == nil, rung.status == .draft, let parentID = rung.rungOf,
              let parent = item(parentID), parent.deletedAt == nil else { return false }
        rung.memory = Ladder.seedMemory(parent: parent.memory, now: now, calendar: calendar)
        rung.status = .active
        touch(rung)
        if parent.status == .active {
            parent.status = .suspended
            touch(parent)
        }
        save()
        return true
    }

    /// "Undo": back to how it was, with the draft still there to decide on.
    func undoRung(_ draftID: UUID) {
        guard let rung = item(draftID), rung.status == .active, let parentID = rung.rungOf else { return }
        rung.memory = .new
        rung.status = .draft
        touch(rung)
        if let parent = item(parentID), parent.deletedAt == nil, parent.status == .suspended {
            parent.status = .active
            touch(parent)
        }
        save()
    }

    /// "Not this one": the draft goes, and the easy one isn't offered again for a while.
    func declineRung(_ draftID: UUID) {
        guard let rung = item(draftID), rung.status == .draft, let parentID = rung.rungOf else { return }
        snoozeLadder(parentID, days: Self.declineDays)
        rung.deletedAt = now
        touch(rung)
        save()
    }

    /// Doesn't offer this question again for `days`.
    func snoozeLadder(_ parentID: UUID, days: Int) {
        var snoozes = ladderSnoozes()
        let nowSeconds = now.timeIntervalSince1970
        snoozes = snoozes.filter { $0.value > nowSeconds }
        snoozes[parentID.uuidString] = nowSeconds + Double(days) * 86_400
        defaults.set(snoozes, forKey: Self.snoozeKey)
    }

    private func ladderSnoozes() -> [String: Double] {
        defaults.dictionary(forKey: Self.snoozeKey) as? [String: Double] ?? [:]
    }

    /// Deleting an added harder question wakes the easy one it replaced.
    func resumeParent(ofDeletedRung rung: StudyItem) {
        guard rung.status == .active, let parentID = rung.rungOf, let parent = item(parentID), parent.deletedAt == nil,
              parent.status == .suspended else { return }
        parent.status = .active
        touch(parent)
    }
}
