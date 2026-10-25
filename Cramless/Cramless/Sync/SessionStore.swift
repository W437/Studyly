import Foundation
import Security

/// Where the auth session lives between launches.
protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

/// The Keychain (generic password, this device only, readable after first unlock so background work can refresh).
final class KeychainSessionStore: SessionStore {
    let service: String
    let account: String

    init(service: String = "com.loopware.Capling.auth", account: String = "session") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> AuthSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder.cramlessSync.decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) {
        guard let session, let data = try? JSONEncoder.cramlessSync.encode(session) else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// For tests and the screenshot harness: nothing touches the Keychain.
final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    init(_ session: AuthSession? = nil) { self.session = session }

    func load() -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func save(_ session: AuthSession?) {
        lock.lock()
        self.session = session
        lock.unlock()
    }
}

extension JSONEncoder {
    /// Sync's own encoder: ISO 8601 with fractional seconds (sessions and the ledger keep sub-second times).
    static let cramlessSync: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(SupabaseDate.format(date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let cramlessSync: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = SupabaseDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(text)")
            }
            return date
        }
        return d
    }()
}
