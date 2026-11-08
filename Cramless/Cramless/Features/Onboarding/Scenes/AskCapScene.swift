#if DEBUG
import SwiftUI

/// Scene 5, "Ask Cap": a question, Cap thinking, and the thinking bubble growing into an answer that cites the
/// textbook page and the lecture moment; then the trust badges settle. The trust page plays once and rests:
/// reassurance shouldn't loop.
struct AskCapScene: View {
    let active: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var asked = false
    @State private var thinking = false
    @State private var answered = false
    @State private var chips = 0
    @State private var badges = 0

    /// In the order they land: the first row, then the second.
    static let badgeTexts: [(symbol: String, text: String)] = [
        ("iphone", "Works offline"),
        ("checkmark.seal", "You approve every set"),
        ("lock", "Never trains on your notes"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            header
            Spacer(minLength: 0)
            if asked {
                Text("Why does anaphase matter?")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.onFill)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(CLColor.tangerine, in: BubbleShape(mine: true))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity),
                                            removal: .opacity))
            }
            if thinking || answered {
                reply
                    .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity),
                                            removal: .opacity))
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    badge(0)
                    badge(1)
                }
                badge(2)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sceneLifecycle(active: active, playsOnce: true, reset: reset, settle: settle, script: play)
    }

    private var header: some View {
        HStack(spacing: 8) {
            CapFace(size: 26)
            Text("Ask Cap").clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
            Spacer(minLength: 6)
            CLPill(text: "Hints first", tone: .sky, systemImage: "lightbulb")
        }
    }

    /// One bubble that holds the thinking dots, then grows into the answer, the way a chat does. (Cap's face is
    /// in the header, so the bubble gets the full width and the two sources sit on one line.)
    private var reply: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if answered {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("It's the moment the sister chromatids are pulled apart, so each new cell gets a full set of chromosomes.")
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        CLFlow(spacing: 6, lineSpacing: 6) {
                            CLSourceChip(label: "Textbook p. 87", systemImage: "book.pages")
                                .scaleEffect(chips >= 1 ? 1 : 0.6)
                                .opacity(chips >= 1 ? 1 : 0)
                            CLSourceChip(label: "Lecture 6 · 12:05", systemImage: "mic")
                                .scaleEffect(chips >= 2 ? 1 : 0.6)
                                .opacity(chips >= 2 ? 1 : 0)
                        }
                    }
                    .padding(12)
                    .transition(.opacity)
                } else {
                    TypingDots(bubble: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .transition(.opacity)
                }
            }
            .background(scheme == .dark ? CLColor.surface2 : CLColor.surface, in: BubbleShape(mine: false))
            .overlay(BubbleShape(mine: false).stroke(CLColor.hairline, lineWidth: 0.5))
            .shadow(color: CLColor.night.opacity(scheme == .dark ? 0.3 : 0.1), radius: 10, y: 5)
            Spacer(minLength: 0)
        }
    }

    private func badge(_ i: Int) -> some View {
        let shown = badges > i
        return HStack(spacing: 5) {
            Image(systemName: Self.badgeTexts[i].symbol).font(.system(size: 11, weight: .bold))
            Text(Self.badgeTexts[i].text).clFont(.caption).fontWeight(.semibold).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .foregroundStyle(CLColor.mintInk)
        .background(CLColor.mintSoft, in: Capsule())
        .fixedSize()
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
    }

    // MARK: Script

    private func reset() {
        asked = false; thinking = false; answered = false; chips = 0; badges = 0
    }

    private func settle() {
        asked = true; thinking = false; answered = true; chips = 2; badges = Self.badgeTexts.count
    }

    private func play() async throws {
        try await nap(450)
        withAnimation(CLMotion.settle) { asked = true }
        try await nap(600)
        withAnimation(CLMotion.settle) { thinking = true }
        try await nap(1100)
        withAnimation(CLMotion.settle) { answered = true; thinking = false }
        try await nap(450)
        for i in 1...2 {
            withAnimation(CLMotion.pop) { chips = i }
            try await nap(150)
        }
        try await nap(700)
        for i in 1...Self.badgeTexts.count {
            withAnimation(CLMotion.pop) { badges = i }
            try await nap(120)
        }
    }
}
#endif
