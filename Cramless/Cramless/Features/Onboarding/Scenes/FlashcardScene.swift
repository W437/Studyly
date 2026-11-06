import SwiftUI

/// Scene 2, "Flashcards": a card turns over to its answer, the four ratings say when it would come back, "Got it" is tapped, and a
/// week lights the day it returns. The session's own flip, tiles and intervals in miniature (`FlipFace`, the rating tones).
struct FlashcardScene: View {
    let active: Bool

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var flipped = false
    @State private var rating = false
    @State private var picked = false
    @State private var scheduled = false

    static let question = "What does mitosis make?"
    static let answer = "Two genetically identical cells."
    /// What each rating would do to the card's next visit, as the scheduler words it for a card you have seen before.
    private static let ratings: [(rating: Rating, when: String)] = [(.again, "10 min"), (.hard, "2 days"), (.good, "5 days"), (.easy, "11 days")]
    /// The week: the days are today and the six after it, and the card comes back on the sixth.
    static let returnsOn = 5
    private static let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("Flashcard", systemImage: "rectangle.on.rectangle")
                    .clFont(.eyebrow)
                    .foregroundStyle(CLColor.ink3)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 6)
                CLPill(text: "Cells · Mitosis", tone: .sky)
            }
            card
            tiles
            week
                .opacity(scheduled ? 1 : 0)
                .offset(y: scheduled ? 0 : 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sceneLifecycle(active: active, reset: reset, settle: settle, script: play)
    }

    // MARK: Parts

    private var card: some View {
        ZStack {
            face(front: true)
                .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: false, flat: reduceMotion))
            face(front: false)
                .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: true, flat: reduceMotion))
        }
        .frame(minHeight: 96, maxHeight: .infinity)
    }

    private func face(front: Bool) -> some View {
        VStack(spacing: 10) {
            if front {
                Text(Self.question)
                    .clFont(.title3)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                Text("Say it to yourself, then tap to check")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
            } else {
                Text(Self.answer)
                    .clFont(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                CLSourceChip(label: "p. 87")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 0.5))
    }

    /// The four ratings, each with when the card comes back. "Got it" is the one that gets tapped.
    private var tiles: some View {
        HStack(spacing: 7) {
            ForEach(Self.ratings, id: \.rating) { item in
                let tone = FlashcardQuestionView.tone(item.rating)
                let chosen = item.rating == .good
                VStack(spacing: 3) {
                    Text(item.rating.title).clFont(.subheadlineEmphasis)
                    Text(item.when).clFont(.number(11, .semibold)).opacity(0.85)
                }
                .foregroundStyle(tone.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CLColor.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tone.fill))
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tone.ink.opacity(chosen && picked ? 0.7 : 0), lineWidth: 2))
                .scaleEffect(chosen && picked ? 0.93 : 1)
                .opacity(rating ? (picked && !chosen ? 0.4 : 1) : 0)
                .offset(y: rating ? 0 : 12)
            }
        }
    }

    /// The week after the tap: today filled, the day the card returns lit, and the words for it.
    private var week: some View {
        HStack(alignment: .center, spacing: 12) {
            CLPill(text: "Back in 5 days", tone: .mint, systemImage: "calendar")
            Spacer(minLength: 4)
            HStack(spacing: 7) {
                ForEach(Self.days.indices, id: \.self) { i in
                    let returns = i == Self.returnsOn
                    VStack(spacing: 4) {
                        Circle()
                            .fill(i == 0 ? CLColor.skyInk : returns ? CLColor.mint : CLColor.hairline)
                            .overlay(Circle().strokeBorder(returns ? CLColor.mintInk : .clear, lineWidth: 2).padding(-3))
                            .frame(width: returns ? 14 : 9, height: returns ? 14 : 9)
                            .frame(height: 16)
                        Text(Self.days[i]).clFont(.number(10, .semibold)).foregroundStyle(returns ? CLColor.mintInk : CLColor.ink3)
                    }
                }
            }
        }
    }

    // MARK: Script

    private func reset() {
        flipped = false; rating = false; picked = false; scheduled = false
    }

    private func settle() {
        flipped = true; rating = true; picked = true; scheduled = true
    }

    private func play() async throws {
        try await nap(1500)                       // long enough to read the question
        withAnimation(reduceMotion ? CLMotion.fade : CLMotion.calm) { flipped = true }
        try await nap(950)
        withAnimation(CLMotion.settle) { rating = true }
        try await nap(1300)
        withAnimation(CLMotion.pop) { picked = true }
        try await nap(550)
        withAnimation(CLMotion.settle) { scheduled = true }
        try await nap(2900)
    }
}
