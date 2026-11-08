#if DEBUG
import SwiftUI

/// The six live demos that opened onboarding until the clarity pass. Onboarding now starts with the person's own page, which
/// shows the same things for real, so the demos are kept only for films and store art: `CRAMLESS_ROUTE=introScene:<n>` (1 to 6)
/// opens one page as a cover, playing.
struct IntroPage: Identifiable, Sendable {
    enum Scene: Sendable { case snap, flashcards, ownWords, readiness, plan, askCap }

    let id: Int
    let scene: Scene
    let title: String
    let body: String
    /// What the demo shows, for VoiceOver.
    let sceneDescription: String

    /// The page's soft wash in light appearance.
    var tint: Color {
        switch scene {
        case .snap, .askCap: CLColor.skySoft
        case .flashcards: CLColor.roseSoft
        case .ownWords: CLColor.mintSoft
        case .readiness: CLColor.sunSoft
        case .plan: CLColor.tangerineSoft
        }
    }

    /// The page's hue, for the glow in dark appearance (a full soft wash turns olive and brown over navy).
    var hue: Color {
        switch scene {
        case .snap, .askCap: CLColor.sky
        case .flashcards: CLColor.rose
        case .ownWords: CLColor.mint
        case .readiness: CLColor.sun
        case .plan: CLColor.tangerine
        }
    }

    static let all: [IntroPage] = [
        IntroPage(id: 0, scene: .snap, title: "Snap a page.\nGet a study set.",
                  body: "Photos, PDFs or a lecture. Flashcards and questions, each linked back to the page it came from.",
                  sceneDescription: "Demo: a textbook page is scanned. Its key lines are highlighted, and three cards appear, a flashcard, a multiple choice question and an own-words question, each linked to page 87."),
        IntroPage(id: 1, scene: .flashcards, title: "Flashcards that\ncome back in time.",
                  body: "Cards return just before you'd forget them. Bring your Anki or Quizlet decks.",
                  sceneDescription: "Demo: a flashcard asks what mitosis makes. It flips to the answer, two genetically identical cells. You mark it Got it, and a week lights the day it comes back: in 5 days."),
        IntroPage(id: 2, scene: .ownWords, title: "Answer in your\nown words.",
                  body: "Type or say it, and see exactly what you nailed and what's missing.",
                  sceneDescription: "Demo: an answer typed in your own words is graded. It hits growth and repair, and identical cells, and the missing idea is named: the same number of chromosomes. Two of three, almost."),
        IntroPage(id: 3, scene: .readiness, title: "Know how\nready you are.",
                  body: "A readiness score for every exam, built from what you actually remember.",
                  sceneDescription: "Demo: readiness for the Bio 101 Midterm climbs to 82 percent. Cell cycle 92 percent, meiosis 71 percent, and genetics is tagged as the weak spot."),
        IntroPage(id: 4, scene: .plan, title: "A plan that bends\nwith your week.",
                  body: "Short daily sessions until exam day. Miss one and the rest of the week quietly absorbs it.",
                  sceneDescription: "Demo: Wednesday's 15 minutes are missed, and Thursday and Friday absorb them, 22 and 18 minutes. A reminder arrives: 22 minutes tonight and you're done."),
        IntroPage(id: 5, scene: .askCap, title: "A tutor that\nknows your notes.",
                  body: "Stuck? Ask Cap. Answers cite your own material, and it nudges you to think before it tells.",
                  sceneDescription: "Demo: you ask Cap why anaphase matters. Cap answers and cites textbook page 87 and lecture 6 at 12:05. Works offline. Never trains on your notes. You approve every set."),
    ]
}

/// One demo page for films (`CRAMLESS_ROUTE=introScene:<n>`): the scene playing on top, its title and two lines, on the page's
/// colour. The close button sits where the pager's Skip was.
struct IntroScenePage: View {
    let number: Int

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var page: IntroPage { IntroPage.all[max(0, min(IntroPage.all.count - 1, number - 1))] }

    var body: some View {
        GeometryReader { geo in
            let sceneHeight = min(410, max(260, geo.size.height * 0.5))
            VStack(spacing: 0) {
                HStack {
                    CaplingWordmark(size: 24, color: CLColor.ink)
                    Spacer()
                    CLIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        SceneCard(height: sceneHeight) { scene }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: page.sceneDescription))
                            .accessibilityAddTraits(.isImage)
                        Text(verbatim: page.title)
                            .clFont(.brandTitle(31))
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 26)
                        Text(verbatim: page.body)
                            .clFont(.body)
                            .foregroundStyle(CLColor.ink2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 24)
                    // Room for the card's shadow: a scroll view clips at its edge.
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .background { backdrop.ignoresSafeArea() }
    }

    @ViewBuilder private var scene: some View {
        switch page.scene {
        case .snap: SnapScene(active: true)
        case .flashcards: FlashcardScene(active: true)
        case .ownWords: OwnWordsScene(active: true)
        case .readiness: ReadinessScene(active: true, now: app.now)
        case .plan: PlanScene(active: true,
                              reminderTime: QuizContent.timeString(minutes: app.settings.reminderMinutes ?? 19 * 60 + 30))
        case .askCap: AskCapScene(active: true)
        }
    }

    /// The page's colour: the soft wash in light, the navy with the page's hue glowing from the top in dark.
    private var backdrop: some View {
        ZStack {
            CLColor.background
            if scheme != .dark { page.tint }
            GeometryReader { geo in
                let glow = scheme == .dark ? page.hue.opacity(0.2) : CLColor.surface.opacity(0.7)
                Circle()
                    .fill(RadialGradient(colors: [glow, glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: geo.size.width * 0.6))
                    .frame(width: geo.size.width * 1.2, height: geo.size.width * 1.2)
                    .position(x: geo.size.width * (0.2 + 0.15 * CGFloat(page.id)), y: geo.size.height * 0.28)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
