import Foundation
import OSLog

/// Where a link goes. Pure values: `DeepLinks.parse` builds them, `DeepLinks.perform` applies them to the router.
enum DeepLink: Equatable, Sendable {
    case tab(AppTab)
    case streak
    case session(kind: SessionKind, examID: UUID?, confusionID: UUID?, courseID: UUID?)
    case scan(courseID: UUID?)
    case record(courseID: UUID?)
    case exam(UUID)
    case newExam
    case squad(code: String)
    /// Settings, optionally one page of it ("notifications", "subscription").
    case settings(SettingsPage?)
    /// A file opened from another app (Open in Capling, the share sheet).
    case importFile(URL)
}

/// capling:// links from widgets, Live Activities, the control, notifications and intents, and files opened from
/// other apps. The links are built in `CramlessLink` (Shared/), which lists them.
///
/// A link never throws away work in progress: while a full-screen flow is up (a session, the scanner, a recording,
/// a capture, onboarding) links that would open another one are ignored, and a session link with a session already
/// open just brings the app forward. Tab, exam and settings links still switch underneath, and sheets (Squad, a new
/// exam) show on top.
/// Before onboarding is done only files are handled.
enum DeepLinks {
    @MainActor
    static func handle(_ url: URL, app: AppModel) {
        guard let link = parse(url) else {
            log.notice("unhandled link \(url.absoluteString, privacy: .private)")
            return
        }
        perform(link, app: app)
    }

    /// Routes App Intent links (`CramlessIntentBridge`) to the running app. Installed by the app delegate at
    /// launch; also installed by the first intent or widget refresh, whichever comes first.
    @MainActor
    static func installIntentBridge() {
        guard !CramlessIntentBridge.isInstalled else { return }
        CramlessIntentBridge.install { url in
            guard let app = AppModel.live else {
                log.error("intent link before the app model exists: \(url.absoluteString, privacy: .private)")
                return
            }
            handle(url, app: app)
        }
    }

    // MARK: Parsing

    static func parse(_ url: URL) -> DeepLink? {
        if url.isFileURL { return .importFile(url) }
        guard url.scheme?.lowercased() == CramlessLink.scheme else { return nil }
        let host = (url.host(percentEncoded: false) ?? "").lowercased()
        let path = url.pathComponents.filter { $0 != "/" }
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            if query[item.name.lowercased()] == nil { query[item.name.lowercased()] = item.value ?? "" }
        }
        func uuid(_ key: String) -> UUID? { query[key].flatMap(UUID.init(uuidString:)) }

        switch host {
        case "today": return .tab(.today)
        case "ask": return .tab(.ask)
        case "progress": return .tab(.progress)
        case "library": return .tab(.library)
        case "streak": return .streak
        case "session":
            var kind = sessionKind(query["kind"]) ?? .daily
            let confusion = uuid("confusion")
            // A fix needs its confusion; the onboarding check isn't reachable from outside.
            if (kind == .fix && confusion == nil) || kind == .quickCheck { kind = .daily }
            return .session(kind: kind, examID: uuid("exam"), confusionID: kind == .fix ? confusion : nil,
                            courseID: uuid("course"))
        case "scan": return .scan(courseID: uuid("course"))
        case "record": return .record(courseID: uuid("course"))
        case "exam":
            if path.first?.lowercased() == "new" { return .newExam }
            guard let id = (path.first ?? query["id"]).flatMap(UUID.init(uuidString:)) else { return nil }
            return .exam(id)
        case "squad":
            guard let code = squadCode(path.first ?? query["code"]) else { return nil }
            return .squad(code: code)
        case "settings":
            guard let raw = path.first else { return .settings(nil) }
            guard let page = SettingsPage(rawValue: raw), page != .debug, page != .feelLab else { return nil }
            return .settings(page)
        default:
            return nil
        }
    }

    private static func sessionKind(_ raw: String?) -> SessionKind? {
        guard let raw = raw?.lowercased() else { return nil }
        let kinds: [SessionKind] = [.daily, .fix, .examEve, .catchUp, .quickCheck, .practice]
        return kinds.first { $0.rawValue.lowercased() == raw }
    }

    /// Letters and digits (and dashes between them), 4 to 32 long.
    private static func squadCode(_ raw: String?) -> String? {
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines), (4...32).contains(code.count) else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard code.unicodeScalars.allSatisfy(allowed.contains), code.first != "-", code.last != "-" else { return nil }
        return code
    }

    // MARK: Dispatch

    @MainActor
    static func perform(_ link: DeepLink, app: AppModel) {
        if case .importFile(let url) = link {
            app.importFile(url)
            return
        }
        guard app.settings.onboardingCompleted else {
            log.notice("link ignored during onboarding")
            return
        }
        let router = app.router
        switch link {
        case .tab(let tab):
            router.dismissSheet()
            router.popToRoot(tab)
            router.tab = tab
        case .streak:
            router.dismissSheet()
            router.popToRoot(.progress)
            router.push(.streak, on: .progress)
        case .exam(let id):
            router.dismissSheet()
            router.popToRoot(.today)
            if let exam = app.exam(id), exam.deletedAt == nil {
                router.push(.exam(id), on: .today)
            } else {
                router.tab = .today
            }
        case .newExam:
            router.present(.newExam(courseID: nil))
        case .settings(let page):
            router.dismissSheet()
            router.popToRoot(.today)
            router.push(.settings, on: .today)
            if let page { router.push(.settingsPage(page), on: .today) }
        case .squad(let code):
            router.present(.squadRedeem(code: code))
        case let .session(kind, examID, confusionID, courseID):
            if case .session = router.cover { return }
            guard router.cover == nil else { return }
            let confusion = confusionID.flatMap { app.confusion($0) != nil ? $0 : nil }
            let request = confusion == nil && kind == .fix
                ? SessionRequest(kind: .daily)
                : SessionRequest(kind: kind, courseID: courseID, examID: examID, confusionID: confusion)
            router.present(.session(request))
        case .scan(let courseID):
            guard router.cover == nil else { return }
            router.present(.scanner(courseID: courseID, isOnboarding: false))
        case .record(let courseID):
            guard router.cover == nil else { return }
            router.present(.record(courseID: courseID))
        case .importFile:
            break
        }
    }

    static let log = Logger(subsystem: "com.loopware.Capling", category: "links")
}
