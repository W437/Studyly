import SwiftUI
import UIKit

/// One question of a mock, in its format, with no verdict: an answer can be changed until it is handed in. Each page holds what it shows in
/// its own state and writes it through to the runner.
struct MockQuestionPage<Extras: View>: View {
    let runner: MockRunner
    let entry: SessionEntry
    let item: StudyItem
    /// Back, Flag and the grid at the accessibility text sizes, where the pinned footer has no room for them.
    @ViewBuilder var extras: Extras

    var body: some View {
        QuestionScroll {
            // No topic in the header: on an exam, the question doesn't say what it is about.
            QuestionHeader(item: item, entry: entry, topic: nil)
            QuestionCard {
                switch entry.kind {
                case .mcq: MockChoiceBody(runner: runner, item: item)
                case .cloze: MockClozeBody(runner: runner, item: item)
                default: MockWrittenBody(runner: runner, item: item)
                }
            }
            AccessibilityOnly { extras }
        }
        .task { app.readAloud(question: item) }
    }

    @Environment(AppModel.self) private var app
}

/// Lettered options; a tap chooses, another tap on the same one clears it.
private struct MockChoiceBody: View {
    let runner: MockRunner
    let item: StudyItem

    @Environment(AppModel.self) private var app
    @State private var chosen: Int?
    @State private var order: [Int] = []

    var body: some View {
        let choices = item.choices
        Text(item.prompt)
            .clFont(.title2)
            .foregroundStyle(CLColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        VStack(spacing: 10) {
            ForEach(Array(order.enumerated()), id: \.element) { position, index in
                let letter = ChoiceOrder.letters[min(position, ChoiceOrder.letters.count - 1)]
                let isChosen = chosen == index
                Button {
                    CLHaptics.select()
                    withAnimation(CLMotion.snap) { chosen = isChosen ? nil : index }
                    runner.setChoice(chosen, for: item.id)
                } label: {
                    ChoiceOptionTile(letter: letter, text: choices[index].text, state: isChosen ? .chosen : .idle)
                        .contentShape(RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
                }
                .buttonStyle(.pressable(depth: 4, edge: (isChosen ? ChoiceOptionState.chosen : .idle).edge))
                .keyboardShortcut(KeyEquivalent(Character(letter.lowercased())), modifiers: [])
                .accessibilityLabel("\(letter). \(choices[index].text)")
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .padding(.top, 18)
        .onAppear {
            guard order.isEmpty else { return }
            order = ChoiceOrder.order(texts: choices.map(\.text), itemID: item.id, day: app.calendar.dayNumber(for: app.now))
            chosen = runner.given(for: item.id).choice
        }
    }
}

/// The sentence with its blanks, with no hint on a mock.
private struct MockClozeBody: View {
    let runner: MockRunner
    let item: StudyItem

    @State private var answers: [String] = []
    @FocusState private var focused: Int?
    @ScaledMetric(relativeTo: .title3) private var letterWidth: CGFloat = 12

    private var spec: ClozeSpec { item.cloze ?? ClozeSpec(text: "{{\(item.answer)}}") }

    private var asks: Bool { !item.prompt.isEmpty && item.prompt != spec.text }

    var body: some View {
        if asks {
            Text(item.prompt)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.ink2)
        }
        CLFlow(spacing: 6, lineSpacing: 4) {
            ForEach(ClozeToken.parse(spec.text)) { token in
                switch token.kind {
                case .word(let word):
                    Text(word).clFont(.title3).foregroundStyle(CLColor.ink).frame(minHeight: 32)
                case .blank(let index, let trailing):
                    HStack(alignment: .center, spacing: 1) {
                        blank(index)
                        if !trailing.isEmpty { Text(trailing).clFont(.title3).foregroundStyle(CLColor.ink) }
                    }
                    .frame(minHeight: 32)
                }
            }
        }
        .padding(.top, asks ? 14 : 0)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard answers.isEmpty else { return }
            let kept = runner.given(for: item.id).blanks
            answers = kept.count == spec.answers.count ? kept : Array(repeating: "", count: spec.answers.count)
        }
    }

    private func blank(_ index: Int) -> some View {
        let answer = spec.answers.indices.contains(index) ? spec.answers[index] : ""
        return TextField("", text: Binding(get: { answers.indices.contains(index) ? answers[index] : "" }, set: { value in
            guard answers.indices.contains(index) else { return }
            answers[index] = value
            runner.setBlanks(answers, for: item.id)
        }))
        .focused($focused, equals: index)
        .clFont(.title3)
        .fontWeight(.semibold)
        .foregroundStyle(CLColor.ink)
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(index == spec.answers.count - 1 ? .done : .next)
        .onSubmit { focused = index == spec.answers.count - 1 ? nil : index + 1 }
        .frame(width: min(240, max(96, CGFloat(answer.count + 3) * letterWidth)))
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(focused == index ? CLColor.tangerine : CLColor.tangerine.opacity(0.55))
                .frame(height: 3)
        }
        .accessibilityLabel("Blank \(index + 1) of \(spec.answers.count)")
    }
}

/// The question and the box for an answer in the person's own words.
private struct MockWrittenBody: View {
    let runner: MockRunner
    let item: StudyItem

    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        Text(item.prompt)
            .clFont(.title2)
            .foregroundStyle(CLColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        AnswerEditor(text: $text, focused: $focused)
            .padding(.top, 16)
            .onAppear {
                guard !loaded else { return }
                text = runner.given(for: item.id).text
                loaded = true
            }
            .onChange(of: text) { _, new in
                guard loaded else { return }
                runner.setText(new, for: item.id)
            }
    }
}
