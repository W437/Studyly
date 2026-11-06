import Foundation
import SwiftData

// The last look on an exam's eve: `LastLookEngine` picks the ideas, this keeps them (`LastLookStore`, in UserDefaults on this iPhone, never synced) and reads their words. Preparing runs on
// launch and whenever the app comes back, and only inside each exam's window, so the sentences are here before the evening. Nothing is recorded: it's reading, not studying.
extension AppModel {
    var lastLookEngine: LastLookEngine { LastLookEngine(fsrs: fsrs, calendar: calendar, now: now) }

    // MARK: Reading

    /// The look for an exam (and whichever exams share its day), with what's been prepared and each idea's words as they stand. Nil with nothing to look at.
    func lastLook(for examID: UUID) -> LastLook? {
        guard let (exams, shown) = lastLookIdeas(for: examID), !shown.isEmpty else { return nil }
        let store = lastLookStore
        let names = topicNames()
        var ideas: [LastLookIdea] = []
        for id in shown {
            guard let model = item(id) else { continue }
            let words = LastLookWords(model)
            guard !words.answer.clTrimmed.isEmpty else { continue }
            let kept = exams.compactMap { store.packs[$0.id]?.sentences[id] }.first
            let sentence = kept.flatMap { $0.prompt == model.prompt && $0.answer == model.answer ? $0.sentence : nil }
            ideas.append(LastLookIdea(id: id, topic: model.topicID.flatMap { names[$0] }, question: words.question, answer: words.answer,
                                      sentence: sentence, ref: model.sourceRef))
        }
        guard !ideas.isEmpty else { return nil }
        return LastLook(examID: examID, ideas: ideas)
    }

    /// How many ideas the look for this exam holds (Today asks, without reading their words).
    func lastLookCount(for examID: UUID) -> Int { lastLookIdeas(for: examID)?.ideas.count ?? 0 }

    private func lastLookIdeas(for examID: UUID) -> (exams: [ExamSnapshot], ideas: [UUID])? {
        let upcoming = examSnapshots(upcomingOnly: true)
        guard let exam = upcoming.first(where: { $0.id == examID }) else { return nil }
        let day = calendar.dayNumber(for: exam.date)
        let exams = [exam] + upcoming.filter { $0.id != exam.id && calendar.dayNumber(for: $0.date) == day }
        let store = lastLookStore
        let prepared = exams.flatMap { store.packs[$0.id]?.itemIDs ?? [] }
        return (exams, lastLookEngine.shown(items: itemSnapshots(), exams: exams, prepared: prepared))
    }

    // MARK: Preparing

    /// Every exam whose window is open: its ideas picked once a day, and their sentences asked for when the cloud is allowed. A quiet job: nothing waits for it, and a failure
    /// is tried again the next time the app comes back. Packs of exams that have gone are dropped.
    func prepareLastLooks() async {
        #if DEBUG
        guard !config.isHarness else { return }
        #endif
        await prepareLastLooks(of: examSnapshots(upcomingOnly: true).filter { lastLookEngine.isPreparing(for: $0) })
    }

    /// Prepares these exams' looks, whatever their windows say.
    func prepareLastLooks(of exams: [ExamSnapshot]) async {
        var store = lastLookStore
        let upcoming = Set(examSnapshots(upcomingOnly: true).map(\.id))
        let kept = store.packs.filter { upcoming.contains($0.key) }
        if kept.count != store.packs.count {
            store.packs = kept
            lastLookStore = store
        }
        guard !lastLookPreparing, !exams.isEmpty else { return }
        lastLookPreparing = true
        defer { lastLookPreparing = false }
        for exam in exams { await prepareLastLook(of: exam) }
    }

    private func prepareLastLook(of exam: ExamSnapshot) async {
        let today = calendar.dayKey(for: now)
        var pack = lastLookStore.packs[exam.id] ?? LastLookPack(examID: exam.id, day: "", itemIDs: [])
        let engine = lastLookEngine
        if pack.day != today {
            let picked = engine.picks(items: itemSnapshots(), exams: [exam], limit: LastLookEngine.prepared)
            pack.itemIDs = picked
            pack.day = today
            pack.sentences = pack.sentences.filter { picked.contains($0.key) }
            storeLastLook(pack)
        }
        guard pack.askedDay != today, ai.route(.lastLook).usesCloud else { return }
        // What it was asked for and from what, as they stand now; a sentence kept from an earlier day whose words have changed goes.
        var asked: [(key: String, id: UUID, words: LastLookPack.Sentence, input: LastLookIdeaInput)] = []
        let names = topicNames()
        var course = ""
        for (index, id) in pack.itemIDs.enumerated() {
            guard let model = item(id) else { continue }
            if course.isEmpty { course = model.course?.name ?? "" }
            // A fill-in is a sentence already, and there's nothing to say about an answer that isn't there.
            guard model.kind != .cloze, !model.prompt.clTrimmed.isEmpty, !model.answer.clTrimmed.isEmpty else { continue }
            if let kept = pack.sentences[id] {
                if kept.prompt == model.prompt, kept.answer == model.answer { continue }
                pack.sentences[id] = nil
            }
            let key = "i\(index + 1)"
            let lines = reportSource(of: model)?.lines ?? []
            let input = LastLookIdeaInput(id: key, topic: model.topicID.flatMap { names[$0] }, prompt: model.prompt, answer: model.answer, lines: lines)
            asked.append((key, id, LastLookPack.Sentence(sentence: "", prompt: model.prompt, answer: model.answer), input))
        }
        guard !asked.isEmpty else { return }
        guard let written = await ai.lastLookSentences(course: course, examTitle: exam.title, ideas: asked.map(\.input)) else { return }
        // The wait is over: the store may have moved on, and the exam may have gone.
        guard examSnapshots(upcomingOnly: true).contains(where: { $0.id == exam.id }) else { return }
        for entry in asked {
            guard let sentence = written[entry.key] else { continue }
            var words = entry.words
            words.sentence = sentence
            pack.sentences[entry.id] = words
        }
        pack.askedDay = today
        storeLastLook(pack)
    }

    // MARK: The store

    private var lastLookStore: LastLookStore {
        get {
            guard let data = defaults.data(forKey: LastLookStore.defaultsKey),
                  let store = try? JSONDecoder.cramless.decode(LastLookStore.self, from: data) else { return LastLookStore() }
            return store
        }
        set {
            if let data = try? JSONEncoder.cramless.encode(newValue) { defaults.set(data, forKey: LastLookStore.defaultsKey) }
        }
    }

    private func storeLastLook(_ pack: LastLookPack) {
        var store = lastLookStore
        store.packs[pack.examID] = pack
        lastLookStore = store
    }

    /// Everything about last looks, for a local wipe.
    func clearLastLooks() {
        defaults.removeObject(forKey: LastLookStore.defaultsKey)
    }
}

/// A question's words as a last look says them. A fill-in is a sentence by itself, once its blanks are filled: it has no question.
struct LastLookWords: Equatable, Sendable {
    var question: String
    var answer: String

    init(_ item: StudyItem) {
        if item.kind == .cloze, let cloze = item.cloze {
            question = ""
            answer = cloze.text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
        } else {
            question = item.prompt
            answer = item.answer
        }
    }
}
