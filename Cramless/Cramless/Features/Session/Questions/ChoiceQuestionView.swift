import SwiftUI

/// Multiple choice: lettered options (A–D, also on a hardware keyboard), shuffled per day. A tap answers: the right
/// option turns mint, a wrong pick rose, the rest step back, and the why shows with the source. The chosen option's
/// text is recorded as the answer, so swapped answers can be spotted later.
struct ChoiceQuestionView: View {
    let runner: SessionRunner
    let entry: SessionEntry
    let item: StudyItem
    /// DEBUG: answer on appear with this option (an original index; `-2` picks a wrong one).
    var autoPick: Int? = nil
    /// DEBUG: press Continue this many milliseconds after the panel shows (session autoplay).
    var autoContinue: Int? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var order: [Int] = []
    /// The original index picked; -1 for "I don't know".
    @State private var picked: Int?
    @State private var grade: GradeOutcome?
    @State private var saved = false
    /// The run this answer makes, fixed when the verdict lands (Continue records it, and the panel must not count
    /// it twice while it leaves).
    @State private var run = 0
    @State private var durationMs = 0
    @Environment(\.clReduceMotion) private var reduceMotion

    private var choices: [Choice] { item.choices }
    private var correctIndex: Int? { choices.firstIndex(where: \.correct) }

    var body: some View {
        QuestionScroll {
            QuestionCard {
                QuestionHeader(item: item, entry: entry, topic: runner.topicName(entry.topicID))
                Text(item.prompt)
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 10) {
                    ForEach(Array(order.enumerated()), id: \.element) { position, index in
                        option(index, letter: ChoiceOrder.letters[min(position, ChoiceOrder.letters.count - 1)])
                    }
                }
                .padding(.top, 18)
                if let panel {
                    AccessibilityOnly { FeedbackDetails(feedback: panel).padding(.top, 10) }
                }
            }
            AccessibilityOnly { secondary }
        }
        .sessionFooter(feedback: panel, primary: { footer }, secondary: { secondary })
        .onAppear {
            if order.isEmpty {
                order = ChoiceOrder.order(texts: choices.map(\.text), itemID: item.id,
                                          day: app.calendar.dayNumber(for: app.now))
            }
        }
        .task {
            app.readAloud(question: item)
            guard let autoPick else { return }
            do { try await nap(500) } catch { return }
            if autoPick == -2 {
                pick(choices.indices.first { !choices[$0].correct } ?? 0)
            } else if autoPick == -3 {
                pick(-1)
            } else {
                pick(autoPick >= 0 ? autoPick : (correctIndex ?? 0))
            }
            guard let autoContinue else { return }
            do { try await nap(autoContinue) } catch { return }
            commit()
        }
    }

    // MARK: Options

    private enum OptionState { case idle, right, wrong, dimmed }

    private func state(_ index: Int) -> OptionState {
        guard picked != nil else { return .idle }
        if index == correctIndex { return .right }
        if index == picked { return .wrong }
        return .dimmed
    }

    private func option(_ index: Int, letter: String) -> some View {
        let state = state(index)
        let text = choices[index].text
        let rippleAmplitude = (state == .right ? FeedbackTone.mint : FeedbackTone.rose).rippleAmplitude
        return Button { pick(index) } label: {
            optionTile(letter: letter, text: text, state: state)
                // The picked option ripples as its verdict lands.
                .clRipple(trigger: index == picked ? 1 : 0, amplitude: rippleAmplitude)
                .opacity(state == .dimmed ? 0.45 : 1)
                .contentShape(RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
        }
        .buttonStyle(.pressable(depth: 4, edge: edge(state)))
        .allowsHitTesting(picked == nil)
        .keyboardShortcut(KeyEquivalent(Character(letter.lowercased())), modifiers: [])
        .accessibilityLabel("\(letter). \(text)")
        .accessibilityValue(accessibilityValue(state))
        .accessibilityAddTraits(state == .wrong ? .isSelected : [])
    }

    private func optionTile(letter: String, text: String, state: OptionState) -> some View {
        let marked = state == .right || state == .wrong
        return HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            Text(letter)
                .clFont(.number(14, .bold))
                .foregroundStyle(marked ? CLColor.onFill : CLColor.ink2)
                .frame(width: 28, height: 28)
                .background(keyFill(state), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(text)
                .clFont(.bodyEmphasis)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if marked {
                Image(systemName: state == .right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(state == .right ? CLColor.mintInk : CLColor.roseInk)
                    // Draws itself on; symbol effects follow the system's Reduce Motion by themselves.
                    .transition(.symbolEffect(.drawOn))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 56)
        .background(fill(state), in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous)
            .strokeBorder(border(state), lineWidth: 2))
    }

    private func keyFill(_ state: OptionState) -> Color {
        switch state {
        case .right: CLColor.mint
        case .wrong: CLColor.rose
        default: CLColor.surface
        }
    }

    private func fill(_ state: OptionState) -> Color {
        switch state {
        case .right: CLColor.mintSoft
        case .wrong: CLColor.roseSoft
        default: CLColor.surface2
        }
    }

    /// The edge each option stands on: it sinks onto it when pressed.
    private func edge(_ state: OptionState) -> Color {
        switch state {
        case .right: CLColor.mintEdge
        case .wrong: CLColor.roseEdge
        default: CLColor.surfaceEdge
        }
    }

    private func border(_ state: OptionState) -> Color {
        switch state {
        case .right: CLColor.mint
        case .wrong: CLColor.rose
        default: .clear
        }
    }

    private func accessibilityValue(_ state: OptionState) -> String {
        switch state {
        case .idle, .dimmed: ""
        case .right: picked == correctIndex ? "Your answer. Correct." : "The correct answer."
        case .wrong: "Your answer. Not correct."
        }
    }

    // MARK: Feedback

    /// The answer panel, once an option is picked.
    private var panel: AnswerFeedback? {
        guard let grade else { return nil }
        let right = grade.isCorrect
        let outcome: SessionRunner.Outcome = right ? .right : .wrong
        let chosen = picked.flatMap { choices.indices.contains($0) ? choices[$0] : nil }
        let answer = correctIndex.map { choices[$0] }
        let message: String
        if right {
            message = chosen?.why ?? (item.explanation.isEmpty ? String(localized: "That's the one.") : item.explanation)
        } else {
            let why = chosen?.why ?? answer?.why ?? item.explanation
            message = [String(localized: "It's \(answer?.text ?? item.answer)."), why].filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return AnswerFeedback(tone: right ? .mint : .rose,
                              headline: SessionCopy.headline(outcome, answered: picked != -1, saved: saved),
                              cap: .verdict(outcome, answered: picked != -1, saved: saved, combo: run),
                              message: message, source: item.sourceRef,
                              combo: run)
    }

    @ViewBuilder private var footer: some View {
        if let panel {
            Button("Continue", action: commit)
                .buttonStyle(.cl(.verdict(panel.tone)))
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var secondary: some View {
        if let grade {
            if !grade.isCorrect {
                Button {
                    CLHaptics.tap()
                    app.router.present(.explain(itemID: item.id, given: pickedText ?? ""))
                } label: {
                    Label("Explain my mistake", systemImage: "bubble.left")
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
        } else {
            Button("I don't know") { pick(-1) }
                .buttonStyle(.cl(.ghost, size: .medium))
        }
    }

    private var pickedText: String? {
        guard let picked, choices.indices.contains(picked) else { return nil }
        return choices[picked].text
    }

    // MARK: Actions

    private func pick(_ index: Int) {
        guard picked == nil else { return }
        durationMs = runner.elapsedMs()
        app.stopReadingAloud()
        let outcome = app.ai.instantGrade(app.gradeSubject(for: item), answer: .choice(index))
        let verdict: SessionRunner.Outcome = outcome.isCorrect ? .right : .wrong
        saved = outcome.isCorrect && runner.wouldSave(item)
        run = outcome.isCorrect ? runner.combo(adding: .right, kind: item.kind) : 0
        CLFeel.play(runner.cues(for: verdict, item: item, answered: index >= 0))
        if saved { runner.flareSave(of: item) }
        withAnimation(CLMotion.snap) {
            picked = index
            grade = outcome
        }
        runner.setProvisional(verdict)
        let answerText = correctIndex.map { choices[$0].text } ?? item.answer
        AccessibilityNotification.Announcement(outcome.isCorrect ? "Right." : "Not quite. It's \(answerText).").post()
    }

    private func commit() {
        guard let grade else { return }
        let score: Double = grade.isCorrect ? 1 : 0
        let rating = AppModel.rating(forScore: score, kind: .mcq, durationMs: durationMs)
        runner.record(rating: rating, score: score, answer: pickedText, gradedBy: grade.gradedBy.rawValue,
                      durationMs: durationMs, outcome: grade.isCorrect ? .right : .wrong)
        CLHaptics.select()
        withAnimation(CLMotion.settle) { runner.advance() }
    }
}
