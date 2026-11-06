import SwiftUI

/// A study session, full screen: a top bar (close, progress segments coloured by result, the time), one question
/// at a time in its own format, then the summary. Answers are recorded as the person commits each one, so closing
/// only asks first when the question on screen has an answer that isn't saved yet (and an answer being typed is kept as a
/// draft for next time). A daily, catch-up or eve session that iOS closed picks up the same day where it stood
/// (`SessionCheckpoint`).
///
/// DEBUG hooks (read once, see `SessionDebug`): `CRAMLESS_SESSION_STATE`, `CRAMLESS_SESSION_ANSWER`,
/// `CRAMLESS_SESSION_PICK`, `CRAMLESS_SESSION_DRAFT=<text>` (with `ownwords`: the first question has those words kept from
/// before), `CRAMLESS_SESSION_RESUME=1` (a session of this kind was cut off earlier today after three answers, with words typed
/// on an own-words question: it picks up).
struct SessionView: View {
    let request: SessionRequest

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var runner: SessionRunner?
    @State private var confirmLeave = false
    #if DEBUG
    @State private var debug = SessionDebug.read()
    #endif

    var body: some View {
        ZStack {
            CLColor.background.ignoresSafeArea()
            if let runner {
                content(runner)
                    .id(runner.id)
                    .transition(.opacity)
            }
        }
        .onAppear { if runner == nil { begin(request) } }
        .onDisappear {
            runner?.close()
            app.stopReadingAloud()
        }
        // Leaving the screen (a call, another app) may be the last moment before iOS closes the app.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { runner?.keepCheckpoint() }
        }
        .confirmationDialog("Leave this question?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive, action: leave)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(leaveMessage)
        }
    }

    /// Words typed on the question are kept for next time; anything else unsaved (a pick, a grade) isn't.
    private var leaveMessage: LocalizedStringResource {
        if let runner, runner.isTypingAnswer || runner.current.map({ app.answerDraft(for: $0.itemID) != nil }) == true {
            return "Cap keeps what you typed for next time. Everything before it is saved."
        }
        return "Your answer to this one isn't saved yet. Everything before it is."
    }

    @ViewBuilder
    private func content(_ runner: SessionRunner) -> some View {
        switch runner.phase {
        case .empty:
            SessionEmptyView(kind: runner.kind) { app.router.dismissCover() }
        case .ready, .question:
            VStack(spacing: 0) {
                SessionTopBar(runner: runner, onClose: close)
                SessionQuestionHost(runner: runner, auto: autoAnswers, autoplay: autoplay)
            }
            .overlay { SkyFlareView(flare: runner.saveFlare) }
            .transition(.opacity)
        case .finished:
            if let summary = runner.summary, runner.kind != .quickCheck {
                SessionSummaryView(runner: runner, summary: summary, onDone: { app.router.dismissCover() },
                                   onStart: { begin($0) })
                    .transition(.opacity)
            } else {
                Color.clear.onAppear { app.router.dismissCover() }
            }
        }
    }

    private var autoAnswers: SessionQuestionHost.Auto? {
        #if DEBUG
        return debug.auto
        #else
        return nil
        #endif
    }

    private var autoplay: SessionQuestionHost.Autoplay? {
        #if DEBUG
        return debug.autoplay
        #else
        return nil
        #endif
    }

    // MARK: Running

    /// Starts `request` (the first session, a fix from the summary, or a bonus round). The day's own session picks up where it
    /// stood when iOS closed the app earlier today.
    private func begin(_ request: SessionRequest) {
        #if DEBUG
        if runner == nil, TestHarness.once("CRAMLESS_SESSION_RESUME") == "1" { app.debugCutOffSession(request) }
        #endif
        let checkpoint = runner == nil ? app.resumableCheckpoint(for: request) : nil
        let next = SessionRunner(app: app, request: request, resuming: checkpoint)
        #if DEBUG
        debug.prepare(next, app: app)
        #endif
        if next.phase == .ready { next.start() }
        CLHaptics.prepare()
        CLFeel.prepare()
        // Cap's reactions are ready by the first answer: opening a clip's file shouldn't be what delays his "Nice!".
        CapClipLibrary.prewarm([.nice, .almost, .notYet, .point, .think, .celebrate, .proud])
        #if DEBUG
        if runner == nil { debug.finishIfAsked(next, app: app) }
        #endif
        withAnimation(runner == nil ? nil : CLMotion.fade) { runner = next }
    }

    private func close() {
        guard let runner, runner.phase == .question else { app.router.dismissCover(); return }
        if runner.hasUnsavedAnswer { confirmLeave = true } else { leave() }
    }

    private func leave() {
        guard let runner else { return }
        let answered = runner.distinctAnswered
        runner.close()
        app.stopReadingAloud()
        app.router.dismissCover()
        if answered > 0, runner.kind != .quickCheck {
            let rest = runner.kind == .daily || runner.kind == .catchUp ? " The rest wait for tomorrow." : ""
            app.router.toast("\(SessionCopy.questions(answered).capitalizedFirst) saved.\(rest)",
                             systemImage: "checkmark.circle.fill", tone: .neutral)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Top bar

/// Close, the progress segments (mint right, sun partly, rose missed, tangerine now), and the time in a glass pill.
/// From three right in a row a second glass pill morphs out of the time with the run, and melts back into it when
/// the run ends.
struct SessionTopBar: View {
    let runner: SessionRunner
    let onClose: () -> Void

    @Namespace private var glass

    var body: some View {
        let combo = runner.liveCombo
        let showsRun = combo >= ComboRun.shownFrom
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                CLIconButton(systemImage: "xmark", label: "End session", action: onClose)
                SessionSegments(runner: runner)
                    .frame(maxWidth: .infinity)
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        if showsRun {
                            Label("\(combo)", systemImage: "bolt.fill")
                                .font(.system(.footnote, design: .rounded, weight: .heavy))
                                .contentTransition(.numericText(value: Double(combo)))
                                .foregroundStyle(CLColor.mintInk)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .glassEffect(.regular.tint(CLColor.mint.opacity(0.3)), in: Capsule())
                                .glassEffectID("run", in: glass)
                                .accessibilityLabel("\(combo) right in a row")
                        }
                        Text(runner.startedAt, style: .timer)
                            .clFont(.number(15, .bold))
                            .foregroundStyle(CLColor.ink2)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 58, minHeight: 32)
                            .glassEffect(.regular, in: Capsule())
                            .glassEffectID("time", in: glass)
                            .accessibilityLabel("Time in this session")
                    }
                }
                .animation(CLMotion.pop, value: showsRun)
                .animation(CLMotion.snap, value: combo)
            }
            if let context = contextLine {
                Text(context)
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
                    .lineLimit(2)
                    .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// For a session that isn't the daily one: what it is ("2-minute fix · Anaphase vs telophase"). A session picked up after a
    /// close says so until the first answer.
    private var contextLine: String? {
        if runner.resumed, runner.answers.isEmpty { return String(localized: "Picked up where you left off.") }
        switch runner.kind {
        case .daily, .quickCheck, .mock: return nil
        case .fix:
            let name = runner.built.weakSpots.first?.name
            return [SessionCopy.title(for: .fix), name].compactMap { $0 }.joined(separator: " · ")
        case .examEve:
            return "Exam eve · weak spots only, then sleep"
        case .catchUp:
            return "Catch-up · the ones you're closest to forgetting"
        case .practice:
            return "Bonus round · extra practice"
        }
    }
}

/// The progress bar: one segment per question, coloured by result. The newest result blooms (a glow that shrinks
/// back), and while a run of three or more right answers is going its segments glow mint, with one shine across
/// the bar for each new step. Nothing loops while the person reads; under Reduce Motion the bar only changes colour.
struct SessionSegments: View {
    let runner: SessionRunner

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var bloom = 0.0
    @State private var shines = 0

    var body: some View {
        let count = runner.queue.count
        // Up to 16 questions read as separate segments; a longer session reads as one bar with fine ticks.
        let dense = count > 16
        let newest = runner.provisional != nil ? runner.queue.position : runner.queue.position - 1
        let run = runner.liveCombo
        let glowing = Set(run >= ComboRun.shownFrom ? Self.runSegments(runner, from: newest) : [])
        HStack(spacing: dense ? 1 : 4) {
            ForEach(0..<count, id: \.self) { index in
                let state = runner.segment(index)
                (dense ? AnyShape(Rectangle()) : AnyShape(Capsule()))
                    .fill(color(state))
                    .frame(height: 8)
                    .shadow(color: glowing.contains(index) ? CLColor.mint.opacity(0.55) : .clear, radius: 4)
                    .shadow(color: index == newest && !reduceMotion ? glow(state).opacity(0.8 * bloom) : .clear,
                            radius: 10 * bloom)
            }
        }
        .overlay {
            if !reduceMotion && run >= ComboRun.shownFrom {
                Shine(trigger: shines)
            }
        }
        .clipShape(Capsule())
        .padding(.vertical, 4)
        .animation(CLMotion.snap, value: runner.queue.position)
        .animation(CLMotion.settle, value: count)
        .onChange(of: "\(runner.queue.position)-\(runner.provisional?.rawValue ?? "")") {
            guard !reduceMotion, runner.provisional != nil else { return }
            bloom = 1
            withAnimation(CLMotion.bloom) { bloom = 0 }
            if runner.liveCombo >= ComboRun.shownFrom { shines += 1 }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("Question \(min(runner.queue.position + 1, count)) of \(count). \(runner.rightFirstTime) right so far.")
    }

    private func color(_ state: SessionRunner.SegmentState) -> Color {
        switch state {
        case .pending: CLColor.surface3
        case .current: CLColor.tangerine
        case .done(let outcome): FeedbackTone(outcome).solid
        }
    }

    private func glow(_ state: SessionRunner.SegmentState) -> Color {
        if case .done(let outcome) = state { return FeedbackTone(outcome).solid }
        return .clear
    }

    /// The segments of the run ending at `newest`: right answers back to the last one that wasn't.
    static func runSegments(_ runner: SessionRunner, from newest: Int) -> [Int] {
        guard newest >= 0 else { return [] }
        var indices: [Int] = []
        for index in stride(from: newest, through: 0, by: -1) {
            guard case .done(let outcome) = runner.segment(index), outcome == .right else { break }
            indices.append(index)
        }
        return indices
    }
}

/// One soft highlight sweeping across the bar each time `trigger` changes.
private struct Shine: View {
    let trigger: Int

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: max(24, geo.size.width * 0.18))
                .keyframeAnimator(initialValue: -0.3, trigger: trigger) { view, position in
                    view.offset(x: position * geo.size.width)
                } keyframes: { _ in
                    MoveKeyframe(-0.3)
                    CubicKeyframe(1.2, duration: 0.65)
                }
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
        .accessibilityHidden(true)
    }
}

// MARK: - Question host

/// The current question in its format, sliding in from the trailing edge (a fade under Reduce Motion).
struct SessionQuestionHost: View {
    let runner: SessionRunner
    /// DEBUG: answers the first question shows by itself.
    var auto: Auto? = nil
    /// DEBUG: answers every question by a pattern and moves on (`CRAMLESS_SESSION_AUTOPLAY`).
    var autoplay: Autoplay? = nil

    struct Auto: Equatable {
        var entryID: String
        var ownWords: String?
        var choice: Int?
        var fill: String?
        var flip = false
        /// A flipped flashcard's rating.
        var rate: Rating?
        /// Milliseconds between the panel showing and Continue.
        var next: Int?
    }

    /// `r` right, `p` partly right, `w` wrong, `k` "I don't know"; Continue `beat` ms after each panel.
    struct Autoplay: Equatable {
        var pattern: [Character]
        var beat: Int
    }

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            if let entry = runner.current {
                if let item = runner.item(for: entry), item.modelContext != nil {
                    question(entry: entry, item: item)
                        .id(entry.id)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    // The item was deleted elsewhere: move past it.
                    Color.clear.onAppear { runner.advance() }
                }
            }
        }
        // Not clipped: the answer panel's fill runs on past this frame, under the home indicator, to the screen's
        // bottom edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func question(entry: SessionEntry, item: StudyItem) -> some View {
        let mine = autoplayed(entry, item) ?? (auto?.entryID == entry.id ? auto : nil)
        switch item.kind {
        case .recall, .apply:
            OwnWordsQuestionView(runner: runner, entry: entry, item: item, autoAnswer: mine?.ownWords, autoContinue: mine?.next)
        case .mcq:
            ChoiceQuestionView(runner: runner, entry: entry, item: item, autoPick: mine?.choice, autoContinue: mine?.next)
        case .cloze:
            ClozeQuestionView(runner: runner, entry: entry, item: item, autoFill: mine?.fill, autoContinue: mine?.next)
        case .diagram:
            if item.diagram != nil {
                DiagramQuestionView(runner: runner, entry: entry, item: item, autoFill: mine?.fill, autoContinue: mine?.next)
            } else {
                OwnWordsQuestionView(runner: runner, entry: entry, item: item, autoAnswer: mine?.ownWords,
                                     autoContinue: mine?.next)
            }
        case .flashcard:
            FlashcardQuestionView(runner: runner, entry: entry, item: item, autoFlip: mine?.flip ?? false,
                                  autoRate: mine?.rate, autoContinue: mine?.next)
        }
    }

    /// The autoplay answer for this question: the pattern's next letter, by how many answers came before.
    private func autoplayed(_ entry: SessionEntry, _ item: StudyItem) -> Auto? {
        guard let autoplay, !autoplay.pattern.isEmpty else { return nil }
        let step = autoplay.pattern[runner.answers.count % autoplay.pattern.count]
        var auto = Auto(entryID: entry.id, next: autoplay.beat)
        switch item.kind {
        case .mcq:
            auto.choice = step == "r" ? -1 : step == "k" ? -3 : -2
        case .cloze:
            auto.fill = step == "r" ? "right" : step == "p" ? "hinted" : "wrong"
        case .diagram where item.diagram != nil:
            auto.fill = step == "r" ? "right" : "wrong"
        case .flashcard:
            auto.flip = true
            auto.rate = step == "r" ? .good : step == "p" ? .hard : .again
        default:
            switch step {
            case "r": auto.ownWords = Self.rightAnswer(to: item, subject: app.gradeSubject(for: item))
            case "p": auto.ownWords = item.keyIdeas.first.map { $0.terms.first ?? $0.label } ?? item.answer
            case "k": auto.ownWords = ""
            default: auto.ownWords = "No idea, sorry."
            }
        }
        return auto
    }

    /// An answer the offline rules grade right: the model answer, plus the terms of any key idea it doesn't name
    /// word for word (a term that only repeats the question never counts, so all of them go in). Autoplay's `r`, so
    /// films repeat whichever grader is on.
    static func rightAnswer(to item: StudyItem, subject: GradeSubject) -> String {
        let missing = Set(LocalGrader.grade(subject, answer: .text(item.answer)).missing.map(\.id))
        let extra = item.keyIdeas.filter { missing.contains($0.id) }.map { $0.terms.joined(separator: ", ") }
        return ([item.answer] + extra).joined(separator: " ")
    }
}

// MARK: - Nothing to study

struct SessionEmptyView: View {
    let kind: SessionKind
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            CapView(pose: .wave, size: 150)
            Text(kind == .fix ? "Nothing to drill here" : "Nothing to study right now")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
            Text(kind == .fix ? "These questions aren't in your library any more."
                 : "You're all caught up. New questions show up here as you add material.")
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Done", action: onDone)
                .buttonStyle(.cl(.primary))
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.bottom, 12)
    }
}

// MARK: - DEBUG

#if DEBUG
/// Screenshot hooks for a session, read once when it opens:
///
/// - `CRAMLESS_SESSION_STATE`:
///   `ownwords`, `mcq`, `cloze`, `diagram`, `flashcard` open on that format;
///   `graded` submits an own-words answer ("why do cells divide by mitosis?", 2 of 3 key ideas);
///   `mcq-answered`, `cloze-answered`, `diagram-answered` answer right (`CRAMLESS_SESSION_PICK=wrong`: wrong);
///   `diagram-filled` places every label without checking; `flipped` turns the flashcard;
///   `flashcard-saved` makes the first flashcard a fading memory, flips it and rates it Good: a save, with the
///   sky's flare; `mcq-saved` does the same with a multiple-choice question answered right ("Saved it.", Cap's sparkles
///   and the flare together);
///   `summary` answers eight questions plus a swapped pair, then shows the summary (with a mix-up offered);
///   `exameve-summary`, `fix-summary` answer everything and finish (use with `session:examEve`, `session:fix`);
///   `milestone-summary`, `badge-summary` and `quest-summary` answer eight questions and show the summary of the game loop
///   (`milestone-summary` with `CRAMLESS_SCENARIO=streak:29`; `quest-summary` with `CRAMLESS_QUESTS=partial|weekFull`;
///   `badge-summary` first forgets the 7-day badge, so the session earns it).
/// - `CRAMLESS_SESSION_ANSWER=<text>`: the own-words answer to submit (with `graded` or `ownwords`).
@MainActor
struct SessionDebug {
    var state: String?
    var answer: String?
    var wrong: Bool
    var auto: SessionQuestionHost.Auto?
    /// `CRAMLESS_SESSION_AUTOPLAY=rrrrrpwk` answers every question by that pattern (`r` right, `p` partly, `w`
    /// wrong, `k` "I don't know") and presses Continue `CRAMLESS_AUTOPLAY_BEAT` ms (default 1400) after each panel,
    /// through to the summary: films of the session's feel, with no taps.
    var autoplay: SessionQuestionHost.Autoplay?
    private var used = false

    static func read() -> SessionDebug {
        var debug = SessionDebug(state: TestHarness.once("CRAMLESS_SESSION_STATE"),
                                 answer: TestHarness.once("CRAMLESS_SESSION_ANSWER"),
                                 wrong: TestHarness.once("CRAMLESS_SESSION_PICK") == "wrong")
        if let pattern = TestHarness.once("CRAMLESS_SESSION_AUTOPLAY") {
            debug.autoplay = .init(pattern: Array(pattern.lowercased()),
                                   beat: TestHarness.value("CRAMLESS_AUTOPLAY_BEAT").flatMap(Int.init) ?? 1400)
        }
        return debug
    }

    init(state: String?, answer: String?, wrong: Bool) {
        self.state = state
        self.answer = answer
        self.wrong = wrong
    }

    /// Puts the right format first and sets up its automatic answer.
    mutating func prepare(_ runner: SessionRunner, app: AppModel) {
        guard !used, let state else {
            if let answer, !used {
                used = true
                runner.debugFront(kinds: [.recall, .apply])
                if let first = runner.queue.current { auto = .init(entryID: first.id, ownWords: answer) }
            }
            return
        }
        used = true
        switch state {
        case "ownwords":
            runner.debugFront(kinds: [.recall, .apply], preferring: "why do cells divide")
            if let draft = TestHarness.once("CRAMLESS_SESSION_DRAFT"), let first = runner.queue.current {
                app.keepAnswerDraft(draft, for: first.itemID)
            }
        case "graded":
            runner.debugFront(kinds: [.recall, .apply], preferring: "why do cells divide")
        case "mcq", "mcq-answered", "mcq-saved":
            runner.debugFront(kinds: [.mcq], preferring: "line up at the equator")
            if state == "mcq-saved", let first = runner.queue.current, let item = runner.item(for: first) {
                item.memory = Self.fading(app)
            }
        case "cloze", "cloze-answered":
            runner.debugFront(kinds: [.cloze], preferring: "Fill in the phase")
        case "diagram", "diagram-answered", "diagram-filled":
            runner.debugFront(kinds: [.diagram])
        case "badge-summary":
            app.debugForgetBadge(.streak7)
        case "flashcard", "flipped", "flashcard-saved":
            runner.debugFront(kinds: [.flashcard], preferring: "Cytokinesis")
            if state == "flashcard-saved", let first = runner.queue.current, let item = runner.item(for: first) {
                item.memory = Self.fading(app)
            }
        default:
            break
        }
        guard let first = runner.queue.current else { return }
        switch state {
        case "graded":
            auto = .init(entryID: first.id,
                         ownWords: answer ?? "So the body can grow and repair tissue, making two identical cells.")
        case "ownwords":
            if let answer { auto = .init(entryID: first.id, ownWords: answer) }
        case "mcq-answered", "mcq-saved":
            auto = .init(entryID: first.id, choice: wrong ? -2 : -1)
        case "cloze-answered":
            auto = .init(entryID: first.id, fill: wrong ? "wrong" : "right")
        case "diagram-answered":
            auto = .init(entryID: first.id, fill: wrong ? "wrong" : "right")
        case "diagram-filled":
            auto = .init(entryID: first.id, fill: "filled")
        case "flipped":
            auto = .init(entryID: first.id, flip: true)
        case "flashcard-saved":
            auto = .init(entryID: first.id, flip: true, rate: .good)
        default:
            break
        }
    }

    /// A memory studied eight days ago whose recall has since fallen to 50%: right now, answering it is a save.
    private static func fading(_ app: AppModel) -> MemoryState {
        let fsrs = app.fsrs
        let days = 8.0
        let stability = fsrs.factor * days / (pow(0.5, 1 / fsrs.decay) - 1)
        return MemoryState(state: .review, stability: stability, difficulty: 5, due: app.now,
                           lastReview: app.calendar.date(byAdding: .day, value: -Int(days), to: app.now), reps: 3)
    }

    /// The summary states: answer the session (and, for `summary`, a swapped pair) and finish it.
    func finishIfAsked(_ runner: SessionRunner, app: AppModel) {
        guard runner.phase == .question else { return }
        switch state {
        case "summary":
            let items = app.fetch(FetchDescriptorFactory.allItems)
            if let a = items.first(where: { $0.prompt == "What does anaphase I separate?" }),
               let b = items.first(where: { $0.prompt == "What does anaphase II separate?" }) {
                runner.debugSwap(a, b)
            }
            runner.debugAnswer(8)
        case "milestone-summary", "badge-summary", "quest-summary":
            runner.debugAnswer(8)
        case "exameve-summary":
            runner.debugAnswer(runner.queue.count, pattern: [.good, .good, .hard, .good])
        case "fix-summary":
            runner.debugAnswer(runner.queue.count, pattern: [.good, .good, .good, .easy, .good])
        default:
            break
        }
    }
}
#endif
