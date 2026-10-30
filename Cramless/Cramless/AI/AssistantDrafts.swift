import Foundation

/// Reads what the model wrote in a tool call into drafts the student can review. Pure: the checks that need the store
/// (is this quote in the notes, is there already a card like this) come in as closures.
///
/// The rules it keeps, because the model's word is not enough:
///  - a quote counts as evidence only if it is really in the student's material (`EvidenceChecker`); a card whose quote is not
///    found is kept, but marked as Cap's own words;
///  - a multiple-choice question must have a right option that is one of its options (else it is dropped), and its options are
///    shuffled here, because models put the right one first;
///  - a fill-in must have a blank in its sentence;
///  - no more than `maxItems`, and nothing the course already has.
enum AssistantDrafts {
    static let maxItems = 12

    /// The evidence for a quote the model gave for a source id, or nil when the quote is not in the notes.
    typealias EvidenceChecker = (_ sourceID: String?, _ quote: String) -> Evidence?

    // MARK: Text

    /// Case, accents, quote marks and runs of white space do not tell two texts apart.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[\u{201C}\u{201D}]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The quote is in the text, however it was cased or spaced.
    static func contains(_ quote: String, in text: String) -> Bool {
        let q = fold(quote)
        return q.count >= 8 && fold(text).contains(q)
    }

    /// What two cards must differ in to count as different: letters and digits only.
    static func key(_ text: String) -> String {
        fold(text).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// A number that depends only on the text, so a shuffle comes out the same on every run.
    static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// The options in an order that depends only on the question, with where the right one went.
    static func shuffled(_ options: [String], correct: Int, seed: String) -> (options: [String], correct: Int) {
        var state = Self.seed(seed)
        func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        var order = Array(options.indices)
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, Int(next() % UInt64(i + 1))) }
        return (order.map { options[$0] }, order.firstIndex(of: correct) ?? correct)
    }

    // MARK: Flashcards

    struct Cards {
        var drafts: [CardDraft]
        /// Cards left out: empty, too long, or the model sent more than a deck holds.
        var dropped: Int
    }

    static func cards(from arguments: AnyJSON, check: EvidenceChecker, existing: Set<String>) -> Cards {
        var drafts: [CardDraft] = []
        var dropped = 0
        var seen = existing
        for raw in arguments["cards"]?.array ?? [] {
            guard let front = raw["front"]?.string?.clTrimmed, let back = raw["back"]?.string?.clTrimmed,
                  front.count >= 2, back.count >= 1, front.count <= 400, back.count <= 800 else { dropped += 1; continue }
            let k = key(front)
            guard !k.isEmpty, !drafts.contains(where: { key($0.front) == k }) else { dropped += 1; continue }
            guard drafts.count < maxItems else { dropped += 1; continue }
            let duplicate = seen.contains(k)
            seen.insert(k)
            drafts.append(CardDraft(id: ModelID.make(), front: front, back: back, basis: basis(for: raw["evidence"], check: check),
                                    kept: !duplicate, isDuplicate: duplicate))
        }
        return Cards(drafts: drafts, dropped: dropped)
    }

    // MARK: Questions

    struct Questions {
        var drafts: [QuestionDraft]
        var dropped: Int
    }

    static func questions(from arguments: AnyJSON, check: EvidenceChecker, existing: Set<String>) -> Questions {
        var drafts: [QuestionDraft] = []
        var dropped = 0
        var seen = existing
        for raw in arguments["questions"]?.array ?? [] {
            guard let draft = question(from: raw, check: check) else { dropped += 1; continue }
            let k = key(draft.prompt)
            guard !k.isEmpty, !drafts.contains(where: { key($0.prompt) == k }), drafts.count < maxItems else { dropped += 1; continue }
            var d = draft
            d.isDuplicate = seen.contains(k)
            d.kept = !d.isDuplicate
            seen.insert(k)
            drafts.append(d)
        }
        return Questions(drafts: drafts, dropped: dropped)
    }

    private static func question(from raw: AnyJSON, check: EvidenceChecker) -> QuestionDraft? {
        guard let type = raw["type"]?.string, var prompt = raw["question"]?.string?.clTrimmed, prompt.count >= 4,
              prompt.count <= 600, var answer = raw["answer"]?.string?.clTrimmed, !answer.isEmpty, answer.count <= 800 else { return nil }
        let explanation = String((raw["explanation"]?.string?.clTrimmed ?? "").prefix(600))
        let found = Self.basis(for: raw["evidence"], check: check)
        switch type {
        case "multiple_choice":
            var options: [String] = []
            for o in raw["options"]?.array?.compactMap(\.string) ?? [] {
                let t = o.clTrimmed
                if !t.isEmpty, t.count <= 300, !options.contains(where: { key($0) == key(t) }) { options.append(t) }
            }
            guard (2...5).contains(options.count) else { return nil }
            var correct = raw["correct_index"]?.int
            if let c = correct, !options.indices.contains(c) { correct = nil }
            // The index and the answer must agree; if the index is wrong, the answer's own text decides.
            if correct == nil || key(options[correct!]) != key(answer) {
                correct = options.firstIndex { key($0) == key(answer) } ?? correct
            }
            guard let right = correct, options.indices.contains(right) else { return nil }
            answer = options[right]
            let mixed = shuffled(options, correct: right, seed: prompt)
            return QuestionDraft(id: ModelID.make(), kind: .multipleChoice, prompt: prompt, answer: answer, choices: mixed.options,
                                 correctIndex: mixed.correct, explanation: explanation, basis: found)
        case "fill_blank":
            if !prompt.contains("{{") {
                // The model forgot the braces: wrap the answer where it stands, once.
                guard let r = prompt.range(of: answer, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
                prompt.replaceSubrange(r, with: "{{\(prompt[r])}}")
            }
            let blanks = ClozeSpec(text: prompt).answers.map(\.clTrimmed).filter { !$0.isEmpty }
            guard let first = blanks.first else { return nil }
            return QuestionDraft(id: ModelID.make(), kind: .fillBlank, prompt: prompt, answer: first, explanation: explanation, basis: found)
        case "short_answer":
            var ideas: [String] = []
            for i in raw["key_ideas"]?.array?.compactMap(\.string) ?? [] {
                let t = i.clTrimmed
                if !t.isEmpty, t.count <= 200, !ideas.contains(where: { key($0) == key(t) }) { ideas.append(t) }
            }
            if ideas.isEmpty { ideas = [answer] }
            return QuestionDraft(id: ModelID.make(), kind: .shortAnswer, prompt: prompt, answer: answer, keyIdeas: Array(ideas.prefix(4)),
                                 explanation: explanation, basis: found)
        default:
            return nil
        }
    }

    // MARK: Notes

    static let maxNoteCharacters = 20_000

    static func note(from arguments: AnyJSON) -> NoteDraft? {
        guard let body = arguments["body"]?.string?.clTrimmed, body.count >= 10 else { return nil }
        let title = arguments["title"]?.string?.clTrimmed ?? ""
        let first = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Note"
        return NoteDraft(title: String((title.isEmpty ? first : title).prefix(80)), body: String(body.prefix(maxNoteCharacters)))
    }

    // MARK: Exams

    enum ExamProblem: Error, Equatable {
        case noDate, pastDate
        /// The words the model reads, so it can ask the student instead.
        var message: String {
            switch self {
            case .noDate: "The date wasn't a real day (yyyy-MM-dd). Ask the student for it."
            case .pastDate: "That day has already passed. Ask the student which day they mean."
            }
        }

        /// The words on the card the student sees.
        var studentMessage: String {
            switch self {
            case .noDate: String(localized: "Cap wasn't sure which day you meant.")
            case .pastDate: String(localized: "That day has already passed.")
            }
        }
    }

    /// A day "yyyy-MM-dd" and an optional time "HH:mm" in the student's calendar; 9:00 when none is given.
    static func examDate(day: String?, time: String?, calendar: Calendar, now: Date) throws -> (date: Date, hasTime: Bool) {
        let parts = (day ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let year = Optional(parts[0]), (1900...2200).contains(year), (1...12).contains(parts[1]),
              (1...31).contains(parts[2]) else { throw ExamProblem.noDate }
        var comps = DateComponents(year: year, month: parts[1], day: parts[2], hour: 9, minute: 0)
        var hasTime = false
        if let time, let hm = Optional(time.split(separator: ":").compactMap { Int($0) }), hm.count == 2, (0...23).contains(hm[0]),
           (0...59).contains(hm[1]) {
            comps.hour = hm[0]
            comps.minute = hm[1]
            hasTime = true
        }
        guard let date = calendar.date(from: comps), calendar.component(.day, from: date) == parts[2] else { throw ExamProblem.noDate }
        guard date >= calendar.startOfDay(for: now) else { throw ExamProblem.pastDate }
        return (date, hasTime)
    }

    // MARK: Pieces

    /// The evidence the model gave, checked: a quote found in the notes, else Cap's own words.
    private static func basis(for raw: AnyJSON?, check: EvidenceChecker) -> DraftBasis {
        guard let raw, !raw.isNull, let quote = raw["quote"]?.string?.clTrimmed, !quote.isEmpty else { return .own }
        if let found = check(raw["source_id"]?.string, quote) { return .notes(found) }
        return .own
    }
}
