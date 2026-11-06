import Foundation

/// What the writer of a harder question gets.
struct RungInput: Sendable {
    var course: String
    var sourceTitle: String
    var level: String?
    var language: String
    var next: ItemKind
    var parentKind: ItemKind
    var prompt: String
    var answer: String
    /// One page: the question's own lines and the ones around them, as line ids from the source.
    var page: PageText
    var headings: [String]
}

enum RungOutcome: Equatable, Sendable {
    case written(GeneratedItem)
    /// The lines don't hold anything harder, or the check didn't back what was written.
    case nothing
    /// Today's free drafts are used up.
    case limit(String)
    /// No Cloud AI now (no consent, offline).
    case unreachable
}

extension AIRouter {
    /// Writes one harder question and checks it against the same lines, as every written question is. Only the relay can: it never falls
    /// back to the offline rules, whose questions would be no harder.
    func writeRung(_ input: RungInput) async -> RungOutcome {
        guard cloudStillAllowed(), let transport else { return .unreachable }
        let page = PageInput(page: input.page.index, label: input.page.label.clipped(toScalars: RelayLimits.label),
                             lines: input.page.lines.prefix(RelayLimits.rungLines).map {
                                 LineInput(id: $0.id, text: $0.text.clipped(toScalars: RelayLimits.lineText))
                             },
                             image: nil)
        let request = GenerateRequest(course: input.course.clipped(toScalars: RelayLimits.course),
                                      sourceTitle: input.sourceTitle.clipped(toScalars: RelayLimits.title),
                                      level: input.level, language: input.language, formats: [input.next], maxItems: 1, pages: [page],
                                      rung: RungRequest(kind: input.parentKind, prompt: input.prompt.clipped(toScalars: RelayLimits.rungText),
                                                        answer: input.answer.clipped(toScalars: RelayLimits.rungText)))
        do {
            let written = try await transport.generate(request)
            guard let item = written.items.first(where: { $0.kind == input.next }) else { return .nothing }
            guard cloudStillAllowed() else { return .unreachable }
            let context = CheckRequest.context(title: input.sourceTitle, headings: input.headings)
            let check = CheckRequest(pages: [page], items: [item], sourceTitle: context.title, headings: context.headings)
            let verdicts = try await transport.check(check).verdicts
            return Self.applyCheck(verdicts, to: [item]).kept.first.map(RungOutcome.written) ?? .nothing
        } catch let error as RelayError {
            switch error {
            case .quotaExceeded(_, let message): return .limit(message.isEmpty ? AIFreeLimits.draftsMessage : message)
            case .upstream: return .nothing
            default: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}
