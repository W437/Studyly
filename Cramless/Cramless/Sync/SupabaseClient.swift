import Foundation

/// A signed-in Supabase session, kept in the Keychain between launches.
struct AuthSession: Codable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
    var isAnonymous: Bool
}

/// The Supabase project over plain URLSession: GoTrue (auth), PostgREST (sync), Edge Functions and Storage.
/// Every request carries the anon key in `apikey`; authenticated ones add the person's access token. Failures
/// surface as `RelayError`, the app's one error vocabulary for the backend.
final class SupabaseClient: Sendable {
    let baseURL: URL
    let anonKey: String
    let session: URLSession

    init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    // MARK: Auth (GoTrue)

    /// A new anonymous user: AI quotas and entitlements work without an account.
    func signUpAnonymously() async throws -> AuthSession {
        try await authSession(path: "auth/v1/signup", body: ["data": JSONValue.object([:])])
    }

    /// Sign in with Apple: the identity token from `ASAuthorizationAppleIDCredential` and the raw nonce whose
    /// SHA-256 the app put in the Apple request.
    func signInWithIdToken(provider: String, idToken: String, nonce: String?) async throws -> AuthSession {
        var body: [String: JSONValue] = ["provider": .string(provider), "id_token": .string(idToken)]
        if let nonce { body["nonce"] = .string(nonce) }
        return try await authSession(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")],
                                     body: body)
    }

    /// Emails a 6-digit sign-in code (creating the user on first use).
    func sendEmailOTP(email: String) async throws {
        _ = try await send(method: "POST", path: "auth/v1/otp",
                           body: try encode(["email": JSONValue.string(email), "create_user": .bool(true)]),
                           kind: .auth)
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        try await authSession(path: "auth/v1/verify",
                              body: ["type": .string("email"), "email": .string(email), "token": .string(code)])
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        try await authSession(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                              body: ["refresh_token": .string(refreshToken)])
    }

    func signOut(accessToken: String) async throws {
        _ = try await send(method: "POST", path: "auth/v1/logout", body: nil, token: accessToken, kind: .auth)
    }

    // MARK: PostgREST

    /// Upserts rows by `onConflict`. `ignoreDuplicates` inserts only (for insert-only tables).
    func upsert(table: String, rows: [SyncRow], onConflict: String, ignoreDuplicates: Bool = false,
                token: String) async throws {
        guard !rows.isEmpty else { return }
        let resolution = ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"
        _ = try await send(method: "POST", path: "rest/v1/\(table)",
                           query: [URLQueryItem(name: "on_conflict", value: onConflict)],
                           body: try encode(rows), token: token,
                           headers: ["Prefer": "resolution=\(resolution),return=minimal"], kind: .rest)
    }

    /// Updates the given columns of one row by id (leaves every other column, and `updated_at`, alone).
    func update(table: String, id: String, values: SyncRow, token: String) async throws {
        _ = try await send(method: "PATCH", path: "rest/v1/\(table)", query: [URLQueryItem(name: "id", value: "eq.\(id)")],
                           body: try encode(values), token: token, headers: ["Prefer": "return=minimal"], kind: .rest)
    }

    /// Selects rows. `rawQuery` items are sent exactly as given (already percent-encoded where needed).
    func select(table: String, rawQuery: [(String, String)], token: String) async throws -> [SyncRow] {
        let data = try await send(method: "GET", path: "rest/v1/\(table)", rawQuery: rawQuery, body: nil,
                                  token: token, kind: .rest)
        do {
            return try JSONDecoder().decode([SyncRow].self, from: data)
        } catch {
            throw RelayError.decoding("rows of \(table)")
        }
    }

    // MARK: Edge Functions

    /// Calls `/functions/v1/<path>`; non-2xx answers are the relay's error envelope.
    func invoke(_ path: String, method: String, body: Data?, token: String) async throws -> Data {
        try await send(method: method, path: "functions/v1/\(path)", body: body, token: token, kind: .function)
    }

    // MARK: Storage

    func upload(bucket: String, path: String, data: Data, contentType: String, token: String) async throws {
        _ = try await send(method: "POST", path: "storage/v1/object/\(bucket)/\(path)", body: data, token: token,
                           headers: ["x-upsert": "true", "Content-Type": contentType], kind: .storage)
    }

    func download(bucket: String, path: String, token: String) async throws -> Data {
        try await send(method: "GET", path: "storage/v1/object/authenticated/\(bucket)/\(path)", body: nil,
                       token: token, kind: .storage)
    }

    // MARK: Plumbing

    enum Kind { case auth, rest, function, storage }

    private func authSession(path: String, query: [URLQueryItem] = [], body: [String: JSONValue]) async throws
        -> AuthSession {
        let data = try await send(method: "POST", path: path, query: query, body: try encode(body), kind: .auth)
        guard let session = Self.parseSession(data) else { throw RelayError.decoding("auth session") }
        return session
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder().encode(value) } catch { throw RelayError.badRequest("unencodable body") }
    }

    @discardableResult
    func send(method: String, path: String, query: [URLQueryItem] = [], rawQuery: [(String, String)] = [],
              body: Data?, token: String? = nil, headers: [String: String] = [:], kind: Kind) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        var encoded: [String] = (components?.percentEncodedQuery.map { [$0] } ?? [])
        for item in query {
            encoded.append("\(Self.percentEncode(item.name))=\(Self.percentEncode(item.value ?? ""))")
        }
        for (name, value) in rawQuery { encoded.append("\(name)=\(value)") }
        if !encoded.isEmpty { components?.percentEncodedQuery = encoded.joined(separator: "&") }
        guard let url = components?.url else { throw RelayError.badRequest("bad URL \(path)") }

        var request = URLRequest(url: url, timeoutInterval: kind == .function ? 90 : 30)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(kind == .storage ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw RelayError.cancelled
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw RelayError.upstream(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw RelayError.upstream("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data, kind: kind)
        }
        return data
    }

    static func map(_ error: URLError) -> RelayError {
        switch error.code {
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            .offline
        default: .upstream(error.localizedDescription)
        }
    }

    /// Maps a failed response: the relay's envelope for functions, GoTrue's and PostgREST's own bodies otherwise.
    static func error(status: Int, data: Data, kind: Kind) -> RelayError {
        if let envelope = try? JSONDecoder.cramless.decode(RelayErrorBody.self, from: data) {
            return RelayError.from(code: envelope.error.code, message: envelope.error.message,
                                   quota: envelope.error.quota)
        }
        let message = messageOf(data) ?? "HTTP \(status)"
        switch status {
        case 401, 403: return .unauthorized
        case 400, 404, 405, 409, 413, 415, 422, 429: return .badRequest(message)
        default:
            if kind == .function, status < 500 { return .badRequest(message) }
            return .upstream(message)
        }
    }

    private static func messageOf(_ data: Data) -> String? {
        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        for key in ["msg", "message", "error_description", "error"] {
            if let text = object[key]?.stringValue, !text.isEmpty { return text }
        }
        return nil
    }

    /// GoTrue's session JSON: `{access_token, expires_in, expires_at, refresh_token, user: {id, email, is_anonymous}}`.
    static func parseSession(_ data: Data, now: Date = Date()) -> AuthSession? {
        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              let access = object.string("access_token"), let refresh = object.string("refresh_token"),
              case .object(let user)? = object["user"], let id = user.string("id") else { return nil }
        let expiresAt: Date
        if let at = object.double("expires_at") {
            expiresAt = Date(timeIntervalSince1970: at)
        } else {
            expiresAt = now.addingTimeInterval(object.double("expires_in") ?? 3600)
        }
        let email = user.string("email").flatMap { $0.isEmpty ? nil : $0 }
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, userID: id.lowercased(),
                           email: email, isAnonymous: user.bool("is_anonymous") ?? false)
    }

    /// Strict percent-encoding for query values: everything but RFC 3986's unreserved characters.
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
