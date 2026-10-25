import SwiftUI
import UIKit

/// Fill in the blank: the sentence wraps like text with an inline field for each blank. Check grades every blank
/// against its answer and the item's alternates (one typo forgiven, and pointed out). A hint shows the first
/// letters; a right answer after a hint counts as Hard.
struct ClozeQuestionView: View {
    let runner: SessionRunner
    let entry: SessionEntry
    let item: StudyItem
    /// DEBUG: fill the blanks on appear and check (`"right"`, `"wrong"`, or the text to type).
    var autoFill: String? = nil
    /// DEBUG: press Continue this many milliseconds after the panel shows (session autoplay).
    var autoContinue: Int? = nil

    @Environment(AppModel.self) private var app
    @FocusState private var focused: Int?
    @ScaledMetric(relativeTo: .title3) private var letterWidth: CGFloat = 12

    @State private var answers: [String] = []
    @State private var grade: GradeOutcome?
    @State private var saved = false
    /// The run this answer makes, fixed when the verdict lands.
    @State private var run = 0
    @State private var hinted = false
    @State private var durationMs = 0

    private var spec: ClozeSpec { item.cloze ?? ClozeSpec(text: "{{\(item.answer)}}") }
    private var expected: [String] { spec.answers }
    private var tokens: [ClozeToken] { ClozeToken.parse(spec.text) }

    var body: some View {
        QuestionScroll {
            QuestionCard {
                QuestionHeader(item: item, entry: entry, topic: runner.topicName(entry.topicID))
                if !item.prompt.isEmpty, item.prompt != spec.text {
                    Text(item.prompt)
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink2)
                        .padding(.top, 8)
                }
                CLFlow(spacing: 6, lineSpacing: 4) {
                    ForEach(tokens) { token in
                        tokenView(token)
                    }
                }
                .padding(.top, 14)
                .accessibilityElement(children: .contain)
                if let panel {
                    AccessibilityOnly { FeedbackDetails(feedback: panel).padding(.top, 10) }
                }
            }
            AccessibilityOnly { secondary }
        }
        .sessionFooter(feedback: panel, primary: { footer }, secondary: { secondary })
        .onAppear {
            if answers.count != expected.count { answers = Array(repeating: "", count: expected.count) }
        }
        .onChange(of: answers) { _, new in
            guard grade == nil else { return }
            runner.hasUnsavedAnswer = new.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        .task {
            app.readAloud(question: item)
            if let autoFill {
                do { try await nap(450) } catch { return }
                switch autoFill {
                case "right": answers = expected
                case "hinted":
                    hinted = true
                    answers = expected
                case "wrong": answers = expected.map { _ in "anaphase" }
                default: answers = expected.map { _ in autoFill }
                }
                check()
                guard let autoContinue else { return }
                do { try await nap(autoContinue) } catch { return }
                commit()
            } else if !UIAccessibility.isVoiceOverRunning {
                do { try await nap(380) } catch { return }
                focused = 0
            }
        }
    }

    // MARK: The sentence

    @ViewBuilder private func tokenView(_ token: ClozeToken) -> some View {
        switch token.kind {
        case .word(let word):
            Text(word)
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
                .frame(minHeight: 32)
        case .blank(let index, let trailing):
            HStack(alignment: .center, spacing: 1) {
                blank(index)
                if !trailing.isEmpty {
                    Text(trailing).clFont(.title3).foregroundStyle(CLColor.ink)
                }
            }
            .frame(minHeight: 32)
        }
    }

    @ViewBuilder private func blank(_ index: Int) -> some View {
        let answer = expected.indices.contains(index) ? expected[index] : ""
        if let grade {
            let right = grade.blankResults.indices.contains(index) ? grade.blankResults[index] : grade.isCorrect
            let given = answers.indices.contains(index) ? answers[index].trimmingCharacters(in: .whitespaces) : ""
            Group {
                if right {
                    Text(given.isEmpty ? answer : given)
                } else if given.isEmpty {
                    Text(answer)
                } else {
                    Text("\(Text(given).strikethrough().foregroundStyle(CLColor.ink3)) \(Text(answer))")
                }
            }
            .clFont(.title3)
            .fontWeight(.bold)
            .foregroundStyle(CLColor.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(right ? CLColor.mintSoft : CLColor.roseSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel(right ? "Blank \(index + 1): \(answer), right" : "Blank \(index + 1): the answer is \(answer)")
        } else {
            TextField("", text: binding(index), prompt: Text(placeholder(index)).foregroundStyle(CLColor.ink4))
                .focused($focused, equals: index)
                .clFont(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(index == expected.count - 1 ? .done : .next)
                .onSubmit {
                    if index == expected.count - 1 { if canCheck { check() } } else { focused = index + 1 }
                }
                .frame(width: min(240, max(96, CGFloat(answer.count + 3) * letterWidth)))
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(focused == index ? CLColor.tangerine : CLColor.tangerine.opacity(0.55))
                        .frame(height: 3)
                }
                .accessibilityLabel("Blank \(index + 1) of \(expected.count)")
        }
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(get: { answers.indices.contains(index) ? answers[index] : "" },
                set: { value in if answers.indices.contains(index) { answers[index] = value } })
    }

    private func placeholder(_ index: Int) -> String {
        guard hinted, expected.indices.contains(index) else { return "" }
        let answer = expected[index]
        let shown = max(1, Int((Double(answer.count) / 3).rounded(.up)))
        return String(answer.prefix(shown)) + "…"
    }

    // MARK: Feedback

    /// How the answer counts: right with a hint counts as partly right.
    private func outcome(_ grade: GradeOutcome) -> SessionRunner.Outcome {
        hinted && grade.isCorrect ? .partial : SessionRunner.Outcome(grade.verdict)
    }

    /// The answer panel, once checked.
    private var panel: AnswerFeedback? {
        guard let grade else { return nil }
        let outcome = outcome(grade)
        let answerList = expected.joined(separator: ", ")
        let message: String
        switch outcome {
        case .right: message = item.explanation.isEmpty ? String(localized: "That's the word.") : item.explanation
        case .partial where grade.isCorrect:
            message = [String(localized: "That's it, with a hint."), item.explanation].filter { !$0.isEmpty }.joined(separator: " ")
        default:
            message = [String(localized: "It's \(answerList)."), item.explanation].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return AnswerFeedback(tone: FeedbackTone(outcome), headline: SessionCopy.headline(outcome, saved: saved),
                              cap: .verdict(outcome, saved: saved, combo: run),
                              message: message, note: grade.spellingNote, source: item.sourceRef,
                              combo: run)
    }

    private var canCheck: Bool {
        answers.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @ViewBuilder private var footer: some View {
        if let panel {
            Button("Continue", action: commit)
                .buttonStyle(.cl(.verdict(panel.tone)))
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Check", action: check)
                .buttonStyle(.cl(.primary))
                .disabled(!canCheck)
        }
    }

    @ViewBuilder private var secondary: some View {
        if let grade {
            if !grade.isCorrect {
                Button {
                    CLHaptics.tap()
                    app.router.present(.explain(itemID: item.id, given: answers.joined(separator: " / ")))
                } label: {
                    Label("Explain my mistake", systemImage: "bubble.left")
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
        } else if !hinted {
            Button {
                CLHaptics.select()
                withAnimation(CLMotion.fade) { hinted = true }
                AccessibilityNotification.Announcement("Hint: it starts with \(placeholder(0))").post()
            } label: {
                Label("Give me a hint", systemImage: "lightbulb")
            }
            .buttonStyle(.cl(.ghost, size: .medium))
        }
    }

    // MARK: Actions

    private func check() {
        guard grade == nil else { return }
        durationMs = runner.elapsedMs()
        focused = nil
        app.stopReadingAloud()
        let given = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let result = app.ai.instantGrade(app.gradeSubject(for: item), answer: .blanks(given))
        let verdict = outcome(result)
        saved = verdict == .right && runner.wouldSave(item)
        run = verdict == .right ? runner.combo(adding: .right, kind: item.kind) : 0
        CLFeel.play(runner.cues(for: verdict, item: item, answered: true))
        if saved { runner.flareSave(of: item) }
        withAnimation(CLMotion.snap) { grade = result }
        runner.setProvisional(verdict)
        let outcome = result
        AccessibilityNotification.Announcement(outcome.isCorrect
            ? "Right." : "Not quite. It's \(expected.joined(separator: ", ")).").post()
    }

    private func commit() {
        guard let grade else { return }
        var rating = AppModel.rating(forScore: grade.score, kind: .cloze, durationMs: durationMs)
        if hinted, rating == .good || rating == .easy { rating = .hard }
        runner.record(rating: rating, score: grade.score, answer: answers.joined(separator: " / "),
                      gradedBy: grade.gradedBy.rawValue, durationMs: durationMs,
                      outcome: outcome(grade))
        CLHaptics.select()
        withAnimation(CLMotion.settle) { runner.advance() }
    }
}

/// A fill-in sentence as wrapping pieces: its words, and each blank with the punctuation glued after it.
struct ClozeToken: Identifiable, Hashable {
    enum Kind: Hashable {
        case word(String)
        case blank(Int, trailing: String)
    }

    var id: Int
    var kind: Kind

    static func parse(_ text: String) -> [ClozeToken] {
        var out: [ClozeToken] = []
        var rest = Substring(text)
        var blank = 0
        func words(_ s: Substring) {
            for word in s.split(whereSeparator: \.isWhitespace) {
                out.append(ClozeToken(id: out.count, kind: .word(String(word))))
            }
        }
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            words(rest[rest.startIndex..<open.lowerBound])
            var after = rest[close.upperBound...]
            // Punctuation right after a blank ("{{telophase}},") stays with it.
            let glued = after.prefix { !$0.isWhitespace }
            after = after.dropFirst(glued.count)
            out.append(ClozeToken(id: out.count, kind: .blank(blank, trailing: String(glued))))
            blank += 1
            rest = after
        }
        words(rest)
        return out
    }
}
