import SwiftUI

/// The shell: onboarding until it's done, then the tabs. Hosts the one sheet, the one cover and the toast, so
/// any screen can present through `app.router`.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = false

    var body: some View {
        @Bindable var router = app.router
        ZStack(alignment: .top) {
            if app.settings.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingFlow(startPage: nil)
            }
            ToastHost()
        }
        #if DEBUG
        .onAppear {
            FilmTimecode.installIfAsked()
            TouchDots.installIfAsked()
        }
        #endif
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        .environment(\.skyTheme, app.skyTheme)
        .preferredColorScheme(colorScheme)
        .tint(CLColor.tangerine)
        .sheet(item: $router.sheet) { sheet in
            SheetDestination(sheet: sheet)
                // A sheet doesn't inherit what's set on the view that presents it.
                .environment(\.clDyslexicFont, app.settings.dyslexicFont)
                .environment(\.skyTheme, app.skyTheme)
                .tint(CLColor.tangerine)
        }
        .fullScreenCover(item: $router.cover) { cover in
            CoverDestination(cover: cover)
                .environment(\.clDyslexicFont, app.settings.dyslexicFont)
                .environment(\.skyTheme, app.skyTheme)
                .preferredColorScheme(colorScheme)
                .tint(CLColor.tangerine)
                // A sheet raised while a cover is up is presented by the cover.
                .sheet(item: $router.sheet) { sheet in
                    SheetDestination(sheet: sheet)
                        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
                        .environment(\.skyTheme, app.skyTheme)
                        .tint(CLColor.tangerine)
                }
                .overlay(alignment: .top) { ToastHost() }
        }
        .task {
            guard !started else { return }
            started = true
            await app.start()
            #if DEBUG
            try? await Task.sleep(for: .milliseconds(350))
            TestHarness.applyRoute(to: app)
            await DeviceProbe.runIfRequested(app: app)
            #endif
        }
        .onOpenURL { url in DeepLinks.handle(url, app: app) }
        .onChange(of: scenePhase) { _, phase in
            // A new day may have started while the app was away: apply streak freezes, refresh what's shown.
            guard phase == .active, started else { return }
            app.applyDailyRollover()
            if app.sideEffectsEnabled { app.widgets.refresh() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch app.settings.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Shows the router's toast and takes it down after its time (or leaves it for VoiceOver to read).
private struct ToastHost: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack {
            if let toast = app.router.toast {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 6)
                    .task(id: toast.id) {
                        if voiceOver {
                            AccessibilityNotification.Announcement(String(localized: toast.message)).post()
                        }
                        try? await Task.sleep(for: .seconds(voiceOver ? max(toast.duration, 6) : toast.duration))
                        if app.router.toast?.id == toast.id {
                            withAnimation(CLMotion.exit) { app.router.toast = nil }
                        }
                    }
                    .onTapGesture { withAnimation(CLMotion.exit) { app.router.toast = nil } }
            }
        }
        .animation(CLMotion.settle, value: app.router.toast?.id)
    }
}

/// The four tabs and the + button. The + is a tab of its own role, which iOS draws apart from the others, but it is a button:
/// `AddTabAction` (in each tab's content) stops UIKit selecting it and opens the capture sheet, so the page behind stays put.
/// The binding's own `.add` branch is the fallback if a selection ever gets through.
struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let router = app.router
        TabView(selection: Binding(get: { router.tab }, set: { newValue in
            if newValue == .add {
                CLHaptics.tap()
                router.present(.capture(courseID: nil))
            } else {
                if newValue == router.tab { router.popToRoot(newValue) }
                router.tab = newValue
            }
        })) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TabRoot(tab: .today) { TodayView() }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                TabRoot(tab: .library) { LibraryView() }
            }
            Tab("Ask", systemImage: "bubble.left.and.bubble.right", value: AppTab.ask) {
                TabRoot(tab: .ask) { AskView() }
            }
            Tab("Progress", systemImage: "chart.bar", value: AppTab.progress) {
                TabRoot(tab: .progress) { ProgressTabView() }
            }
            Tab("Add", systemImage: "plus", value: AppTab.add, role: Self.addRole) {
                Color.clear
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: router.tab) { _, _ in CLHaptics.select() }
    }

    /// iOS 27 has a prominent role for a primary action tab; iOS 26 draws a search-role tab apart instead.
    private static var addRole: TabRole {
        #if HAS_IOS27_SDK
        if #available(iOS 27.0, *) { return .prominent }
        #endif
        return .search
    }
}

/// One tab's navigation stack.
private struct TabRoot<Content: View>: View {
    @Environment(AppModel.self) private var app
    let tab: AppTab
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack(path: app.router.pathBinding(tab)) {
            content
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .background(AddTabAction {
            CLHaptics.tap()
            app.router.present(.capture(courseID: nil))
        })
    }
}

/// Every pushed screen, by route.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .course(let id): CourseView(courseID: id)
        case .exam(let id): ExamDetailView(examID: id)
        case .source(let id): SourceView(sourceID: id)
        case .sourcePage(let id, let index, let highlight): SourcePageView(sourceID: id, pageIndex: index, highlight: highlight)
        case .lectureNotes(let id): LectureNotesView(sourceID: id)
        case .confusion(let id): ConfusionView(confusionID: id)
        case .settings: SettingsView()
        case .settingsPage(let page): SettingsPageView(page: page)
        case .squad: SquadView()
        case .streak: StreakView()
        case .sky: SkyScreen()
        case .badges: BadgesView()
        case .chat(let id): ChatView(threadID: id)
        }
    }
}

/// Every sheet, by case.
struct SheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .capture(let courseID): CaptureSheet(courseID: courseID)
        case .paste(let courseID): PasteTextView(courseID: courseID)
        case .importDeck(let courseID): ImportDeckView(courseID: courseID)
        case .newCourse: CourseEditorView(courseID: nil)
        case .editCourse(let id): CourseEditorView(courseID: id)
        case .newExam(let courseID): ExamEditorView(courseID: courseID, examID: nil)
        case .editExam(let id): ExamEditorView(courseID: nil, examID: id)
        case .logGrade(let id): LogGradeView(examID: id)
        case .editItem(let id): ItemEditorView(itemID: id, courseID: nil)
        case .newItem(let courseID): ItemEditorView(itemID: nil, courseID: courseID)
        case .explain(let id, let given): ExplainMistakeView(itemID: id, given: given)
        case .makeCards(let id): MakeCardsView(threadID: id)
        case .reviewDraft(let id): DraftReviewView(sourceID: id, isOnboarding: false)
        case .sourcePage(let id, let index, let highlight):
            NavigationStack { SourcePageView(sourceID: id, pageIndex: index, highlight: highlight) }
        case .lectureMoment(let id, let time):
            NavigationStack { LectureNotesView(sourceID: id, focusTime: time) }
        case .paywall(let context): PaywallView(context: context)
        case .examPass(let id): ExamPassView(examID: id)
        case .consent(let reason): ConsentSheet(reason: reason)
        case .squadRedeem(let code): SquadRedeemView(code: code)
        case .badge(let badge): BadgeSheet(badge: badge)
        }
    }
}

/// Every full-screen cover, by case.
struct CoverDestination: View {
    let cover: AppCover

    var body: some View {
        switch cover {
        case .session(let request): SessionView(request: request)
        case .scanner(let courseID, let isOnboarding): ScannerFlowView(courseID: courseID, isOnboarding: isOnboarding)
        case .captureFlow(let request): CaptureFlowView(request: request)
        case .record(let courseID): RecordView(courseID: courseID)
        case .onboarding(let page): OnboardingFlow(startPage: page)
        }
    }
}
