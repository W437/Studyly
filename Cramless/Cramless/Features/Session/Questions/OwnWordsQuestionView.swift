import SwiftUI
import UIKit

/// "In your own words" and "Apply it": the person types an answer and submits. The offline grade lands at once:
/// the highlighter sweeps the key ideas found word for word in their own answer (a tick as each one lands), the
/// missed ideas are named, the feedback and the one-line fix show. A refined grade (this iPhone's model or Cloud
/// AI) updates it in place with a quiet cross-fade. "Grade again" appears when the grader isn't sure. The rating
/// comes from the score, and the person can change it before moving on.
///
/// When no model will grade the answer and the rules' verdict can't be trusted (`GradeMode.selfCheck`), there is no verdict: the
/// panel says "Compare with the answer.", the card shows the model answer and its source, and the key ideas are a checklist
/// ("Tick what you had", then "None of these"). The ideas the rules found in the person's own words start ticked, a tap toggles one,
/// and the rating comes from the ticks (all right, some partly, none not yet). Continue waits until the person has marked
/// something (a tick changed, "None of these", or the rules found at least one idea for them to agree with), so an answer is never
/// logged as a deliberate "I had none" that nobody said. It is recorded as marked by the person ("self"), with a score that agrees
/// with the rating they end up with.
///
/// While a model is still looking at an answer (`GradeMode.provisional`) Continue says "Double-checking…" and waits: the rules' first
/// guess is never what gets recorded. The router lets the model go after `SelfCheck.modelWait`, and the answer is then the person's to
/// mark (or, where the rules can be trusted, final).
///
/// What is typed is kept as a draft (`AnswerDrafts`): saved after a 400 ms pause and whenever the app leaves the screen, put back
/// into the empty editor the next time the question comes up ("Kept from before"), and cleared once the answer is recorded, so a
/// call, another app or iOS closing Capling loses nothing.
///
/// A rating the person gave (the marks of a self-check, "Counts as") can be undone for a moment (`SessionRunner.PendingGrade`): this view
/// then comes back with its panel as it stood, no new grade and no sounds, and its draft is still there, since a draft goes only once
/// the answer is really recorded.
///
/// DEBUG: `CRAMLESS_SESSION_ANSWER=<text>` submits that answer as soon as the question shows (the session's
/// `CRAMLESS_SESSION_STATE=graded` supplies one of its own). `CRAMLESS_SESSION_DRAFT=<text>` (with `ownwords`) keeps those words
/// as the question's draft first.
struct OwnWordsQuestionView: View {
    let runner: SessionRunner
    let entry: SessionEntry
    let item: StudyItem
    /// Submitted on appear (DEBUG hooks, onboarding demos never: they're real).
    var autoAnswer: String? = nil
    /// DEBUG: press Continue this many milliseconds after the panel shows (session autoplay).
    var autoContinue: Int? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editorFocused: Bool

    @State private var text = ""
    /// The editor opened with words kept from before.
    @State private var restoredDraft = false
    @State private var lookedForDraft = false
    @State private var draftTask: Task<Void, Never>?
    @State private var submitted: String?
    @State private var grade: GradeOutcome?
    @State private var saved = false
    /// The run this answer makes, fixed when the verdict lands.
    @State private var run = 0
    @State private var swept = false
    @State private var revealed = 0
    @State private var refining = false
    @State private var regrading = false
    @State private var secondLook: String?
    @State private var override: Rating?
    @State private var durationMs = 0
    @State private var intervals: [Rating: Double] = [:]
    @State private var gradeTask: Task<Void, Never>?
    @State private var revealTask: Task<Void, Never>?
    /// A self-check: the key ideas the person ticked, starting from the ones the rules found.
    @State private var ticked: Set<String> = []
    /// The person has changed a tick or chosen "None of these", so the line under the answer says they marked it.
    @State private var marked = false
    /// The rules found at least one key idea in the person's own words: their ticks stand as the mark if the person agrees.
    @State private var rulesFound = false
    /// Back from an Undo: the panel as it stood, nothing plays again.
    @State private var restored = false

    private var ideas: [KeyIdea] { item.keyIdeas }
    /// Steps of the reveal after the sweep: each idea row, then the feedback, then the rating line.
    private var revealSteps: Int { ideas.count + 2 }
    /// No model graded this answer: the person marks it.
    private var isSelfCheck: Bool { grade?.mode == .selfCheck }
    /// A model is still looking at the answer; what is on screen is the rules' first guess.
    private var isProvisional: Bool { grade?.mode == .provisional }
    /// The person has marked a self-check: Continue waits for it. (Not a self-check: nothing to mark.)
    private var hasMarked: Bool { !isSelfCheck || SelfCheck.canContinue(changedByPerson: marked, rulesFoundIdeas: rulesFound) }

    var body: some View {
        ScrollViewReader { proxy in
            QuestionScroll {
                QuestionCard {
                    QuestionHeader(item: item, entry: entry, topic: runner.topicName(entry.topicID))
                    Text(item.prompt)
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)
                    if let grade, let submitted {
                        graded(grade, answer: submitted)
                            .padding(.top, 16)
                            .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if restoredDraft {
                                Label("Kept from before", systemImage: "clock.arrow.circlepath")
                                    .clFont(.footnoteEmphasis)
                                    .foregroundStyle(CLColor.ink3)
                                    .padding(.horizontal, 4)
                                    .transition(.opacity)
                            }
                            editor
                            // Once the day's free Cloud AI checks run low: a quiet count, never a nudge.
                            if let line = SessionCopy.freeChecksLeft(app.ai.freeCloudUsesLeft(for: .grade)) {
                                Text(line)
                                    .clFont(.footnote)
                                    .foregroundStyle(CLColor.ink3)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.top, 16)
                        .id("editor")
                        .transition(.opacity)
                    }
                }
                AccessibilityOnly { secondary }
            }
            .onChange(of: editorFocused) { _, focused in
                guard focused else { return }
                withAnimation(CLMotion.settle) { proxy.scrollTo("editor", anchor: .bottom) }
            }
            .onChange(of: revealed) { _, step in
                // The checklist is what a self-check is for: once everything has shown, bring it (and the rating under it) above the
                // panel that has risen, so it isn't left below the fold.
                guard isSelfCheck, step == revealSteps else { return }
                withAnimation(CLMotion.settle) { proxy.scrollTo("rating", anchor: .bottom) }
            }
        }
        .sessionFooter(feedback: panel, primary: { footer }, secondary: { secondary })
        // "My answer should count" from the sheet: the grader looks again.
        .onChange(of: app.recheckDelivery) { _, delivery in
            guard let delivery, delivery.itemID == item.id, delivery.result == .regrade else { return }
            app.takeRecheckDelivery()
            gradeAgain()
        }
        .onChange(of: text) { _, new in
            guard submitted == nil else { return }
            let typed = !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            runner.hasUnsavedAnswer = typed
            runner.isTypingAnswer = typed
            if !typed { restoredDraft = false }
            scheduleDraft()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { keepDraftNow() }
        }
        // The rating held for Undo moved the session's due load when it was recorded: a label can be a day off until then.
        .onChange(of: runner.pending == nil) { _, recorded in
            if recorded, submitted != nil, runner.current?.id == entry.id {
                intervals = app.intervalPreview(itemID: item.id, sessionID: runner.sessionID)
            }
        }
        .onAppear {
            pickUpRestore()
            // Words kept from before go back into the empty editor, before the first frame (once: a sheet coming and going
            // re-runs this).
            guard !lookedForDraft else { return }
            lookedForDraft = true
            if autoAnswer == nil, text.isEmpty, let draft = app.answerDraft(for: item.id) {
                text = draft
                restoredDraft = true
            }
        }
        .task {
            pickUpRestore()
            guard !restored else { return }
            app.readAloud(question: item)
            if let autoAnswer {
                do { try await nap(450) } catch { return }
                text = autoAnswer
                submit()
                #if DEBUG
                // `CRAMLESS_SESSION_TICK=0,2` (with an own-words answer that is a self-check): toggles the key ideas at those positions
                // once the panel has risen, as taps on their rows would; `none` is a tap on "None of these".
                if let taps = TestHarness.once("CRAMLESS_SESSION_TICK") {
                    for _ in 0..<80 where panel == nil {
                        do { try await nap(100) } catch { return }
                    }
                    do { try await nap(900) } catch { return }
                    for tap in taps.split(separator: ",") {
                        if tap == "none" {
                            chooseNone()
                        } else if let position = Int(tap), ideas.indices.contains(position) {
                            toggle(ideas[position])
                        }
                    }
                }
                #endif
                guard let autoContinue else { return }
                for _ in 0..<80 where panel == nil {
                    do { try await nap(100) } catch { return }
                }
                // Continue waits while a model looks at the answer (`SelfCheck.modelWait` at most).
                for _ in 0..<120 where isProvisional {
                    do { try await nap(100) } catch { return }
                }
                do { try await nap(autoContinue) } catch { return }
                // A film or a screenshot run that Continues on its own marks a self-check nobody has marked as "None of these".
                if isSelfCheck, !hasMarked { chooseNone() }
                commit()
            } else if !UIAccessibility.isVoiceOverRunning {
                do { try await nap(380) } catch { return }
                editorFocused = true
            }
        }
        .onDisappear {
            gradeTask?.cancel()
            revealTask?.cancel()
            keepDraftNow()
        }
    }

    // MARK: Keeping what's typed

    /// Saves the draft after a 400 ms pause in typing.
    private func scheduleDraft() {
        draftTask?.cancel()
        draftTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            keepDraftNow()
        }
    }

    /// Saves the draft now (leaving the screen, the app going to the background). Never once the answer is recorded: its
    /// draft has gone for good.
    private func keepDraftNow() {
        draftTask?.cancel()
        draftTask = nil
        guard !runner.hasRecorded(entry.id) else { return }
        app.keepAnswerDraft(text, for: item.id)
    }

    // MARK: Answering

    private var editor: some View {
        AnswerEditor(text: $text, focused: $editorFocused)
    }

    // MARK: Graded

    private func graded(_ grade: GradeOutcome, answer: String) -> some View {
        let answered = !answer.isEmpty
        let selfCheck = grade.mode == .selfCheck
        let tone: FeedbackTone = selfCheck ? .neutral : FeedbackTone(grade.verdict)
        return VStack(alignment: .leading, spacing: 12) {
            let pill = ScorePill(text: selfCheck ? SessionCopy.selfCheckPill
                                    : SessionCopy.scoreLine(hits: hitCount(grade), total: ideas.count, verdict: grade.verdict),
                                 tone: tone)
                .scaleEffect(revealed > ideas.count ? 1 : 0.7)
                .opacity(revealed > ideas.count ? 1 : 0)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    CLEyebrow(text: "Your answer")
                    Spacer(minLength: 8)
                    pill
                }
                VStack(alignment: .leading, spacing: 6) {
                    CLEyebrow(text: "Your answer")
                    pill
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            HighlightedText(text: answered ? answer : "No answer yet", marks: answered ? grade.highlightMarks : [],
                            revealed: swept, style: .body, color: answered ? CLColor.ink : CLColor.ink3)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel(Text(answered ? "Your answer: \(answer)" : "No answer"))
                .accessibilityValue(Text(markedSummary(grade, answer: answer)))
            if selfCheck {
                selfCheckCard
            } else if !ideas.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                        ideaRow(idea, hit: grade.hitIdeaIDs.contains(idea.id))
                            .opacity(revealed > index ? 1 : 0)
                            .offset(y: revealed > index ? 0 : 10)
                    }
                }
            }
            if let panel {
                AccessibilityOnly { FeedbackDetails(feedback: panel) }
            }
            if let suggestion = grade.suggestion {
                SuggestionBanner(suggestion: suggestion, selfMarked: selfCheck, inSession: true)
                    .opacity(revealed > ideas.count ? 1 : 0)
                    .transition(.opacity)
            }
            if let secondLook {
                Label(secondLook, systemImage: "checkmark.seal")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .transition(.opacity)
            }
            RatingAdjuster(auto: autoRating(grade), override: $override, intervals: intervals)
                .padding(.bottom, -10)
                // A self-check says how it counts once the person has marked it, not before.
                .opacity(revealed > ideas.count + 1 && hasMarked ? 1 : 0)
                .accessibilityHidden(!hasMarked)
                .id("rating")
        }
    }

    private func ideaRow(_ idea: KeyIdea, hit: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: hit ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(hit ? CLColor.mintInk : CLColor.roseInk)
                .accessibilityHidden(true)
            Text(hit ? idea.label : "Missing: \(SessionCopy.lowerFirst(idea.label))")
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(hit ? CLColor.ink : CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hit ? "Hit: \(idea.label)" : "Missing: \(idea.label)")
    }

    // MARK: Marking it yourself

    /// The model answer in a plain card with its source, then the key ideas as a checklist: "Tick what you had".
    private var selfCheckCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                CLEyebrow(text: "The answer")
                Text(item.answer)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let ref = item.sourceRef { SourceButton(ref: ref) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, item.sourceRef == nil ? 14 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain)
            .opacity(swept ? 1 : 0)
            VStack(alignment: .leading, spacing: 0) {
                CLEyebrow(text: "Tick what you had")
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                    checkRow(idea)
                        .opacity(revealed > index ? 1 : 0)
                        .offset(y: revealed > index ? 0 : 10)
                }
                noneRow
                    .opacity(revealed >= ideas.count ? 1 : 0)
                    .offset(y: revealed >= ideas.count ? 0 : 10)
            }
        }
    }

    /// "None of these": the person had none of the key ideas. Answering that is a mark like any other, so it is a row of its own: an
    /// answer nobody has marked is never logged as one.
    private var noneRow: some View {
        let isOn = marked && ticked.isEmpty
        return Button(action: chooseNone) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? CLColor.mintInk : CLColor.ink3)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text("None of these")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("None of these")
        .accessibilityValue(isOn ? "Chosen" : "Not chosen")
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint("Double-tap if you had none of the key ideas")
    }

    /// One key idea of the checklist; a tap ticks or unticks it. The ones the rules found in the person's own words start ticked.
    private func checkRow(_ idea: KeyIdea) -> some View {
        let isOn = ticked.contains(idea.id)
        return Button { toggle(idea) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? CLColor.mintInk : CLColor.ink3)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(idea.label)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(idea.label)
        .accessibilityValue(isOn ? "Ticked" : "Not ticked")
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint("Double-tap to change")
    }

    private func toggle(_ idea: KeyIdea) {
        CLHaptics.select()
        withAnimation(CLMotion.snap) {
            if ticked.contains(idea.id) { ticked.remove(idea.id) } else { ticked.insert(idea.id) }
            marked = true
        }
        // The ticks decide the rating again, unless the person picks one themselves afterwards.
        override = nil
    }

    /// The person had none of the key ideas: nothing is ticked, and that is their mark.
    private func chooseNone() {
        CLHaptics.select()
        withAnimation(CLMotion.snap) {
            ticked.removeAll()
            marked = true
        }
        override = nil
    }

    /// The answer is the person's to mark: the ideas the rules found start ticked, the rest unticked; no verdict is colouring the
    /// progress bar or counting toward a run.
    private func startMarking(_ outcome: GradeOutcome) {
        ticked = SelfCheck.startingTicks(of: outcome, ideas: ideas)
        rulesFound = !ticked.isEmpty
        marked = false
        override = nil
        saved = false
        run = 0
        runner.setProvisional(nil)
    }

    /// A model's verdict is on screen: whether it saves a fading memory and the run it makes.
    private func settleVerdict(_ outcome: GradeOutcome) {
        let verdict = SessionRunner.Outcome(outcome.verdict)
        saved = verdict == .right && runner.wouldSave(item)
        run = verdict == .right ? runner.shownRun(adding: .right, kind: item.kind) : 0
    }

    // MARK: Rating and panel

    private func hitCount(_ grade: GradeOutcome) -> Int {
        ideas.filter { grade.hitIdeaIDs.contains($0.id) }.count
    }

    private func autoRating(_ grade: GradeOutcome) -> Rating {
        let score = grade.mode == .selfCheck ? SelfCheck.score(ticked: ticked, of: ideas) : grade.score
        return AppModel.rating(forScore: score, kind: item.kind, durationMs: durationMs)
    }

    /// The answer panel: it rises once the key ideas have shown (the step where the feedback used to appear), and a
    /// refined grade updates it in place. A self-check has no verdict to colour or word it: it is neutral until the person has marked.
    private var panel: AnswerFeedback? {
        guard let grade, let submitted, revealed > ideas.count else { return nil }
        if grade.mode == .selfCheck {
            return AnswerFeedback(tone: .neutral, headline: SessionCopy.selfCheckHeadline, cap: .answerShown,
                                  provenance: provenance(grade), working: refining || regrading)
        }
        let outcome = SessionRunner.Outcome(grade.verdict)
        return AnswerFeedback(tone: FeedbackTone(grade.verdict),
                              headline: SessionCopy.headline(outcome, answered: !submitted.isEmpty, saved: saved),
                              cap: .verdict(outcome, answered: !submitted.isEmpty, saved: saved, combo: run),
                              message: grade.feedback, fix: grade.fix, note: grade.spellingNote, source: item.sourceRef,
                              provenance: provenance(grade), working: refining || regrading,
                              combo: run)
    }

    private func provenance(_ grade: GradeOutcome) -> String {
        if regrading { return "Taking a second look…" }
        if refining { return "Double-checking…" }
        if grade.mode == .selfCheck { return marked ? SessionCopy.markedByYou : SessionCopy.selfCheckLine(grade.selfCheckReason) }
        return SessionCopy.gradedBy(grade.gradedBy)
    }

    /// The marks as words, for VoiceOver: "Highlighted: grow, repair tissue, identical cells".
    private func markedSummary(_ grade: GradeOutcome, answer: String) -> String {
        let chars = Array(answer)
        let quotes = grade.highlightMarks.compactMap { mark -> String? in
            let lower = max(0, min(chars.count, mark.range.lowerBound))
            let upper = max(lower, min(chars.count, mark.range.upperBound))
            return upper > lower ? String(chars[lower..<upper]) : nil
        }
        return quotes.isEmpty ? "Nothing highlighted" : "Highlighted: " + quotes.joined(separator: ", ")
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        if let panel {
            if isProvisional {
                // A model is still looking at the answer: what is recorded is its grade, not the rules' first guess. (The router lets
                // it go after `SelfCheck.modelWait`.)
                Button("Double-checking…") {}
                    .buttonStyle(.cl(.soft))
                    .disabled(true)
            } else {
                Button("Continue", action: commit)
                    .buttonStyle(.cl(.verdict(panel.tone)))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasMarked)
                    .accessibilityHint(hasMarked ? LocalizedStringKey("") : LocalizedStringKey("Tick what you had, or choose None of these, first."))
            }
        } else if grade != nil {
            // The highlighter is still sweeping: the panel rises when it's done.
            Button("Checking…") {}
                .buttonStyle(.cl(.soft))
                .disabled(true)
        } else {
            Button("Check my answer", action: submit)
                .buttonStyle(.cl(.primary))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// A model could grade this self-check now (Cloud AI was allowed since, or the connection is back).
    private var canGradeAgain: Bool {
        guard let submitted else { return false }
        let subject = GradeSubject(kind: item.kind, prompt: item.prompt, modelAnswer: item.answer, keyIdeas: item.keyIdeas)
        return app.ai.canGradeAgain(subject, answer: .text(submitted))
    }

    @ViewBuilder private var secondary: some View {
        if let grade {
            // A self-check has a mistake to explain only once the person has left an idea unticked.
            if grade.mode == .selfCheck ? ticked.count < ideas.count : grade.verdict != .correct {
                Button {
                    CLHaptics.tap()
                    app.router.present(.explain(itemID: item.id, given: submitted ?? ""))
                } label: {
                    Label("Explain my mistake", systemImage: "bubble.left")
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
            if grade.mode == .selfCheck ? canGradeAgain : (grade.needsSecondLook && grade.mode != .provisional) {
                Button(action: gradeAgain) {
                    Label(regrading ? "Checking…" : "Grade again", systemImage: "flag")
                }
                .buttonStyle(.cl(.soft, size: .medium))
                .disabled(regrading)
            }
            if runner.offersLooksWrong { LooksWrongButton(item: item, given: submitted) }
        } else {
            Button("I don't know yet") {
                text = ""
                submit()
            }
            .buttonStyle(.cl(.ghost, size: .medium))
        }
    }

    // MARK: Actions

    private func submit() {
        guard submitted == nil else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kept until the answer is recorded: a close before Continue still has the words.
        keepDraftNow()
        runner.isTypingAnswer = false
        durationMs = runner.elapsedMs()
        editorFocused = false
        CLHaptics.commit()
        app.stopReadingAloud()
        intervals = app.intervalPreview(itemID: item.id, sessionID: runner.sessionID)
        let stream = app.ai.grade(app.gradeSubject(for: item), answer: .text(answer))
        gradeTask = Task { @MainActor in
            var count = 0
            var hint: Task<Void, Never>?
            for await outcome in stream {
                count += 1
                if count == 1 {
                    land(outcome, answer: answer)
                    // "Double-checking…" shows only while a refinement is still under way after a beat.
                    if outcome.mode == .provisional {
                        hint = Task { @MainActor in
                            try? await nap(300)
                            guard !Task.isCancelled else { return }
                            withAnimation(CLMotion.fade) { refining = true }
                        }
                    }
                } else {
                    hint?.cancel()
                    refine(to: outcome)
                }
            }
            hint?.cancel()
            withAnimation(CLMotion.fade) { refining = false }
        }
    }

    /// The sounds the panel plays as it rises, from the grade it shows at that moment. A self-check plays the answer-shown cue,
    /// never a verdict's: nothing is judged until the person has marked it.
    private func cues(for answer: String) -> [CLCue] {
        guard let grade else { return [] }
        if grade.mode == .selfCheck { return [.revealed] }
        return runner.cues(for: SessionRunner.Outcome(grade.verdict), item: item, answered: !answer.isEmpty)
    }

    /// The panel's sounds, and a save also flares in the sky.
    private func sound(_ cues: [CLCue]) {
        CLFeel.play(cues)
        if saved, !isSelfCheck { runner.flareSave(of: item) }
    }

    /// The instant grade arrives: the answer stays where it was typed, the marks sweep in (a tick as each key
    /// idea lands), then the ideas, the feedback and the rating rise in turn.
    private func land(_ outcome: GradeOutcome, answer: String) {
        withAnimation(CLMotion.settle) {
            submitted = answer
            grade = outcome
        }
        if outcome.mode == .selfCheck {
            startMarking(outcome)
        } else {
            settleVerdict(outcome)
            runner.setProvisional(SessionRunner.Outcome(outcome.verdict))
        }
        announce(outcome, refined: false)
        revealTask = Task { @MainActor in
            if reduceMotion {
                swept = true
                revealed = revealSteps
                sound(cues(for: answer))
                return
            }
            do {
                try await nap(140)
                swept = true
                let marks = answer.isEmpty ? 0 : outcome.highlightMarks.count
                var elapsed = 0.0
                for index in 0..<marks {
                    let at = SweepTiming.landing(of: index, count: marks)
                    try await Task.sleep(for: .milliseconds(Int(max(0, at - elapsed) * 1000)))
                    elapsed = at
                    CLHaptics.tick()
                }
                try await nap(marks > 0 ? 220 : 120)
                for step in 1...revealSteps {
                    withAnimation(CLMotion.settle) { revealed = step }
                    // The panel rises at this step: its sound goes with it, for whatever the grade is by then.
                    if step == ideas.count + 1 { sound(cues(for: answer)) }
                    try await nap(step <= ideas.count ? 120 : 90)
                }
            } catch {
                swept = true
                revealed = revealSteps
            }
        }
    }

    /// A refined grade replaces the instant one in place: same layout, a cross-fade, no second sweep. If no model answered after
    /// all, the answer becomes the person's to mark.
    private func refine(to outcome: GradeOutcome) {
        let previous = grade
        withAnimation(CLMotion.fade) {
            grade = outcome
            refining = false
        }
        if outcome.mode == .selfCheck {
            startMarking(outcome)
            announce(outcome, refined: true)
            return
        }
        runner.setProvisional(SessionRunner.Outcome(outcome.verdict))
        if previous?.verdict != outcome.verdict || Set(previous?.hitIdeaIDs ?? []) != Set(outcome.hitIdeaIDs) {
            override = nil
            // The run and the save the panel shows are those of the verdict that stands now, not of the rules' first guess.
            settleVerdict(outcome)
            announce(outcome, refined: true)
        }
    }

    private func gradeAgain() {
        guard let submitted, let previous = grade, !regrading else { return }
        withAnimation(CLMotion.fade) {
            regrading = true
            secondLook = nil
        }
        Task { @MainActor in
            let outcome = await app.ai.gradeAgain(app.gradeSubject(for: item), answer: .text(submitted), previous: previous)
            if outcome.mode == .selfCheck {
                // Still no model to grade it (the reason may have changed): the person goes on marking, their ticks kept.
                withAnimation(CLMotion.fade) {
                    grade = outcome
                    regrading = false
                }
                if previous.mode != .selfCheck { startMarking(outcome); announce(outcome, refined: true) }
                return
            }
            // A self-check has no grade to agree with: the model's is simply the grade now.
            let wasSelfCheck = previous.mode == .selfCheck
            let agrees = wasSelfCheck ? false : (outcome.agreesWithPrevious ?? true)
            withAnimation(CLMotion.fade) {
                grade = outcome
                regrading = false
                secondLook = wasSelfCheck ? nil : (agrees ? "A second look agrees with this grade." : "Updated after a second look.")
            }
            if !agrees { override = nil }
            if wasSelfCheck { settleVerdict(outcome) }
            runner.setProvisional(SessionRunner.Outcome(outcome.verdict))
            if wasSelfCheck {
                announce(outcome, refined: false)
            } else {
                AccessibilityNotification.Announcement(secondLook ?? "").post()
            }
        }
    }

    private func commit() {
        // Not while a model is still looking at the answer (the rules' first guess is not what is recorded), and not before a
        // self-check has been marked.
        guard let grade, grade.mode != .provisional, hasMarked else { return }
        gradeTask?.cancel()
        revealTask?.cancel()
        if grade.mode == .selfCheck {
            commitMarks()
            return
        }
        let rating = override ?? autoRating(grade)
        // "Counts as" is the person's own call, so it can be taken back; a grade as it stands already waited for Continue.
        runner.record(rating: rating, score: grade.score, answer: submitted,
                      gradedBy: override == nil ? grade.gradedBy.rawValue : "person", durationMs: durationMs,
                      outcome: override.map(SessionRunner.Outcome.init(rating:)) ?? SessionRunner.Outcome(grade.verdict),
                      undo: override == nil ? nil : restoreState(grade))
        CLHaptics.select()
        app.stopReadingAloud()
        withAnimation(CLMotion.settle) { runner.advance() }
    }

    /// Records what the person marked, as marked by themselves ("self"): the rating the ticks come to (ticked over all the key ideas)
    /// unless the person picked another, and a score that agrees with the rating it ends up as, so the log never says Good over a
    /// score that says wrong (`Grading.score(standingFor:near:)`: the ticks' own score when it is in the rating's band). Like a
    /// flashcard's rating it sounds the same whatever it is; it counts in a run like any answer, by its rating.
    private func commitMarks() {
        let ticks = SelfCheck.score(ticked: ticked, of: ideas)
        let rating = override ?? AppModel.rating(forScore: ticks, kind: item.kind, durationMs: durationMs)
        let score = Grading.score(standingFor: rating, near: ticks)
        CLFeel.play(.rated)
        guard let grade else { return }
        let review = runner.record(rating: rating, score: score, answer: submitted, gradedBy: "self", durationMs: durationMs,
                                   outcome: SessionRunner.Outcome(rating: rating), undo: restoreState(grade))
        if review?.isSave == true { runner.flareSave(of: item) }
        app.stopReadingAloud()
        withAnimation(CLMotion.settle) { runner.advance() }
    }

    /// Everything the panel showed, for an Undo to bring back.
    private func restoreState(_ grade: GradeOutcome) -> SessionRunner.AnswerRestore {
        .ownWords(.init(submitted: submitted ?? "", grade: grade, durationMs: durationMs, intervals: intervals, ticked: ticked,
                        marked: marked, rulesFound: rulesFound, override: override, secondLook: secondLook, run: run, saved: saved))
    }

    /// The rating was undone: the panel is back as it stood, with no new grade and no sounds.
    private func pickUpRestore() {
        guard !restored, case .ownWords(let state)? = runner.takeRestore(for: entry.id) else { return }
        restored = true
        lookedForDraft = true
        submitted = state.submitted
        text = state.submitted
        grade = state.grade
        durationMs = state.durationMs
        intervals = state.intervals
        ticked = state.ticked
        marked = state.marked
        rulesFound = state.rulesFound
        override = state.override
        secondLook = state.secondLook
        run = state.run
        saved = state.saved
        swept = true
        revealed = revealSteps
        if state.grade.mode == .selfCheck {
            runner.hasUnsavedAnswer = true
        } else {
            runner.setProvisional(SessionRunner.Outcome(state.grade.verdict))
        }
    }

    private func announce(_ outcome: GradeOutcome, refined: Bool) {
        if outcome.mode == .selfCheck {
            AccessibilityNotification.Announcement(SessionCopy.selfCheckAnnouncement(ticked: ticked.count, total: ideas.count)).post()
            return
        }
        var parts: [String] = []
        if refined { parts.append("Updated grade.") }
        parts.append(SessionCopy.scoreLine(hits: hitCount(outcome), total: ideas.count, verdict: outcome.verdict) + ".")
        let hits = ideas.filter { outcome.hitIdeaIDs.contains($0.id) }.map(\.label)
        if !hits.isEmpty { parts.append("You hit: " + hits.joined(separator: ", ") + ".") }
        if !outcome.missing.isEmpty { parts.append("Missing: " + outcome.missing.map(\.label).joined(separator: ", ") + ".") }
        if !outcome.fix.isEmpty { parts.append(outcome.fix) }
        AccessibilityNotification.Announcement(parts.joined(separator: " ")).post()
    }
}
