import SwiftUI

/// Edits one draft question before it's approved: the question, and its answer in the form its format needs (the
/// choices of a multiple choice with the right one marked, a fill-in's sentence with the blanks in [brackets]), in the words the
/// question editor uses (`ItemEditorView`).
/// A diagram's labels come from the page's own text, so only its question can change.
struct DraftItemEditor: View {
    let itemID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ItemKind = .recall
    @State private var prompt = ""
    @State private var answer = ""
    @State private var choices: [Choice] = []
    @State private var sentence = ""
    @State private var sourceLabel: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Question", text: $prompt, axis: .vertical)
                        .clFont(.body)
                        .lineLimit(2...6)
                } header: {
                    Text("Question")
                } footer: {
                    if let sourceLabel { Text("From \(sourceLabel). Keep it to what the page says.") }
                }
                answerSection
            }
            .scrollContentBackground(.hidden)
            .background(CLColor.background.ignoresSafeArea())
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    @ViewBuilder private var answerSection: some View {
        switch kind {
        case .mcq:
            Section {
                ForEach(choices.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Button {
                            CLHaptics.select()
                            for i in choices.indices { choices[i].correct = i == index }
                        } label: {
                            Image(systemName: choices[index].correct ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(choices[index].correct ? CLColor.mintInk : CLColor.ink4)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(choices[index].correct ? "Right answer" : "Mark as the right answer"))
                        TextField("Choice \(index + 1)", text: $choices[index].text, axis: .vertical)
                            .clFont(.body)
                    }
                }
            } header: {
                Text("Choices")
            } footer: {
                Text("Tap a circle to mark the one right answer.")
            }
        case .cloze:
            Section {
                TextField("Sentence", text: $sentence, axis: .vertical)
                    .clFont(.body)
                    .lineLimit(2...6)
            } header: {
                Text("Sentence")
            } footer: {
                Text("The words in [brackets] are the blanks.")
            }
        case .diagram:
            Section {
                Text("The labels come from the text on your page, so they stay as they are.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
            }
        default:
            Section("Answer") {
                TextField("Answer", text: $answer, axis: .vertical)
                    .clFont(.body)
                    .lineLimit(2...8)
            }
        }
    }

    private var canSave: Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch kind {
        case .mcq:
            return choices.filter(\.correct).count == 1
                && choices.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        case .cloze:
            return sentence.contains("[") && sentence.contains("]")
        case .diagram:
            return true
        default:
            return !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func load() {
        guard !loaded, let item = app.item(itemID), item.modelContext != nil else { return }
        loaded = true
        kind = item.kind
        prompt = item.prompt
        answer = item.answer
        choices = item.choices
        sentence = ItemDraft.bracketed(item.cloze?.text ?? "")
        sourceLabel = item.sourceRef?.label
    }

    private func save() {
        CLHaptics.tap()
        let cleanChoices = choices.map { Choice(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), correct: $0.correct, why: $0.why) }
        let cloze = kind == .cloze ? ItemDraft.braced(sentence) : nil
        app.updateDraft(itemID, prompt: prompt, answer: answer, choices: kind == .mcq ? cleanChoices : nil, clozeText: cloze)
        dismiss()
    }
}
