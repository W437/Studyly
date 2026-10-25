import SwiftUI
import UIKit

/// "In your own words" and "Apply it": the person types an answer and submits. The offline grade lands at once:
/// the highlighter sweeps the key ideas found word for word in their own answer (a tick as each one lands), the
/// missed ideas are named, the feedback and the one-line fix show. A refined grade (this iPhone's model or Cloud
/// AI) updates it in place with a quiet cross-fade. "Grade again" appears when the grader isn't sure. The rating
/// comes from the score, and the person can change it before moving on.
///
/// DEBUG: `CRAMLESS_SESSION_ANSWER=<text>` submits that answer as soon as the question shows (the session's
/// `CRAMLESS_SESSION_STATE=graded` supplies one of its own).
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
    @FocusState private var editorFocused: Bool

    @State private var text = ""
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

    private var ideas: [KeyIdea] { item.keyIdeas }
    /// Steps of the reveal after the sweep: each idea row, then the feedback, then the rating line.
    private var revealSteps: Int { ideas.count + 2 }

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
                        editor
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
        }
        .sessionFooter(feedback: panel, primary: { footer }, secondary: { secondary })
        .onChange(of: text) { _, new in
            guard submitted == nil else { return }
            runner.hasUnsavedAnswer = !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .task {
            app.readAloud(question: item)
            if let autoAnswer {
                do { try await nap(450) } catch { return }
                text = autoAnswer
                submit()
                guard let autoContinue else { return }
                for _ in 0..<80 where panel == nil {
                    do { try await nap(100) } catch { return }
                }
                do { try await nap(autoContinue) } catch { return }
                commit()
            } else if !UIAccessibility.isVoiceOverRunning {
                do { try await nap(380) } catch { return }
                editorFocused = true
            }
        }
        .onDisappear {
            gradeTask?.cancel()
            revealTask?.cancel()
        }
    }

    // MARK: Answering

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Type your answer…")
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .focused($editorFocused)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 116)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Your answer")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(editorFocused ? CLColor.sky : CLColor.surface3, lineWidth: 2))
        .animation(CLMotion.snap, value: editorFocused)
    }

    // MARK: Graded

    private func graded(_ grade: GradeOutcome, answer: String) -> some View {
        let answered = !answer.isEmpty
        let tone = FeedbackTone(grade.verdict)
        return VStack(alignment: .leading, spacing: 12) {
            let pill = ScorePill(text: SessionCopy.scoreLine(hits: hitCount(grade), total: ideas.count, verdict: grade.verdict),
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
            if !ideas.isEmpty {
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
                SuggestionBanner(suggestion: suggestion)
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
                .opacity(revealed > ideas.count + 1 ? 1 : 0)
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

    private func hitCount(_ grade: GradeOutcome) -> Int {
        ideas.filter { grade.hitIdeaIDs.contains($0.id) }.count
    }

    private func autoRating(_ grade: GradeOutcome) -> Rating {
        AppModel.rating(forScore: grade.score, kind: item.kind, durationMs: durationMs)
    }

    /// The answer panel: it rises once the key ideas have shown (the step where the feedback used to appear), and a
    /// refined grade updates it in place.
    private var panel: AnswerFeedback? {
        guard let grade, let submitted, revealed > ideas.count else { return nil }
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
            Button("Continue", action: commit)
                .buttonStyle(.cl(.verdict(panel.tone)))
                .keyboardShortcut(.defaultAction)
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

    @ViewBuilder private var secondary: some View {
        if let grade {
            if grade.verdict != .correct {
                Button {
                    CLHaptics.tap()
                    app.router.present(.explain(itemID: item.id, given: submitted ?? ""))
                } label: {
                    Label("Explain my mistake", systemImage: "bubble.left")
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
            if grade.needsSecondLook {
                Button(action: gradeAgain) {
                    Label(regrading ? "Checking…" : "Grade again", systemImage: "flag")
                }
                .buttonStyle(.cl(.soft, size: .medium))
                .disabled(regrading)
            }
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
                    hint = Task { @MainActor in
                        try? await nap(300)
                        guard !Task.isCancelled else { return }
                        withAnimation(CLMotion.fade) { refining = true }
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

    /// The panel's verdict sounds, and a save also flares in the sky.
    private func sound(_ cues: [CLCue]) {
        CLFeel.play(cues)
        if saved { runner.flareSave(of: item) }
    }

    /// The instant grade arrives: the answer stays where it was typed, the marks sweep in (a tick as each key
    /// idea lands), then the ideas, the feedback and the rating rise in turn.
    private func land(_ outcome: GradeOutcome, answer: String) {
        let verdict = SessionRunner.Outcome(outcome.verdict)
        saved = verdict == .right && runner.wouldSave(item)
        run = verdict == .right ? runner.combo(adding: .right, kind: item.kind) : 0
        let cues = runner.cues(for: verdict, item: item, answered: !answer.isEmpty)
        withAnimation(CLMotion.settle) {
            submitted = answer
            grade = outcome
        }
        runner.setProvisional(verdict)
        announce(outcome, refined: false)
        revealTask = Task { @MainActor in
            if reduceMotion {
                swept = true
                revealed = revealSteps
                sound(cues)
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
                    // The panel rises at this step: its verdict sounds with it.
                    if step == ideas.count + 1 { sound(cues) }
                    try await nap(step <= ideas.count ? 120 : 90)
                }
            } catch {
                swept = true
                revealed = revealSteps
            }
        }
    }

    /// A refined grade replaces the instant one in place: same layout, a cross-fade, no second sweep.
    private func refine(to outcome: GradeOutcome) {
        let previous = grade
        withAnimation(CLMotion.fade) {
            grade = outcome
            refining = false
        }
        runner.setProvisional(SessionRunner.Outcome(outcome.verdict))
        if previous?.verdict != outcome.verdict || Set(previous?.hitIdeaIDs ?? []) != Set(outcome.hitIdeaIDs) {
            override = nil
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
            let agrees = outcome.agreesWithPrevious ?? true
            withAnimation(CLMotion.fade) {
                grade = outcome
                regrading = false
                secondLook = agrees ? "A second look agrees with this grade." : "Updated after a second look."
            }
            if !agrees { override = nil }
            runner.setProvisional(SessionRunner.Outcome(outcome.verdict))
            AccessibilityNotification.Announcement(secondLook ?? "").post()
        }
    }

    private func commit() {
        guard let grade else { return }
        gradeTask?.cancel()
        revealTask?.cancel()
        let rating = override ?? autoRating(grade)
        runner.record(rating: rating, score: grade.score, answer: submitted,
                      gradedBy: override == nil ? grade.gradedBy.rawValue : "person", durationMs: durationMs,
                      outcome: override.map(SessionRunner.Outcome.init(rating:)) ?? SessionRunner.Outcome(grade.verdict))
        CLHaptics.select()
        app.stopReadingAloud()
        withAnimation(CLMotion.settle) { runner.advance() }
    }

    private func announce(_ outcome: GradeOutcome, refined: Bool) {
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
