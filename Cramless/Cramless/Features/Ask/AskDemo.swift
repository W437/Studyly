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
