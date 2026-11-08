#if DEBUG
import SwiftUI

/// Scene 2, "Your own words": an answer types itself, the highlighter marks the key ideas it hit (the same
/// `HighlightedText` sweep grading uses), the ideas are checked off, and the missing one is named.
struct OwnWordsScene: View {
    let active: Bool

    @State private var typed = 0
    @State private var graded = false
    @State private var swept = false
    @State private var ideas = 0
    @State private var scored = false

    static let answer = "So the body can grow and repair tissue, making two identical cells."
    static let marks: [HighlightMark] = ["grow and repair tissue", "identical cells"].compactMap { quote in
        HighlightMark.locate(quote, in: answer).map { HighlightMark(range: $0, tone: .hit) }
    }
    private static let ideaRows: [(hit: Bool, text: String)] = [
        (true, "Growth and repair"),
        (true, "Genetically identical cells"),
        (false, "Missing: same number of chromosomes"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("In your own words", systemImage: "pencil.line")
                    .clFont(.eyebrow)
                    .foregroundStyle(CLColor.ink3)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 6)
                CLPill(text: "2 of 3 · Almost", tone: .sun)
                    .scaleEffect(scored ? 1 : 0.6)
                    .opacity(scored ? 1 : 0)
            }
            Text("Why do cells divide by mitosis?")
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
            answerBox
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Self.ideaRows.indices, id: \.self) { i in
                    idea(Self.ideaRows[i].hit, Self.ideaRows[i].text)
                        .opacity(ideas > i ? 1 : 0)
                        .offset(y: ideas > i ? 0 : 14)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sceneLifecycle(active: active, reset: reset, settle: settle, script: play)
    }

    private var answerBox: some View {
        ZStack(alignment: .topLeading) {
            // The full answer, invisible, holds the box at its final height while the answer types.
            Text(Self.answer).clFont(.callout).hidden()
            if graded {
                HighlightedText(text: Self.answer, marks: Self.marks, revealed: swept, style: .callout)
            } else {
                Text("\(String(Self.answer.prefix(typed)))\(Text("|").foregroundStyle(CLColor.tangerine).fontWeight(.semibold))")
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink)
            }
        }
        .lineSpacing(3)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func idea(_ hit: Bool, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: hit ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(hit ? CLColor.mintInk : CLColor.roseInk)
            Text(text)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(hit ? CLColor.ink : CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Script

    private func reset() {
        typed = 0; graded = false; swept = false; ideas = 0; scored = false
    }

    private func settle() {
        typed = Self.answer.count; graded = true; swept = true; ideas = Self.ideaRows.count; scored = true
    }

    private func play() async throws {
        try await nap(500)
        for i in 1...Self.answer.count {
            typed = i
            try await nap(34)
        }
        try await nap(450)
        graded = true
        try await nap(120)
        swept = true
        try await nap(900)
        for i in 1...Self.ideaRows.count {
            withAnimation(CLMotion.settle) { ideas = i }
            try await nap(260)
        }
        withAnimation(CLMotion.pop) { scored = true }
        try await nap(2600)
    }
}
#endif
