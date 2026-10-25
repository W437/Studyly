import Foundation

/// Finds the moments a lecturer marks as exam material: "this will be on the midterm", "you'll be tested on
/// this", "make sure you know", "this is important", "remember this". Plain phrase rules (no model), so a flag is
/// always explainable: the phrase is in the segment it points at. English first, with the commonest phrasings in
/// Spanish, French, German, Italian, Portuguese and Hebrew.
///
/// The person's own flags (a tap while recording) are added by the session as `.tapped`; this type only reads
/// transcript text.
enum ExamFlagDetector {
    /// A phrase flag closer than this to the previous flag repeats it ("This is on the exam. Make sure you know
    /// it.") and is left out.
    static let mergeWindow: Double = 20

    private static let patterns: [NSRegularExpression] = {
        let exam = #"(?:exam|exams|test|tests|midterm|midterms|mid-term|final|finals|quiz|quizzes)"#
        // Nouns that turn "on the test …" / "the final …" into something else ("test tube", "final answer").
        let notExam = #"(?!\s+(?:tubes?|cases?|subjects?|results?|scores?|answers?|steps?|pages?|slides?|products?|stages?|phases?|versions?|rounds?|drafts?|days?|weeks?|chapters?|sections?|grades?|rooms?|halls?|dates?|times?|scores?|strips?|runs?|drives?|cells?|samples?|groups?|conditions?)\b)"#
        let sources = [
            // "on the exam", "on your midterm", "on the final exam", "for the test", "in the quiz"
            #"\b(?:on|for|in)\s+(?:the|your|our|this|that|next|each|every|the\s+next|tomorrow's|friday's|monday's)\s+(?:\w+\s+)?"# + exam + #"\b"# + notExam,
            // "will be tested", "you'll be tested on", "is going to be asked", "gets examined"
            #"\b(?:will|'ll|is going to|are going to|gonna|might|may|could|definitely|probably|likely to|gets?)\s+(?:be\s+|get\s+)?(?:tested|examined|assessed|asked about)\b"#,
            #"\byou(?:'ll| will) be tested\b"#,
            // "make sure you know", "be sure you understand"
            #"\b(?:make|be)\s+sure\s+(?:that\s+)?you\s+(?:know|understand|remember|learn|memori[sz]e|can|review|get)\b"#,
            // "this is important", "that's really important"
            #"\b(?:this|that)(?:'s|\s+is|\s+was)\s+(?:really\s+|very\s+|super\s+|extremely\s+|so\s+|especially\s+|particularly\s+|most\s+)?important\b"#,
            #"\bimportant\s+for\s+(?:the|your)\s+"# + exam + #"\b"#,
            // "remember this", "don't forget that", "write this down"
            #"\bremember\s+(?:this|that)\b"#,
            #"\bdon't\s+forget\s+(?:this|that)\b"#,
            #"\b(?:write|jot|note)\s+(?:this|that)\s+down\b"#,
            #"\b"# + exam + #"\s+question\b"#,
            #"\bwill\s+(?:show up|come up|appear)\s+(?:on|in)\b"#,
            #"\bkey\s+(?:point|takeaway|concept|idea)s?\b"#,
            // Spanish, French, German, Italian, Portuguese
            #"\b(?:en|para)\s+el\s+(?:examen|parcial|final)\b"#, #"\bentra\s+en\s+el\s+examen\b"#,
            #"\b(?:esto|eso)\s+es\s+(?:muy\s+)?importante\b"#,
            #"\b(?:à|a|pour|dans)\s+l'(?:examen|interro)\b"#, #"\b(?:au|pour le)\s+(?:partiel|contrôle|bac)\b"#,
            #"\bc'est\s+(?:très\s+)?important\b"#, #"\b(?:retenez|retiens)\s+(?:bien\s+)?(?:ça|cela)\b"#,
            #"\b(?:in der|für die)\s+(?:prüfung|klausur)\b"#, #"\bprüfungsrelevant\b"#,
            #"\bdas\s+ist\s+(?:sehr\s+|wirklich\s+)?wichtig\b"#, #"\bmerkt\s+euch\s+das\b"#,
            #"\b(?:all'|per l')esame\b"#, #"\b(?:questo|ciò)\s+è\s+(?:molto\s+)?importante\b"#,
            #"\b(?:na|para a)\s+prova\b"#, #"\bcai\s+na\s+prova\b"#, #"\b(?:isso|isto)\s+é\s+(?:muito\s+)?importante\b"#,
            // Hebrew (prefixes attach to the word, so no word boundaries)
            "במבחן", "למבחן", "לבחינה", "בבחינה", "זה חשוב", "תזכרו את זה",
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// The text says this moment matters for an exam.
    static func matches(_ text: String) -> Bool {
        let normalized = normalize(text)
        let range = NSRange(normalized.startIndex..., in: normalized)
        return patterns.contains { $0.firstMatch(in: normalized, range: range) != nil }
    }

    /// Phrase flags for segments that say so, one per segment, skipping any within `mergeWindow` seconds of a flag
    /// already there (including `existing`). Ids continue after the existing ones ("f1", "f2", …).
    static func phraseFlags(in segments: [TranscriptSegment], existing: [ExamFlag] = []) -> [ExamFlag] {
        var all = existing
        var added: [ExamFlag] = []
        for segment in segments where matches(segment.text) {
            if all.contains(where: { $0.reason == .phrase && abs($0.time - segment.start) < mergeWindow }) { continue }
            if all.contains(where: { $0.text == segment.text && abs($0.time - segment.start) < 0.5 }) { continue }
            let flag = ExamFlag(id: nextID(after: all), time: segment.start, reason: .phrase, text: segment.text)
            all.append(flag)
            added.append(flag)
        }
        return added
    }

    /// "f<n>" one past the highest id in use.
    static func nextID(after flags: [ExamFlag]) -> String {
        let highest = flags.compactMap { Int($0.id.dropFirst()) }.max() ?? 0
        return "f\(highest + 1)"
    }

    /// Lowercase, straight apostrophes, single spaces.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
