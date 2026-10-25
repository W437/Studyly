import Foundation

/// What sync remembers between runs, in UserDefaults: whose data this device last synced, how far each table's
/// pull got (the server's raw `synced_at` text plus the row key, so pages never skip rows that share a stamp),
/// when the last push started, which page photos are uploaded and which still need downloading.
struct SyncLedger: Codable, Equatable, Sendable {
    struct Cursor: Codable, Equatable, Sendable {
        /// `synced_at` exactly as the server sent it.
        var syncedAt: String
        /// The row's key (`id`, or `day_key` for day records).
        var key: String
    }

    var userID: String?
    var cursors: [String: Cursor] = [:]
    var lastPushStartedAt: Date?
    /// Page ids (lowercased) whose photo is in the `sources` bucket.
    var uploadedPageIDs: Set<String> = []
    /// Page id (lowercased) → bucket path, for photos another device uploaded and this one hasn't fetched yet.
    var pendingDownloads: [String: String] = [:]

    init(userID: String? = nil) {
        self.userID = userID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decodeIfPresent(String.self, forKey: .userID)
        cursors = try c.decodeIfPresent([String: Cursor].self, forKey: .cursors) ?? [:]
        lastPushStartedAt = try c.decodeIfPresent(Date.self, forKey: .lastPushStartedAt)
        uploadedPageIDs = try c.decodeIfPresent(Set<String>.self, forKey: .uploadedPageIDs) ?? []
        pendingDownloads = try c.decodeIfPresent([String: String].self, forKey: .pendingDownloads) ?? [:]
    }

    static let defaultsKey = "capling.sync.ledger.v1"

    static func load(from defaults: UserDefaults) -> SyncLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder.cramlessSync.decode(SyncLedger.self, from: data) else { return SyncLedger() }
        return ledger
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder.cramlessSync.encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
