import Foundation
import FoundationModels

// The app's own on-device AI code against the real Foundation Models model on this Mac (the same system model family
// an Apple Intelligence iPhone has). Usage: probe <sample-ocr.json> <generate-fixture.json>
struct OCRFile: Decodable { var lines: [TextLine] }
let lines = try JSONDecoder().decode(OCRFile.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))).lines
let fixture = try JSONDecoder().decode(GenerateResponse.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
let backend = FoundationModelsBackend()
let budget = OnDeviceBudget()
print("capability:", SystemOnDeviceProbe(allowed: true).capability())

func timed<T>(_ label: String, _ body: () async throws -> T) async -> T? {
    let t = Date()
    do {
        let v = try await body()
        print("\n== \(label) (\(String(format: "%.1f", Date().timeIntervalSince(t))) s)")
        return v
    } catch {
        print("\n== \(label) FAILED after \(String(format: "%.1f", Date().timeIntervalSince(t))) s: \(error)")
        return nil
    }
}

// 1. Generation from the page's lines, then the grounding check.
let call = OnDevicePageCall(lines: lines, maxQuestions: 8)
print("page call fits the window:", budget.fits(call.prompt, instructions: OnDevicePageCall.instructions,
                                                schemaTokens: OnDevicePageCall.schemaTokens,
                                                responseTokens: OnDevicePageCall.responseTokens))
if let out = await timed("generate", { try await backend.respond(call) }) {
    for q in out.questions {
        print("  raw [\(q.kind)] \(q.prompt) → \(q.answer) | cloze: \(q.clozeSentence) | wrong: \(q.wrongChoices) | ideas: \(q.keyIdeas.map { "\($0.label)=\($0.terms)" }) | lines: \(q.lines) | negative: \(OnDeviceGeneration.hasNegativeStem(q.prompt))")
    }
    let mapped = OnDeviceGeneration.items(from: out, call: call, startingAt: 1)
    let texts = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.text) })
    let checked = GroundingCheck.apply(mapped.items, texts: texts)
    print("topics:", mapped.topics)
    print("model questions: \(out.questions.count) · usable: \(mapped.items.count) · grounded: \(checked.kept.count) · dropped: \(checked.dropped.count)")
    for item in checked.kept {
        var extra = ""
        if !item.keyIdeas.isEmpty { extra += " ideas=\(item.keyIdeas.map(\.label))" }
        if !item.choices.isEmpty { extra += " choices=\(item.choices.map(\.text))" }
        if let c = item.cloze { extra += " cloze=\(c.text)" }
        print("  ✓ [\(item.kind.rawValue)] \(item.prompt) → \(item.answer)\(extra) lines=\(item.anchors)")
    }
    for d in checked.dropped { print("  ✗ [\(d.item.kind.rawValue)] \(d.item.prompt) — \(d.reason)") }
}

// 2. Grading three answers to "why do cells divide by mitosis?" (local rules first, then the model).
if let i1 = fixture.items.first(where: { $0.id == "i1" }) {
    let subject = GradeSubject(kind: i1.kind, prompt: i1.prompt, modelAnswer: i1.answer, keyIdeas: i1.keyIdeas)
    for answer in ["So the body can grow and repair tissue, making two identical cells.",
                   "To get bigger and fix wounds. Each new cell gets an exact copy of the DNA and the same number of chromosomes.",
                   "To make sex cells with half the chromosomes."] {
        let local = LocalGrader.grade(subject, answer: .text(answer))
        print("\n-- answer: \(answer)")
        print("   rules:     score \(String(format: "%.2f", local.score)) \(local.verdict.rawValue) conf \(String(format: "%.2f", local.confidence)) hits \(local.hitIdeaIDs)")
        let gcall = OnDeviceGradeCall(subject: subject, answer: answer)
        if let out = await timed("grade on device", { try await backend.respond(gcall) }),
           let graded = OnDeviceGrading.outcome(from: out, subject: subject, answer: answer, local: local) {
            print("   on-device: score \(String(format: "%.2f", graded.score)) \(graded.verdict.rawValue) conf \(String(format: "%.2f", graded.confidence)) hits \(graded.hitIdeaIDs) marks \(graded.marks.count)")
            print("   feedback: \(graded.feedback)")
            print("   fix: \(graded.fix)")
        } else {
            print("   on-device: no usable grade (the rules' grade stands)")
        }
    }
}

// 3. The tutor, grounded in passages the app retrieves.
let material = [TutorMaterial(sourceID: UUID(), title: "Biology textbook", kind: .scan,
                              pages: [PageText(index: 0, label: "87", lines: lines, imageURL: nil)])]
let retriever = LocalRetriever(material: material)
for (question, mode) in [("What's the difference between mitosis and cytokinesis?", TutorMode.hints),
                         ("What's the difference between mitosis and cytokinesis?", .explain),
                         ("Who won the 2022 World Cup?", .explain),
                         ("Write my 500-word essay on mitosis so I can hand it in.", .explain)] {
    let hits = retriever.search(question, limit: 4)
    let sources = hits.enumerated().map { n, h in
        TutorSource(id: "s\(n + 1)", title: h.passage.title, label: h.passage.label, text: h.passage.text)
    }
    let tcall = OnDeviceTutorCall(question: question, mode: mode, passages: sources, context: nil)
    print("\n-- tutor (\(mode.rawValue)): \(question) · passages \(sources.count)")
    if let out = await timed("tutor on device", { try await backend.respond(tcall) }) {
        print("   covered: \(out.covered) · passages cited: \(out.passages)")
        print("   reply: \(out.reply)")
        let mapped = OnDeviceTutoring.reply(from: out, passages: sources)
        let usedInApp = mapped != nil && (mode != .hints || mapped!.text.contains("?")) && !sources.isEmpty
        print("   grounded after the quote check: \(mapped != nil) · quotes kept: \(mapped?.quotes.map(\.quote) ?? [])")
        print("   the app would show this reply: \(usedInApp) (otherwise the offline tutor answers)")
    }
}
