import SwiftUI

// Navigation as data. One NavigationStack per tab, one sheet and one full-screen cover at a time, one toast.
// Every destination is a case here, mapped to its view in RootView's destination builders; a lane that needs a
// new destination adds a case and its mapping in the same change.

enum AppTab: String, Hashable, CaseIterable, Sendable {
    case today, library, ask, progress
    /// The + button. Selecting it opens the capture sheet; it never becomes the selected tab.
    case add
}

enum Route: Hashable, Sendable {
    case course(UUID)
    case exam(UUID)
    case source(UUID)
    case sourcePage(sourceID: UUID, pageIndex: Int, highlight: [String])
    case lectureNotes(UUID)
    case confusion(UUID)
    case settings
    case settingsPage(SettingsPage)
    case squad
    case streak
    case chat(UUID)
    /// The memory sky, full screen.
    case sky
    /// The memory sky as a list, every topic with Practice ("Study something else" on Today).
    case skyList
    /// Every badge.
    case badges
}

enum SettingsPage: String, Hashable, CaseIterable, Sendable, Identifiable {
    case account, subscription, study, notifications, aiPrivacy, assistant, accessibility, appearance, help, data, about, debug
    /// DEBUG builds: every sound and haptic, for auditioning and filming.
    case feelLab
    var id: String { rawValue }
}

enum PaywallContext: Hashable, Sendable {
    /// The end of onboarding, naming the plan just built ("Your Bio 101 plan is set").
    case onboarding(planLine: String)
    /// A free limit was reached or a paid feature was tapped.
    case feature(String)
    case settings
}

enum ConsentReason: Hashable, Sendable {
    /// Cloud AI for a named feature ("Write questions from this page").
    case cloudAI(feature: String)
    /// Sending page photos (handwriting, math, diagrams).
    case photos
}

struct SessionRequest: Hashable, Sendable, Identifiable {
    var id = UUID()
    var kind: SessionKind
    var courseID: UUID?
    var examID: UUID?
    var confusionID: UUID?
    /// Explicit items (a fix drill, the onboarding check). Empty means the builder chooses.
    var itemIDs: [UUID] = []
    var minutes: Int?
    /// A practice session for one topic (with `kind: .practice`).
    var topicID: UUID? = nil
}

struct CaptureRequest: Hashable, Sendable, Identifiable {
    enum Input: Hashable, Sendable {
        /// Page images already captured by the scanner or picked from Photos (files under FileStore.root).
        case images([String])
        case pdf(URL)
        case text(title: String, body: String)
        /// The bundled sample page (onboarding and the empty state).
        case sample
    }

    var id = UUID()
    var input: Input
    var courseID: UUID?
    /// True inside onboarding: the flow hands back to it instead of closing.
    var isOnboarding = false
    /// "Add questions for the rest": the flow writes a new draft set for a source already in the library, from the part of it decided
    /// when the person asked (`AppModel.restRequest`), so writing the set again with Cloud AI, from the review, uses the same part
    /// (`input` is not used). The source is never thrown away with its drafts.
    var rest: Coverage.Rest? = nil
    /// The source a rest adds questions to.
    var restOf: UUID? { rest?.sourceID }

    /// The request that adds questions for the rest of a source, from the part decided.
    static func rest(_ plan: Coverage.Rest, in courseID: UUID?) -> CaptureRequest {
        CaptureRequest(input: .text(title: "", body: ""), courseID: courseID, rest: plan)
    }
}

enum AppSheet: Identifiable, Hashable, Sendable {
    case capture(courseID: UUID?)
    case paste(courseID: UUID?)
    case importDeck(courseID: UUID?)
    case newCourse
    case editCourse(UUID)
    case newExam(courseID: UUID?)
    case editExam(UUID)
    case logGrade(examID: UUID)
    case editItem(UUID)
    case newItem(courseID: UUID?)
    case explain(itemID: UUID, given: String)
    case makeCards(threadID: UUID, maxItems: Int = 6)
    case reviewDraft(sourceID: UUID)
    /// A source page over a cover or chat (sessions and the tutor can't push onto a tab's stack).
    case sourcePage(sourceID: UUID, pageIndex: Int, highlight: [String])
    /// A lecture's notes, scrolled to a moment (a tutor citation, a question's timestamp).
    case lectureMoment(sourceID: UUID, time: Double?)
    /// The card of an imported deck that a tutor citation's quote came from (`label` is the citation's: it numbers the card).
    case deckCard(sourceID: UUID, quote: String, label: String)
    case paywall(PaywallContext)
    case examPass(examID: UUID?)
    case consent(ConsentReason)
    case squadRedeem(code: String?)
    /// One badge up close.
    case badge(Badge)
    /// "Why these?": why today's session holds what it holds.
    case todayReasons
    /// Today's quests up close.
    case quests
    /// Help: write to a real person, what is always free, restore.
    case help
    /// Two look-alike questions side by side (Cap's card "Show me").
    case lookAlike(a: UUID, b: UUID, examID: UUID?)

    var id: String { String(describing: self) }
}

enum AppCover: Identifiable, Hashable, Sendable {
    case session(SessionRequest)
    case scanner(courseID: UUID?, isOnboarding: Bool)
    case captureFlow(CaptureRequest)
    case record(courseID: UUID?)
    case onboarding(page: Int?)

    var id: String { String(describing: self) }
}

/// What a toast's button opens.
enum ToastAction: Hashable, Sendable {
    /// A screen pushed on a tab, which becomes the selected one.
    case push(Route, AppTab)
    case present(AppSheet)
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .today
    var paths: [AppTab: [Route]] = [.today: [], .library: [], .ask: [], .progress: []]
    var sheet: AppSheet?
    var cover: AppCover?
    var toast: Toast?

    func push(_ route: Route, on tab: AppTab? = nil) {
        let target = tab ?? self.tab
        paths[target, default: []].append(route)
        if self.tab != target { self.tab = target }
    }

    func pop() {
        guard var path = paths[tab], !path.isEmpty else { return }
        path.removeLast()
        paths[tab] = path
    }

    func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? self.tab] = []
    }

    /// Presents a sheet. While a cover is up, the cover hosts it (RootView attaches the same sheet to both).
    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    func present(_ cover: AppCover) {
        sheet = nil
        self.cover = cover
    }

    func dismissSheet() { sheet = nil }
    func dismissCover() { cover = nil }

    func show(_ toast: Toast) {
        self.toast = toast
    }

    func toast(_ message: LocalizedStringResource, systemImage: String = "checkmark.circle.fill", tone: Toast.Tone = .success) {
        toast = Toast(message: message, systemImage: systemImage, tone: tone)
    }

    /// A toast with a button ("Open"): stays a little longer, and its button runs `action`.
    func toast(_ message: LocalizedStringResource, systemImage: String = "checkmark.circle.fill", tone: Toast.Tone = .success,
               actionTitle: LocalizedStringResource, action: ToastAction, duration: Double = 6) {
        toast = Toast(message: message, systemImage: systemImage, tone: tone, actionTitle: actionTitle, action: action,
                      duration: duration)
    }

    /// The toast's button was pressed: the toast goes, and what it offered opens (a pushed screen over any cover, or a sheet).
    func runToastAction() {
        guard let action = toast?.action else { return }
        toast = nil
        switch action {
        case .push(let route, let tab):
            sheet = nil
            cover = nil
            push(route, on: tab)
        case .present(let sheet):
            present(sheet)
        }
    }

    /// Binding for a tab's navigation path.
    func pathBinding(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }
}
