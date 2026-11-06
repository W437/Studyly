import SwiftUI

/// The Today tab, "plan first": a short band of your memory sky with the greeting, the streak and Cap (`TodaySkyHero`); the day's
/// one card (`TodayDayCard`: its exam and why, readiness now and about where today takes it, "Study · 15 min", "Why these?"); "Your
/// plan" for the week (`TodayPlanCard`, with today's quests in one line); one of Cap's cards (`TodayNoticeCard`; on an exam's eve his
/// quiet line instead); and the exams as a row (`TodayExamsRow`, or "When is your next exam?" with material and no exam).
///
/// DEBUG hooks: `CRAMLESS_TODAY=catchup|partway|split|noExam|examEve|eveDone|done|caughtUp|noMaterial|empty` (see `TodaySnapshot`);
/// `CRAMLESS_TODAY_NOTICES=0|1|2|3` deals that many of Cap's cards; `CRAMLESS_NOTICES`, `CRAMLESS_NOTICE_STATE` shape the world for his
/// real ones (`AppModel+NoticeHarness`); `CRAMLESS_TODAY_WHY=<ms>`, `CRAMLESS_TODAY_QUESTS=<ms>` open "Why these?" and the quests that
/// long after launch, `CRAMLESS_TODAY_LATER=<ms>` presses Cap's "Later" and `CRAMLESS_NOTICE_TAP=<ms>` his card's button; `CRAMLESS_TODAY_SCROLL=1`
/// scrolls down to the exams and back, to film it; `CRAMLESS_SKY_TOUR=<ms>` shows each sky behind the stars in turn;
/// `CRAMLESS_TODAY_OPEN=<ms>` opens the sky that long after launch, as a tap on the band would; `CRAMLESS_TODAY_TYPE=ax3` draws
/// Today at that text size; `CRAMLESS_HERO_PULL=2500:96:500`
/// pulls the page down 96 points at 2.5 s, holds it 0.5 s and lets go (the readings a finger gives it; the page itself doesn't
/// move), to film the refresh; `CRAMLESS_CANVAS=375x667` draws the page at an iPhone SE's size; and
/// `CRAMLESS_STEP=firstSession|readiness|plan` opens an onboarding step of this lane over Today (with `CRAMLESS_SEED=0` it first
/// makes the world onboarding would have made).
///
/// The band is pinned: pulled down past its top, the page moves under it and the band stays put. The pull is a pull to refresh, and
/// the band's world answers it (`HeroRefresh.swift`).
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var snapshot: TodaySnapshot?
    /// How far the page is pulled past its top, and the refresh a long enough pull starts.
    @State private var pull = HeroPullModel()
    /// The shape the band's sky was last laid out for.
    @State private var skyAspect = TodaySnapshot.skyAspect
    /// The band has scrolled up out of sight: the status bar gets the page's colour behind it, so cards don't run under the clock.
    @State private var pastBand = false
    #if DEBUG
    @State private var debugStep: OnboardingDebugStep?
    #endif

    private struct Key: Equatable {
        var revision: Int
        var settings: AppSettings
        var active: Bool
        var plan: Plan
        /// The band's sky is laid out for its own shape, so a different screen or text size lays it out again.
        var aspect: Int
    }

    /// Where everything in the band sits on this screen, and so what shape its sky is laid out for.
    private func heroGeometry(_ geo: GeometryProxy) -> HeroWorldGeometry {
        HeroWorldGeometry.band(width: geo.size.width, topInset: geo.safeAreaInsets.top, compact: textSize.isAccessibilitySize)
    }

    /// The text size Today is drawn at: the person's, or in DEBUG `CRAMLESS_TODAY_TYPE=xxxl|ax1…ax5` (to look at the largest sizes
    /// without changing a shared simulator's setting).
    private var textSize: DynamicTypeSize {
        #if DEBUG
        if let raw = TestHarness.value("CRAMLESS_TODAY_TYPE") {
            let sizes: [String: DynamicTypeSize] = ["xxxl": .xxxLarge, "ax1": .accessibility1, "ax2": .accessibility2,
                                                    "ax3": .accessibility3, "ax4": .accessibility4, "ax5": .accessibility5]
            if let size = sizes[raw] { return size }
        }
        #endif
        return typeSize
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
                                     onOpenSky: { open(.sky) }, onStreak: { open(.streak) }, onProfile: { open(.settings) })
                            .id("today-top")
                            // Pulled down past its top the page moves under the band, which stays where it was. (Scrolled up it
                            // goes with the page, as ever.)
                            .visualEffect { content, proxy in
                                content.offset(y: -max(0, proxy.frame(in: .scrollView).minY))
                            }
                        VStack(alignment: .leading, spacing: 16) {
                            TodayDayCard(content: content, perform: { perform($0, snap) }, onWhy: { present(.todayReasons) })
                            rest(snap)
                        }
                        .padding(.horizontal, CLSpace.gutter)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                        .animation(CLMotion.settle, value: snap.notices.first?.id)
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
                // Only the crossing is reported, so this costs nothing while scrolling.
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > hero.height - hero.topInset
                } action: { _, past in
                    withAnimation(CLMotion.fade) { pastBand = past }
                }
                .overlay(alignment: .top) {
                    LinearGradient(stops: [.init(color: CLColor.background, location: 0),
                                           .init(color: CLColor.background, location: 0.7),
                                           .init(color: CLColor.background.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: hero.topInset + 14)
                        .ignoresSafeArea(edges: .top)
                        .opacity(pastBand ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #if DEBUG
                .task { await runScrollHook(proxy) }
                .task { await runPullHook() }
                .task { await runSheetHooks(snap) }
                #endif
            }
            .task(id: Key(revision: app.revision, settings: app.settings, active: scenePhase == .active,
                          plan: app.purchases.plan, aspect: Int((hero.skyAspect * 100).rounded()))) {
                skyAspect = hero.skyAspect
                snapshot = TodaySnapshot.make(app: app, skyAspect: hero.skyAspect)
            }
        }
        .background(CLColor.background.ignoresSafeArea())
        .dynamicTypeSize(textSize)
        .captureDebugCanvas()
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

    // MARK: Below the day card

    /// "Your plan", Cap's card (or on the eve his quiet line), and the exams.
    @ViewBuilder
    private func rest(_ snap: TodaySnapshot) -> some View {
        if snap.hasMaterial, !snap.strip.isEmpty {
            TodayPlanCard(days: snap.strip, quests: snap.isEve ? QuestsToday() : snap.quests,
                          onCalendar: { open(.streak) }, onQuests: { present(.quests) })
        }
        if snap.isEve, let eve = snap.eveExam {
            TodayQuietLine(text: TodayCopy.quietLine(examTitle: eve.title, others: snap.eveOthers))
        } else if snap.hasMaterial, let notice = snap.notices.first {
            TodayNoticeCard(notice: notice, index: snap.noticePosition, total: snap.noticeTotal,
                            onAction: { act(on: $0) }, onLater: { later(notice) }, onOpen: { follow($0) }, onHide: { hide(notice) })
                .id(notice.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                // On screen, not just on the page: a card seen today needs no notification today.
                .onScrollVisibilityChange(threshold: 0.6) { visible in
                    if visible, !notice.isConfirmation { app.noteNoticeShown(notice.id) }
                }
        }
        if snap.hasMaterial, !snap.isEve {
            Group {
                if snap.exams.isEmpty {
                    TodayAddExamCard { app.router.present(.newExam(courseID: snap.firstCourseID)) }
                } else {
                    TodayExamsRow(exams: snap.exams, onOpen: { open(.exam($0)) }, onSeeAll: seeAllExams)
                }
            }
            .id("today-bottom")
        }
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

    /// `CRAMLESS_TODAY_WHY=<ms>` and `CRAMLESS_TODAY_QUESTS=<ms>` open "Why these?" and the quests that long after launch;
    /// `CRAMLESS_TODAY_LATER=<ms>` presses "Later" on Cap's card.
    private func runSheetHooks(_ snap: TodaySnapshot) async {
        if let ms = TestHarness.once("CRAMLESS_TODAY_WHY").flatMap(Int.init) {
            try? await nap(ms)
            present(.todayReasons)
        }
        if let ms = TestHarness.once("CRAMLESS_TODAY_QUESTS").flatMap(Int.init) {
            try? await nap(ms)
            present(.quests)
        }
        if let ms = TestHarness.once("CRAMLESS_TODAY_LATER").flatMap(Int.init) {
            try? await nap(ms)
            if let notice = (snapshot ?? snap).notices.first { later(notice) }
        }
        // `CRAMLESS_NOTICE_TAP=<ms>` presses the button on Cap's card.
        if let ms = TestHarness.once("CRAMLESS_NOTICE_TAP").flatMap(Int.init) {
            try? await nap(ms)
            if let action = (snapshot ?? snap).notices.first?.action { act(on: action) }
        }
    }

    /// `CRAMLESS_TODAY_SCROLL=1`: after a moment, down the page to the exams and back up, for a film. `=notice`: to Cap's card, and it stays.
    private func runScrollHook(_ proxy: ScrollViewProxy) async {
        guard let scroll = TestHarness.once("CRAMLESS_TODAY_SCROLL") else { return }
        if scroll == "notice" {
            try? await nap(900)
            if let id = (snapshot ?? TodaySnapshot.make(app: app, skyAspect: skyAspect)).notices.first?.id { proxy.scrollTo(id, anchor: .center) }
            return
        }
        try? await nap(2200)
        withAnimation(.easeInOut(duration: 2.4)) { proxy.scrollTo("today-bottom", anchor: .bottom) }
        try? await nap(3600)
        withAnimation(.easeInOut(duration: 2.0)) { proxy.scrollTo("today-top", anchor: .top) }
    }
    #endif

    // MARK: Actions

    private func perform(_ action: TodayHeroContent.Action, _ snap: TodaySnapshot) {
        switch action.kind {
        case .session, .practice:
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

    private func present(_ sheet: AppSheet) {
        CLHaptics.tap()
        app.router.present(sheet)
    }

    /// "See all" exams: the Progress tab, the one list of exams, at its top.
    private func seeAllExams() {
        CLHaptics.tap()
        app.router.popToRoot(.progress)
        app.router.tab = .progress
    }

    /// Cap's card's button.
    private func act(on action: CapNotice.Action) {
        CLHaptics.commit()
        app.perform(action)
    }

    /// A tap on Cap's card's title: what it is about.
    private func follow(_ link: CapNotice.Link) {
        switch link {
        case .confusion(let id): open(.confusion(id))
        case .exam(let id): open(.exam(id))
        }
    }

    /// "Later": the card waits until tomorrow, and the next one (if any) takes its place. On "Plan updated", "OK": it just goes.
    private func later(_ notice: CapNotice) {
        CLHaptics.tap()
        if notice.isConfirmation {
            app.dismissNoticeConfirmation()
        } else {
            app.snoozeNotice(notice.id)
            app.router.toast("Cap will bring it up tomorrow", systemImage: "clock", tone: .neutral)
        }
        withAnimation(CLMotion.exit) { snapshot = TodaySnapshot.make(app: app, skyAspect: skyAspect) }
    }

    /// "Don't show these": the kind's switch goes off.
    private func hide(_ notice: CapNotice) {
        CLHaptics.tap()
        app.setNoticeKind(notice.kind, on: false)
        withAnimation(CLMotion.exit) { snapshot = TodaySnapshot.make(app: app, skyAspect: skyAspect) }
        app.router.toast("Cap won't bring these up. Turn them on again in Settings.", systemImage: "checkmark.circle.fill", tone: .neutral)
    }

    private func sample() {
        CLHaptics.tap()
        app.router.present(.captureFlow(CaptureRequest(input: .sample, courseID: app.courses.first?.id)))
    }

    private func scan(_ snap: TodaySnapshot) {
        app.router.present(.scanner(courseID: snap.firstCourseID, isOnboarding: false))
    }
}
