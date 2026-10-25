import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The local Supabase stack `LocalStackTests` run against (`scripts/local_stack.sh up`): real Auth, PostgREST,
/// Storage and the Edge Functions in MOCK mode, over the network to the Mac's localhost (the simulator shares it).
///
/// Opt-in: the tests skip unless `CRAMLESS_LOCAL_STACK_URL` and `CRAMLESS_LOCAL_STACK_ANON_KEY` reach the test host
/// (the `TEST_RUNNER_` prefix on xcodebuild; `scripts/local_stack.sh env --test-runner` prints them). The service
/// key (`CRAMLESS_LOCAL_STACK_SERVICE_KEY`) is only ever used by `Admin`, for test setup (sign-in codes, a Squad
/// purchase) and read-only checks of what the server holds. The app's classes see the URL and the anon key.
struct LocalStack: Sendable {
    let url: URL
    let anonKey: String
    let serviceKey: String?

    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) throws -> LocalStack {
        let raw = env["CRAMLESS_LOCAL_STACK_URL"] ?? ""
        let anon = env["CRAMLESS_LOCAL_STACK_ANON_KEY"] ?? ""
        guard !raw.isEmpty, !anon.isEmpty, let url = URL(string: raw) else {
            throw XCTSkip("Local stack tests are opt-in: scripts/local_stack.sh up, then pass "
                + "TEST_RUNNER_CRAMLESS_LOCAL_STACK_URL and TEST_RUNNER_CRAMLESS_LOCAL_STACK_ANON_KEY "
                + "(eval \"$(scripts/local_stack.sh env --service --test-runner)\").")
        }
        let service = env["CRAMLESS_LOCAL_STACK_SERVICE_KEY"] ?? ""
        return LocalStack(url: url, anonKey: anon, serviceKey: service.isEmpty ? nil : service)
    }

    /// The configuration the app resolves when Secrets.xcconfig points at this stack (`CRAMLESS_SUPABASE_HOST =
    /// http:/$()/127.0.0.1:58421`, read from Info.plist): relay mode, the explicit http scheme kept, and the
    /// in-memory store a test run gets.
    var config: AppConfig {
        AppConfig.resolve(environment: ["XCTestConfigurationFilePath": "LocalStackTests"],
                          info: ["CramlessSupabaseHost": url.absoluteString, "CramlessSupabaseAnonKey": anonKey])
    }

    /// A fresh in-memory app, wired as the app wires itself in relay mode: `AccountService(app:)` (URLSession.shared
    /// and, for an in-memory store, an in-memory session store), `AIRouter.transport` (HTTP). With `session`, the
    /// account starts from that stored session, as a second device signed in to the same account would.
    @MainActor
    func makeApp(session: AuthSession? = nil) -> AppModel {
        let app = AppModel(config: config, defaults: UserDefaults(suiteName: "capling.localstack.\(UUID().uuidString)")!)
        app.sideEffectsEnabled = false
        if let session {
            app.account = AccountService(app: app, config: config, urlSession: .shared,
                                         store: InMemorySessionStore(session))
            app.account.restoreSession()
        }
        return app
    }

    /// The relay transport the app itself builds in relay mode.
    @MainActor
    func relay(of app: AppModel) throws -> HTTPRelayTransport {
        let transport = try XCTUnwrap(app.ai.transport as? HTTPRelayTransport, "relay mode builds the HTTP transport")
        XCTAssertEqual(transport.baseURL, url)
        return transport
    }

    /// A raw request with the anon key and a bearer token, for checks of status codes and envelopes on the wire.
    func raw(_ method: String, _ path: String, token: String?, body: Data? = nil) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: url.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func admin() throws -> Admin {
        guard let serviceKey else {
            throw XCTSkip("This check needs TEST_RUNNER_CRAMLESS_LOCAL_STACK_SERVICE_KEY (test setup only).")
        }
        return Admin(url: url, serviceKey: serviceKey)
    }

    /// Service-role calls: test setup and read-only checks of the server's rows. Never the app's path.
    struct Admin: Sendable {
        let url: URL
        let serviceKey: String

        struct Failure: Error, CustomStringConvertible {
            var description: String
        }

        @discardableResult
        func call(_ method: String, _ path: String, query: String? = nil, json: Any? = nil,
                  headers: [String: String] = [:]) async throws -> (status: Int, data: Data) {
            var components = try XCTUnwrap(URLComponents(url: url.appending(path: path), resolvingAgainstBaseURL: false))
            if let query { components.percentEncodedQuery = query }
            var request = URLRequest(url: try XCTUnwrap(components.url), cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = method
            request.setValue(serviceKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
            if let json {
                request.httpBody = try JSONSerialization.data(withJSONObject: json)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }

        private func object(_ result: (status: Int, data: Data), _ what: String) throws -> [String: Any] {
            guard (200..<300).contains(result.status),
                  let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] else {
                throw Failure(description: "\(what): HTTP \(result.status) \(String(decoding: result.data, as: UTF8.self))")
            }
            return object
        }

        /// The 6-digit code a sign-in email would carry (Auth admin `generate_link`: the local stack sends no mail).
        func emailCode(for email: String) async throws -> String {
            let link = try object(await call("POST", "auth/v1/admin/generate_link",
                                             json: ["type": "magiclink", "email": email]), "generate link")
            return try XCTUnwrap(link["email_otp"] as? String)
        }

        /// An active Squad subscription, as a verified App Store purchase leaves it in `entitlements`.
        func grantSquad(to userID: String, now: Date = Date()) async throws {
            let transaction = String(UInt64.random(in: 1_000_000_000_000...9_999_999_999_999))
            let result = try await call("POST", "rest/v1/entitlements", json: [[
                "user_id": userID, "plan": "squad", "product_id": "com.loopware.Capling.squad.yearly",
                "original_transaction_id": transaction, "transaction_id": transaction,
                "purchase_date": SupabaseDate.format(now),
                "expires_at": SupabaseDate.format(now.addingTimeInterval(365 * 86_400)), "environment": "Sandbox",
            ]], headers: ["Prefer": "return=minimal"])
            guard (200..<300).contains(result.status) else {
                throw Failure(description: "grant squad: HTTP \(result.status) \(String(decoding: result.data, as: UTF8.self))")
            }
        }

        /// The rows of a table that belong to the user (the service role sees past RLS).
        func rows(_ table: String, _ userID: String, owner column: String = "user_id",
                  select: String = "*") async throws -> [[String: Any]] {
            let result = try await call("GET", "rest/v1/\(table)", query: "select=\(select)&\(column)=eq.\(userID)")
            guard result.status == 200, let rows = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] else {
                throw Failure(description: "rows of \(table): HTTP \(result.status) \(String(decoding: result.data, as: UTF8.self))")
            }
            return rows
        }

        func authUserExists(_ userID: String) async throws -> Bool {
            let result = try await call("GET", "auth/v1/admin/users/\(userID)")
            switch result.status {
            case 200: return true
            case 404: return false
            default: throw Failure(description: "auth user: HTTP \(result.status) \(String(decoding: result.data, as: UTF8.self))")
            }
        }

        /// The names of the files in a folder of the private `sources` bucket.
        func storageFiles(in folder: String) async throws -> [String] {
            let result = try await call("POST", "storage/v1/object/list/sources", json: ["prefix": folder, "limit": 100])
            guard result.status == 200, let entries = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] else {
                throw Failure(description: "storage list: HTTP \(result.status) \(String(decoding: result.data, as: UTF8.self))")
            }
            return entries.filter { !($0["id"] is NSNull) }.compactMap { $0["name"] as? String }
        }
    }

    /// Waits for work the functions finish after answering (the `ai_requests` row is written in the background).
    static func eventually(timeout: TimeInterval = 10, _ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(200))
        }
        return try await condition()
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}

/// Everything one app holds that sync carries, field by field (dates at the server's microsecond grain, blobs
/// through the models' own accessors), so two devices can be compared and every difference named.
@MainActor
enum LocalStackSnapshot {
    typealias Table = [String: [String: String]]

    private static func t(_ date: Date?) -> String { date.map { String(SupabaseDate.micros($0)) } ?? "nil" }
    private static func n(_ value: Double?) -> String { value.map { String($0) } ?? "nil" }
    private static func u(_ id: UUID?) -> String { id.map(LocalStack.key) ?? "nil" }
    private static func d<T>(_ value: T) -> String { String(describing: value) }

    static func of(_ app: AppModel) -> [String: Table] {
        var out: [String: Table] = [:]
        for c in app.fetch(FetchDescriptor<Course>()) {
            out["courses", default: [:]][u(c.id)] = [
                "name": c.name, "color": c.colorRaw, "symbol": c.symbol, "sortOrder": d(c.sortOrder),
                "createdAt": t(c.createdAt), "updatedAt": t(c.updatedAt), "deletedAt": t(c.deletedAt),
            ]
        }
        for x in app.fetch(FetchDescriptor<Topic>()) {
            out["topics", default: [:]][u(x.id)] = [
                "course": u(x.course?.id), "name": x.name, "summary": x.summary, "sortOrder": d(x.sortOrder),
                "createdAt": t(x.createdAt), "updatedAt": t(x.updatedAt), "deletedAt": t(x.deletedAt),
            ]
        }
        for s in app.fetch(FetchDescriptor<Source>()) {
            out["sources", default: [:]][u(s.id)] = [
                "course": u(s.course?.id), "kind": s.kindRaw, "status": s.statusRaw, "title": s.title,
                "fileName": s.fileName ?? "nil", "duration": n(s.duration), "segments": d(s.segments),
                "flags": d(s.flags), "notes": d(s.notes), "pages": d(s.sortedPages.map { LocalStack.key($0.id) }),
                "createdAt": t(s.createdAt), "updatedAt": t(s.updatedAt), "deletedAt": t(s.deletedAt),
            ]
        }
        for p in app.fetch(FetchDescriptor<SourcePage>()) {
            // The image's file name is each device's own; the photo's bytes are compared separately.
            out["source_pages", default: [:]][u(p.id)] = [
                "source": u(p.source?.id), "pageIndex": d(p.pageIndex), "label": p.label, "text": p.text,
                "lines": d(p.lines), "read": d(p.read), "width": n(p.width), "height": n(p.height),
            ]
        }
        for i in app.fetch(FetchDescriptor<StudyItem>()) {
            let m = i.memory
            out["items", default: [:]][u(i.id)] = [
                "course": u(i.course?.id), "topic": u(i.topicID), "kind": i.kindRaw, "status": i.statusRaw,
                "origin": i.originRaw, "prompt": i.prompt, "answer": i.answer, "explanation": i.explanation,
                "keyIdeas": d(i.keyIdeas), "choices": d(i.choices), "cloze": d(i.cloze), "diagram": d(i.diagram),
                "sourceRef": d(i.sourceRef), "checkedAt": t(i.checkedAt), "difficultyHint": n(i.difficultyHint),
                "reported": d(i.reported), "state": d(m.state), "stability": n(m.stability),
                "difficulty": n(m.difficulty), "due": t(m.due), "lastReview": t(m.lastReview), "reps": d(m.reps),
                "lapses": d(m.lapses), "step": d(m.step), "createdAt": t(i.createdAt), "updatedAt": t(i.updatedAt),
                "deletedAt": t(i.deletedAt),
            ]
        }
        for r in app.fetch(FetchDescriptor<ReviewLog>()) {
            out["review_logs", default: [:]][u(r.id)] = [
                "item": u(r.itemID), "course": u(r.courseID), "session": u(r.sessionID), "reviewedAt": t(r.reviewedAt),
                "rating": d(r.ratingRaw), "score": n(r.score), "answer": r.answer ?? "nil", "gradedBy": r.gradedBy,
                "durationMs": d(r.durationMs), "stateBefore": d(r.stateBeforeRaw), "stabilityBefore": n(r.stabilityBefore),
                "difficultyBefore": n(r.difficultyBefore), "elapsedDays": n(r.elapsedDays),
                "scheduledDays": n(r.scheduledDays), "stabilityAfter": n(r.stabilityAfter),
                "difficultyAfter": n(r.difficultyAfter),
            ]
        }
        for e in app.fetch(FetchDescriptor<Exam>()) {
            out["exams", default: [:]][u(e.id)] = [
                "course": u(e.course?.id), "title": e.title, "date": t(e.date), "scope": d(e.scope.map(LocalStack.key)),
                "format": d(e.format), "targetReadiness": n(e.targetReadiness), "resultScore": n(e.resultScore),
                "resultLoggedAt": t(e.resultLoggedAt), "readinessAtExam": n(e.readinessAtExam),
                "createdAt": t(e.createdAt), "updatedAt": t(e.updatedAt), "deletedAt": t(e.deletedAt),
            ]
        }
        for s in app.fetch(FetchDescriptor<StudySession>()) {
            out["study_sessions", default: [:]][u(s.id)] = [
                "kind": s.kindRaw, "startedAt": t(s.startedAt), "endedAt": t(s.endedAt),
                "plannedSeconds": n(s.plannedSeconds), "activeSeconds": n(s.activeSeconds), "itemCount": d(s.itemCount),
                "correctCount": d(s.correctCount), "course": u(s.courseID), "exam": u(s.examID),
                "confusion": u(s.confusionID), "readinessBefore": n(s.readinessBefore),
                "readinessAfter": n(s.readinessAfter),
            ]
        }
        for r in app.fetch(FetchDescriptor<DayRecord>()) {
            out["day_records", default: [:]][r.dayKey] = [
                "day": t(r.day), "studySeconds": n(r.studySeconds), "itemsReviewed": d(r.itemsReviewed),
                "sessions": d(r.sessions), "frozen": d(r.frozen), "repaired": d(r.repaired),
            ]
        }
        for c in app.fetch(FetchDescriptor<Confusion>()) {
            out["confusions", default: [:]][u(c.id)] = [
                "course": u(c.course?.id), "name": c.name, "explanation": c.explanation,
                "itemIDs": d(c.itemIDs.map(LocalStack.key)), "fix": d(c.fix), "status": c.statusRaw,
                "missCount": d(c.missCount), "createdAt": t(c.createdAt), "updatedAt": t(c.updatedAt),
                "lastSeenAt": t(c.lastSeenAt), "deletedAt": t(c.deletedAt),
            ]
        }
        return out
    }

    /// Every row or field that differs between two snapshots, as `table/id.field: a ≠ b` lines.
    static func differences(_ a: [String: Table], _ b: [String: Table]) -> [String] {
        var out: [String] = []
        for table in Set(a.keys).union(b.keys).sorted() {
            let left = a[table] ?? [:], right = b[table] ?? [:]
            for id in Set(left.keys).union(right.keys).sorted() {
                guard let l = left[id] else { out.append("\(table)/\(id): only on the second device"); continue }
                guard let r = right[id] else { out.append("\(table)/\(id): only on the first device"); continue }
                for field in Set(l.keys).union(r.keys).sorted() where l[field] != r[field] {
                    out.append("\(table)/\(id).\(field): \(l[field] ?? "-") ≠ \(r[field] ?? "-")")
                }
            }
        }
        return out
    }

    static func counts(_ snapshot: [String: Table]) -> [String: Int] { snapshot.mapValues(\.count) }
}
