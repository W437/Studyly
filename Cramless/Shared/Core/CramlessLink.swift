import Foundation

/// The capling:// links that widgets, Live Activities, the control, notifications and intents open. The app parses
/// them in `DeepLinks` (Cramless/App/DeepLinks.swift); `DeepLinkTests` checks that every link built here parses.
///
///     capling://today | ask | progress | library | streak
///     capling://session[?kind=<SessionKind>&exam=<uuid>&confusion=<uuid>&course=<uuid>]
///     capling://scan[?course=<uuid>]     capling://record[?course=<uuid>]
///     capling://exam/<uuid>              capling://exam/new           capling://squad/<code>
///     capling://settings[/<page>]        (page: a `SettingsPage` raw value: "notifications", "subscription", …)
enum CramlessLink {
    static let scheme = "capling"

    static let today = URL(string: "capling://today")!
    static let ask = URL(string: "capling://ask")!
    static let progress = URL(string: "capling://progress")!
    static let library = URL(string: "capling://library")!
    static let streak = URL(string: "capling://streak")!
    static let session = URL(string: "capling://session")!
    static let scan = URL(string: "capling://scan")!
    static let record = URL(string: "capling://record")!

    /// A session of a given kind (`SessionKind` raw value: "daily", "fix", "examEve", …).
    static func session(kind: String, exam: UUID? = nil, confusion: UUID? = nil, course: UUID? = nil) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "session"
        var items = [URLQueryItem(name: "kind", value: kind)]
        if let exam { items.append(URLQueryItem(name: "exam", value: exam.uuidString)) }
        if let confusion { items.append(URLQueryItem(name: "confusion", value: confusion.uuidString)) }
        if let course { items.append(URLQueryItem(name: "course", value: course.uuidString)) }
        c.queryItems = items
        return c.url ?? session
    }

    /// Settings, or one page of it by its raw value ("notifications", "subscription").
    static func settings(page: String? = nil) -> URL {
        URL(string: "capling://settings" + (page.map { "/\($0)" } ?? "")) ?? today
    }

    /// The new-exam sheet.
    static let newExam = URL(string: "capling://exam/new")!

    static func exam(_ id: UUID) -> URL {
        URL(string: "capling://exam/\(id.uuidString)")!
    }

    /// A Squad invite code; anything but letters, digits and dashes is dropped.
    static func squad(_ code: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let clean = String(code.unicodeScalars.filter { allowed.contains($0) }.map(Character.init))
        return URL(string: "capling://squad/\(clean)") ?? today
    }
}

/// Hands capling:// links from App Intents to the running app. An intent compiled into both the app and the widget
/// extension (`StartSessionIntent`, which the control uses) can't see `AppModel`, so the app installs a handler at
/// launch (`CramlessAppDelegate`); a link that arrives before that waits and is delivered on install.
@MainActor
enum CramlessIntentBridge {
    private static var handler: ((URL) -> Void)?
    private static var pending: [URL] = []

    static var isInstalled: Bool { handler != nil }

    static func install(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        let waiting = pending
        pending = []
        waiting.forEach(handler)
    }

    static func open(_ url: URL) {
        if let handler {
            handler(url)
        } else {
            pending.append(url)
        }
    }

    /// Tests only: forget the handler and anything waiting.
    static func reset() {
        handler = nil
        pending = []
    }
}
