import Foundation
import FoundationModels

// The structured answers the on-device model writes (guided generation), one shape per job. They are also
// Codable, so the scripted test backend decodes the same shapes from JSON and the real mapping code runs in tests.
//
// Every type here has a name used nowhere else in the app. Foundation Models builds a schema from type names, and
// a name that two different types share (two nested `Item`s, say) can make schema building throw "Duplicate type"
// at run time on a device, where no simulator test would see it; `AIOnDeviceTests` builds each schema to catch it.
// Ranges and choices are given as guides, never trusted: the mapping in `OnDeviceJobs` re-checks everything.

@Generable(description: "Study questions written only from the numbered lines of a student's page")
struct FMPageQuestions: Codable, Equatable, Sendable {
    @Guide(description: "Two to four short names for what the lines cover", .maximumCount(4))
    var topics: [String]

    @Guide(description: "Questions a student can answer from these lines alone", .maximumCount(8))
    var questions: [FMQuestion]
}

@Generable(description: "One study question")
struct FMQuestion: Codable, Equatable, Sendable {
    @Guide(description: "The kind of question", .anyOf(["recall", "multipleChoice", "fillIn", "flashcard"]))
    var kind: String

    @Guide(description: "One of the topic names")
    var topic: String

    @Guide(description: "The question. For a flashcard, the term on the front")
    var prompt: String

    @Guide(description: "The right answer in one short sentence, in the page's words")
    var answer: String

    @Guide(description: "For recall: one to three ideas a good answer must contain", .maximumCount(3))
    var keyIdeas: [FMKeyIdea]

    @Guide(description: "For multipleChoice: three wrong answers taken from the same lines", .maximumCount(3))
    var wrongChoices: [String]

    @Guide(description: "For fillIn: a sentence from the lines with the answer replaced by ____; otherwise empty")
    var clozeSentence: String

    @Guide(description: "The numbers of the lines the answer comes from, written like L3", .maximumCount(6))
    var lines: [String]
}

@Generable(description: "An idea a good answer contains")
struct FMKeyIdea: Codable, Equatable, Sendable {
    @Guide(description: "Two to six words naming the idea")
    var label: String

    @Guide(description: "Two to five short words or phrases from the lines that show the idea", .maximumCount(5))
    var terms: [String]
}

@Generable(description: "A check of a student's answer against its key ideas")
struct FMGrade: Codable, Equatable, Sendable {
    @Guide(description: "One entry for each key idea, in the order given", .maximumCount(6))
    var ideas: [FMIdeaCheck]

    @Guide(description: "One short, kind sentence about what the answer got right")
    var feedback: String

    @Guide(description: "One sentence that would complete the answer; empty when nothing is missing")
    var fix: String
}

@Generable(description: "Whether an answer states one key idea")
struct FMIdeaCheck: Codable, Equatable, Sendable {
    @Guide(description: "The key idea's number, like K1")
    var id: String

    @Guide(description: "True only if the answer clearly states this idea")
    var present: Bool

    @Guide(description: "The exact words from the answer that state it; empty when absent")
    var quote: String
}

@Generable(description: "Cap's short reply to a student, from their own notes")
struct FMTutorReply: Codable, Equatable, Sendable {
    @Guide(description: "False when the passages don't answer the question")
    var covered: Bool

    @Guide(description: "The reply, at most four short sentences")
    var reply: String

    @Guide(description: "The numbers of the passages the reply uses, like 1", .maximumCount(3))
    var passages: [Int]

    @Guide(description: "One or two sentences copied exactly from those passages", .maximumCount(2))
    var quotes: [String]
}

@Generable(description: "Notes for one part of a lecture")
struct FMLectureSection: Codable, Equatable, Sendable {
    @Guide(description: "A title of two to five words")
    var title: String

    @Guide(description: "One to three short notes, each one sentence, using only what the lecturer said", .maximumCount(3))
    var bullets: [String]
}

@Generable(description: "Flashcards of facts stated in a conversation")
struct FMCards: Codable, Equatable, Sendable {
    @Guide(description: "Flashcards, each a fact the conversation states", .maximumCount(6))
    var cards: [FMCard]
}

@Generable(description: "One flashcard")
struct FMCard: Codable, Equatable, Sendable {
    @Guide(description: "A term or a short question")
    var front: String

    @Guide(description: "The answer in one sentence, in the conversation's words")
    var back: String
}

@Generable(description: "Which sentence of a student's notes answers a question")
struct FMPick: Codable, Equatable, Sendable {
    @Guide(description: "The number of the one sentence that answers the question; 0 when none of them does", .range(0...12))
    var number: Int
}
