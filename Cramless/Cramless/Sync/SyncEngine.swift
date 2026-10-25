import Foundation
import SwiftData

/// Keeps the person's study data in their Supabase account, local-first: every change lands on the device and is
/// pushed afterwards; other devices' changes are pulled and merged.
///
/// - Runs only in `relay` mode with a signed-in (non-anonymous) account; everywhere else it does nothing.
/// - Push: rows where `syncedAt == nil || updatedAt > syncedAt`, in batches; `syncedAt` becomes the `updatedAt`
///   that was sent, so an edit made during the push goes up next time. Review logs are append-only (inserted
///   once, never updated). Sessions and day records have no `updatedAt` on the device and use their own rules.
/// - Pull: each table from its cursor (the server's `synced_at`), a minute early for late commits, page by page.
///   A server row replaces the local one only when its `updated_at` is newer (last writer wins). Deletions are
///   tombstones (`deletedAt`), never hard deletes. Day records merge (the larger count wins).
/// - Page photos go to the private `sources` bucket only with "Send page photos" on; other devices fetch them.
///   Chats never sync.
/// - A different account on this device resets every `syncedAt`, so the new account receives everything.
@MainActor
@Observable
final class SyncEngine {
    @ObservationIgnored weak var app: AppModel?

    /// The pause before a requested push: edits come in bursts.
    @ObservationIgnored var debounce: Duration = .seconds(2)
    /// Rows per pull page and per upsert (tests lower them).
    static var pageSize = 500
    static var batchSize = 200
    /// A pull starts this many seconds before its cursor, for rows whose transaction committed late.
    static let overlap: TimeInterval = 60
    /// An incremental push looks this far back before the previous push started (clock adjustments).
    static let pushLookback: TimeInterval = 600

    /// The last failure, for a "couldn't sync" line in Settings. Nil after a clean run.
    private(set) var lastError: RelayError?
    /// When the last run finished cleanly ("Synced 2 minutes ago").
    private(set) var lastSyncedAt: Date?
    /// A run is in progress.
    private(set) var isSyncing = false

    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var chain: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    /// Sync is on: a configured project and a real account.
    var isEnabled: Bool {
        guard let app, app.config.aiMode == .relay else { return false }
        let account = app.account
        return account.client != nil && account.isSignedIn && !account.isSimulatedAccount && account.userID != nil
    }

    // MARK: Entry points

    /// Pushes after a short pause; repeated calls restart the pause.
    func pushSoon() {
        guard let app, app.config.aiMode == .relay else { return }
        pushTask?.cancel()
        let delay = debounce
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.pushNow()
        }
    }

    func pushNow() async {
        await run { try await $0.performPush(fullScan: false) }
    }

    func pullNow() async {
        await run { try await $0.performPull() }
    }

    /// Pull, then push everything that differs (launch, sign-in, the Settings button).
    func syncNow() async {
        await run { engine in
            try await engine.performPull()
            try await engine.performPush(fullScan: true)
        }
    }

    /// Forgets cursors and the synced account (account deletion, a local wipe).
    func resetLedger() {
        guard let app else { return }
        SyncLedger.clear(in: app.defaults)
        lastError = nil
        lastSyncedAt = nil
    }

    /// Runs one job at a time, in order.
    private func run(_ work: @escaping @MainActor (SyncEngine) async throws -> Void) async {
        let previous = chain
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, let app = self.app else { return }
            guard app.config.aiMode == .relay else { return }
            await app.account.pushProfileIfNeeded()
            guard self.isEnabled else { return }
            self.isSyncing = true
            defer { self.isSyncing = false }
            do {
                try self.prepare()
                try await work(self)
                self.lastError = nil
                self.lastSyncedAt = Date()
            } catch let error as RelayError {
                self.lastError = error
                AppConfig.log.error("sync failed: \(String(describing: error), privacy: .public)")
            } catch {
                self.lastError = .upstream(error.localizedDescription)
                AppConfig.log.error("sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        chain = task
        await task.value
    }

    /// A new account on this device: everything goes up to it, and every cursor starts over.
    private func prepare() throws {
        guard let app, let userID = app.account.userID else { throw RelayError.unauthorized }
        var ledger = SyncLedger.load(from: app.defaults)
        guard ledger.userID != userID else { return }
        resetSyncStamps()
        ledger = SyncLedger()
        ledger.userID = userID
        ledger.save(to: app.defaults)
    }

    private func resetSyncStamps() {
        guard let app else { return }
        for m in app.fetch(FetchDescriptor<Course>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<Topic>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<Source>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<StudyItem>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<ReviewLog>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<Exam>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<StudySession>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<DayRecord>()) { m.syncedAt = nil }
        for m in app.fetch(FetchDescriptor<Confusion>()) { m.syncedAt = nil }
        try? app.context.save()
    }

    // MARK: Push

    private func performPush(fullScan: Bool) async throws {
        guard let app, let client = app.account.client else { return }
        var ledger = SyncLedger.load(from: app.defaults)
        let startedAt = Date()
        let since: Date = fullScan ? .distantPast
            : (ledger.lastPushStartedAt?.addingTimeInterval(-Self.pushLookback) ?? .distantPast)
        let token = try await app.account.currentAccessToken()

        let courses = app.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.syncedAt == nil || $0.updatedAt > since }))
            .filter { Self.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt) }
        try await push(courses, table: "courses", client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { $0.updatedAt }, mark: { $0.syncedAt = $1 })

        let topics = app.fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.syncedAt == nil || $0.updatedAt > since }))
            .filter { Self.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt) }
        try await push(topics, table: "topics", client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { $0.updatedAt }, mark: { $0.syncedAt = $1 })

        let sources = app.fetch(FetchDescriptor<Source>(predicate: #Predicate { $0.syncedAt == nil || $0.updatedAt > since }))
            .filter { Self.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt) }
        try await pushSources(sources, client: client, token: token)

        let items = app.fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.syncedAt == nil || $0.updatedAt > since }))
            .filter { Self.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt) }
        try await push(items, table: "items", client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { $0.updatedAt }, mark: { $0.syncedAt = $1 })

        let exams = app.fetch(FetchDescriptor<Exam>(predicate: #Predicate { $0.syncedAt == nil || $0.updatedAt > since }))
            .filter { Self.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt) }
        try await push(exams, table: "exams", client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { $0.updatedAt }, mark: { $0.syncedAt = $1 })

        let confusions = app.fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.syncedAt == nil || $0.updatedAt > since }))
            .filter { Self.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt) }
        try await push(confusions, table: "confusions", client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { $0.updatedAt }, mark: { $0.syncedAt = $1 })

        // A session can run for hours; look back a day from `since` for ones that ended since.
        let sessionSince = since == .distantPast ? since : since.addingTimeInterval(-86_400)
        let sessions = app.fetch(FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.syncedAt == nil || $0.startedAt > sessionSince
        })).filter { Self.isDirty(updatedAt: SyncRecords.stamp($0), syncedAt: $0.syncedAt) }
        try await push(sessions, table: "study_sessions", client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { SyncRecords.stamp($0) }, mark: { $0.syncedAt = $1 })

        // Today's and yesterday's records keep changing; older ones go up once (or again after a merge).
        let yesterday = app.calendar.dayKey(for: app.calendar.date(byAdding: .day, value: -1, to: app.now) ?? app.now)
        let days = app.fetch(FetchDescriptor<DayRecord>()).filter { $0.syncedAt == nil || $0.dayKey >= yesterday }
        let pushedAt = Date()
        try await push(days, table: "day_records", onConflict: "user_id,day_key", client: client, token: token,
                       row: { SyncRecords.row($0, now: pushedAt) }, stamp: { _ in pushedAt }, mark: { $0.syncedAt = $1 })

        let logs = app.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.syncedAt == nil }))
        try await push(logs, table: "review_logs", ignoreDuplicates: true, client: client, token: token,
                       row: { SyncRecords.row($0) }, stamp: { _ in pushedAt }, mark: { $0.syncedAt = $1 })

        try await pushPageImages(client: client, token: token)

        ledger = SyncLedger.load(from: app.defaults)
        ledger.lastPushStartedAt = startedAt
        ledger.save(to: app.defaults)
    }

    // MARK: Page photos

    /// Photos uploaded or downloaded per run, so a big library trickles instead of stalling a sync.
    static var imageBatch = 20

    /// Uploads page photos this device holds to `sources/<user>/<source>/<page>.<ext>` (once per page), then
    /// points the page's `image_path` at it so other devices can fetch it. Only with "Send page photos" on:
    /// without it, photos never leave the iPhone (the text and lines still sync).
    private func pushPageImages(client: SupabaseClient, token: String) async throws {
        guard let app, app.settings.sendPhotos, let userID = app.account.userID else { return }
        let uploaded = SyncLedger.load(from: app.defaults).uploadedPageIDs
        let pages = app.fetch(FetchDescriptor<SourcePage>(predicate: #Predicate { $0.imageFileName != nil }))
            .filter { !uploaded.contains(Self.key($0.id)) && $0.source != nil }
        for page in pages.prefix(Self.imageBatch) {
            guard let file = page.imageFileName, let source = page.source,
                  let data = try? Data(contentsOf: FileStore.url(for: file)) else { continue }
            let ext = (file as NSString).pathExtension.lowercased()
            let type = switch ext {
            case "png": "image/png"
            case "heic": "image/heic"
            default: "image/jpeg"
            }
            let path = "\(userID)/\(Self.key(source.id))/\(Self.key(page.id)).\(ext.isEmpty ? "jpg" : ext)"
            try await client.upload(bucket: "sources", path: path, data: data, contentType: type, token: token)
            try await client.update(table: "source_pages", id: Self.key(page.id), values: ["image_path": .string(path)],
                                    token: token)
            var ledger = SyncLedger.load(from: app.defaults)
            ledger.uploadedPageIDs.insert(Self.key(page.id))
            ledger.save(to: app.defaults)
        }
    }

    /// Fetches photos other devices uploaded for pages that have none here.
    private func downloadPageImages(client: SupabaseClient, token: String) async {
        guard let app else { return }
        let pending = SyncLedger.load(from: app.defaults).pendingDownloads
        guard !pending.isEmpty else { return }
        var changed = false
        for (pageKey, path) in pending.sorted(by: { $0.key < $1.key }).prefix(Self.imageBatch) {
            guard let id = UUID(uuidString: pageKey),
                  let page = pages([id])[id], page.imageFileName == nil, let source = page.source else {
                forgetDownload(pageKey)
                continue
            }
            guard let data = try? await client.download(bucket: "sources", path: path, token: token) else { continue }
            let ext = (path as NSString).pathExtension
            if let relative = try? FileStore.write(data, folder: "sync/\(Self.key(source.id))",
                                                   name: "\(pageKey).\(ext.isEmpty ? "jpg" : ext)") {
                page.imageFileName = relative
                changed = true
            }
            forgetDownload(pageKey)
        }
        if changed { app.save() }
    }

    private func forgetDownload(_ pageKey: String) {
        guard let app else { return }
        var ledger = SyncLedger.load(from: app.defaults)
        ledger.pendingDownloads[pageKey] = nil
        ledger.save(to: app.defaults)
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    static func isDirty(updatedAt: Date, syncedAt: Date?) -> Bool {
        guard let syncedAt else { return true }
        return updatedAt > syncedAt
    }

    private func push<M: PersistentModel>(_ models: [M], table: String, onConflict: String = "id",
                                          ignoreDuplicates: Bool = false, client: SupabaseClient, token: String,
                                          row: (M) -> SyncRow, stamp: (M) -> Date,
                                          mark: (M, Date) -> Void) async throws {
        for start in stride(from: 0, to: models.count, by: Self.batchSize) {
            let batch = Array(models[start..<min(start + Self.batchSize, models.count)])
            let stamps = batch.map(stamp)
            let rows = batch.map(row)
            try await client.upsert(table: table, rows: rows, onConflict: onConflict,
                                    ignoreDuplicates: ignoreDuplicates, token: token)
            for (model, value) in zip(batch, stamps) where model.modelContext != nil { mark(model, value) }
            try? app?.context.save()
        }
    }

    /// Sources go up with all their pages (pages have no stamps of their own).
    private func pushSources(_ sources: [Source], client: SupabaseClient, token: String) async throws {
        for start in stride(from: 0, to: sources.count, by: Self.batchSize) {
            let batch = Array(sources[start..<min(start + Self.batchSize, sources.count)])
            let stamps = batch.map(\.updatedAt)
            try await client.upsert(table: "sources", rows: batch.map { SyncRecords.row($0) }, onConflict: "id",
                                    token: token)
            let pages = batch.flatMap { source in source.sortedPages.map { SyncRecords.row($0, source: source) } }
            for pageStart in stride(from: 0, to: pages.count, by: Self.batchSize) {
                let chunk = Array(pages[pageStart..<min(pageStart + Self.batchSize, pages.count)])
                try await client.upsert(table: "source_pages", rows: chunk, onConflict: "id", token: token)
            }
            for (source, value) in zip(batch, stamps) where source.modelContext != nil { source.syncedAt = value }
            try? app?.context.save()
        }
    }

    // MARK: Pull

    /// What one pull knows: the local courses and sources by id (rows point at them) and whether anything changed.
    private final class PullState {
        var courses: [UUID: Course] = [:]
        var sources: [UUID: Source] = [:]
        var changed = false

        var resolver: SyncResolver {
            SyncResolver(course: { [unowned self] id in id.flatMap { self.courses[$0] } },
                         source: { [unowned self] id in id.flatMap { self.sources[$0] } })
        }
    }

    private func performPull() async throws {
        guard let app, let client = app.account.client else { return }
        let token = try await app.account.currentAccessToken()
        let context = app.context
        let state = PullState()
        for course in app.fetch(FetchDescriptor<Course>()) { state.courses[course.id] = course }
        for source in app.fetch(FetchDescriptor<Source>()) { state.sources[source.id] = source }

        try await pull("courses", client: client, token: token) { rows in
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = state.courses[id] {
                    guard Self.isNewer(updated, than: local.updatedAt) else { continue }
                    SyncRecords.fill(local, from: row)
                    local.updatedAt = updated
                    local.syncedAt = updated
                } else if let course = SyncRecords.makeCourse(row) {
                    course.updatedAt = updated
                    course.syncedAt = updated
                    context.insert(course)
                    state.courses[id] = course
                }
                state.changed = true
            }
        }

        try await pull("topics", client: client, token: token) { rows in
            let existing = self.topics(Self.ids(rows))
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = existing[id] {
                    guard Self.isNewer(updated, than: local.updatedAt) else { continue }
                    SyncRecords.fill(local, from: row, state.resolver)
                    local.updatedAt = updated
                    local.syncedAt = updated
                } else if let topic = SyncRecords.makeTopic(row, state.resolver) {
                    topic.updatedAt = updated
                    topic.syncedAt = updated
                    context.insert(topic)
                }
                state.changed = true
            }
        }

        try await pull("sources", client: client, token: token) { rows in
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = state.sources[id] {
                    guard Self.isNewer(updated, than: local.updatedAt) else { continue }
                    SyncRecords.fill(local, from: row, state.resolver)
                    local.updatedAt = updated
                    local.syncedAt = updated
                } else if let source = SyncRecords.makeSource(row, state.resolver) {
                    source.updatedAt = updated
                    source.syncedAt = updated
                    context.insert(source)
                    state.sources[id] = source
                }
                state.changed = true
            }
        }

        try await pull("source_pages", client: client, token: token) { rows in
            let existing = self.pages(Self.ids(rows))
            var wanted: [String: String] = [:]
            for row in rows {
                guard let id = row.uuid("id"), let source = state.sources[row.uuid("source_id") ?? UUID()] else { continue }
                // A source with unpushed edits keeps its own pages; otherwise the server's pages are the truth.
                if Self.isDirty(updatedAt: source.updatedAt, syncedAt: source.syncedAt) { continue }
                let page: SourcePage
                if let local = existing[id] {
                    page = local
                    if Self.pageDiffers(local, row) {
                        SyncRecords.fill(local, from: row)
                        state.changed = true
                    }
                } else if let made = SyncRecords.makePage(row, source: source) {
                    context.insert(made)
                    page = made
                    state.changed = true
                } else {
                    continue
                }
                if page.imageFileName == nil, let path = row.string("image_path"), !path.isEmpty {
                    wanted[Self.key(id)] = path
                }
            }
            if !wanted.isEmpty {
                var ledger = SyncLedger.load(from: app.defaults)
                ledger.pendingDownloads.merge(wanted) { _, new in new }
                ledger.save(to: app.defaults)
            }
        }

        try await pull("items", client: client, token: token) { rows in
            let existing = self.items(Self.ids(rows))
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = existing[id] {
                    guard Self.isNewer(updated, than: local.updatedAt) else { continue }
                    SyncRecords.fill(local, from: row, state.resolver)
                    local.updatedAt = updated
                    local.syncedAt = updated
                } else if let item = SyncRecords.makeItem(row, state.resolver) {
                    item.updatedAt = updated
                    item.syncedAt = updated
                    context.insert(item)
                }
                state.changed = true
            }
        }

        try await pull("exams", client: client, token: token) { rows in
            let existing = self.exams(Self.ids(rows))
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = existing[id] {
                    guard Self.isNewer(updated, than: local.updatedAt) else { continue }
                    SyncRecords.fill(local, from: row, state.resolver)
                    local.updatedAt = updated
                    local.syncedAt = updated
                } else if let exam = SyncRecords.makeExam(row, state.resolver) {
                    exam.updatedAt = updated
                    exam.syncedAt = updated
                    context.insert(exam)
                }
                state.changed = true
            }
        }

        try await pull("confusions", client: client, token: token) { rows in
            let existing = self.confusions(Self.ids(rows))
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = existing[id] {
                    guard Self.isNewer(updated, than: local.updatedAt) else { continue }
                    SyncRecords.fill(local, from: row, state.resolver)
                    local.updatedAt = updated
                    local.syncedAt = updated
                } else if let confusion = SyncRecords.makeConfusion(row, state.resolver) {
                    confusion.updatedAt = updated
                    confusion.syncedAt = updated
                    context.insert(confusion)
                }
                state.changed = true
            }
        }

        try await pull("study_sessions", client: client, token: token) { rows in
            let existing = self.sessions(Self.ids(rows))
            for row in rows {
                guard let id = row.uuid("id"), let updated = row.date("updated_at") else { continue }
                if let local = existing[id] {
                    guard Self.isNewer(updated, than: SyncRecords.stamp(local)) else { continue }
                    SyncRecords.fill(local, from: row)
                    local.syncedAt = updated
                } else if let session = SyncRecords.makeSession(row) {
                    session.syncedAt = updated
                    context.insert(session)
                }
                state.changed = true
            }
        }

        try await pull("day_records", key: "day_key", client: client, token: token) { rows in
            let keys = rows.compactMap { $0.string("day_key") }
            let existing = self.days(keys)
            for row in rows {
                guard let key = row.string("day_key") else { continue }
                if let local = existing[key] {
                    if SyncRecords.merge(local, with: row) { state.changed = true }
                    // The server holds less than this device knows: send the merged record back up.
                    local.syncedAt = SyncRecords.serverIsBehind(local, row) ? nil : (local.syncedAt ?? Date())
                } else if let day = SyncRecords.makeDay(row) {
                    day.syncedAt = Date()
                    context.insert(day)
                    state.changed = true
                }
            }
        }

        try await pull("review_logs", client: client, token: token) { rows in
            let existing = self.reviewLogIDs(Self.ids(rows))
            for row in rows {
                guard let id = row.uuid("id"), !existing.contains(id), let log = SyncRecords.makeReviewLog(row) else {
                    continue
                }
                log.syncedAt = Date()
                context.insert(log)
                state.changed = true
            }
        }

        if state.changed {
            app.save()
        } else {
            try? context.save()
        }
        await downloadPageImages(client: client, token: token)
    }

    /// Pulls one table page by page from its cursor and applies each page; the cursor moves after every page.
    private func pull(_ table: String, key: String = "id", client: SupabaseClient, token: String,
                      apply: ([SyncRow]) -> Void) async throws {
        guard let app else { return }
        var after: SyncLedger.Cursor? = SyncLedger.load(from: app.defaults).cursors[table].map { cursor in
            let early = SupabaseDate.parse(cursor.syncedAt).map { SupabaseDate.format($0.addingTimeInterval(-Self.overlap)) }
            return SyncLedger.Cursor(syncedAt: early ?? cursor.syncedAt, key: "")
        }
        while true {
            var query: [(String, String)] = [("select", "*")]
            if let after { query.append(Self.cursorFilter(after, key: key)) }
            query.append(("order", "synced_at.asc,\(key).asc"))
            query.append(("limit", "\(Self.pageSize)"))
            let rows = try await client.select(table: table, rawQuery: query, token: token)
            if rows.isEmpty { break }
            apply(rows)
            guard let last = rows.last, let stamp = last.string("synced_at"), let lastKey = last.string(key) else { break }
            let cursor = SyncLedger.Cursor(syncedAt: stamp, key: lastKey)
            var ledger = SyncLedger.load(from: app.defaults)
            if let stored = ledger.cursors[table], Self.cursor(stored, isAfter: cursor) {
                // The overlap re-read older rows: keep the stored cursor.
            } else {
                ledger.cursors[table] = cursor
                ledger.save(to: app.defaults)
            }
            after = cursor
            if rows.count < Self.pageSize { break }
        }
    }

    /// `synced_at > ts`, or after a page: `(synced_at, key) > (ts, key)` so rows sharing a stamp aren't skipped.
    static func cursorFilter(_ cursor: SyncLedger.Cursor, key: String) -> (String, String) {
        let ts = SupabaseClient.percentEncode(cursor.syncedAt)
        if cursor.key.isEmpty { return ("synced_at", "gt.\(ts)") }
        let value = SupabaseClient.percentEncode(cursor.key)
        return ("or", "(synced_at.gt.%22\(ts)%22,and(synced_at.eq.%22\(ts)%22,\(key).gt.%22\(value)%22))")
    }

    static func cursor(_ a: SyncLedger.Cursor, isAfter b: SyncLedger.Cursor) -> Bool {
        guard let da = SupabaseDate.parse(a.syncedAt), let db = SupabaseDate.parse(b.syncedAt) else { return false }
        let ma = SupabaseDate.micros(da), mb = SupabaseDate.micros(db)
        return ma > mb || (ma == mb && a.key > b.key)
    }

    /// Last writer wins at the server's grain (microseconds), so a row's own echo never looks newer.
    static func isNewer(_ server: Date, than local: Date) -> Bool {
        SupabaseDate.micros(server) > SupabaseDate.micros(local)
    }

    static func ids(_ rows: [SyncRow]) -> [UUID] { rows.compactMap { $0.uuid("id") } }

    static func pageDiffers(_ page: SourcePage, _ row: SyncRow) -> Bool {
        page.pageIndex != (row.int("page_index") ?? page.pageIndex) || page.label != (row.string("label") ?? page.label)
            || page.text != (row.string("text") ?? page.text) || page.width != (row.double("width") ?? page.width)
            || page.height != (row.double("height") ?? page.height)
            || JSONValue.blob(page.linesData) != (row["lines"] ?? .null)
    }

    // MARK: Lookups by id

    private func topics(_ ids: [UUID]) -> [UUID: Topic] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<Topic>(predicate: #Predicate { ids.contains($0.id) })), \.id)
    }

    private func pages(_ ids: [UUID]) -> [UUID: SourcePage] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<SourcePage>(predicate: #Predicate { ids.contains($0.id) })), \.id)
    }

    private func items(_ ids: [UUID]) -> [UUID: StudyItem] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { ids.contains($0.id) })), \.id)
    }

    private func exams(_ ids: [UUID]) -> [UUID: Exam] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<Exam>(predicate: #Predicate { ids.contains($0.id) })), \.id)
    }

    private func confusions(_ ids: [UUID]) -> [UUID: Confusion] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<Confusion>(predicate: #Predicate { ids.contains($0.id) })), \.id)
    }

    private func sessions(_ ids: [UUID]) -> [UUID: StudySession] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { ids.contains($0.id) })), \.id)
    }

    private func days(_ keys: [String]) -> [String: DayRecord] {
        guard let app else { return [:] }
        return Self.byID(app.fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { keys.contains($0.dayKey) })), \.dayKey)
    }

    private func reviewLogIDs(_ ids: [UUID]) -> Set<UUID> {
        guard let app else { return [] }
        return Set(app.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { ids.contains($0.id) })).map(\.id))
    }

    private static func byID<M, K: Hashable>(_ models: [M], _ key: KeyPath<M, K>) -> [K: M] {
        Dictionary(models.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { first, _ in first })
    }
}
