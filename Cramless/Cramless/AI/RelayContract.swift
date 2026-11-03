import Foundation

// The relay's normalized contract: what the app sends to the Supabase `ai` function and what comes back.
// It is ours, not a provider's, so a provider swap never reaches shipped apps. The spec is
// docs/relay-contract.md; the canned replies in supabase/functions/_shared/fixtures are its examples, read by
// both the app's mock transport and the relay's MOCK mode. `RelayContractTests` decodes every fixture with
// these types, so a renamed field fails a test instead of a session.
//
// Wire format: JSON, camelCase keys, ISO 8601 dates. Add fields as optionals; never repurpose one.

// MARK: - Shared pieces

struct LineInput: Codable, Hashable, Sendable {
    var id: String
    var text: String
}

/// One page of material as the relay sees it. `image` (base64 JPEG) is sent only when the person turned on
/// "Send page photos"; otherwise the relay works from the recognised text alone.
struct PageInput: Codable, Hashable, Sendable {
    var page: Int
    var label: String
    var lines: [LineInput]
    var image: String?
}

/// A question as any generator returns it, before the app gives it a UUID and a home.
struct GeneratedItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: ItemKind
    var topic: String
    var prompt: String
    var answer: String
    var explanation: String
    var keyIdeas: [KeyIdea]
    var choices: [Choice]
    var cloze: ClozeSpec?
    /// For a diagram: the anchor ids of the label lines to hide. Boxes come from the page's own lines.
    var diagramLabels: [String]?
    /// Line ids ("p0.l12") or transcript segment ids ("s5") the item came from.
    var anchors: [String]
    /// 0 (easy) … 1 (hard).
    var difficulty: Double

    init(id: String, kind: ItemKind, topic: String, prompt: String, answer: String, explanation: String = "",
         keyIdeas: [KeyIdea] = [], choices: [Choice] = [], cloze: ClozeSpec? = nil, diagramLabels: [String]? = nil,
         anchors: [String] = [], difficulty: Double = 0.5) {
        self.id = id
        self.kind = kind
        self.topic = topic
        self.prompt = prompt
        self.answer = answer
        self.explanation = explanation
        self.keyIdeas = keyIdeas
        self.choices = choices
        self.cloze = cloze
        self.diagramLabels = diagramLabels
        self.anchors = anchors
        self.difficulty = difficulty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        prompt = try c.decode(String.self, forKey: .prompt)
        answer = try c.decode(String.self, forKey: .answer)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        keyIdeas = try c.decodeIfPresent([KeyIdea].self, forKey: .keyIdeas) ?? []
        choices = try c.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        cloze = try c.decodeIfPresent(ClozeSpec.self, forKey: .cloze)
        diagramLabels = try c.decodeIfPresent([String].self, forKey: .diagramLabels)
        anchors = try c.decodeIfPresent([String].self, forKey: .anchors) ?? []
        difficulty = try c.decodeIfPresent(Double.self, forKey: .difficulty) ?? 0.5
    }
}

struct GeneratedTopic: Codable, Hashable, Sendable {
    var name: String
    var summary: String
}

// MARK: - generate

struct GenerateRequest: Codable, Hashable, Sendable {
    var course: String
    var sourceTitle: String
    var level: String?
    var language: String
    var formats: [ItemKind]
    var maxItems: Int
    var pages: [PageInput]
}

struct GenerateResponse: Codable, Hashable, Sendable {
    var title: String
    var model: String
    var topics: [GeneratedTopic]
    var items: [GeneratedItem]
}

// MARK: - check

struct CheckRequest: Codable, Hashable, Sendable {
    var pages: [PageInput]
    var items: [GeneratedItem]
    /// The source's title (at most 200 characters) and its section headings (at most 60, each at most 120): a question
    /// can name the case or the author that only the title and headings carry, and the cited lines don't. Optional.
    var sourceTitle: String? = nil
    var headings: [String]? = nil
    /// The first pass rejected nearly everything, so the second judges only whether the source supports what the
    /// question and answer say, not whether the cited lines name every party. Optional; absent means strict.
    var lenient: Bool? = nil

    /// The title and headings as the relay takes them: trimmed, de-duplicated, and cut to its limits (in code points: `RelayLimits`).
    static func context(title: String, headings: [String]) -> (title: String?, headings: [String]?) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).clipped(toScalars: RelayLimits.checkTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var out: [String] = []
        for heading in headings {
            let clean = heading.trimmingCharacters(in: .whitespacesAndNewlines).clipped(toScalars: RelayLimits.heading)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { continue }
            out.append(clean)
            if out.count == RelayLimits.headings { break }
        }
        return (name.isEmpty ? nil : name, out.isEmpty ? nil : out)
    }
}

struct CheckVerdict: Codable, Hashable, Sendable {
    enum Verdict: String, Codable, Sendable {
        /// The source backs the item as written.
        case supported
        /// The item was corrected against the source; use the fixed fields.
        case fixed
        /// The source doesn't back it; the item is dropped before the person sees it.
        case unsupported
    }

    var id: String
    var verdict: Verdict
    var reason: String
    var fixedAnswer: String?
    var fixedChoices: [Choice]?
}

struct CheckResponse: Codable, Hashable, Sendable {
    var model: String
    var verdicts: [CheckVerdict]
}

// MARK: - grade

struct GradeRequest: Codable, Hashable, Sendable {
    var kind: ItemKind
    var level: String?
    var prompt: String
    var modelAnswer: String
    var keyIdeas: [KeyIdea]
    var response: String
    var sourceExcerpt: String?
}

struct GradeHit: Codable, Hashable, Sendable {
    var ideaId: String
    /// Words from the person's answer, verbatim. The app marks them only if it finds them.
    var quote: String
}

struct GradeResponse: Codable, Hashable, Sendable {
    enum Verdict: String, Codable, Sendable { case correct, partial, incorrect }

    var model: String
    /// 0…1.
    var score: Double
    var verdict: Verdict
    /// 0…1: how sure the grader is. Below 0.6 the app offers "Grade again".
    var confidence: Double
    var hits: [GradeHit]
    /// Key idea ids the answer missed.
    var missing: [String]
    var feedback: String
    /// One sentence that would complete the answer; empty when nothing is missing.
    var fix: String
}

// MARK: - tutor (streamed)

struct TutorMessage: Codable, Hashable, Sendable {
    var role: ChatRole
    var text: String
}

/// A passage of the person's material the tutor may cite. The app retrieves these; the model never searches.
struct TutorSource: Codable, Hashable, Sendable {
    var id: String
    var title: String
    var label: String
    var text: String
}

/// Set when the chat starts from a wrong answer ("Explain my mistake").
struct TutorContext: Codable, Hashable, Sendable {
    var itemPrompt: String
    var expected: String
    var given: String
}

struct TutorRequest: Codable, Hashable, Sendable {
    var mode: TutorMode
    var minor: Bool
    var course: String?
    var messages: [TutorMessage]
    var sources: [TutorSource]
    var context: TutorContext?
    /// What the student has added to the course, one line a source ("Cardiac cycle (6 pages)", "Lecture 7 (38 min)",
    /// "Classmate deck (21 cards)"), at most 20 lines of 120 characters, so the model can say what it looked at. Optional:
    /// a relay that doesn't know it ignores it, and it is left out of the body when empty.
    var materials: [String]? = nil
}

/// The tutor's server-sent events, normalized.
enum TutorEvent: Hashable, Sendable {
    case start(model: String)
    case delta(String)
    case citation(sourceID: String, label: String, quote: String)
    case done(model: String)
    case failure(code: String, message: String)
}

/// One event of a canned tutor script (fixtures/tutor-*.json): what the mock transport replays.
struct TutorScriptEvent: Codable, Hashable, Sendable {
    struct Payload: Codable, Hashable, Sendable {
        var text: String?
        var model: String?
        var sourceId: String?
        var label: String?
        var quote: String?
        var code: String?
        var message: String?
    }

    var event: String
    var delayMs: Int
    var data: Payload

    var tutorEvent: TutorEvent? {
        switch event {
        case "start": .start(model: data.model ?? "")
        case "delta": data.text.map { .delta($0) }
        case "citation": .citation(sourceID: data.sourceId ?? "", label: data.label ?? "", quote: data.quote ?? "")
        case "done": .done(model: data.model ?? "")
        case "error": .failure(code: data.code ?? "upstream", message: data.message ?? "")
        default: nil
        }
    }
}

struct TutorScript: Codable, Hashable, Sendable {
    var events: [TutorScriptEvent]
}

// MARK: - confusions

struct MistakeInput: Codable, Hashable, Sendable {
    var itemId: String
    var topic: String
    var prompt: String
    var expected: String
    var given: String
    var misses: Int
}

struct ConfusionsRequest: Codable, Hashable, Sendable {
    var course: String
    var mistakes: [MistakeInput]
}

struct ConfusionOut: Codable, Hashable, Sendable {
    var name: String
    var explanation: String
    var itemIds: [String]
    var lesson: String
    var questions: [GeneratedItem]
}

struct ConfusionsResponse: Codable, Hashable, Sendable {
    var model: String
    var confusions: [ConfusionOut]
}

// MARK: - lecture

struct SegmentInput: Codable, Hashable, Sendable {
    var id: String
    var start: Double
    var end: Double
    var text: String
}

struct FlagInput: Codable, Hashable, Sendable {
    var time: Double
    var text: String
}

struct LectureRequest: Codable, Hashable, Sendable {
    var course: String
    var title: String
    var segments: [SegmentInput]
    var flags: [FlagInput]
    var maxItems: Int
}

struct LectureExamFlag: Codable, Hashable, Sendable {
    var time: Double
    var text: String
    var why: String
}

struct LectureResponse: Codable, Hashable, Sendable {
    var model: String
    var title: String
    var summary: String
    var sections: [LectureNotes.Section]
    var keyTerms: [String]
    var examFlags: [LectureExamFlag]
    var items: [GeneratedItem]
    /// How many exam-relevant ideas the notes did not turn into questions (the cap on questions was reached). Optional.
    var leftOut: Int? = nil
}

// MARK: - cards from chat

struct CardsFromChatRequest: Codable, Hashable, Sendable {
    var course: String?
    var messages: [TutorMessage]
    var maxItems: Int
}

struct CardsFromChatResponse: Codable, Hashable, Sendable {
    var model: String
    var items: [GeneratedItem]
}

// MARK: - transcribe image (cloud vision for handwriting and math)

struct TranscribeImageRequest: Codable, Hashable, Sendable {
    var image: String
    var page: Int
    var label: String
}

/// Cloud transcription has no geometry: its lines can be cited and searched, never boxed on the page.
struct TranscribeImageResponse: Codable, Hashable, Sendable {
    var model: String
    var lines: [LineInput]
}

// MARK: - quota and entitlement

struct QuotaMeter: Codable, Hashable, Sendable {
    enum Key: String, Codable, Sendable { case scans, grades, tutor, lectures }
    enum Period: String, Codable, Sendable { case day, week }

    var key: Key
    var used: Int
    /// Nil means unlimited.
    var limit: Int?
    var period: Period

    var remaining: Int? { limit.map { max(0, $0 - used) } }
}

enum Plan: String, Codable, Sendable, CaseIterable {
    case free, pro, squad, pass

    var isPaid: Bool { self != .free }
}

struct QuotaStatus: Codable, Hashable, Sendable {
    var plan: Plan
    var meters: [QuotaMeter]

    func meter(_ key: QuotaMeter.Key) -> QuotaMeter? { meters.first { $0.key == key } }
}

struct EntitlementRequest: Codable, Hashable, Sendable {
    /// `Transaction.jwsRepresentation` for each current entitlement.
    var signedTransactions: [String]
}

struct EntitlementResponse: Codable, Hashable, Sendable {
    var plan: Plan
    var expiresAt: Date?
    var quota: QuotaStatus
}

// MARK: - squad and account

struct SquadInvite: Codable, Hashable, Sendable {
    var code: String
    var url: String
    var expiresAt: Date
}

struct SquadRedeemRequest: Codable, Hashable, Sendable {
    var code: String
}

struct SquadRedeemResponse: Codable, Hashable, Sendable {
    var plan: Plan
    var ownerName: String
}

struct SquadMember: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var joinedAt: Date
    var isOwner: Bool
}

struct SquadMembers: Codable, Hashable, Sendable {
    var seats: Int
    var members: [SquadMember]
}

struct SquadRemoveRequest: Codable, Hashable, Sendable {
    var memberId: String
}

struct AccountDeleteResponse: Codable, Hashable, Sendable {
    var deleted: Bool
}

// MARK: - errors

/// The relay's error envelope: `{"error": {"code", "message", "retryAfter"?, "quota"?}}`.
struct RelayErrorBody: Codable, Hashable, Sendable {
    struct Inner: Codable, Hashable, Sendable {
        var code: String
        var message: String
        var retryAfter: Double?
        var quota: QuotaStatus?
    }

    var error: Inner
}

enum RelayError: Error, Equatable, Sendable {
    /// No relay is configured in this build (blank Secrets.xcconfig).
    case notConfigured
    /// The person hasn't allowed cloud AI.
    case consentRequired
    case unauthorized
    case quotaExceeded(QuotaStatus?, message: String)
    case entitlementRequired
    case badRequest(String)
    case upstream(String)
    case offline
    case decoding(String)
    case cancelled

    /// Maps the relay's error code to a case.
    static func from(code: String, message: String, quota: QuotaStatus?) -> RelayError {
        switch code {
        case "unauthorized": .unauthorized
        case "quota_exceeded": .quotaExceeded(quota, message: message)
        case "entitlement_required": .entitlementRequired
        case "bad_request": .badRequest(message)
        default: .upstream(message)
        }
    }

    /// The anonymous account the relay needs isn't made yet: sign-ups are rate limited or the network is out, and the app
    /// keeps trying in the background (`AccountService`). A cloud job that meets this falls back to the next tier and says
    /// Cloud AI is getting ready. (An `.upstream` with a fixed message, so nothing that switches over the cases changes.)
    static let accountPending = RelayError.upstream("Cloud AI is getting ready.")
}

// MARK: - Fixtures

/// The canned replies bundled from supabase/functions/_shared/fixtures (the `fixtures` folder resource).
enum RelayFixtures {
    static func data(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "fixtures") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        guard let data = data(name) else { throw RelayError.decoding("missing fixture \(name).json") }
        return try JSONDecoder.cramless.decode(type, from: data)
    }
}
