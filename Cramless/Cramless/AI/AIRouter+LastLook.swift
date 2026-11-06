import Foundation

// The last look's sentences: written ahead of an exam's eve when the cloud is allowed, on the hidden `extras` meter. Whatever goes wrong, the question and its
// answer stand in for the idea.
extension AIRouter {
    /// A plain sentence for each idea (by the idea's id), keeping only those `LastLookEngine.keeps` lets through. Nil when the cloud isn't allowed or doesn't
    /// answer, so the caller can ask again later; empty when it answered and nothing passed.
    func lastLookSentences(course: String, examTitle: String, ideas: [LastLookIdeaInput]) async -> [String: String]? {
        guard !ideas.isEmpty, route(.lastLook).usesCloud, cloudStillAllowed(), let transport else { return nil }
        let language = LocalGenerator.dominantLanguage(ideas.map(\.answer).joined(separator: " "))
        let request = LastLookRequest(course: course, examTitle: examTitle, language: language, ideas: ideas).fitted()
        guard let response = try? await transport.lastLook(request) else { return nil }
        let asked = Dictionary(ideas.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: String] = [:]
        for entry in response.ideas {
            guard let idea = asked[entry.id],
                  LastLookEngine.keeps(sentence: entry.sentence, question: idea.prompt, answer: idea.answer, lines: idea.lines) else { continue }
            out[entry.id] = entry.sentence
        }
        return out
    }
}
