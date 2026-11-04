import SwiftUI

/// One of the six live-demo pages.
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
                  body: "Photos, PDFs, slides or a lecture. Flashcards and questions, each linked back to the page it came from.",
                  sceneDescription: "Demo: a textbook page is scanned. Its key lines are highlighted, and three cards appear, a flashcard, a multiple choice question and an own-words question, each linked to page 87."),
        IntroPage(id: 1, scene: .flashcards, title: "Flashcards that\ncome back in time.",
                  body: "Cards return just before you'd forget them. Bring your Anki or Quizlet decks.",
                  sceneDescription: "Demo: a flashcard asks what mitosis makes. It flips to the answer, two genetically identical cells. You rate it Good, and a week lights the day it comes back: in 5 days."),
        IntroPage(id: 2, scene: .ownWords, title: "Answer in your\nown words.",
                  body: "No more flip-and-guess. Type or say it, and see exactly what you nailed and what's missing.",
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

/// The six live demos in a native pager: custom dots (the active one stretches with the swipe), a haptic tick
/// on page turns only, Skip on every page but the last, and one button that reads Continue, then Let's go.
struct IntroPager: View {
    @Environment(OnboardingCoordinator.self) private var onboarding
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

    @State private var scrolledID: Int?
    /// The continuous page position (1.5 = halfway from page 2 to page 3), for the dots and the backdrop.
    @State private var position: CGFloat = 0

    private var page: Int {
        if case .intro(let p) = onboarding.step { return p }
        return onboarding.machine.introPage
    }

    private var isFrontmost: Bool {
        if case .intro = onboarding.step { return true }
        return false
    }

    private var isLast: Bool { page == IntroPage.all.count - 1 }

    var body: some View {
        GeometryReader { geo in
            let sceneHeight = min(410, max(260, geo.size.height * 0.5))
            VStack(spacing: 0) {
                topBar
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(IntroPage.all) { item in
                            IntroPageView(page: item, active: isFrontmost && item.id == page, sceneHeight: sceneHeight)
                                .containerRelativeFrame(.horizontal)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledID)
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.containerSize.width > 0 ? geometry.contentOffset.x / geometry.containerSize.width : 0
                } action: { _, value in
                    position = value
                }
                footer
            }
        }
        .background { backdrop.ignoresSafeArea() }
        .onAppear {
            if scrolledID == nil { scrolledID = page; position = CGFloat(page) }
        }
        .onChange(of: scrolledID) { _, new in
            guard let new, new != page else { return }
            // The one owner of the page-turn haptic: swipes and the Continue button both land here.
            CLHaptics.select()
            onboarding.showIntroPage(new)
        }
    }

    private var topBar: some View {
        HStack {
            CaplingWordmark(size: 24, color: CLColor.ink)
            Spacer()
            Button {
                CLHaptics.tap()
                onboarding.skipIntro()
            } label: {
                Text("Skip").clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink2)
            }
            .buttonStyle(.glass)
            .opacity(isLast ? 0 : 1)
            .disabled(isLast)
            .accessibilityHidden(isLast)
            .accessibilityHint("Goes to the questions")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 44)
        .animation(CLMotion.fade, value: isLast)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            PagerDots(count: IntroPage.all.count, position: position)
            Button(action: next) {
                Text(isLast ? "Let's go" : "Continue")
                    .contentTransition(.opacity)
            }
            .buttonStyle(.cl(.primary))
            .animation(CLMotion.fade, value: isLast)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// One continuous backdrop: each page's colour, blended as the page moves, with a glow drifting across.
    /// Light gets the soft wash; dark keeps the navy and lets the page's hue glow from the top.
    private var backdrop: some View {
        let pages = IntroPage.all
        let clamped = max(0, min(CGFloat(pages.count - 1), position))
        let lower = Int(clamped.rounded(.down))
        let upper = min(pages.count - 1, lower + 1)
        let fraction = Double(clamped - CGFloat(lower))
        let dark = scheme == .dark
        return ZStack {
            CLColor.background
            if !dark {
                pages[lower].tint.mix(with: pages[upper].tint, by: fraction)
            }
            GeometryReader { geo in
                let glow = dark
                    ? pages[lower].hue.mix(with: pages[upper].hue, by: fraction).opacity(0.2)
                    : CLColor.surface.opacity(0.7)
                Circle()
                    .fill(RadialGradient(colors: [glow, glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: geo.size.width * 0.6))
                    .frame(width: geo.size.width * 1.2, height: geo.size.width * 1.2)
                    .position(x: geo.size.width * (0.2 + 0.15 * clamped), y: geo.size.height * 0.28)
            }
        }
        .accessibilityHidden(true)
    }

    private func next() {
        if isLast {
            CLHaptics.tap()
            onboarding.advance()
        } else {
            withAnimation(CLMotion.settle) { scrolledID = page + 1 }
        }
    }
}

/// A page: the scene on top, then the title and two lines. Scrolls when the text is very large.
private struct IntroPageView: View {
    let page: IntroPage
    let active: Bool
    let sceneHeight: CGFloat

    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                SceneCard(height: sceneHeight) { scene }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(page.sceneDescription))
                    .accessibilityAddTraits(.isImage)
                Text(page.title)
                    .clFont(.brandTitle(31))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 26)
                Text(page.body)
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

    @ViewBuilder private var scene: some View {
        switch page.scene {
        case .snap: SnapScene(active: active)
        case .flashcards: FlashcardScene(active: active)
        case .ownWords: OwnWordsScene(active: active)
        case .readiness: ReadinessScene(active: active, now: app.now)
        case .plan: PlanScene(active: active,
                              reminderTime: QuizContent.timeString(minutes: app.settings.reminderMinutes ?? 19 * 60 + 30))
        case .askCap: AskCapScene(active: active)
        }
    }
}

/// Pager dots: the active one stretches, following the finger between pages.
struct PagerDots: View {
    let count: Int
    let position: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                let nearness = max(0, 1 - abs(position - CGFloat(i)))
                Capsule()
                    .fill(CLColor.ink)
                    .frame(width: 7 + 15 * nearness, height: 7)
                    .opacity(0.18 + 0.67 * nearness)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(Int(position.rounded()) + 1) of \(count)"))
    }
}
