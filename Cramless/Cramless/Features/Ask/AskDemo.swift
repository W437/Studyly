#if DEBUG
import Foundation

/// Demo conversations for the harness (`CRAMLESS_ASK=demo`, `CRAMLESS_CHAT=demo`), built in the demo world
/// (`SampleData`): every citation quotes a real line of Maya's material, so tapping one highlights it.
@MainActor
enum AskDemo {
    /// Once per launch: a person using the harness app keeps what they change afterwards.
    private static var launchStateApplied = false

    /// "How is meiosis different from mitosis?": bold, a small table, citations from the textbook, the slides and
    /// Lecture 6, a quick check with options, the person's answer and Cap's reply.
    @discardableResult
    static func conversation(app: AppModel) -> ChatThread? {
        guard let bio = app.courses.first(where: { $0.name == "Bio 101" }) ?? app.courses.first else { return nil }
        let thread = app.startChat(courseID: bio.id, title: "Mitosis vs meiosis")
        extend(thread, app: app)
        return thread
    }

    /// Adds the worked exchange to a chat.
    static func extend(_ thread: ChatThread, app: AppModel) {
        guard let course = app.liveCourse(thread.courseID) ?? app.courses.first else { return }
        let textbook = course.liveSources.first { $0.kind == .sample }
        let slides = course.liveSources.first { $0.kind == .pdf }
        let lecture = course.liveSources.first { $0.kind == .lecture }
        func cite(_ source: Source?, page: Int?, start: Double? = nil, _ quote: String, _ label: String, _ n: Int) -> Citation? {
            guard let source else { return nil }
            return Citation(id: "demo\(n)", sourceID: source.id, pageIndex: page, start: start, quote: quote, label: label)
        }
        let first = TutorOutcome(
            text: """
            Short version: **mitosis copies a cell**, and **meiosis makes egg and sperm cells** with half the chromosomes.

            | | Mitosis | Meiosis |
            |---|---|---|
            | Divisions | 1 | 2 |
            | New cells | 2, identical | 4, all different |
            | Chromosomes | Same as the parent | Half |

            Both start the same way: the chromatin condenses, so you can see the chromosomes.

            Quick check before we go on: how many cells does meiosis end with: 2, 4 or 8?
            """,
            citations: [
                cite(textbook, page: 0, "Mitosis is the process by which a single eukaryotic cell divides to produce two identical daughter cells.", "Textbook p. 87", 1),
                cite(textbook, page: 0, "Each daughter cell is genetically identical to the parent cell, with the same number of chromosomes.", "Textbook p. 87", 2),
                cite(slides, page: 1, "Two divisions make four cells, each with half the chromosomes of the parent.", "Slides p. 12", 3),
                cite(lecture, page: nil, start: 192, "The chromatin condenses, and you can finally see chromosomes under the microscope.", "Lecture 6 · 03:12", 4),
            ].compactMap { $0 },
            origin: .cloud, model: "demo", mode: .explain, grounded: true)
        let second = TutorOutcome(
            text: "Yes: four cells, each with half the chromosomes of the parent. That's how meiosis makes gametes, the eggs and sperm.",
            citations: [
                cite(slides, page: 1, "Two divisions make four cells, each with half the chromosomes of the parent.", "Slides p. 12", 5),
                cite(slides, page: 1, "Meiosis makes gametes: eggs and sperm.", "Slides p. 12", 6),
            ].compactMap { $0 },
            origin: .cloud, model: "demo", mode: .explain, grounded: true)
        app.addQuestion("How is meiosis different from mitosis?", to: thread)
        app.saveAnswer(first, to: thread)
        app.addQuestion("4", to: thread)
        app.saveAnswer(second, to: thread)
    }

    /// `CRAMLESS_ASSISTANT=cards|quiz|note|exam|practice|research|multi|answer|limit|error` asks Cap in a Bio 101 chat and lets the
    /// mock relay play its script as it would live. `CRAMLESS_ASSISTANT_FREEZE=<n>` holds the reply after n updates (a card half
    /// way through its work), `CRAMLESS_ASSISTANT_AUTO=cards,notes,exams` switches on "Let Cap do it", `CRAMLESS_ASSISTANT_SEND=<text>`
    /// asks something else, `CRAMLESS_ASSISTANT_APPROVE=<ms>` presses Add on the first open step that long after launch and
    /// `CRAMLESS_ASSISTANT_UNDO=<ms>` takes it back later, `CRAMLESS_RESEARCH=pro` makes web research need Capling Pro.
    @MainActor
    static func assistant(_ script: String, app: AppModel, courseID: UUID?) -> UUID? {
        let say: [String: String] = [
            "cards": "Make me flashcards on mitosis",
            "quiz": "Quiz me on mitosis",
            "note": "Write me a note summarising mitosis",
            "exam": "Plan my midterm for 12 November",
            "practice": "Start a practice session on mitosis",
            "research": "Research mitosis vs meiosis online",
            "multi": "Look through my notes and make cards on anaphase",
            "answer": "What is the difference between mitosis and meiosis?",
            "limit": "Make flashcards on mitosis #limit",
            "error": "Make flashcards on mitosis #fail",
        ]
        guard let text = TestHarness.value("CRAMLESS_ASSISTANT_SEND") ?? say[script] else { return nil }
        if let auto = TestHarness.value("CRAMLESS_ASSISTANT_AUTO") {
            app.settings.assistant.auto = Set(auto.split(separator: ",").compactMap { AssistantAutoKind(rawValue: String($0)) })
        }
        let course = courseID ?? app.courses.first(where: { $0.name == "Bio 101" })?.id ?? app.courses.first?.id
        let thread = app.startChat(courseID: course)
        app.setTutorMode(.explain, in: thread)
        if let n = TestHarness.value("CRAMLESS_ASSISTANT_FREEZE").flatMap(Int.init) { AskStreams.shared.freezeAfterUpdates = n }
        AskStreams.shared.ask(text, in: thread, app: app)
        func latest() -> (ChatMessage, AssistantStep)? {
            guard let message = thread.sortedMessages.last(where: { $0.role == .assistant }),
                  let step = message.steps.first(where: { $0.isOpen || $0.status == .applied }) else { return nil }
            return (message, step)
        }
        if let ms = TestHarness.value("CRAMLESS_ASSISTANT_APPROVE").flatMap(Int.init) {
            Task { @MainActor in
                try? await nap(ms)
                if let (message, step) = latest(), step.isOpen {
                    app.approveAssistantStep(messageID: message.id, stepID: step.id)
                    CLFeel.play(.saved)
                }
            }
        }
        if let ms = TestHarness.value("CRAMLESS_ASSISTANT_UNDO").flatMap(Int.init) {
            Task { @MainActor in
                try? await nap(ms)
                if let (message, step) = latest(), step.status == .applied { app.undoAssistantStep(messageID: message.id, stepID: step.id) }
            }
        }
        return thread.id
    }

    /// `CRAMLESS_ASSISTANT_SEED=1`: a deck, a note and an exam that Cap "added" earlier, made through the real add code, so
    /// Settings ▸ What Cap can do has its list to show.
    @MainActor
    static func seedAdditions(_ app: AppModel) {
        guard TestHarness.once("CRAMLESS_ASSISTANT_SEED") != nil,
              let course = app.courses.first(where: { $0.name == "Bio 101" }) ?? app.courses.first else { return }
        let thread = app.startChat(courseID: course.id, title: "Mitosis")
        let cards = [("What is mitosis?", "One cell divides into two identical cells."),
                     ("What happens after mitosis?", "Cytokinesis divides the cytoplasm."),
                     ("Why do we need mitosis?", "To grow, replace cells and heal.")]
            .map { CardDraft(id: ModelID.make(), front: $0.0, back: $0.1, basis: .own) }
        var drafts: [AssistantStep] = [
            AssistantStep(id: "seed-cards", tool: .createFlashcards, status: .proposed, courseID: course.id, courseName: course.name,
                          topicName: "Mitosis", title: "3 flashcards on Mitosis", payload: .cards(cards)),
            AssistantStep(id: "seed-note", tool: .createNote, status: .proposed, courseID: course.id, courseName: course.name,
                          title: "Mitosis in short",
                          payload: .note(NoteDraft(title: "Mitosis in short", body: "Mitosis makes two identical cells.\n\nThe four phases\n• Prophase\n• Metaphase\n• Anaphase\n• Telophase"))),
            AssistantStep(id: "seed-exam", tool: .createExam, status: .proposed, courseID: course.id, courseName: course.name,
                          title: "Bio 101 midterm",
                          payload: .exam(ExamPlanDraft(title: "Bio 101 midterm", date: app.now.addingTimeInterval(16 * 86_400), hasTime: false,
                                                       topicIDs: [], topicNames: []))),
        ]
        for i in drafts.indices { drafts[i] = app.applyAssistantStep(drafts[i], auto: i == 0) }
        app.saveAssistantAnswer(AssistantOutcome(text: "I added these for you.", citations: [], steps: drafts, model: "demo"), to: thread)
    }

    /// Every harness launch starts the Ask and AI screens from the same state, because settings persist between
    /// launches and a hook's change would leak into the next screenshot: the age band from `CRAMLESS_AGE=teen|
    /// under13|adult` (else not shared), hints first unless `CRAMLESS_TUTOR=explain`, and Cloud AI off when
    /// `CRAMLESS_CONSENT=0` (the launch settings only ever turn it on).
    static func applyLaunchState(_ app: AppModel) {
        guard app.config.isHarness, !launchStateApplied else { return }
        launchStateApplied = true
        let band = TestHarness.value("CRAMLESS_AGE").flatMap(AppSettings.AgeBand.init(rawValue:)) ?? .unknown
        if app.settings.ageBand != band { app.settings.ageBand = band }
        let mode: TutorMode = TestHarness.value("CRAMLESS_TUTOR") == "explain" ? .explain : .hints
        if app.settings.tutorMode != mode { app.settings.tutorMode = mode }
        if TestHarness.value("CRAMLESS_CONSENT") == "0", app.settings.cloudConsentVersion != 0 { app.withdrawCloudAI() }
    }
}
#endif
