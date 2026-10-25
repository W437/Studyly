import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// A fake Supabase project behind a URLProtocol: records every request and answers from routes. No network.
/// Each server answers its own made-up host (`baseURL`), so tests stay isolated.
final class StubServer: @unchecked Sendable {
    struct Request {
        var method: String
        var url: URL
        var headers: [String: String]
        var body: Data?

        var path: String { url.path }
        /// The query exactly as sent (percent-encoded).
        var rawQuery: String { URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? "" }
        func query(_ name: String) -> String? {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        var json: Any? { body.flatMap { try? JSONSerialization.jsonObject(with: $0) } }
        var object: [String: Any]? { json as? [String: Any] }
        var rows: [[String: Any]] { (json as? [[String: Any]]) ?? [] }
    }

    struct Response {
        var status: Int
        var body: Data
        var delay: TimeInterval = 0
        var error: URLError?

        static func json(_ data: Data, status: Int = 200, delay: TimeInterval = 0) -> Response {
            Response(status: status, body: data, delay: delay)
        }
        static func json(_ object: Any, status: Int = 200, delay: TimeInterval = 0) -> Response {
            Response(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), delay: delay)
        }
        static func empty(_ status: Int = 201) -> Response { Response(status: status, body: Data()) }
        static func failure(_ code: URLError.Code) -> Response { Response(status: 0, body: Data(), error: URLError(code)) }
    }

    let id = UUID().uuidString
    /// Requests are routed by host: each server answers its own made-up project.
    var host: String { "s\(id.replacingOccurrences(of: "-", with: "").lowercased()).stub.test" }
    var baseURL: URL { URL(string: "https://\(host)")! }
    private let lock = NSLock()
    private var recorded: [Request] = []
    private var routes: [(method: String, path: String, respond: @Sendable (Request) -> Response)] = []

    init() { StubURLProtocol.register(self) }
    deinit { StubURLProtocol.unregister(host) }

    /// Answers `method path` (the last matching route wins, so tests can override).
    func on(_ method: String, _ path: String, _ respond: @escaping @Sendable (Request) -> Response) {
        lock.lock()
        routes.append((method, path, respond))
        lock.unlock()
    }

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func requests(_ method: String, _ path: String) -> [Request] {
        requests.filter { $0.method == method && $0.path == path }
    }

    func handle(_ request: Request) -> Response {
        lock.lock()
        recorded.append(request)
        let route = routes.last { $0.method == request.method && $0.path == request.path }
        lock.unlock()
        if let route { return route.respond(request) }
        // Defaults: empty selects, accepted writes.
        return request.method == "GET" ? .json(Data("[]".utf8)) : .empty(201)
    }

    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer) {
        lock.lock()
        servers[server.host] = server
        lock.unlock()
    }

    static func unregister(_ host: String) {
        lock.lock()
        servers[host] = nil
        lock.unlock()
    }

    private static func server(_ host: String?) -> StubServer? {
        guard let host else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return servers[host]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = Self.server(url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let headers = request.allHTTPHeaderFields ?? [:]
        let recorded = StubServer.Request(method: request.httpMethod ?? "GET", url: url, headers: headers,
                                          body: request.httpBody ?? Self.read(request.httpBodyStream))
        let response = server.handle(recorded)
        let deliver = { [weak self] in
            guard let self else { return }
            if let error = response.error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A thread-safe counter for routes that answer differently on each call.
final class StubCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Builders shared by the Sync and Backend tests.
enum BackendTest {
    static let userID = "11111111-1111-4111-8111-111111111111"
    static let otherUserID = "22222222-2222-4222-8222-222222222222"

    static func config(_ mode: AppConfig.AIMode = .relay, server: StubServer? = nil,
                       environment: [String: String] = [:], isHarness: Bool = false) -> AppConfig {
        AppConfig(supabaseURL: mode == .local ? nil : (server?.baseURL ?? URL(string: "https://test.supabase.co")),
                  supabaseAnonKey: mode == .local ? nil : "anon-key", aiMode: mode, isHarness: isHarness,
                  inMemoryStore: true, seedDemoData: false, environment: environment)
    }

    /// An in-memory app whose account talks to `server`, with side effects off.
    @MainActor
    static func app(_ mode: AppConfig.AIMode = .relay, server: StubServer? = nil,
                    store: SessionStore = InMemorySessionStore(), environment: [String: String] = [:],
                    isHarness: Bool = false) -> AppModel {
        let config = config(mode, server: server, environment: environment, isHarness: isHarness)
        let app = AppModel(config: config, defaults: UserDefaults(suiteName: "cramless-tests-\(UUID().uuidString)")!)
        app.sideEffectsEnabled = false
        let session = server?.makeSession() ?? URLSession(configuration: .ephemeral)
        let account = AccountService(app: app, config: config, urlSession: session, store: store)
        account.mockLatency = .milliseconds(10)
        app.account = account
        return app
    }

    static func session(userID: String = userID, token: String = "access-1", refresh: String = "refresh-1",
                        expiresIn: TimeInterval = 3600, anonymous: Bool = false,
                        email: String? = "maya@example.com") -> AuthSession {
        AuthSession(accessToken: token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn),
                    userID: userID, email: anonymous ? nil : email, isAnonymous: anonymous)
    }

    /// GoTrue's session JSON.
    static func sessionJSON(userID: String = userID, token: String = "access-1", refresh: String = "refresh-1",
                            expiresIn: Int = 3600, anonymous: Bool = true, email: String? = nil) -> Data {
        var user: [String: Any] = ["id": userID, "is_anonymous": anonymous, "aud": "authenticated"]
        if let email { user["email"] = email }
        let object: [String: Any] = ["access_token": token, "token_type": "bearer", "expires_in": expiresIn,
                                     "expires_at": Int(Date().timeIntervalSince1970) + expiresIn,
                                     "refresh_token": refresh, "user": user]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func fixture(_ name: String) -> Data {
        RelayFixtures.data(name) ?? Data()
    }
}
