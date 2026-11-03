import Foundation
import SwiftData
import XCTest
@testable import Cramless

private func rowID(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

private func courseRow(_ uuid: UUID, name: String, updated: Date, synced: String, deleted: Date? = nil) -> [String: Any] {
    ["id": rowID(uuid), "user_id": BackendTest.userID, "name": name, "color": "rose", "symbol": "leaf",
     "sort_order": 1, "created_at": SupabaseDate.format(updated), "updated_at": SupabaseDate.format(updated),
     "deleted_at": deleted.map { SupabaseDate.format($0) as Any } ?? NSNull(), "synced_at": synced]
}

/// SyncEngine against a stubbed PostgREST: what goes up, how pulled rows merge, cursors and account changes.
@MainActor
final class SyncEngineTests: XCTestCase {
    override func tearDown() async throws {
        SyncEngine.pageSize = 500
        SyncEngine.batchSize = 200
        try await super.tearDown()
    }

    /// A signed-in app whose ledger already belongs to the same account (no reset on the first run).
    private func signedInApp(_ server: StubServer) -> AppModel {
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        SyncLedger(userID: BackendTest.userID).save(to: app.defaults)
        return app
    }

    private func id(_ uuid: UUID) -> String { rowID(uuid) }

    // MARK: Push

    func testPushSendsOnlyDirtyRowsInSnakeCaseWithoutTheOwner() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let t0 = Date().addingTimeInterval(-120)
        let dirty = Course(name: "Bio 101", color: .mint, sortOrder: 2, now: t0)
        let clean = Course(name: "Chem", now: t0)
        clean.syncedAt = t0
        app.context.insert(dirty)
        app.context.insert(clean)
        let item = StudyItem(course: dirty, kind: .mcq, status: .active, origin: .cloud, prompt: "Which phase?",
                             answer: "Metaphase", choices: [Choice(text: "Metaphase", correct: true)], now: t0)
        item.memory = MemoryState(state: .review, stability: 3.5, difficulty: 5, due: t0.addingTimeInterval(86_400),
                                  lastReview: t0, reps: 2, lapses: 1, step: 0)
        app.context.insert(item)
        let session = StudySession(kind: .daily, startedAt: t0, plannedSeconds: 900)
        app.context.insert(session)
        try app.context.save()

        await app.sync.pushNow()
        XCTAssertNil(app.sync.lastError)

        let courses = server.requests("POST", "/rest/v1/courses")
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.rows.count, 1)
        let row = try XCTUnwrap(courses.first?.rows.first)
        XCTAssertEqual(row["id"] as? String, id(dirty.id))
        XCTAssertEqual(row["name"] as? String, "Bio 101")
        XCTAssertEqual(row["color"] as? String, "mint")
        XCTAssertEqual(row["sort_order"] as? Int, 2)
        XCTAssertEqual(row["updated_at"] as? String, SupabaseDate.format(t0))
        XCTAssertTrue(row["deleted_at"] is NSNull, "nil goes up as an explicit null")
        XCTAssertNil(row["user_id"])
        XCTAssertNil(row["synced_at"])
        XCTAssertEqual(courses.first?.query("on_conflict"), "id")
        XCTAssertEqual(courses.first?.header("Prefer"), "resolution=merge-duplicates,return=minimal")
        XCTAssertEqual(courses.first?.header("Authorization"), "Bearer access-1")
        XCTAssertEqual(dirty.syncedAt, dirty.updatedAt)

        let itemRow = try XCTUnwrap(server.requests("POST", "/rest/v1/items").first?.rows.first)
        XCTAssertEqual(itemRow["course_id"] as? String, id(dirty.id))
        XCTAssertEqual(itemRow["kind"] as? String, "mcq")
        XCTAssertEqual(itemRow["status"] as? String, "active")
        XCTAssertEqual(((itemRow["choices"] as? [[String: Any]])?.first)?["text"] as? String, "Metaphase",
                       "blobs go up as embedded JSON")
        XCTAssertTrue(itemRow["key_ideas"] is NSNull)
        XCTAssertEqual(itemRow["state"] as? Int, 2)
        XCTAssertEqual(itemRow["stability"] as? Double, 3.5)
        XCTAssertEqual(itemRow["lapses"] as? Int, 1)
        XCTAssertEqual(itemRow["due"] as? String, SupabaseDate.format(t0.addingTimeInterval(86_400)))
        XCTAssertNil(itemRow["user_id"])

        let sessionRow = try XCTUnwrap(server.requests("POST", "/rest/v1/study_sessions").first?.rows.first)
        XCTAssertEqual(sessionRow["updated_at"] as? String, SupabaseDate.format(t0), "a running session's stamp is its start")
        XCTAssertEqual(session.syncedAt, t0)

        // Nothing changed: nothing goes up.
        let before = server.requests.count
        await app.sync.pushNow()
        XCTAssertEqual(server.requests.count, before)
    }

    func testAnEditAfterThePushGoesUpAgain() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let course = Course(name: "Bio", now: Date().addingTimeInterval(-300))
        app.context.insert(course)
        try app.context.save()
        await app.sync.pushNow()
        XCTAssertEqual(server.requests("POST", "/rest/v1/courses").count, 1)

        course.name = "Biology"
        course.updatedAt = Date()
        try app.context.save()
        await app.sync.pushNow()

        let pushes = server.requests("POST", "/rest/v1/courses")
        XCTAssertEqual(pushes.count, 2)
        XCTAssertEqual(pushes.last?.rows.first?["name"] as? String, "Biology")
        XCTAssertEqual(course.syncedAt, course.updatedAt)
    }

    func testAFailedPushLeavesRowsDirty() async throws {
        let server = StubServer()
        server.on("POST", "/rest/v1/courses") { _ in .failure(.notConnectedToInternet) }
        let app = signedInApp(server)
        let course = Course(name: "Bio")
        app.context.insert(course)
        try app.context.save()

        await app.sync.pushNow()

        XCTAssertEqual(app.sync.lastError, .offline)
        XCTAssertNil(course.syncedAt)
    }

    func testBatchesSplitLargePushes() async throws {
        SyncEngine.batchSize = 2
        let server = StubServer()
        let app = signedInApp(server)
        for i in 0..<5 { app.context.insert(Course(name: "Course \(i)")) }
        try app.context.save()

        await app.sync.pushNow()

        XCTAssertEqual(server.requests("POST", "/rest/v1/courses").map(\.rows.count), [2, 2, 1])
    }

    func testReviewLogsAreInsertedOnceWithIgnoreDuplicates() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let itemID = UUID()
        let log = ReviewLog(itemID: itemID, courseID: nil, sessionID: nil, reviewedAt: Date(), rating: .hard, score: 0.67,
                            answer: "two identical cells", gradedBy: "cloud", durationMs: 41_000, before: .new,
                            after: MemoryState(stability: 2.3, difficulty: 6.1), elapsedDays: 0, scheduledDays: 1)
        app.context.insert(log)
        try app.context.save()

        await app.sync.pushNow()

        let insert = try XCTUnwrap(server.requests("POST", "/rest/v1/review_logs").first)
        XCTAssertEqual(insert.header("Prefer"), "resolution=ignore-duplicates,return=minimal")
        let row = try XCTUnwrap(insert.rows.first)
        XCTAssertEqual(row["item_id"] as? String, id(itemID))
        XCTAssertEqual(row["rating"] as? Int, 2)
        XCTAssertEqual(row["score"] as? Double, 0.67)
        XCTAssertEqual(row["graded_by"] as? String, "cloud")
        XCTAssertEqual(row["stability_after"] as? Double, 2.3)
        XCTAssertTrue(row["course_id"] is NSNull)
        XCTAssertNotNil(log.syncedAt)

        await app.sync.pushNow()
        XCTAssertEqual(server.requests("POST", "/rest/v1/review_logs").count, 1, "append-only: never sent again")
    }

    /// An own-words answer the person marked themselves is logged as "self": the column is free text, so it goes up as it is.
    func testAnAnswerTheyMarkedThemselvesSyncsAsSelf() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let log = ReviewLog(itemID: UUID(), courseID: nil, sessionID: nil, reviewedAt: Date(), rating: .good, score: 0.9,
                            answer: "so they can grow", gradedBy: "self", durationMs: 30_000, before: .new,
                            after: MemoryState(stability: 2.3, difficulty: 6.1), elapsedDays: 0, scheduledDays: 1)
        app.context.insert(log)
        try app.context.save()

        await app.sync.pushNow()

        let row = try XCTUnwrap(server.requests("POST", "/rest/v1/review_logs").first?.rows.first)
        XCTAssertEqual(row["graded_by"] as? String, "self")
        XCTAssertEqual(row["score"] as? Double, 0.9)
    }

    func testSourcesGoUpWithTheirPages() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let source = Source(course: nil, kind: .scan, title: "Biology textbook", status: .read)
        app.context.insert(source)
        let lines = [TextLine(id: "p0.l0", text: "Mitosis", box: NormRect(x: 0.1, y: 0.1, w: 0.5, h: 0.05))]
        app.context.insert(SourcePage(source: source, pageIndex: 0, label: "87", text: "Mitosis", lines: lines,
                                      imageFileName: "pages/p0.jpg", width: 1200, height: 1600))
        app.context.insert(SourcePage(source: source, pageIndex: 1, label: "88", text: "Meiosis", lines: []))
        try app.context.save()

        await app.sync.pushNow()

        XCTAssertEqual(server.requests("POST", "/rest/v1/sources").first?.rows.first?["kind"] as? String, "scan")
        let pages = try XCTUnwrap(server.requests("POST", "/rest/v1/source_pages").first?.rows)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.map { $0["label"] as? String }, ["87", "88"])
        XCTAssertEqual(pages.first?["source_id"] as? String, id(source.id))
        XCTAssertEqual(pages.first?["updated_at"] as? String, SupabaseDate.format(source.updatedAt))
        XCTAssertEqual(((pages.first?["lines"] as? [[String: Any]])?.first)?["id"] as? String, "p0.l0")
        XCTAssertNil(pages.first?["image_path"], "only the uploading device sets image_path")
        XCTAssertEqual(source.syncedAt, source.updatedAt)
    }

    // MARK: Pull

    func testPullAppliesNewerRowsKeepsNewerLocalOnesAndTombstones() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let old = Date().addingTimeInterval(-3600)
        let behind = Course(name: "Old name", now: old)
        behind.syncedAt = old
        let ahead = Course(name: "Local edit", now: Date())
        app.context.insert(behind)
        app.context.insert(ahead)
        try app.context.save()
        let serverTime = Date().addingTimeInterval(-60)
        let gone = UUID()
        let itemID = UUID()
        let (behindID, aheadID) = (behind.id, ahead.id)
        server.on("GET", "/rest/v1/courses") { _ in
            .json([courseRow(behindID, name: "Server name", updated: serverTime, synced: "2026-10-22T10:00:00.000001+00:00"),
                   courseRow(aheadID, name: "Server loses", updated: serverTime, synced: "2026-10-22T10:00:00.000002+00:00"),
                   courseRow(gone, name: "Deleted elsewhere", updated: serverTime,
                             synced: "2026-10-22T10:00:00.000003+00:00", deleted: serverTime)])
        }
        server.on("GET", "/rest/v1/items") { _ in
            .json([["id": rowID(itemID), "course_id": rowID(behindID), "topic_id": NSNull(), "kind": "mcq",
                    "status": "active", "origin": "cloud", "prompt": "Which phase?", "answer": "Anaphase",
                    "explanation": "", "key_ideas": NSNull(),
                    "choices": [["text": "Anaphase", "correct": true], ["text": "Telophase", "correct": false]],
                    "cloze": NSNull(), "diagram": NSNull(), "source_ref": NSNull(), "checked_at": NSNull(),
                    "difficulty_hint": 0.4, "reported": false, "state": 2, "stability": 4.25, "difficulty": 5,
                    "due": "2026-11-01T09:00:00+00:00", "last_review": NSNull(), "reps": 3, "lapses": 0, "step": 0,
                    "created_at": SupabaseDate.format(serverTime), "updated_at": SupabaseDate.format(serverTime),
                    "deleted_at": NSNull(), "synced_at": "2026-10-22T10:00:01+00:00"]])
        }

        await app.sync.pullNow()
        XCTAssertNil(app.sync.lastError)

        XCTAssertEqual(behind.name, "Server name")
        XCTAssertEqual(behind.colorRaw, "rose")
        XCTAssertEqual(SupabaseDate.micros(behind.updatedAt), SupabaseDate.micros(serverTime))
        XCTAssertEqual(behind.syncedAt, behind.updatedAt)
        XCTAssertEqual(ahead.name, "Local edit", "the newer local row wins")
        let tombstone = try XCTUnwrap(app.course(gone))
        XCTAssertNotNil(tombstone.deletedAt, "deletions arrive as tombstones")
        XCTAssertEqual(tombstone.name, "Deleted elsewhere")

        let item = try XCTUnwrap(app.item(itemID))
        XCTAssertTrue(item.course === behind, "relationships resolve by id")
        XCTAssertEqual(item.choices.map(\.text), ["Anaphase", "Telophase"])
        XCTAssertEqual(item.memory.state, .review)
        XCTAssertEqual(item.memory.stability, 4.25)
        XCTAssertEqual(item.memory.due, SupabaseDate.parse("2026-11-01T09:00:00Z"))
        XCTAssertEqual(item.syncedAt, item.updatedAt)

        let first = try XCTUnwrap(server.requests("GET", "/rest/v1/courses").first)
        XCTAssertNil(first.query("synced_at"))
        XCTAssertNil(first.query("or"))
        XCTAssertEqual(first.query("order"), "synced_at.asc,id.asc")
        XCTAssertEqual(first.query("limit"), "500")
        XCTAssertEqual(first.header("Authorization"), "Bearer access-1")
        let ledger = SyncLedger.load(from: app.defaults)
        XCTAssertEqual(ledger.cursors["courses"], SyncLedger.Cursor(syncedAt: "2026-10-22T10:00:00.000003+00:00", key: id(gone)))
        XCTAssertEqual(ledger.cursors["items"]?.key, id(itemID))

        // Pulling the same rows again changes nothing (merging is idempotent).
        let name = behind.name
        await app.sync.pullNow()
        XCTAssertEqual(behind.name, name)
        XCTAssertEqual(app.fetch(FetchDescriptor<Course>()).count, 3)
        XCTAssertEqual(app.fetch(FetchDescriptor<StudyItem>()).count, 1)
    }

    func testPullPagesWithACompoundCursorAndStartsTheNextPullEarly() async throws {
        SyncEngine.pageSize = 2
        let server = StubServer()
        let app = signedInApp(server)
        let (a, b, c) = (UUID(), UUID(), UUID())
        let stamp1 = "2026-10-22T10:00:00.5+00:00"
        let stamp2 = "2026-10-22T10:05:00.25+00:00"
        let updated = Date().addingTimeInterval(-30)
        let calls = StubCounter()
        server.on("GET", "/rest/v1/courses") { _ in
            switch calls.next() {
            case 1: return .json([courseRow(a, name: "A", updated: updated, synced: stamp1),
                                  courseRow(b, name: "B", updated: updated, synced: stamp1)])
            case 2: return .json([courseRow(c, name: "C", updated: updated, synced: stamp2)])
            default: return .json([Any]())
            }
        }

        await app.sync.pullNow()

        let requests = server.requests("GET", "/rest/v1/courses")
        XCTAssertEqual(requests.count, 2)
        let ts = SupabaseClient.percentEncode(stamp1)
        XCTAssertTrue(requests[1].rawQuery.contains(
            "or=(synced_at.gt.%22\(ts)%22,and(synced_at.eq.%22\(ts)%22,id.gt.%22\(id(b))%22))"), requests[1].rawQuery)
        XCTAssertEqual(requests[1].query("or"), "(synced_at.gt.\"\(stamp1)\",and(synced_at.eq.\"\(stamp1)\",id.gt.\"\(id(b))\"))")
        XCTAssertEqual(app.fetch(FetchDescriptor<Course>()).count, 3)
        XCTAssertEqual(SyncLedger.load(from: app.defaults).cursors["courses"], SyncLedger.Cursor(syncedAt: stamp2, key: id(c)))

        // The next pull starts a minute before the cursor.
        await app.sync.pullNow()
        let next = try XCTUnwrap(server.requests("GET", "/rest/v1/courses").last)
        let early = SupabaseDate.format(try XCTUnwrap(SupabaseDate.parse(stamp2)).addingTimeInterval(-60))
        XCTAssertEqual(next.query("synced_at"), "gt.\(early)")
        XCTAssertTrue(next.rawQuery.contains("synced_at=gt.\(SupabaseClient.percentEncode(early))"))
        XCTAssertEqual(SyncLedger.load(from: app.defaults).cursors["courses"]?.syncedAt, stamp2, "the cursor never moves back")
    }

    func testDayRecordsMergeByMaxAndGoBackUpWhenTheServerIsBehind() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let record = DayRecord(dayKey: "2026-09-21", day: day, studySeconds: 50, itemsReviewed: 30, sessions: 2)
        record.syncedAt = day
        app.context.insert(record)
        try app.context.save()
        server.on("GET", "/rest/v1/day_records") { _ in
            .json([["day_key": "2026-09-21", "day": SupabaseDate.format(day), "study_seconds": 100,
                    "items_reviewed": 40, "sessions": 1, "frozen": true, "repaired": false,
                    "updated_at": SupabaseDate.format(day), "synced_at": "2026-10-22T10:00:00+00:00"]])
        }

        await app.sync.pullNow()

        XCTAssertEqual(record.studySeconds, 100)
        XCTAssertEqual(record.itemsReviewed, 40)
        XCTAssertEqual(record.sessions, 2)
        XCTAssertTrue(record.frozen)
        XCTAssertNil(record.syncedAt, "the server had fewer sessions: the merged record goes back up")
        XCTAssertEqual(server.requests("GET", "/rest/v1/day_records").first?.query("order"), "synced_at.asc,day_key.asc")

        await app.sync.pushNow()
        let push = try XCTUnwrap(server.requests("POST", "/rest/v1/day_records").first)
        XCTAssertEqual(push.query("on_conflict"), "user_id,day_key")
        XCTAssertEqual(push.rows.first?["sessions"] as? Int, 2)
        XCTAssertEqual(push.rows.first?["day_key"] as? String, "2026-09-21")
        XCTAssertNil(push.rows.first?["id"])
    }

    func testPulledReviewLogsAndPagesAreAdded() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let sourceID = UUID()
        let pageID = UUID()
        let logID = UUID()
        let stamp = Date().addingTimeInterval(-100)
        server.on("GET", "/rest/v1/sources") { _ in
            .json([["id": rowID(sourceID), "course_id": NSNull(), "kind": "scan", "status": "ready",
                    "title": "Textbook", "file_name": NSNull(), "storage_path": NSNull(), "duration": 0,
                    "segments": NSNull(), "flags": NSNull(), "notes": NSNull(),
                    "created_at": SupabaseDate.format(stamp), "updated_at": SupabaseDate.format(stamp),
                    "deleted_at": NSNull(), "synced_at": "2026-10-22T10:00:00+00:00"]])
        }
        server.on("GET", "/rest/v1/source_pages") { _ in
            .json([["id": rowID(pageID), "source_id": rowID(sourceID), "page_index": 0, "label": "87",
                    "text": "Mitosis", "lines": [["id": "p0.l0", "text": "Mitosis"]], "image_path": NSNull(),
                    "width": 1200, "height": 1600, "updated_at": SupabaseDate.format(stamp), "deleted_at": NSNull(),
                    "synced_at": "2026-10-22T10:00:00+00:00"]])
        }
        server.on("GET", "/rest/v1/review_logs") { _ in
            .json([["id": rowID(logID), "item_id": rowID(UUID()), "course_id": NSNull(), "session_id": NSNull(),
                    "reviewed_at": "2026-10-21T18:00:00+00:00", "rating": 3, "score": -1, "answer": NSNull(),
                    "graded_by": "person", "duration_ms": 9000, "state_before": 0, "stability_before": 0,
                    "difficulty_before": 0, "elapsed_days": 0, "scheduled_days": 1, "stability_after": 2.5,
                    "difficulty_after": 5.5, "synced_at": "2026-10-22T10:00:00+00:00"]])
        }

        await app.sync.pullNow()

        let source = try XCTUnwrap(app.source(sourceID))
        XCTAssertEqual(source.pages.count, 1)
        XCTAssertEqual(source.pages.first?.lines.first?.text, "Mitosis")
        XCTAssertEqual(source.pages.first?.width, 1200)
        let logs = app.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(logs.map(\.id), [logID])
        XCTAssertEqual(logs.first?.rating, .good)
        XCTAssertEqual(logs.first?.stabilityAfter, 2.5)
        XCTAssertNotNil(logs.first?.syncedAt)

        // A second pull of the same log doesn't duplicate it.
        await app.sync.pullNow()
        XCTAssertEqual(app.fetch(FetchDescriptor<ReviewLog>()).count, 1)
    }

    // MARK: Page photos

    func testPagePhotosUploadOnceAndOnlyWithSendPhotosOn() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sync-photos-\(UUID().uuidString)")
        FileStore.rootOverride = root
        defer { FileStore.rootOverride = nil; try? FileManager.default.removeItem(at: root) }
        let server = StubServer()
        let app = signedInApp(server)
        let source = Source(course: nil, kind: .scan, title: "Textbook")
        app.context.insert(source)
        let file = try FileStore.write(Data([0xFF, 0xD8, 0xFF, 0x01]), folder: "pages", name: "p0.jpg")
        let page = SourcePage(source: source, pageIndex: 0, label: "87", text: "Mitosis", lines: [], imageFileName: file)
        app.context.insert(page)
        try app.context.save()

        app.settings.sendPhotos = false
        await app.sync.pushNow()
        XCTAssertTrue(server.requests.filter { $0.path.hasPrefix("/storage") }.isEmpty, "photos stay on the iPhone")

        app.settings.sendPhotos = true
        await app.sync.pushNow()

        let path = "\(BackendTest.userID)/\(id(source.id))/\(id(page.id)).jpg"
        let upload = try XCTUnwrap(server.requests("POST", "/storage/v1/object/sources/\(path)").first)
        XCTAssertEqual(upload.header("Content-Type"), "image/jpeg")
        XCTAssertEqual(upload.header("x-upsert"), "true")
        XCTAssertEqual(upload.body, Data([0xFF, 0xD8, 0xFF, 0x01]))
        let patch = try XCTUnwrap(server.requests("PATCH", "/rest/v1/source_pages").first)
        XCTAssertEqual(patch.query("id"), "eq.\(id(page.id))")
        XCTAssertEqual(patch.object?["image_path"] as? String, path)
        XCTAssertEqual(patch.object?.count, 1, "only image_path changes")

        await app.sync.pushNow()
        XCTAssertEqual(server.requests.filter { $0.path.hasPrefix("/storage") }.count, 1, "uploaded once")
    }

    func testPagePhotosFromAnotherDeviceDownloadOnPull() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sync-photos-\(UUID().uuidString)")
        FileStore.rootOverride = root
        defer { FileStore.rootOverride = nil; try? FileManager.default.removeItem(at: root) }
        let server = StubServer()
        let app = signedInApp(server)
        let sourceID = UUID()
        let pageID = UUID()
        let stamp = Date().addingTimeInterval(-100)
        let path = "\(BackendTest.userID)/\(rowID(sourceID))/\(rowID(pageID)).jpg"
        server.on("GET", "/rest/v1/sources") { _ in
            .json([["id": rowID(sourceID), "course_id": NSNull(), "kind": "scan", "status": "ready", "title": "Notes",
                    "file_name": NSNull(), "duration": 0, "segments": NSNull(), "flags": NSNull(), "notes": NSNull(),
                    "created_at": SupabaseDate.format(stamp), "updated_at": SupabaseDate.format(stamp),
                    "deleted_at": NSNull(), "synced_at": "2026-10-22T10:00:00+00:00"]])
        }
        server.on("GET", "/rest/v1/source_pages") { _ in
            .json([["id": rowID(pageID), "source_id": rowID(sourceID), "page_index": 0, "label": "1", "text": "Notes",
                    "lines": NSNull(), "image_path": path, "width": 800, "height": 1000,
                    "updated_at": SupabaseDate.format(stamp), "deleted_at": NSNull(),
                    "synced_at": "2026-10-22T10:00:00+00:00"]])
        }
        server.on("GET", "/storage/v1/object/authenticated/sources/\(path)") { _ in .json(Data([1, 2, 3])) }

        await app.sync.pullNow()

        let page = try XCTUnwrap(app.source(sourceID)?.pages.first)
        let file = try XCTUnwrap(page.imageFileName)
        XCTAssertEqual(try Data(contentsOf: FileStore.url(for: file)), Data([1, 2, 3]))
        XCTAssertTrue(SyncLedger.load(from: app.defaults).pendingDownloads.isEmpty)
        XCTAssertEqual(server.requests("GET", "/storage/v1/object/authenticated/sources/\(path)").first?.header("Authorization"),
                       "Bearer access-1")
    }

    // MARK: Accounts and modes

    func testANewAccountOnThisDeviceResetsStampsAndPushesEverything() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        var ledger = SyncLedger(userID: BackendTest.otherUserID)
        ledger.cursors["courses"] = SyncLedger.Cursor(syncedAt: "2026-10-01T00:00:00+00:00", key: "x")
        ledger.save(to: app.defaults)
        let course = Course(name: "Pushed to the other account")
        course.syncedAt = course.updatedAt
        app.context.insert(course)
        try app.context.save()

        await app.sync.syncNow()

        XCTAssertEqual(server.requests("POST", "/rest/v1/courses").first?.rows.count, 1)
        let fresh = SyncLedger.load(from: app.defaults)
        XCTAssertEqual(fresh.userID, BackendTest.userID)
        XCTAssertNil(server.requests("GET", "/rest/v1/courses").first?.query("synced_at"), "cursors start over")
        XCTAssertEqual(course.syncedAt, course.updatedAt)
    }

    func testSyncNeedsARealAccount() async throws {
        // An anonymous session: the profile goes up (quotas need the time zone), study data doesn't.
        let server = StubServer()
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session(anonymous: true)))
        app.account.restoreSession()
        app.context.insert(Course(name: "Bio"))
        try app.context.save()

        await app.sync.syncNow()

        XCTAssertFalse(app.sync.isEnabled)
        XCTAssertEqual(Set(server.requests.map(\.path)), ["/rest/v1/profiles"])
    }

    func testSyncIsANoOpInLocalAndMockModes() async throws {
        for mode in [AppConfig.AIMode.local, .mock] {
            let app = BackendTest.app(mode)
            app.context.insert(Course(name: "Bio"))
            try app.context.save()
            await app.sync.syncNow()
            await app.sync.pushNow()
            app.sync.pushSoon()
            XCTAssertFalse(app.sync.isEnabled)
            XCTAssertNil(app.sync.lastError)
            XCTAssertNil(app.fetch(FetchDescriptor<Course>()).first?.syncedAt)
        }
    }

    func testSignedOutIsANoOp() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server)
        app.context.insert(Course(name: "Bio"))
        try app.context.save()
        await app.sync.syncNow()
        XCTAssertTrue(server.requests.isEmpty)
    }
}

/// Dates, JSON values and row mapping.
final class SyncRecordsTests: XCTestCase {
    func testPostgresTimestampsParseAndFormat() throws {
        let base = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-22T09:00:00Z"))
        XCTAssertEqual(SupabaseDate.parse("2026-10-22T09:00:00Z"), base)
        XCTAssertEqual(SupabaseDate.parse("2026-10-22T09:00:00+00:00"), base)
        XCTAssertEqual(SupabaseDate.parse("2026-10-22T11:00:00+02:00"), base)
        XCTAssertEqual(SupabaseDate.parse("2026-10-22 09:00:00+00"), base)
        let micro = try XCTUnwrap(SupabaseDate.parse("2026-10-22T09:00:00.123456+00:00"))
        XCTAssertEqual(SupabaseDate.micros(micro) - SupabaseDate.micros(base), 123_456)
        XCTAssertEqual(SupabaseDate.format(micro), "2026-10-22T09:00:00.123456Z")
        XCTAssertEqual(SupabaseDate.format(base), "2026-10-22T09:00:00.000000Z")
        XCTAssertEqual(SupabaseDate.micros(try XCTUnwrap(SupabaseDate.parse("2026-10-22T09:00:00.5Z"))) - SupabaseDate.micros(base),
                       500_000)
        XCTAssertNil(SupabaseDate.parse("yesterday"))
        XCTAssertNil(SupabaseDate.parse("2026-10-22T09:00:00+0"))
        // Round trip at the server's grain.
        let now = Date()
        XCTAssertEqual(SupabaseDate.micros(try XCTUnwrap(SupabaseDate.parse(SupabaseDate.format(now)))),
                       SupabaseDate.micros(now))
    }

    func testJSONValuesKeepIntegersAndBlobsRoundTrip() throws {
        let data = Data(#"{"a":1,"b":1.5,"c":true,"d":null,"e":["x",2],"f":{"g":"h"}}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let object) = value else { return XCTFail("not an object") }
        XCTAssertEqual(object["a"], .int(1))
        XCTAssertEqual(object["b"], .double(1.5))
        XCTAssertEqual(object["c"], .bool(true))
        XCTAssertEqual(object["d"], .null)
        XCTAssertEqual(object["e"], .array([.string("x"), .int(2)]))
        let ideas = [KeyIdea(id: "k1", label: "Growth", terms: ["grow", "repair"])]
        let blob = try JSONEncoder.cramless.encode(ideas)
        let back = try XCTUnwrap(JSONValue.blob(blob).blobData)
        XCTAssertEqual(try JSONDecoder.cramless.decode([KeyIdea].self, from: back), ideas)
        XCTAssertEqual(JSONValue.blob(nil), .null)
        XCTAssertNil(JSONValue.null.blobData)
    }

    @MainActor
    func testEveryTableSendsTheSameKeysForEveryRow() throws {
        let course = Course(name: "Bio")
        let deleted = Course(name: "Old")
        deleted.deletedAt = Date()
        XCTAssertEqual(Set(SyncRecords.row(course).keys), Set(SyncRecords.row(deleted).keys))
        let plain = StudyItem(course: nil, kind: .flashcard, origin: .person, prompt: "Q", answer: "A")
        let rich = StudyItem(course: course, topicID: UUID(), kind: .cloze, origin: .cloud, prompt: "Fill",
                             answer: "telophase", keyIdeas: [KeyIdea(id: "k", label: "l", terms: [])],
                             cloze: ClozeSpec(text: "During {{telophase}}"), sourceRef: SourceRef(sourceID: UUID(), label: "p. 87"))
        XCTAssertEqual(Set(SyncRecords.row(plain).keys), Set(SyncRecords.row(rich).keys))
        XCTAssertEqual(Set(SyncRecords.row(plain).keys), [
            "id", "course_id", "topic_id", "kind", "status", "origin", "prompt", "answer", "explanation", "key_ideas",
            "choices", "cloze", "diagram", "source_ref", "checked_at", "difficulty_hint", "reported", "state",
            "stability", "difficulty", "due", "last_review", "reps", "lapses", "step", "created_at", "updated_at",
            "deleted_at",
        ])
        let exam = Exam(course: course, title: "Midterm", date: Date())
        XCTAssertEqual(SyncRecords.row(exam)["format"].flatMap { if case .object = $0 { true } else { nil } }, true)
        let confusion = Confusion(course: course, name: "Anaphase vs telophase", explanation: "", itemIDs: [UUID()],
                                  missCount: 2)
        XCTAssertEqual(Set(SyncRecords.row(confusion).keys), [
            "id", "course_id", "name", "explanation", "item_ids", "fix", "status", "miss_count", "created_at",
            "updated_at", "last_seen_at", "deleted_at",
        ])
    }
}
