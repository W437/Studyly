import Foundation

// The relay's assistant and web research routes, as the app speaks them: the Swift side of
// supabase/functions/_shared/contract.ts (spec: docs/relay-contract.md ▸ Assistant). Ask Cap's model can call tools; the
// relay only lets it choose, streams the choice here, and the app runs it (`AppModel+Assistant`) because the notes and the
// screens are here. The round's own items travel as an opaque `continuation` and come back with the results, so the relay
// stores nothing between rounds.

// MARK: - Any JSON

/// A JSON value of any shape: a tool's arguments, a round's continuation. Kept exactly as the relay sent it.
enum AnyJSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyJSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: AnyJSON].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not JSON") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> AnyJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var array: [AnyJSON]? { if case .array(let a) = self { return a } else { return nil } }
    var object: [String: AnyJSON]? { if case .object(let o) = self { return o } else { return nil } }
    var double: Double? { if case .number(let n) = self { return n } else { return nil } }
    var int: Int? {
        guard case .number(let n) = self, n.isFinite, n == n.rounded(), abs(n) < 1e15 else { return nil }
        return Int(n)
    }
    var isNull: Bool { if case .null = self { return true } else { return false } }

    /// The text of a string, nil for null and for anything that isn't text.
    var text: String? { string }
}

// MARK: - The tools

enum AssistantToolName: String, Codable, CaseIterable, Sendable {
    case searchNotes = "search_notes"
    case createFlashcards = "create_flashcards"
    case createQuizQuestions = "create_quiz_questions"
    case createNote = "create_note"
    case createExam = "create_exam"
    case startPractice = "start_practice"
    case openScreen = "open_screen"
    case researchWeb = "research_web"

    /// What the student can approve: Cap drafts it, they add it.
    var isDraft: Bool {
        switch self {
        case .createFlashcards, .createQuizQuestions, .createNote, .createExam: true
        default: false
        }
    }
}

// MARK: - What the model is told about the student's study

struct StudyTopicState: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var weak: Bool?
}

struct StudyCourseState: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var sources: Int
    var questions: Int
    var due: Int
    var topics: [StudyTopicState]
}

struct StudyExamState: Codable, Hashable, Sendable {
    var id: String
    var courseId: String
    var title: String
    /// yyyy-MM-dd, the student's local day.
    var date: String
    /// 0 to 100.
    var readiness: Int
}

struct StudyState: Codable, Hashable, Sendable {
    /// yyyy-MM-dd, the student's local day.
    var today: String
    var currentCourseId: String?
    var courses: [StudyCourseState]
    var exams: [StudyExamState]
}

// MARK: - assistant (streamed)

struct AssistantResult: Codable, Hashable, Sendable {
    var callId: String
    var output: String
}

/// One round of tool calls already made in this reply.
struct AssistantTurn: Codable, Hashable, Sendable {
    var continuation: [AnyJSON]
    var results: [AssistantResult]
}

struct AssistantRequest: Codable, Hashable, Sendable {
    var mode: TutorMode
    var minor: Bool
    var course: String?
    var messages: [TutorMessage]
    var sources: [TutorSource]
    var context: TutorContext?
    var study: StudyState
    var tools: [AssistantToolName]
    var turns: [AssistantTurn]
}

/// The assistant's server-sent events, normalized.
enum AssistantEvent: Hashable, Sendable {
    case start(model: String)
    case delta(String)
    case citation(sourceID: String, label: String, quote: String)
    /// The model began a call.
    case toolStart(callID: String, name: String)
    /// One finished element of the call's array (a card, a question), as the model wrote it.
    case toolItem(callID: String, index: Int, item: AnyJSON)
    /// A piece of the call's text (a note's body).
    case toolText(callID: String, text: String)
    /// The call, whole.
    case toolCall(callID: String, name: String, arguments: AnyJSON)
    /// `stop` is "tool_calls" (run them and call again with `continuation`) or "end_turn". `limit` names a free
    /// allowance that has run out ("drafts").
    case done(model: String, stop: String, continuation: [AnyJSON], limit: String?)
    case failure(code: String, message: String)
}

/// One event of a canned assistant script (fixtures/assistant-*.json): what the mock transport replays.
struct AssistantScriptEvent: Codable, Hashable, Sendable {
    var event: String
    var delayMs: Int
    var data: AnyJSON

    var assistantEvent: AssistantEvent? {
        let d = data
        switch event {
        case "start": return .start(model: d["model"]?.string ?? "")
        case "delta": return d["text"]?.string.map { .delta($0) }
        case "citation":
            return .citation(sourceID: d["sourceId"]?.string ?? "", label: d["label"]?.string ?? "", quote: d["quote"]?.string ?? "")
        case "tool_start":
            guard let id = d["callId"]?.string, let name = d["name"]?.string else { return nil }
            return .toolStart(callID: id, name: name)
        case "tool_item":
            guard let id = d["callId"]?.string, let item = d["item"] else { return nil }
            return .toolItem(callID: id, index: d["index"]?.int ?? 0, item: item)
        case "tool_text":
            guard let id = d["callId"]?.string, let text = d["text"]?.string else { return nil }
            return .toolText(callID: id, text: text)
        case "tool_call":
            guard let id = d["callId"]?.string, let name = d["name"]?.string, let args = d["arguments"] else { return nil }
            return .toolCall(callID: id, name: name, arguments: args)
        case "done":
            return .done(model: d["model"]?.string ?? "", stop: d["stop"]?.string ?? "end_turn",
                         continuation: d["continuation"]?.array ?? [], limit: d["limit"]?.string)
        case "error":
            return .failure(code: d["code"]?.string ?? "upstream", message: d["message"]?.string ?? "")
        default: return nil
        }
    }
}

struct AssistantScript: Codable, Hashable, Sendable {
    var events: [AssistantScriptEvent]
}

// MARK: - research (streamed)

struct ResearchRequest: Codable, Hashable, Sendable {
    var minor: Bool
    var topic: String
    var focus: String?
    var course: String?
}

struct ResearchSource: Codable, Hashable, Sendable {
    var url: String
    var domain: String
}

enum ResearchPhase: String, Codable, Hashable, Sendable { case started, searching, done }

/// Web research's server-sent events, normalized.
enum ResearchEvent: Hashable, Sendable {
    case start(model: String)
    case search(id: String, phase: ResearchPhase, queries: [String], sources: [ResearchSource])
    case delta(String)
    case citation(url: String, title: String, domain: String)
    case done(model: String, searches: Int)
    case failure(code: String, message: String)
}

struct ResearchScriptEvent: Codable, Hashable, Sendable {
    var event: String
    var delayMs: Int
    var data: AnyJSON

    var researchEvent: ResearchEvent? {
        let d = data
        switch event {
        case "start": return .start(model: d["model"]?.string ?? "")
        case "search":
            guard let id = d["id"]?.string, let phase = d["phase"]?.string.flatMap(ResearchPhase.init(rawValue:)) else { return nil }
            let queries = d["queries"]?.array?.compactMap(\.string) ?? []
            let sources = d["sources"]?.array?.compactMap { s -> ResearchSource? in
                guard let url = s["url"]?.string else { return nil }
                return ResearchSource(url: url, domain: s["domain"]?.string ?? "")
            } ?? []
            return .search(id: id, phase: phase, queries: queries, sources: sources)
        case "delta": return d["text"]?.string.map { .delta($0) }
        case "citation":
            guard let url = d["url"]?.string else { return nil }
            return .citation(url: url, title: d["title"]?.string ?? "", domain: d["domain"]?.string ?? "")
        case "done": return .done(model: d["model"]?.string ?? "", searches: d["searches"]?.int ?? 0)
        case "error": return .failure(code: d["code"]?.string ?? "upstream", message: d["message"]?.string ?? "")
        default: return nil
        }
    }
}

struct ResearchScript: Codable, Hashable, Sendable {
    var events: [ResearchScriptEvent]
}

// MARK: - Which canned reply the mock plays

extension AssistantRequest {
    /// The script an assistant request gets from the mock transport. The first round is chosen by what the student asked, a
    /// later one by the tool the model last called. `assistantFixture` in supabase/functions/_shared/mock.ts chooses the
    /// same way (both are tested against one table).
    var mockScript: String {
        let asked = (messages.last?.text ?? "").lowercased()
        if let last = turns.last {
            // A call that failed gets a wrap-up that says so, whichever tool it was.
            if last.results.contains(where: { $0.output.range(of: #""error"\s*:"#, options: .regularExpression) != nil }) {
                return "assistant-failed-final"
            }
            let name = last.continuation.first { $0["type"]?.string == "function_call" }?["name"]?.string
            let afterLookup = turns.dropLast().contains { turn in
                turn.continuation.contains { $0["type"]?.string == "function_call" && $0["name"]?.string == "search_notes" }
            }
            switch name {
            case "search_notes": return "assistant-multi-2"
            case "create_flashcards": return afterLookup ? "assistant-multi-final" : "assistant-cards-final"
            case "create_quiz_questions": return "assistant-quiz-final"
            case "create_note": return "assistant-note-final"
            case "create_exam": return "assistant-exam-final"
            case "start_practice": return "assistant-practice-final"
            case "open_screen": return "assistant-open-final"
            case "research_web": return "assistant-research-final"
            default: return "assistant-answer"
            }
        }
        func has(_ pattern: String) -> Bool { asked.range(of: pattern, options: .regularExpression) != nil }
        if asked.contains("#fail") { return "assistant-error" }
        if asked.contains("#limit") { return "assistant-limit" }
        if has(#"\b(research|on the web|online|web search)\b|search the web"#) { return "assistant-research" }
        if has(#"look (it )?up|look through|check my notes|search my notes"#), has(#"\bcards?\b"#) { return "assistant-multi-1" }
        if has(#"\b(exam|midterm)\b"#), has(#"\b(plan|add|schedule|create|set|put|draft)\b"#) { return "assistant-exam" }
        if has(#"flash\s?cards?|\bcards\b"#) { return "assistant-cards" }
        if has(#"\b(quiz|questions?)\b"#) { return "assistant-quiz" }
        if has(#"\b(practice|practise|drill)\b"#) { return "assistant-practice" }
        if has(#"\b(notes?|summary|study sheet)\b"#), has(#"\b(make|write|add|create|draft)\b"#) { return "assistant-note" }
        if has(#"\b(open|show me|go to)\b.*\b(progress|sky|library|today)\b"#) { return "assistant-open" }
        return "assistant-answer"
    }
}
