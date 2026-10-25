import Foundation

/// Lecture notes by the offline rules (tier T0), from the transcript alone:
///
/// - **sections** by topic shift and time: a new section where the words of the transcript change (low overlap
///   between what came before and what comes next) or after a long pause; a section shorter than 45 s joins its
///   neighbour, one longer than 6 minutes is cut at its weakest point;
/// - a **title** for each section from the term its sentences lead with ("Prophase first." → "Prophase");
/// - **bullets**: the section's fullest sentences, with filler ("OK, so", "by the way") taken out;
/// - **flagged moments**: the person's taps and phrases like "this will be on the midterm";
/// - **key terms** and **questions from the flagged segments**, anchored to their segment ids.
///
/// The on-device model may rewrite a section's title and bullets afterwards (`AIRouter.lectureNotes`); the
/// sections and their times always come from here.
enum LocalLectureNotes {

    struct Section: Equatable, Sendable {
        var id: String
        var title: String
        var start: Double
        var end: Double
        var segmentIDs: [String]
        /// The section's transcript, for the on-device step.
        var text: String
        var bullets: [String]
    }

    struct Result: Equatable, Sendable {
        var title: String
        var summary: String
        var sections: [Section]
        var keyTerms: [String]
        var examFlags: [LectureExamFlag]
        var items: [GeneratedItem]

        var notes: LectureNotes {
            LectureNotes(summary: summary,
                         sections: sections.map { .init(id: $0.id, title: $0.title, start: $0.start, end: $0.end, bullets: $0.bullets) },
                         keyTerms: keyTerms, origin: ItemOrigin.rules.rawValue)
        }
    }

    static func make(title: String, segments: [TranscriptSegment], flags: [ExamFlag], maxItems: Int = 8) -> Result {
        let segs = segments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.sorted { $0.start < $1.start }
        guard !segs.isEmpty else {
            return Result(title: title, summary: "", sections: [], keyTerms: [], examFlags: [], items: [])
        }
        let groups = sectionize(segs)
        var sections: [Section] = []
        for (n, group) in groups.enumerated() {
            let text = group.map(\.text).joined(separator: " ")
            sections.append(Section(id: "n\(n + 1)", title: sectionTitle(group) ?? "Part \(n + 1)",
                                    start: group.first!.start, end: group.last!.end, segmentIDs: group.map(\.id),
                                    text: text, bullets: bullets(from: group)))
        }

        let allFlags = mergedFlags(flags, segments: segs)
        let examFlags = allFlags.map { flag -> LectureExamFlag in
            let segment = segment(at: flag.time, in: segs)
            let sentence = segment.flatMap { flaggedSentence(in: $0.text) } ?? flag.text
            return LectureExamFlag(time: flag.time, text: sentence.isEmpty ? (segment?.text ?? flag.text) : sentence,
                                   why: why(for: flag, text: segment?.text ?? flag.text))
        }

        var items: [GeneratedItem] = []
        for flag in allFlags {
            guard items.count < maxItems, let segment = segment(at: flag.time, in: segs),
                  !items.contains(where: { $0.anchors == [segment.id] }) else { continue }
            if let item = question(from: segment, flag: flag, examWord: examWord(in: segment.text), n: items.count + 1) {
                items.append(item)
            }
        }
        for section in sections where items.count < maxItems {
            guard let first = section.bullets.first, !section.title.hasPrefix("Part ") else { continue }
            items.append(GeneratedItem(id: "l\(items.count + 1)", kind: .flashcard, topic: section.title, prompt: section.title,
                                       answer: first, explanation: "", anchors: section.segmentIDs, difficulty: 0.3))
        }

        let titles = sections.map(\.title).filter { !$0.hasPrefix("Part ") }
        var summary = titles.isEmpty ? "" : "Covers \(LocalGrader.list(titles.map { LocalGrader.lowerFirst($0) }))."
        if let first = examFlags.first {
            let word = examWord(in: first.text) ?? "exam"
            let point = Lexicon.trimmedSentence(cleanFiller(first.text))
            summary += (summary.isEmpty ? "" : " ") + "Flagged for the \(word): \(LocalGrader.lowerFirst(point))."
        }
        return Result(title: title, summary: summary, sections: sections, keyTerms: keyTerms(segs, titles: titles),
                      examFlags: examFlags, items: items)
    }

    // MARK: Sections

    /// Where the words change: overlap of the content words in about forty seconds of transcript before a point
    /// with about forty seconds after it (at least one segment each side, so long segments compare one to one).
    private static func sectionize(_ segs: [TranscriptSegment]) -> [[TranscriptSegment]] {
        let stems = segs.map { Set(Lexicon.contentStems($0.text)).subtracting(LocalGenerator.genericStems) }
        func similarity(at i: Int) -> Double {
            var lo = i - 1
            while lo > 0, segs[i - 1].end - segs[lo].start < 40 { lo -= 1 }
            var hi = i
            while hi < segs.count - 1, segs[hi].end - segs[i].start < 40 { hi += 1 }
            let before = stems[lo..<i].reduce(Set<String>()) { $0.union($1) }
            let after = stems[i...hi].reduce(Set<String>()) { $0.union($1) }
            let union = before.union(after).count
            return union == 0 ? 1 : Double(before.intersection(after).count) / Double(union)
        }
        var groups: [[TranscriptSegment]] = [[segs[0]]]
        var sims: [Double] = []
        for i in 1..<segs.count {
            let s = similarity(at: i)
            let pause = segs[i].start - segs[i - 1].end
            if s < 0.12 || pause >= 20 {
                groups.append([segs[i]])
                sims.append(s)
            } else {
                groups[groups.count - 1].append(segs[i])
            }
        }
        // A section under 45 seconds joins the neighbour it shares more words with (the next one on a tie).
        var merged = true
        while merged, groups.count > 1 {
            merged = false
            for (i, g) in groups.enumerated() where duration(g) < 45 {
                let words = Set(g.flatMap { Lexicon.contentStems($0.text) })
                func overlap(_ other: [TranscriptSegment]) -> Int { words.intersection(Set(other.flatMap { Lexicon.contentStems($0.text) })).count }
                let target: Int
                if i == 0 { target = 1 } else if i == groups.count - 1 { target = i - 1 } else {
                    target = overlap(groups[i - 1]) > overlap(groups[i + 1]) ? i - 1 : i + 1
                }
                if target < i { groups[target] += g } else { groups[target] = g + groups[target] }
                groups.remove(at: i)
                merged = true
                break
            }
        }
        // A section over six minutes is cut where its words change most.
        var out: [[TranscriptSegment]] = []
        for g in groups {
            var queue = [g]
            while let next = queue.first {
                queue.removeFirst()
                guard duration(next) > 360, next.count >= 4 else { out.append(next); continue }
                let local = next.map { Set(Lexicon.contentStems($0.text)) }
                var best = 2, bestScore = Double.infinity
                for i in 2..<(next.count - 1) {
                    let before = local[(i - 2)..<i].reduce(Set<String>()) { $0.union($1) }
                    let after = local[i..<min(local.count, i + 2)].reduce(Set<String>()) { $0.union($1) }
                    let union = before.union(after).count
                    let score = union == 0 ? 1 : Double(before.intersection(after).count) / Double(union)
                    if score < bestScore { bestScore = score; best = i }
                }
                queue.insert(contentsOf: [Array(next[..<best]), Array(next[best...])], at: 0)
            }
        }
        return out
    }

    private static func duration(_ g: [TranscriptSegment]) -> Double {
        guard let first = g.first, let last = g.last else { return 0 }
        return last.end - first.start
    }

    /// The term the section's sentences lead with ("Prophase first.", "Metaphase is the easy one", "… by the way:
    /// anaphase is where …"), with the word after it when the two make one name ("Nuclear envelope").
    static func sectionTitle(_ group: [TranscriptSegment]) -> String? {
        var scores: [String: (score: Double, first: Int, display: String)] = [:]
        var position = 0
        for segment in group {
            for sentence in Lexicon.sentences(segment.text) {
                for clause in sentence.split(whereSeparator: { ":;".contains($0) }) {
                    let text = String(clause)
                    let tokens = Lexicon.tokens(text)
                    let chars = Array(text)
                    guard let i = tokens.firstIndex(where: { $0.isContent && !$0.isNumber && !LocalGenerator.genericStems.contains($0.stem) && $0.word.count >= 4 }) else { continue }
                    var display = String(chars[tokens[i].range])
                    var key = tokens[i].stem
                    if i + 1 < tokens.count, tokens[i + 1].isContent, !tokens[i].endsClause,
                       !LocalGenerator.genericStems.contains(tokens[i + 1].stem), tokens[i + 1].word.count >= 4 {
                        display += " " + String(chars[tokens[i + 1].range])
                        key += " " + tokens[i + 1].stem
                    }
                    position += 1
                    let current = scores[key] ?? (0, position, display)
                    scores[key] = (current.score + 2, current.first, current.display)
                }
            }
            for token in Lexicon.tokens(segment.text) where token.isContent && !LocalGenerator.genericStems.contains(token.stem) {
                if var entry = scores[token.stem] { entry.score += 0.5; scores[token.stem] = entry }
            }
        }
        guard let best = scores.max(by: { $0.value.score == $1.value.score ? $0.value.first > $1.value.first : $0.value.score < $1.value.score }) else {
            return nil
        }
        return Lexicon.capitalizedFirst(best.value.display.lowercased())
    }

    /// Up to three of the section's fullest sentences, filler removed.
    private static func bullets(from group: [TranscriptSegment]) -> [String] {
        var sentences: [(text: String, weight: Int, order: Int)] = []
        var order = 0
        for segment in group {
            for sentence in Lexicon.sentences(segment.text) {
                let cleaned = cleanFiller(sentence)
                let weight = Lexicon.contentStems(cleaned).filter { !LocalGenerator.genericStems.contains($0) }.count
                order += 1
                if weight >= 3 { sentences.append((cleaned, weight, order)) }
            }
        }
        return sentences.sorted { $0.weight == $1.weight ? $0.order < $1.order : $0.weight > $1.weight }
            .prefix(3).sorted { $0.order < $1.order }.map(\.text)
    }

    /// "OK, so last time we …" → "Last time we …"; "This one will be on the midterm, by the way: anaphase is …" →
    /// "Anaphase is …".
    static func cleanFiller(_ sentence: String) -> String {
        var s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = s.firstIndex(of: ":"), flaggedPhrase(in: String(s[..<colon])) != nil {
            s = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let leading = #"^(?i)(?:(?:ok(?:ay)?|so|and|then|now|alright|all right|right|well|um|uh|basically|like|you know)[,]?\s+)+"#
        if let r = s.range(of: leading, options: .regularExpression) { s.removeSubrange(r) }
        for filler in [", by the way", " by the way,", ", basically,", " basically", ", you know,", " you know"] {
            s = s.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
        }
        return Lexicon.capitalizedFirst(s.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Flags

    private static let flagPatterns = [
        #"\b(?:will|is going to|might|could|would) be on the (?<word>exam|test|midterm|final|quiz)\b"#,
        #"\bon the (?<word>exam|test|midterm|final|quiz)\b"#,
        #"\b(?:this is|that's|it's) (?:really |very )?important\b"#,
        #"\bremember this\b"#, #"\bmake sure you (?:know|understand|remember)\b"#, #"\bwrite this down\b"#,
        #"\byou (?:need|have) to know\b"#, #"\bkey point\b"#,
    ]

    static func flaggedPhrase(in text: String) -> String? {
        let folded = Lexicon.fold(text)
        for pattern in flagPatterns {
            if let r = folded.range(of: pattern, options: .regularExpression) { return String(folded[r]) }
        }
        return nil
    }

    private static func examWord(in text: String) -> String? {
        let folded = Lexicon.fold(text)
        for word in ["midterm", "final", "exam", "test", "quiz"] where folded.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
            return word
        }
        return nil
    }

    /// The person's own flags plus a phrase flag for every segment that says "this will be on the exam".
    private static func mergedFlags(_ flags: [ExamFlag], segments: [TranscriptSegment]) -> [ExamFlag] {
        var out = flags.sorted { $0.time < $1.time }
        for segment in segments where flaggedPhrase(in: segment.text) != nil {
            if !out.contains(where: { $0.time >= segment.start && $0.time <= segment.end }) {
                out.append(ExamFlag(id: "auto-\(segment.id)", time: segment.start, reason: .phrase, text: segment.text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    private static func segment(at time: Double, in segments: [TranscriptSegment]) -> TranscriptSegment? {
        segments.first { time >= $0.start && time <= $0.end } ?? segments.min { abs($0.start - time) < abs($1.start - time) }
    }

    private static func flaggedSentence(in text: String) -> String? {
        let sentences = Lexicon.sentences(text)
        return sentences.first { flaggedPhrase(in: $0) != nil } ?? sentences.first
    }

    private static func why(for flag: ExamFlag, text: String) -> String {
        if flag.reason == .tapped { return "You flagged this moment." }
        if let word = examWord(in: text) { return "The lecturer said it will be on the \(word)." }
        return "The lecturer said it's important."
    }

    // MARK: Questions

    /// A question from a flagged segment: "anaphase is where the sister chromatids get pulled apart" → "What
    /// happens in anaphase?"; "X is Y" → "What is X?"; otherwise a fill-in of the segment's main term.
    private static func question(from segment: TranscriptSegment, flag: ExamFlag, examWord: String?, n: Int) -> GeneratedItem? {
        let lead = examWord.map { "Your lecturer said this will be on the \($0): " } ?? (flag.reason == .tapped ? "You flagged this: " : "Your lecturer flagged this: ")
        for sentence in Lexicon.sentences(segment.text) {
            let core = cleanFiller(sentence)
            if let m = core.firstMatch(of: #/^(?<x>[A-Za-z][\w\-]*(?:\s[\w\-]+)?)\s+(?:is|are)\s+(?:where|when)\s+(?<y>.+?)\.?$/#) {
                let x = String(m.x), y = Lexicon.capitalizedFirst(String(m.y))
                let answer = y.hasSuffix(".") ? y : y + "."
                let echo = Set(Lexicon.contentStems(x))
                let tokens = Lexicon.tokens(String(m.y)).filter { $0.isContent && !echo.contains($0.stem) && !LocalGenerator.genericStems.contains($0.stem) }
                let terms = Array(Set(tokens.map(\.word))).sorted()
                guard !terms.isEmpty else { continue }
                return GeneratedItem(id: "l\(n)", kind: .recall, topic: Lexicon.capitalizedFirst(x.lowercased()),
                                     prompt: lead + "what happens in \(x.lowercased())?", answer: answer,
                                     explanation: "Flagged at \(ItemFactory.timestamp(segment.start)).",
                                     keyIdeas: [KeyIdea(id: "k1", label: Lexicon.trimmedSentence(answer), terms: terms)],
                                     anchors: [segment.id], difficulty: 0.5)
            }
            if let d = PageStructure.sentenceDefinition(core) {
                return GeneratedItem(id: "l\(n)", kind: .flashcard, topic: d.term, prompt: d.term,
                                     answer: Lexicon.capitalizedFirst(d.meaning) + ".",
                                     explanation: "Flagged at \(ItemFactory.timestamp(segment.start)).",
                                     anchors: [segment.id], difficulty: 0.35)
            }
        }
        guard let title = sectionTitle([segment]) else { return nil }
        let sentence = cleanFiller(flaggedSentence(in: segment.text) ?? segment.text)
        guard let r = sentence.range(of: title, options: [.caseInsensitive]) else { return nil }
        let cloze = sentence.replacingCharacters(in: r, with: "{{\(sentence[r])}}")
        return GeneratedItem(id: "l\(n)", kind: .cloze, topic: title, prompt: "Fill in the word.", answer: String(sentence[r]),
                             explanation: "Flagged at \(ItemFactory.timestamp(segment.start)).",
                             cloze: ClozeSpec(text: cloze), anchors: [segment.id], difficulty: 0.4)
    }

    // MARK: Key terms

    private static func keyTerms(_ segs: [TranscriptSegment], titles: [String]) -> [String] {
        var out = titles.map { $0.lowercased() }
        var counts: [String: (n: Int, display: String)] = [:]
        for segment in segs {
            let chars = Array(segment.text)
            for token in Lexicon.tokens(segment.text) where token.isContent && token.word.count >= 7
                && !LocalGenerator.genericStems.contains(token.stem) {
                let entry = counts[token.stem] ?? (0, String(chars[token.range]).lowercased())
                counts[token.stem] = (entry.n + 1, entry.display)
            }
        }
        for (_, entry) in counts.sorted(by: { $0.value.n == $1.value.n ? $0.key < $1.key : $0.value.n > $1.value.n }) {
            if out.count >= 8 { break }
            let stems = Set(Lexicon.contentStems(entry.display))
            // "envelope" adds nothing next to "nuclear envelope".
            if !out.contains(where: { stems.isSubset(of: Set(Lexicon.contentStems($0))) }) { out.append(entry.display) }
        }
        return out
    }
}
