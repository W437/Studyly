import Foundation

/// What a student already has in a course, for a syllabus to be read against: plain values, built once by `AppModel.syllabusLibrary(courseID:)`.
struct SyllabusLibrary: Sendable {
    struct Question: Sendable {
        var topicID: UUID?
        /// Its prompt, its answer, its key ideas and its topic's name.
        var text: String
    }

    var questions: [Question] = []
    struct Topic: Sendable {
        var id: UUID
        var name: String
    }

    /// The course's topics.
    var topics: [Topic] = []
    /// The lines of the course's notes.
    var noteLines: [String] = []

    static let empty = SyllabusLibrary()
}

/// Does a course already hold what a topic names? A syllabus and a set of notes name the same thing in different words ("The Gettysburg Address", "Dedication at Gettysburg"), so
/// this reads the questions and the notes themselves, not only the topics' titles. Pure, and in any language the tokenizer reads. The one matching for a syllabus's proposal and for
/// an exam's gaps, so "no notes yet" means there are none.
struct SyllabusMatcher: Sendable {
    /// How many questions or lines one word needs to count: it can come up in passing. Two or more words together are rarer: one place is enough.
    static let enoughForOneWord = 3
    /// At most this many lines are read: a 300-page PDF says what it covers long before the end.
    static let lineLimit = 20_000

    struct Match: Equatable, Sendable {
        /// Questions that speak of it.
        var questions = 0
        /// The course topics those questions sit in.
        var topicIDs: Set<UUID> = []
        var inNotes = false
    }

    private let questions: [(topicID: UUID?, stems: Set<String>)]
    private let questionWords: [String: [Int]]
    private let lineWords: [String: [Int]]
    private let foldedLines: [String]
    /// The stems of the names of the course's topics that have questions: a question filed under "Well pumping" is about pumping, whatever else its words say.
    private let topicNames: [Set<String>]

    init(_ library: SyllabusLibrary) {
        var questions: [(topicID: UUID?, stems: Set<String>)] = []
        questions.reserveCapacity(library.questions.count)
        var words: [String: [Int]] = [:]
        for (index, question) in library.questions.enumerated() {
            let stems = Set(Lexicon.contentStems(question.text))
            questions.append((question.topicID, stems))
            for stem in stems { words[stem, default: []].append(index) }
        }
        self.questions = questions
        questionWords = words
        var lines: [String: [Int]] = [:]
        let read = library.noteLines.prefix(Self.lineLimit)
        for (index, line) in read.enumerated() {
            for stem in Set(Lexicon.contentStems(line)) { lines[stem, default: []].append(index) }
        }
        lineWords = lines
        foldedLines = read.map { Lexicon.fold($0).lowercased() }
        let filled = Set(library.questions.compactMap(\.topicID))
        topicNames = library.topics.filter { filled.contains($0.id) }.map { Set(Lexicon.contentStems($0.name)) }
    }

    /// Words a topic's title can have that say nothing about what's in it.
    private static let emptyWords: Set<String> = {
        let words = ["chapter", "chapters", "chap", "ch", "unit", "units", "week", "weeks", "wk", "module", "modules", "lecture", "lectures", "lesson", "lessons", "part", "parts", "section", "sections",
                     "period", "periods", "topic", "topics", "session", "sessions", "class", "introduction", "intro", "overview", "basic", "basics", "fundamental", "fundamentals", "review",
                     "end", "rise", "fall", "start", "beginning", "origin", "origins",
                     "capítulo", "capitulo", "tema", "temas", "unidad", "semana", "kapitel", "thema", "woche", "sitzung", "chapitre", "semaine", "第", "章"]
        return Set(words.flatMap { Lexicon.contentStems($0) + [Lexicon.fold($0).lowercased()] })
    }()

    /// What a title names, each part by the stems that say what it's about: "Period 3 (1754-1800) American Revolution and the Constitution" is two parts, and "Chapter 3" none.
    /// No numbers, and none of the words every syllabus uses.
    static func parts(of name: String) -> [[String]] {
        let split = name.replacingOccurrences(of: #"\s+(?:and|y|e|und|et|&|vs\.?|versus)\s+|[,;/()、・]"#, with: "|", options: [.regularExpression, .caseInsensitive])
        return split.components(separatedBy: "|").compactMap { part in
            var seen = Set<String>()
            let stems = Lexicon.contentStems(part).filter { stem in
                stem.contains(where: \.isLetter) && !emptyWords.contains(stem) && seen.insert(stem).inserted
            }
            return stems.isEmpty ? nil : stems
        }
    }

    /// A title with nothing to match on: "Chapter 3", "Week 5". It can't be said to have notes or not.
    static func saysNothing(_ name: String) -> Bool { parts(of: name).isEmpty }

    /// The same word, or the same word across a spelling or a language ("inflation", "inflación"; "cause", "causas").
    static func sameRoot(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shared = zip(a, b).prefix { $0 == $1 }.count
        let longer = max(a.count, b.count)
        return (shared >= 4 && Double(shared) >= 0.8 * Double(longer)) || (shared >= 5 && Double(shared) >= 0.55 * Double(longer))
    }

    /// The places (questions or lines) that speak of one part of a title: all its stems together; of three or more, all but one, as long as every one of them is somewhere in the
    /// course ("Spectroscopy of carbonyl compounds" isn't covered by carbonyl compounds when spectroscopy appears nowhere).
    private static func hits(_ stems: [String], in words: [String: [Int]]) -> [Int] {
        var counts: [Int: Int] = [:]
        for stem in stems {
            var found = Set<Int>()
            if let exact = words[stem] { found.formUnion(exact) }
            for (word, places) in words where word != stem && sameRoot(word, stem) { found.formUnion(places) }
            if found.isEmpty, stems.count >= 3 { return [] }
            for place in found { counts[place, default: 0] += 1 }
        }
        let need = stems.count <= 2 ? stems.count : stems.count - 1
        return counts.filter { $0.value >= need }.keys.sorted()
    }

    private static func enough(_ stems: [String]) -> Int { stems.count == 1 ? enoughForOneWord : 1 }

    /// A topic of the course has this in its name.
    private func namesATopic(_ stems: [String]) -> Bool {
        topicNames.contains { name in stems.allSatisfy { stem in name.contains { Self.sameRoot($0, stem) } } }
    }

    func match(_ name: String) -> Match {
        let parts = Self.parts(of: name)
        guard !parts.isEmpty else {
            let bare = Lexicon.fold(name).lowercased()
            return Match(inNotes: bare.count >= 3 && foldedLines.contains { $0.contains(bare) })
        }
        var found = Set<Int>()
        var inNotes = false
        for part in parts {
            let places = Self.hits(part, in: questionWords)
            // One of several parts, on a word most of the course uses ("Streamflow and water" in hydrology), says nothing about that part being covered.
            let courseWide = part.count == 1 && parts.count > 1 && questions.count >= 10 && places.count * 2 > questions.count
            if !courseWide, !places.isEmpty, places.count >= Self.enough(part) || namesATopic(part) { found.formUnion(places) }
            if Self.hits(part, in: lineWords).count >= Self.enough(part) { inNotes = true }
        }
        return Match(questions: found.count, topicIDs: Set(found.compactMap { questions[$0].topicID }), inNotes: inNotes)
    }
}
