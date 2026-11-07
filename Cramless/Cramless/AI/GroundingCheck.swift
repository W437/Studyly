import Foundation

/// The check every on-device and offline item passes before the person sees it ("checked before you see it"),
/// and the anchor half of it for cloud items too:
///
/// 1. it points at lines (anchors), and **every anchor exists** on the page or in the transcript;
/// 2. its answer is backed by the lines it points at: enough of the answer's content words are in them (a fill-in's
///    blanks and a choice question's right option must be there; a diagram's labels must be anchors).
///
/// It can only catch an answer that strays from its lines; it can't judge meaning. The cloud's second pass
/// (`check`) does that for cloud items.
enum GroundingCheck {

    /// The share of an answer's content words its anchored lines must contain.
    static let defaultOverlap = 0.5

    /// Splits items into the ones the lines back and the ones they don't, with a reason for each drop.
    /// `texts` maps every anchor id the source has (line ids "p0.l12", segment ids "s5") to its text.
    static func apply(_ items: [GeneratedItem], texts: [String: String], minimumOverlap: Double = defaultOverlap,
                      anchorsOnly: Bool = false) -> (kept: [GeneratedItem], dropped: [DroppedItem]) {
        var kept: [GeneratedItem] = []
        var dropped: [DroppedItem] = []
        for item in items {
            if let reason = problem(with: item, texts: texts, minimumOverlap: minimumOverlap, anchorsOnly: anchorsOnly) {
                dropped.append(DroppedItem(item: item, reason: reason))
            } else {
                kept.append(item)
            }
        }
        return (kept, dropped)
    }

    /// Nil when the item is grounded; otherwise why not, in words the review screen can show.
    static func problem(with item: GeneratedItem, texts: [String: String], minimumOverlap: Double = defaultOverlap,
                        anchorsOnly: Bool = false) -> String? {
        if item.prompt.trimmingCharacters(in: .whitespaces).isEmpty { return "It has no question." }
        if item.answer.trimmingCharacters(in: .whitespaces).isEmpty, item.kind != .cloze { return "It has no answer." }
        guard !item.anchors.isEmpty else { return "It doesn't point at any line of your page." }
        if let missing = item.anchors.first(where: { texts[$0] == nil }) {
            return "It points at a line that isn't on your page (\(missing))."
        }
        if let labels = item.diagramLabels, labels.contains(where: { texts[$0] == nil || !item.anchors.contains($0) }) {
            return "Its labels aren't on your page."
        }
        if anchorsOnly { return nil }

        let anchored = item.anchors.compactMap { texts[$0] }.joined(separator: " ")
        switch item.kind {
        case .mcq:
            let right = item.choices.filter(\.correct)
            guard right.count == 1, item.choices.count >= 2 else { return "It doesn't have exactly one right option." }
            if Lexicon.overlap(of: right[0].text, with: anchored) < 0.99, Lexicon.overlap(of: item.answer, with: anchored) < 0.99 {
                return "Its right answer isn't on the lines it points to."
            }
        case .cloze:
            guard let cloze = item.cloze, !cloze.answers.isEmpty else { return "It has no blank." }
            for blank in cloze.answers where Lexicon.overlap(of: blank, with: anchored) < 0.99 {
                return "Its blank isn't on the lines it points to."
            }
        case .diagram:
            break
        case .recall, .apply, .flashcard:
            if Lexicon.overlap(of: item.answer, with: anchored) < minimumOverlap {
                return "Its answer isn't backed by the lines it points to."
            }
        }
        return nil
    }

    /// The relay's fix questions come with no anchors: they're written from the expected answers, not from lines of a page. Each is held to the same rules as any
    /// other, against the page and those answers together, and then points at the page's lines that hold its answer, when any do.
    static func groundedByWords(_ items: [GeneratedItem], texts: [String: String], facts: [String], minimumOverlap: Double = defaultOverlap) -> [GeneratedItem] {
        var everything = texts
        for (index, fact) in facts.enumerated() { everything["fact\(index)"] = fact }
        let allIDs = everything.keys.sorted()
        return items.compactMap { item in
            var whole = item
            whole.anchors = allIDs
            guard problem(with: whole, texts: everything, minimumOverlap: minimumOverlap) == nil else { return nil }
            var grounded = item
            grounded.anchors = lines(holdingAnswerOf: item, in: texts)
            return grounded
        }
    }

    /// The lines most of the item's right answer is on, the best two.
    private static func lines(holdingAnswerOf item: GeneratedItem, in texts: [String: String]) -> [String] {
        let answer = item.kind == .cloze ? (item.cloze?.answers ?? []).joined(separator: " ")
            : item.kind == .mcq ? (item.choices.first(where: \.correct)?.text ?? item.answer) : item.answer
        guard !Lexicon.contentStems(answer).isEmpty else { return [] }
        var found: [(id: String, overlap: Double)] = []
        for (id, line) in texts {
            let overlap = Lexicon.overlap(of: answer, with: line)
            if overlap > 0 { found.append((id, overlap)) }
        }
        found.sort { $0.overlap != $1.overlap ? $0.overlap > $1.overlap : $0.id < $1.id }
        return found.prefix(2).map(\.id)
    }

    /// Every anchor id of a set of pages, with its text.
    static func texts(of pages: [PageText]) -> [String: String] {
        var out: [String: String] = [:]
        for page in pages { for line in page.lines { out[line.id] = line.text } }
        return out
    }

    static func texts(of segments: [TranscriptSegment]) -> [String: String] {
        Dictionary(segments.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
    }
}
