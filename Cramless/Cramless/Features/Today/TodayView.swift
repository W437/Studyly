import SwiftUI

/// The Today tab: your memory sky edge to edge with the date, "Today" and the streak on it and Cap on the horizon
/// (`TodaySkyHero`); under it the day's one button and one caption (`TodayHeroActions`); then the next exam, Cap's note
/// on the top mix-up, the other exams, ways to add material, and the Squad (and, once a first session is done, today's quests
/// right under the button: `TodayQuestsCard`). With no questions yet the sky is unlit
/// outlines, and the button is "Try a sample page".
///
/// DEBUG hooks: `CRAMLESS_TODAY=catchup|examEve|eveDone|done|caughtUp|noMaterial|empty` (see `TodaySnapshot`);
/// `CRAMLESS_TODAY_SCROLL=1` scrolls down the page and back, to film it; `CRAMLESS_SKY_TOUR=<ms>` shows each sky behind the stars in
/// turn; `CRAMLESS_TODAY_OPEN=<ms>` opens the sky
/// that long after launch, as a tap on it would; `CRAMLESS_HERO_PULL=2500:96:500` pulls the page down 96 points at 2.5 s, holds
/// it 0.5 s and lets go (the readings a finger gives it; the page itself doesn't move), to film the refresh; and
/// `CRAMLESS_STEP=firstSession|readiness|plan` opens an onboarding step of this lane over Today (with `CRAMLESS_SEED=0` it first
/// makes the world onboarding would have made).
///
/// The hero is pinned: pulled down past its top, the page moves under it and the hero stays put (a full-bleed picture that came
/// loose from the top of the screen showed the page behind it). The pull is a pull to refresh, and the hero's world answers it
/// (`HeroRefresh.swift`).
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var snapshot: TodaySnapshot?
    /// How far the page is pulled past its top, and the refresh a long enough pull starts.
    @State private var pull = HeroPullModel()
    /// The shape the hero's sky was last laid out for.
    @State private var skyAspect = TodaySnapshot.skyAspect
    #if DEBUG
    @State private var debugStep: OnboardingDebugStep?
    #endif

    private struct Key: Equatable {
        var revision: Int
        var settings: AppSettings
        var active: Bool
        var plan: Plan
        /// The hero's sky is laid out for its own shape, so a different screen or text size lays it out again.
        var aspect: Int
    }

    /// Where everything in the hero sits on this screen, and so what shape its sky is laid out for.
    private func heroGeometry(_ geo: GeometryProxy) -> HeroWorldGeometry {
        HeroWorldGeometry.make(width: geo.size.width,
                               screenHeight: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom,
                               topInset: geo.safeAreaInsets.top, compact: typeSize.isAccessibilitySize)
    }

    var body: some View {
        GeometryReader { geo in
            let hero = heroGeometry(geo)
            let snap = snapshot ?? TodaySnapshot.make(app: app, skyAspect: hero.skyAspect)
            let content = TodayHeroContent.make(snap)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TodaySkyHero(snapshot: snap, content: content, geometry: hero, pull: pull,
                                     onOpenSky: { open(.sky) }, onRelight: { relight($0, in: snap) },
                                     onStreak: { open(.streak) }, onProfile: { open(.settings) })
                            .id("today-top")
                            // Pulled down past its top the page moves under the hero, which stays where it was. (Scrolled up it
                            // goes with the page, as ever.)
                            .visualEffect { content, proxy in
                                content.offset(y: -max(0, proxy.frame(in: .scrollView).minY))
                            }
                        VStack(alignment: .leading, spacing: 16) {
                            TodayHeroActions(content: content) { perform($0, snap) }
                            rest(snap)
                        }
                        .padding(.horizontal, CLSpace.gutter)
                        .padding(.bottom, 28)
                        .animation(CLMotion.settle, value: snap.confusion?.id)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                } action: { _, pulled in
                    pull.scrolled(to: Double(pulled))
                }
                .onScrollPhaseChange { _, phase in
                    pull.finger(dragging: phase == .interacting)
                }
                #if DEBUG
                .task { await runScrollHook(proxy) }
                .task { await runPullHook() }
                #endif
            }
            .task(id: Key(revision: app.revision, settings: app.settings, active: scenePhase == .active,
                          plan: app.purchases.plan, aspect: Int((hero.skyAspect * 100).rounded()))) {
                skyAspect = hero.skyAspect
                snapshot = TodaySnapshot.make(app: app, skyAspect: hero.skyAspect)
            }
        }
        .background(CLColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { pull.work = { await refreshToday() } }
        #if DEBUG
        .task {
            guard let raw = TestHarness.once("CRAMLESS_STEP"), let step = OnboardingDebugStep(rawValue: raw) else { return }
            app.debugPrepareOnboardingWorld(answered: step != .firstSession)
            try? await nap(300)
            debugStep = step
        }
        .task {
            guard let ms = TestHarness.once("CRAMLESS_TODAY_OPEN").flatMap(Int.init) else { return }
            try? await nap(ms)
            open(.sky)
        }
        .task {
            // `CRAMLESS_SKY_TOUR=<ms>`: each sky in turn behind the stars, that long each, and Night again at the end.
            guard let ms = TestHarness.once("CRAMLESS_SKY_TOUR").flatMap(Int.init) else { return }
            app.debugUnlockAll = true
            for theme in Array(SkyTheme.allCases.dropFirst()) + [.night] {
                try? await nap(ms)
                guard !Task.isCancelled else { return }
                app.settings.skyTheme = theme
            }
        }
        .fullScreenCover(item: $debugStep) { step in
            OnboardingDebugHost(start: step)
        }
        #endif
    }

    // MARK: Below the hero

    /// Today's quests, the next exam, Cap's note, the other exams, ways to add material and the Squad, in that order.
    @ViewBuilder
    private func rest(_ snap: TodaySnapshot) -> some View {
        if !snap.quests.isEmpty {
            TodayQuestsCard(quests: snap.quests)
        }
        if showsExams(snap), let next = snap.exams.first {
            TodayExamCard(exam: next) { open(.exam(next.id)) }
        }
        if let note = snap.confusion {
            TodayCapNote(note: note, onFix: { fix(note) }, onLater: { later(note) },
                         onOpen: { open(.confusion(note.id)) })
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        if showsExams(snap), snap.exams.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                CLSectionHeader(title: "Other exams", actionTitle: "See all") {
                    app.router.tab = .progress
                }
                .padding(.top, -10)
                TodayOtherExams(exams: Array(snap.exams.dropFirst())) { open(.exam($0)) }
            }
        }
        if snap.hero != .empty {
            VStack(alignment: .leading, spacing: 0) {
                CLSectionHeader(title: "Add material")
                    .padding(.top, -10)
                TodayQuickAdd(onScan: { scan(snap) }, onPDF: { app.router.present(.capture(courseID: snap.firstCourseID)) },
                              onLecture: { app.router.present(.record(courseID: snap.firstCourseID)) },
                              onPaste: { app.router.present(.paste(courseID: snap.firstCourseID)) })
            }
            .id("today-bottom")
        }
        if snap.isSquad {
            CLList {
                Button { open(.squad) } label: {
                    CLRow(icon: "person.3.fill", tint: .sky, title: "Your Squad", subtitle: "See who's studying today")
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func showsExams(_ snap: TodaySnapshot) -> Bool {
        snap.hero != .empty && snap.hero != .noMaterial && !snap.exams.isEmpty
    }

    /// Pull to refresh (and VoiceOver's "Refresh"): rolls the day over, brings in what other devices changed, and looks at the sky
    /// again as of now.
    private func refreshToday() async -> HeroPullModel.Outcome {
        let reached = await app.refreshToday()
        snapshot = TodaySnapshot.make(app: app, skyAspect: skyAspect)
        guard reached else {
            app.router.toast("Couldn't reach your account. Your sky is up to date on this iPhone.", systemImage: "wifi.slash", tone: .neutral)
            return .offline
        }
        return .fresh
    }

    #if DEBUG
    /// `CRAMLESS_HERO_PULL=2500:96:500,9000:50:400`: at each first number of milliseconds, a pull of the second number of points, held
    /// for the third number of milliseconds and let go: the readings a finger would give the page (the page itself doesn't move).
    private func runPullHook() async {
        guard let raw = TestHarness.once("CRAMLESS_HERO_PULL") else { return }
        var elapsed = 0
        for entry in raw.split(separator: ",") {
            let numbers = entry.split(separator: ":").compactMap { Int($0) }
            guard numbers.count == 3 else { continue }
            try? await nap(max(0, numbers[0] - elapsed))
            guard !Task.isCancelled else { return }
            let peak = Double(numbers[1])
            pull.finger(dragging: true)
            let steps = 24
            for k in 1...steps {
                let x = Double(k) / Double(steps)
                // A finger's pull slows as the rubber band tightens.
                pull.scrolled(to: peak * (1 - pow(1 - x, 2)))
                try? await nap(19)
            }
            try? await nap(numbers[2])
            pull.finger(dragging: false)
            // The page springs back.
            for k in 1...12 {
                pull.scrolled(to: peak * pow(1 - Double(k) / 12, 2))
                try? await nap(20)
            }
            elapsed = numbers[0] + steps * 19 + numbers[2] + 12 * 20
        }
    }

    /// `CRAMLESS_TODAY_SCROLL=1`: after a moment, down the page and back up, for a film.
    private func runScrollHook(_ proxy: ScrollViewProxy) async {
        guard TestHarness.once("CRAMLESS_TODAY_SCROLL") != nil else { return }
        try? await nap(2200)
        withAnimation(.easeInOut(duration: 2.4)) { proxy.scrollTo("today-bottom", anchor: .bottom) }
        try? await nap(3600)
        withAnimation(.easeInOut(duration: 2.0)) { proxy.scrollTo("today-top", anchor: .top) }
    }
    #endif

    // MARK: Actions

    private func perform(_ action: TodayHeroContent.Action, _ snap: TodaySnapshot) {
        switch action.kind {
        case .session:
            if let request = action.request { start(request) }
        case .sample: sample()
        case .scan: scan(snap)
        }
    }

    private func start(_ request: SessionRequest) {
        CLHaptics.commit()
        app.router.present(.session(request))
    }

    private func open(_ route: Route) {
        CLHaptics.tap()
        app.router.push(route, on: .today)
    }

    /// A constellation's card in the hero: a practice session on that topic, as the full sky's card starts one.
    private func relight(_ constellation: SkyLayout.Constellation, in snap: TodaySnapshot) {
        CLHaptics.commit()
        app.router.present(.session(app.relightRequest(constellation, in: snap.sky)))
    }

    private func fix(_ note: ConfusionNote) {
        guard let request = app.prepareFix(note.id) else { return }
        start(request)
    }

    private func later(_ note: ConfusionNote) {
        CLHaptics.tap()
        app.snoozeConfusion(note.id)
        withAnimation(CLMotion.exit) { snapshot = TodaySnapshot.make(app: app, skyAspect: skyAspect) }
        app.router.toast("Cap will bring it up tomorrow", systemImage: "clock", tone: .neutral)
    }

    private func sample() {
        CLHaptics.tap()
        app.router.present(.captureFlow(CaptureRequest(input: .sample, courseID: app.courses.first?.id)))
    }

    private func scan(_ snap: TodaySnapshot) {
        app.router.present(.scanner(courseID: snap.firstCourseID, isOnboarding: false))
    }
}
