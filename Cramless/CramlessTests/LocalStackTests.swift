import Foundation
import StoreKitTest
import SwiftData
import XCTest
@testable import Cramless

/// The app's own networking against a real backend: the local Supabase stack (`scripts/local_stack.sh up`), with
/// GoTrue, PostgREST, Storage, Kong and the Edge Functions in MOCK mode. No stubs: `AccountService`,
/// `HTTPRelayTransport`, `BackendClient`, `SyncEngine`, `PurchaseStore` and `AppModel` talk HTTP to localhost.
///
/// Opt-in (`LocalStackSupport.swift`): skipped unless TEST_RUNNER_CRAMLESS_LOCAL_STACK_URL and
/// TEST_RUNNER_CRAMLESS_LOCAL_STACK_ANON_KEY are set; email sign-in, sync, Squad and deletion also need
/// TEST_RUNNER_CRAMLESS_LOCAL_STACK_SERVICE_KEY, which only test setup and server-side checks use. The StoreKit
/// purchase that syncs to the backend also needs TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1.
///
///   eval "$(scripts/local_stack.sh env --service --test-runner)"
///   SIM_ID=<udid> scripts/xc.sh test -only-testing:CramlessTests/LocalStackTests
@MainActor
final class LocalStackTests: XCTestCase {
    private var stack: LocalStack!
    private var savedLive: AppModel?
    private var filesRoot: URL?

    override func setUp() async throws {
        try await super.setUp()
        stack = try LocalStack.fromEnvironment()
        savedLive = AppModel.live
    }

    override func tearDown() async throws {
        AppModel.live = savedLive
        SyncEngine.pageSize = 500
        SyncEngine.batchSize = 200
        if let filesRoot {
            FileStore.rootOverride = nil
            try? FileManager.default.removeItem(at: filesRoot)
        }
        try await super.tearDown()
    }

    /// Page photos and synced downloads go to a folder of this test's own.
    private func useTemporaryFiles() {
        let root = FileManager.default.temporaryDirectory.appending(path: "localstack-\(UUID().uuidString)")
        FileStore.rootOverride = root
        filesRoot = root
    }

    private func newEmail(_ purpose: String) -> String {
        "\(purpose)-\(UUID().uuidString.prefix(8).lowercased())@capling.test"
    }

    private func key(_ id: UUID) -> String { LocalStack.key(id) }

    /// An app signed in the way a person signs in: `sendEmailCode` (GoTrue creates the account; the local stack has
    /// no mail server, so the Auth admin API reads out the code the email would carry), then `verifyEmailCode`.
    private func signedInApp(_ admin: LocalStack.Admin, email: String, firstName: String = "") async throws
        -> (app: AppModel, userID: String) {
        let app = stack.makeApp()
        app.settings.firstName = firstName
        try await app.account.sendEmailCode(to: email)
        let code = try await admin.emailCode(for: email)
        try await app.account.verifyEmailCode(email: email, code: code)
        XCTAssertTrue(app.account.isSignedIn)
        XCTAssertFalse(app.account.isAnonymous)
        XCTAssertEqual(app.account.email, email)
        let userID = try XCTUnwrap(app.account.userID)
        XCTAssertNotNil(UUID(uuidString: userID))
        return (app, userID)
    }

    // MARK: Auth

    func testAnAnonymousSessionIsCreatedOnFirstNeedReusedAndRefreshed() async throws {
        let app = stack.makeApp()
        XCTAssertEqual(app.config.aiMode, .relay)
        XCTAssertEqual(app.config.supabaseURL, stack.url, "an explicit http host stays http")
        XCTAssertTrue(app.config.inMemoryStore)
        XCTAssertNil(app.account.userID)

        let first = try await app.account.accessToken()
        let userID = try XCTUnwrap(app.account.userID)
        XCTAssertTrue(app.account.isAnonymous)
        XCTAssertFalse(app.account.isSignedIn, "an anonymous session doesn't turn sync on")
        XCTAssertFalse(app.sync.isEnabled)
        XCTAssertNotNil(UUID(uuidString: userID))
        XCTAssertEqual(userID, userID.lowercased())
        let stored = try XCTUnwrap(app.account.store.load())
        XCTAssertEqual(stored.accessToken, first)
        XCTAssertTrue(stored.isAnonymous)
        XCTAssertNil(stored.email)
        XCTAssertEqual(stored.expiresAt.timeIntervalSinceNow, 3600, accuracy: 120, "GoTrue's expires_at: an hour")

        let second = try await app.account.accessToken()
        XCTAssertEqual(second, first, "the second call reuses the session")
        XCTAssertEqual(app.account.userID, userID)
        XCTAssertEqual(app.account.store.load(), stored)

        // The relay accepts it (it asks GoTrue): a new free account with nothing used.
        let quota = try await stack.relay(of: app).quota()
        XCTAssertEqual(quota.plan, .free)
        XCTAssertEqual(quota.meters.map(\.used), [0, 0, 0, 0])

        // A fresh install whose first requests arrive together signs up once.
        let other = stack.makeApp()
        async let a = other.account.accessToken()
        async let b = other.account.accessToken()
        async let c = other.account.accessToken()
        let tokens = try await [a, b, c]
        XCTAssertEqual(Set(tokens).count, 1, "concurrent callers share one sign-up")
        XCTAssertNotEqual(other.account.userID, userID)

        // Within a minute of expiry the session is refreshed with GoTrue: same user, a rotated refresh token.
        app.account.now = { Date().addingTimeInterval(3600) }
        _ = try await app.account.accessToken()
        app.account.now = { Date() }
        let refreshed = try XCTUnwrap(app.account.store.load())
        XCTAssertEqual(refreshed.userID, userID)
        XCTAssertTrue(refreshed.isAnonymous)
        XCTAssertNotEqual(refreshed.refreshToken, stored.refreshToken)
        let again = try await stack.relay(of: app).quota()
        XCTAssertEqual(again.plan, .free, "the refreshed token works")
    }

    func testEmailCodeSignInThenSignOutEndsTheSessionOnTheServer() async throws {
        let admin = try stack.admin()
        let email = newEmail("signin")
        let app = stack.makeApp()
        try await app.account.sendEmailCode(to: "  \(email.uppercased()) ")
        let code = try await admin.emailCode(for: email)

        // A wrong code is the person's typo, not a lost session.
        do {
            try await app.account.verifyEmailCode(email: email, code: code == "000000" ? "111111" : "000000")
            XCTFail("a wrong code must not sign in")
        } catch let error as RelayError {
            XCTAssertEqual(error, .badRequest("That code didn't work. Check the latest email, or send a new code."))
        }
        XCTAssertFalse(app.account.isSignedIn)

        try await app.account.verifyEmailCode(email: email, code: code)
        XCTAssertTrue(app.account.isSignedIn)
        XCTAssertEqual(app.account.email, email)
        XCTAssertTrue(app.sync.isEnabled, "a real account turns sync on")
        let userID = try XCTUnwrap(app.account.userID)
        let session = try XCTUnwrap(app.account.store.load())
        XCTAssertFalse(session.isAnonymous)
        let quota = try await stack.relay(of: app).quota()
        XCTAssertEqual(quota.plan, .free)

        await app.signOut()
        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertNil(app.account.userID)
        XCTAssertNil(app.account.store.load())
        XCTAssertFalse(app.sync.isEnabled)
        // GoTrue ended the session too: its refresh token no longer works.
        do {
            _ = try await SupabaseClient(baseURL: stack.url, anonKey: stack.anonKey).refresh(refreshToken: session.refreshToken)
            XCTFail("a signed-out session's refresh token must not work")
        } catch let error as RelayError {
            switch error {
            case .unauthorized, .badRequest: break
            default: XCTFail("\(error)")
            }
        }
        // The next AI request starts an anonymous session; the account itself stays.
        _ = try await app.account.accessToken()
        XCTAssertTrue(app.account.isAnonymous)
        XCTAssertNotEqual(app.account.userID, userID)
        let stillThere = try await admin.authUserExists(userID)
        XCTAssertTrue(stillThere)
    }

    // MARK: Relay

    func testRelayGenerateCheckGradeAndQuotaAnswerWithTheFixtures() async throws {
        let app = stack.makeApp()
        let relay = try stack.relay(of: app)

        // A page transcription opens a scan; the generate that follows rides on it.
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(7), count: 60)).base64EncodedString()
        let lines = try await relay.transcribeImage(TranscribeImageRequest(image: photo, page: 0, label: "87"))
        XCTAssertEqual(lines, try RelayFixtures.load(TranscribeImageResponse.self, "transcribe-image"))

        let generateRequest = try fixtureRequest(GenerateRequest.self, "generate")
        let generated = try await relay.generate(generateRequest)
        XCTAssertEqual(generated, try RelayFixtures.load(GenerateResponse.self, "generate"))
        XCTAssertEqual(generated.items.count, 16)

        let checked = try await relay.check(CheckRequest(pages: generateRequest.pages, items: generated.items))
        XCTAssertEqual(checked, try RelayFixtures.load(CheckResponse.self, "check"))
        XCTAssertEqual(checked.verdicts.map(\.id), generated.items.map(\.id))

        // MOCK grading picks the fixture by how many key ideas the answer names.
        let gradeRequest = try fixtureRequest(GradeRequest.self, "grade")
        let partial = try await relay.grade(gradeRequest)
        XCTAssertEqual(partial, try RelayFixtures.load(GradeResponse.self, "grade-partial"))
        var all = gradeRequest
        all.response = "To grow and repair, making identical cells with the same number of chromosomes."
        let correct = try await relay.grade(all)
        XCTAssertEqual(correct, try RelayFixtures.load(GradeResponse.self, "grade-correct"))
        var none = gradeRequest
        none.response = "Cells divide so they can make sex cells."
        let incorrect = try await relay.grade(none)
        XCTAssertEqual(incorrect, try RelayFixtures.load(GradeResponse.self, "grade-incorrect"))

        let quota = try await relay.quota()
        XCTAssertEqual(quota.plan, .free)
        XCTAssertEqual(quota.meters, [
            QuotaMeter(key: .scans, used: 1, limit: 3, period: .week),
            QuotaMeter(key: .grades, used: 3, limit: 20, period: .day),
            QuotaMeter(key: .tutor, used: 0, limit: 10, period: .day),
            QuotaMeter(key: .lectures, used: 0, limit: 1, period: .week),
        ])
    }

    func testRelayTutorStreamsItsEventsWithACitation() async throws {
        let app = stack.makeApp()
        let relay = try stack.relay(of: app)
        let request = try fixtureRequest(TutorRequest.self, "tutor")
        let script = try RelayFixtures.load(TutorScript.self, "tutor-hints")

        var events: [TutorEvent] = []
        var arrivals: [Date] = []
        for try await event in relay.tutor(request) {
            events.append(event)
            arrivals.append(Date())
        }

        XCTAssertEqual(events, script.events.compactMap(\.tutorEvent))
        XCTAssertEqual(events.first, .start(model: "mock"))
        XCTAssertEqual(events.last, .done(model: "mock"))
        let citation = TutorEvent.citation(
            sourceID: "s1", label: "Textbook p. 87",
            quote: "During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei.")
        let at = try XCTUnwrap(events.firstIndex(of: citation), "the citation arrives")
        XCTAssertEqual(request.sources.map(\.id), ["s1"], "it cites a passage the app sent")
        let isDelta: (TutorEvent) -> Bool = { if case .delta = $0 { true } else { false } }
        XCTAssertEqual(events[1..<at].filter(isDelta).count, 12, "after the words it rests on")
        XCTAssertEqual(events[(at + 1)...].filter(isDelta).count, 2)
        let text = events.compactMap { event -> String? in if case .delta(let t) = event { t } else { nil } }.joined()
        XCTAssertEqual(text, "Let's work it out from your page. p. 87 says mitosis copies the DNA and separates it into "
            + "two new nuclei. Then something else happens to the rest of the cell. What does the page say is divided in "
            + "cytokinesis?")
        // Streamed through the gateway, not buffered: the deltas arrive over the script's ~0.9 s of pauses.
        let firstDelta = try XCTUnwrap(events.firstIndex(where: isDelta))
        XCTAssertGreaterThan(arrivals[arrivals.count - 1].timeIntervalSince(arrivals[firstDelta]), 0.5)

        // An adult asking to just explain gets the explaining script.
        var explain = request
        explain.mode = .explain
        var explained: [TutorEvent] = []
        for try await event in relay.tutor(explain) { explained.append(event) }
        XCTAssertEqual(explained, try RelayFixtures.load(TutorScript.self, "tutor-explain").events.compactMap(\.tutorEvent))

        let quota = try await relay.quota()
        XCTAssertEqual(quota.meter(.tutor), QuotaMeter(key: .tutor, used: 2, limit: 10, period: .day))
    }

    func testRelayLectureConfusionsAndCardsAnswerWithTheFixtures() async throws {
        let app = stack.makeApp()
        let relay = try stack.relay(of: app)

        let lecture = try await relay.lecture(LectureRequest(
            course: "Bio 101", title: "Lecture 6: Cell division",
            segments: [SegmentInput(id: "s1", start: 178, end: 190, text: "Today: what happens when the cell divides."),
                       SegmentInput(id: "s2", start: 725, end: 918, text: "Anaphase will be on the midterm.")],
            flags: [FlagInput(time: 730, text: "on the exam")], maxItems: 8))
        XCTAssertEqual(lecture, try RelayFixtures.load(LectureResponse.self, "lecture"))

        let confusions = try await relay.confusions(ConfusionsRequest(course: "Bio 101", mistakes: [
            MistakeInput(itemId: "i1", topic: "Mitosis", prompt: "When do sister chromatids separate?",
                         expected: "Anaphase", given: "Telophase", misses: 2),
        ]))
        XCTAssertEqual(confusions, try RelayFixtures.load(ConfusionsResponse.self, "confusions"))

        let cards = try await relay.cardsFromChat(CardsFromChatRequest(course: "Bio 101", messages: [
            TutorMessage(role: .user, text: "What's the difference between mitosis and cytokinesis?"),
            TutorMessage(role: .assistant, text: "Mitosis divides the nucleus; cytokinesis divides the cytoplasm."),
        ], maxItems: 6))
        XCTAssertEqual(cards, try RelayFixtures.load(CardsFromChatResponse.self, "cards-from-chat"))

        let quota = try await relay.quota()
        XCTAssertEqual(quota.meter(.lectures), QuotaMeter(key: .lectures, used: 1, limit: 1, period: .week))
    }

    func testRefusalsArriveAsTheAppsErrorsAndCostNothing() async throws {
        let app = stack.makeApp()
        let relay = try stack.relay(of: app)
        let generate = try fixtureRequest(GenerateRequest.self, "generate")

        // A free scan holds up to 10 pages: more is a paid feature (403 entitlement_required).
        var big = generate
        let page = try XCTUnwrap(generate.pages.first)
        big.pages = (0..<11).map { index in
            var copy = page
            copy.page = index
            return copy
        }
        do {
            _ = try await relay.generate(big)
            XCTFail("11 pages on free should need a plan")
        } catch let error as RelayError {
            XCTAssertEqual(error, .entitlementRequired)
        }

        // A body that fails validation (400 bad_request) names the field.
        var invalid = generate
        invalid.maxItems = 0
        do {
            _ = try await relay.generate(invalid)
            XCTFail("maxItems 0 should be refused")
        } catch let error as RelayError {
            guard case .badRequest(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("maxItems"), message)
        }

        // The tutor's refusals before the stream starts are envelopes too, read off the byte stream.
        var tutor = try fixtureRequest(TutorRequest.self, "tutor")
        tutor.messages.append(TutorMessage(role: .assistant, text: "Let's look at your page."))
        var events: [TutorEvent] = []
        do {
            for try await event in relay.tutor(tutor) { events.append(event) }
            XCTFail("the last message must be the student's")
        } catch let error as RelayError {
            XCTAssertEqual(error, .badRequest("The last message must be the student's."))
        }
        XCTAssertEqual(events, [])

        let quota = try await relay.quota()
        XCTAssertEqual(quota.meters.map(\.used), [0, 0, 0, 0], "refused requests cost nothing")
    }

    // MARK: Quotas

    func testTheFreeGradeLimitAnswersTheQuotaExceededEnvelope() async throws {
        let app = stack.makeApp()
        let relay = try stack.relay(of: app)
        let token = try await app.account.accessToken()
        let request = try fixtureRequest(GradeRequest.self, "grade")

        // Today's 20 free graded answers, sent together (each request meters in one transaction).
        let verdicts = try await withThrowingTaskGroup(of: GradeResponse.Verdict.self) { group in
            for _ in 0..<20 { group.addTask { try await relay.grade(request).verdict } }
            var out: [GradeResponse.Verdict] = []
            for try await verdict in group { out.append(verdict) }
            return out
        }
        XCTAssertEqual(verdicts, Array(repeating: .partial, count: 20))

        let expected = try RelayFixtures.load(RelayErrorBody.self, "error-quota")
        do {
            _ = try await relay.grade(request)
            XCTFail("the 21st graded answer of the day should be refused")
        } catch let error as RelayError {
            XCTAssertEqual(error, .quotaExceeded(expected.error.quota, message: expected.error.message))
        }

        // On the wire: HTTP 429 and the envelope the app's copy was written from.
        let wire = try await stack.raw("POST", "functions/v1/ai/grade", token: token,
                                       body: JSONEncoder.cramless.encode(request))
        XCTAssertEqual(wire.status, 429)
        XCTAssertEqual(try JSONDecoder.cramless.decode(RelayErrorBody.self, from: wire.data), expected)

        // Refused requests cost nothing.
        let quota = try await relay.quota()
        XCTAssertEqual(quota.meter(.grades), QuotaMeter(key: .grades, used: 20, limit: 20, period: .day))
    }

    // MARK: Sync

    func testSyncPushesEverythingAndAFreshAppOnTheSameSessionPullsIt() async throws {
        let admin = try stack.admin()
        useTemporaryFiles()
        // Small pages and batches, so pulls page through the compound (synced_at, id) cursor and pushes split, on
        // real PostgREST with its own timestamps.
        SyncEngine.pageSize = 2
        SyncEngine.batchSize = 2
        let email = newEmail("sync")
        let (a, userID) = try await signedInApp(admin, email: email, firstName: "Maya")
        a.settings.sendPhotos = true
        XCTAssertTrue(a.sync.isEnabled)

        // Signing in sent the profile (Squad's name, the quotas' time zone).
        let profile = try await admin.rows("profiles", userID, owner: "id").first
        XCTAssertEqual(profile?["display_name"] as? String, "Maya")
        XCTAssertEqual(profile?["timezone"] as? String, TimeZone.current.identifier)

        let world = try seed(a)
        await a.sync.syncNow()
        XCTAssertNil(a.sync.lastError, "push failed: \(String(describing: a.sync.lastError))")
        XCTAssertTrue(a.fetch(FetchDescriptor<StudyItem>()).allSatisfy { $0.syncedAt == $0.updatedAt })
        XCTAssertTrue(a.fetch(FetchDescriptor<ReviewLog>()).allSatisfy { $0.syncedAt != nil })

        // What the server holds, owned by this account.
        let expected = ["courses": 2, "topics": 1, "sources": 1, "source_pages": 1, "items": 3, "review_logs": 2,
                        "exams": 1, "study_sessions": 1, "day_records": 2, "confusions": 1]
        for (table, count) in expected {
            let rows = try await admin.rows(table, userID, select: "user_id")
            XCTAssertEqual(rows.count, count, table)
        }
        let photoPath = "\(userID)/\(key(world.source))/\(key(world.page)).jpg"
        let pageRow = try await admin.rows("source_pages", userID, select: "id,image_path").first
        XCTAssertEqual(pageRow?["image_path"] as? String, photoPath, "the photo went up and the page points at it")
        let photoFiles = try await admin.storageFiles(in: "\(userID)/\(key(world.source))")
        XCTAssertEqual(photoFiles, ["\(key(world.page)).jpg"])

        // A second device on the same session pulls it all, field for field, photo included.
        let b = stack.makeApp(session: try XCTUnwrap(a.account.store.load()))
        XCTAssertTrue(b.account.isSignedIn)
        XCTAssertTrue(b.sync.isEnabled)
        await b.sync.syncNow()
        XCTAssertNil(b.sync.lastError, "pull failed: \(String(describing: b.sync.lastError))")
        let pushed = LocalStackSnapshot.of(a)
        let pulled = LocalStackSnapshot.of(b)
        XCTAssertEqual(LocalStackSnapshot.counts(pulled), LocalStackSnapshot.counts(pushed))
        XCTAssertEqual(LocalStackSnapshot.counts(pulled), expected)
        XCTAssertEqual(LocalStackSnapshot.differences(pushed, pulled), [])
        let pageID = world.page
        let pulledPage = try XCTUnwrap(b.fetch(FetchDescriptor<SourcePage>(predicate: #Predicate { $0.id == pageID })).first)
        let pulledFile = try XCTUnwrap(pulledPage.imageFileName, "the page photo was downloaded")
        XCTAssertEqual(try Data(contentsOf: FileStore.url(for: pulledFile)), world.photo)
        XCTAssertTrue(b.item(world.mcq)?.course === b.course(world.bio), "relationships resolve on the new device")
        XCTAssertEqual(b.item(world.mcq)?.choices.map(\.text), ["Metaphase", "Anaphase"])

        // Edits and deletes on the first device: deletes arrive as tombstones.
        a.updateCourse(world.bio, name: "Biology 101", color: .sky, symbol: "leaf")
        a.deleteItems([world.cloze])
        a.deleteExam(world.exam)
        a.deleteCourse(world.chem)
        await a.sync.pushNow()
        XCTAssertNil(a.sync.lastError, "push failed: \(String(describing: a.sync.lastError))")
        await b.sync.pullNow()
        XCTAssertNil(b.sync.lastError, "pull failed: \(String(describing: b.sync.lastError))")

        XCTAssertEqual(b.course(world.bio)?.name, "Biology 101")
        XCTAssertEqual(b.course(world.bio)?.colorRaw, "sky")
        XCTAssertNotNil(b.item(world.cloze)?.deletedAt, "a deleted question arrives as a tombstone")
        XCTAssertNotNil(b.exam(world.exam)?.deletedAt)
        XCTAssertNotNil(b.course(world.chem)?.deletedAt)
        XCTAssertNotNil(b.item(world.recall)?.deletedAt, "a deleted course takes its questions with it")
        XCTAssertNil(b.item(world.mcq)?.deletedAt)
        XCTAssertEqual(b.courses.map(\.id), [world.bio])
        XCTAssertEqual(LocalStackSnapshot.differences(LocalStackSnapshot.of(a), LocalStackSnapshot.of(b)), [])
        let items = try await admin.rows("items", userID, select: "id,deleted_at")
        XCTAssertEqual(items.count, 3, "tombstones, never deletes")
        let tombstones = Set(items.filter { !($0["deleted_at"] is NSNull) }.compactMap { $0["id"] as? String })
        XCTAssertEqual(tombstones, [key(world.cloze), key(world.recall)])

        // And the other way: an edit on the second device reaches the first.
        b.renameTopic(world.topic, to: "Mitosis and cytokinesis")
        await b.sync.pushNow()
        XCTAssertNil(b.sync.lastError, "push failed: \(String(describing: b.sync.lastError))")
        await a.sync.pullNow()
        XCTAssertNil(a.sync.lastError, "pull failed: \(String(describing: a.sync.lastError))")
        let topicID = world.topic
        XCTAssertEqual(a.fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.id == topicID })).first?.name,
                       "Mitosis and cytokinesis")
        XCTAssertEqual(LocalStackSnapshot.differences(LocalStackSnapshot.of(a), LocalStackSnapshot.of(b)), [])
    }

    /// The ids of what `seed` made.
    private struct World {
        var bio: UUID, chem: UUID, topic: UUID, source: UUID, page: UUID
        var mcq: UUID, cloze: UUID, recall: UUID, session: UUID, exam: UUID, confusion: UUID
        var photo: Data
    }

    /// Two courses, a topic, a scanned page with its photo, three questions of different kinds (one with a
    /// review history), a finished session with two reviews, an exam, two day records and a confusion.
    private func seed(_ app: AppModel) throws -> World {
        let now = Date()
        let t0 = now.addingTimeInterval(-3 * 3600)
        let calendar = app.calendar
        let bio = Course(name: "Bio 101", color: .mint, symbol: "leaf", sortOrder: 1, now: t0)
        let chem = Course(name: "Chem 110", color: .rose, symbol: "flask", sortOrder: 2, now: t0.addingTimeInterval(5))
        let topic = Topic(course: bio, name: "Mitosis", summary: "How one cell becomes two.", now: t0)
        let source = Source(course: bio, kind: .scan, title: "Biology textbook", status: .ready, now: t0)
        let photo = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array("a page photo from the local stack test".utf8))
        let file = try FileStore.write(photo, folder: "pages", name: "\(UUID().uuidString).jpg")
        let page = SourcePage(source: source, pageIndex: 0, label: "87",
                              text: "Mitosis\nDuring mitosis, the genetic material (DNA) is copied.",
                              lines: [TextLine(id: "p0.l0", text: "Mitosis", box: NormRect(x: 0.1, y: 0.08, w: 0.3, h: 0.04)),
                                      TextLine(id: "p0.l1", text: "During mitosis, the genetic material (DNA) is copied.",
                                               box: NormRect(x: 0.1, y: 0.14, w: 0.8, h: 0.03))],
                              imageFileName: file, width: 1240, height: 1754)
        page.read = PageRead(engine: .vision, confidence: 0.93)

        let mcq = StudyItem(course: bio, topicID: topic.id, kind: .mcq, status: .active, origin: .cloud,
                            prompt: "When do chromosomes line up at the cell's equator?", answer: "Metaphase",
                            explanation: "The spindle fibres line them up on the metaphase plate.",
                            choices: [Choice(text: "Metaphase", correct: true),
                                      Choice(text: "Anaphase", correct: false, why: "That's when they're pulled apart.")],
                            sourceRef: SourceRef(sourceID: source.id, pageIndex: 0, anchorIDs: ["p0.l0"], label: "p. 87"),
                            difficultyHint: 0.35, now: t0)
        mcq.checkedAt = t0.addingTimeInterval(30)
        mcq.memory = MemoryState(state: .review, stability: 3.25, difficulty: 5.5, due: now.addingTimeInterval(2 * 86_400),
                                 lastReview: t0.addingTimeInterval(600), reps: 2, lapses: 1, step: 0)
        let cloze = StudyItem(course: bio, topicID: topic.id, kind: .cloze, status: .active, origin: .person,
                              prompt: "Fill in the phase", answer: "telophase",
                              cloze: ClozeSpec(text: "During {{telophase}} the nuclear envelopes re-form.",
                                               alternates: [["telophase II"]]), now: t0)
        let recall = StudyItem(course: chem, kind: .recall, status: .draft, origin: .rules,
                               prompt: "Why do cells divide by mitosis?", answer: "To grow and repair tissue.",
                               keyIdeas: [KeyIdea(id: "k1", label: "Growth and repair", terms: ["grow", "repair"])],
                               now: t0)

        let session = StudySession(kind: .daily, startedAt: t0.addingTimeInterval(500), plannedSeconds: 900,
                                   courseID: bio.id)
        session.endedAt = t0.addingTimeInterval(1_100)
        session.activeSeconds = 540
        session.itemCount = 2
        session.correctCount = 1
        session.readinessBefore = 0.41
        session.readinessAfter = 0.47
        let good = ReviewLog(itemID: mcq.id, courseID: bio.id, sessionID: session.id, reviewedAt: t0.addingTimeInterval(600),
                             rating: .good, answer: "Metaphase", gradedBy: "person", durationMs: 9_000, before: .new,
                             after: MemoryState(stability: 3.25, difficulty: 5.5), elapsedDays: 0, scheduledDays: 2)
        let hard = ReviewLog(itemID: recall.id, courseID: chem.id, sessionID: session.id,
                             reviewedAt: t0.addingTimeInterval(700), rating: .hard, score: 0.67,
                             answer: "two identical cells", gradedBy: "cloud", durationMs: 41_000, before: .new,
                             after: MemoryState(stability: 1.5, difficulty: 6.25), elapsedDays: 0, scheduledDays: 1)

        let examDay = calendar.date(byAdding: .day, value: 9, to: calendar.startOfDay(for: now))!
        let exam = Exam(course: bio, title: "Midterm 1", date: examDay.addingTimeInterval(9 * 3600), scope: [topic.id],
                        format: ExamFormat(multipleChoice: true, shortAnswer: false, essay: true, notes: "Bring a pencil"),
                        targetReadiness: 0.85, now: t0)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let today = DayRecord(dayKey: calendar.dayKey(for: now), day: calendar.startOfDay(for: now), studySeconds: 540,
                              itemsReviewed: 2, sessions: 1)
        let earlier = DayRecord(dayKey: calendar.dayKey(for: weekAgo), day: calendar.startOfDay(for: weekAgo),
                                studySeconds: 300, itemsReviewed: 5, sessions: 1, repaired: true)
        let confusion = Confusion(course: bio, name: "Anaphase vs telophase",
                                  explanation: "Both end with two sets of chromosomes; only one has new envelopes.",
                                  itemIDs: [mcq.id, cloze.id],
                                  fix: ConfusionFix(lesson: "Anaphase pulls apart; telophase rebuilds.", itemIDs: [cloze.id]),
                                  missCount: 2, now: t0)

        let context = app.context
        context.insert(bio)
        context.insert(chem)
        context.insert(topic)
        context.insert(source)
        context.insert(page)
        context.insert(mcq)
        context.insert(cloze)
        context.insert(recall)
        context.insert(session)
        context.insert(good)
        context.insert(hard)
        context.insert(exam)
        context.insert(today)
        context.insert(earlier)
        context.insert(confusion)
        try context.save()
        return World(bio: bio.id, chem: chem.id, topic: topic.id, source: source.id, page: page.id, mcq: mcq.id,
                     cloze: cloze.id, recall: recall.id, session: session.id, exam: exam.id, confusion: confusion.id,
                     photo: photo)
    }

    // MARK: Squad

    func testASquadOwnerInvitesAFriendWhosePlanBecomesSquad() async throws {
        let admin = try stack.admin()
        let owner = stack.makeApp()
        owner.settings.firstName = "Maya"
        _ = try await owner.account.accessToken()
        await owner.account.pushProfileIfNeeded()
        let ownerID = try XCTUnwrap(owner.account.userID)

        // Without a Squad subscription there's nothing to invite to.
        do {
            _ = try await owner.createSquadInvite()
            XCTFail("inviting needs a Squad subscription")
        } catch let error as RelayError {
            XCTAssertEqual(error, .entitlementRequired)
        }

        try await admin.grantSquad(to: ownerID)
        await owner.account.refreshEntitlement()
        XCTAssertEqual(owner.account.entitlement?.plan, .squad)
        let invite = try await owner.createSquadInvite()
        XCTAssertNotNil(invite.code.range(of: "^CAP-[A-Z0-9]{4}$", options: .regularExpression), invite.code)
        XCTAssertEqual(invite.url, "https://capling.app/squad/\(invite.code)")
        XCTAssertEqual(invite.expiresAt.timeIntervalSinceNow, 14 * 86_400, accuracy: 300)

        // A friend on another anonymous session redeems it (codes work in any case).
        let friend = stack.makeApp()
        _ = try await friend.account.accessToken()
        let friendID = try XCTUnwrap(friend.account.userID)
        XCTAssertNotEqual(friendID, ownerID)
        await friend.account.refreshEntitlement()
        XCTAssertEqual(friend.account.entitlement?.plan, .free)
        let redeemed = try await friend.redeemSquadInvite(invite.code.lowercased())
        XCTAssertEqual(redeemed, SquadRedeemResponse(plan: .squad, ownerName: "Maya"))
        XCTAssertEqual(friend.account.entitlement?.plan, .squad, "the backend's entitlement is now Squad")
        XCTAssertEqual(friend.purchases.plan, .squad, "and the app counts it at once")
        let friendQuota = try await stack.relay(of: friend).quota()
        XCTAssertEqual(friendQuota.plan, .squad, "the relay sees the seat")
        XCTAssertEqual(friendQuota.meters.map(\.limit), [nil, nil, nil, nil])

        let members = try await owner.squadMembers()
        XCTAssertEqual(members.seats, 4)
        XCTAssertEqual(members.members.map(\.id), [ownerID, friendID])
        XCTAssertEqual(members.members.map(\.isOwner), [true, false])
        XCTAssertEqual(members.members.first?.name, "Maya")
        let seenByFriend = try await friend.squadMembers()
        XCTAssertEqual(seenByFriend.members.map(\.id), [ownerID, friendID])

        // A member who doesn't own the Squad can't invite.
        do {
            _ = try await friend.createSquadInvite()
            XCTFail("only the owner invites")
        } catch let error as RelayError {
            XCTAssertEqual(error, .entitlementRequired)
        }
        // Codes are single use.
        let stranger = stack.makeApp()
        do {
            _ = try await stranger.redeemSquadInvite(invite.code)
            XCTFail("a used code can't be redeemed again")
        } catch let error as RelayError {
            XCTAssertEqual(error, .badRequest("That invite code was already used. Ask your friend for a new one."))
        }
        XCTAssertNotNil(stranger.account.userID, "redeeming started an anonymous session")
        XCTAssertNotEqual(stranger.account.entitlement?.plan, .squad)

        // A member can leave; their plan is free again, and the owner's Squad has a seat back.
        let left = try await friend.removeSquadMember(friendID)
        XCTAssertEqual(left, SquadMembers(seats: 4, sharing: false, members: []))
        XCTAssertEqual(friend.account.entitlement?.plan, .free)
        XCTAssertEqual(friend.purchases.plan, .free)
        let after = try await owner.squadMembers()
        XCTAssertEqual(after.members.map(\.id), [ownerID])
    }

    // MARK: Deletion

    func testDeletingAIDataThenTheAccountAndTheOldTokenIsRefused() async throws {
        let admin = try stack.admin()
        useTemporaryFiles()
        let (app, userID) = try await signedInApp(admin, email: newEmail("delete"))
        app.settings.sendPhotos = true
        let relay = try stack.relay(of: app)

        // Something on every side: a synced course and page photo, an AI request in the log, a quota count.
        let course = Course(name: "Bio 101")
        let source = Source(course: course, kind: .scan, title: "Notes", status: .ready)
        let file = try FileStore.write(Data([0xFF, 0xD8, 0xFF, 0x01, 0x02]), folder: "pages", name: "p0.jpg")
        let page = SourcePage(source: source, pageIndex: 0, label: "1", text: "Notes", lines: [], imageFileName: file)
        app.context.insert(course)
        app.context.insert(source)
        app.context.insert(page)
        try app.context.save()
        await app.sync.syncNow()
        XCTAssertNil(app.sync.lastError, "push failed: \(String(describing: app.sync.lastError))")
        let folder = "\(userID)/\(key(source.id))"
        let filesBefore = try await admin.storageFiles(in: folder)
        XCTAssertEqual(filesBefore.count, 1)

        _ = try await relay.grade(try fixtureRequest(GradeRequest.self, "grade"))
        let logged = try await LocalStack.eventually {
            try await admin.rows("ai_requests", userID, select: "route").count == 1
        }
        XCTAssertTrue(logged, "the relay logs the AI request after answering")
        let logRow = try await admin.rows("ai_requests", userID, select: "route,model,mock,status").first
        XCTAssertEqual(logRow?["route"] as? String, "grade")
        XCTAssertEqual(logRow?["model"] as? String, "mock")
        XCTAssertEqual(logRow?["status"] as? Int, 200)

        // Delete AI data: the request log goes, study data and quota counts stay.
        try await app.deleteAIData()
        let logAfter = try await admin.rows("ai_requests", userID)
        XCTAssertEqual(logAfter.count, 0)
        let quota = try await relay.quota()
        XCTAssertEqual(quota.meter(.grades)?.used, 1, "deleting AI data never resets a quota")
        let courses = try await admin.rows("courses", userID)
        XCTAssertEqual(courses.count, 1, "study data stays")
        XCTAssertTrue(app.account.isSignedIn)

        // Delete the account: the server first, then this iPhone.
        let old = try XCTUnwrap(app.account.store.load())
        try await app.deleteAccount()
        XCTAssertNil(app.account.userID)
        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertNil(app.account.store.load())
        XCTAssertTrue(app.fetch(FetchDescriptor<Course>()).isEmpty)
        let userExists = try await admin.authUserExists(userID)
        XCTAssertFalse(userExists, "the auth user is gone")
        for table in ["courses", "sources", "source_pages", "usage_counters", "ai_requests", "entitlements"] {
            let rows = try await admin.rows(table, userID)
            XCTAssertEqual(rows.count, 0, table)
        }
        let profiles = try await admin.rows("profiles", userID, owner: "id")
        XCTAssertEqual(profiles.count, 0)
        let filesAfter = try await admin.storageFiles(in: folder)
        XCTAssertEqual(filesAfter, [], "the storage folder is emptied")

        // The old session is refused: the relay, the account function and GoTrue's refresh.
        let stale = HTTPRelayTransport(baseURL: stack.url, anonKey: stack.anonKey, tokens: StaticToken(token: old.accessToken))
        do {
            _ = try await stale.quota()
            XCTFail("a deleted account's token must not work")
        } catch let error as RelayError {
            XCTAssertEqual(error, .unauthorized)
        }
        let account = try await stack.raw("GET", "functions/v1/account/entitlements", token: old.accessToken)
        XCTAssertEqual(account.status, 401)
        XCTAssertEqual(try JSONDecoder.cramless.decode(RelayErrorBody.self, from: account.data).error.code, "unauthorized")
        do {
            _ = try await SupabaseClient(baseURL: stack.url, anonKey: stack.anonKey).refresh(refreshToken: old.refreshToken)
            XCTFail("a deleted account's refresh token must not work")
        } catch let error as RelayError {
            switch error {
            case .unauthorized, .badRequest: break
            default: XCTFail("\(error)")
            }
        }
    }

    // MARK: Purchases

    /// A StoreKit purchase reaches the backend the way the app sends it: `PurchaseStore` collects the signed
    /// transactions (Cramless.storekit's Xcode environment, which a local stack accepts with
    /// CRAMLESS_ALLOW_XCODE_JWS=1), `AccountService` posts them to `account/entitlements`, and the relay's plan
    /// follows. Also opt-in for StoreKit (TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1); the transaction is made with
    /// `SKTestSession.buyProduct`, which needs no purchase sheet.
    func testAStoreKitPurchaseSyncsToTheBackendAndTheRelaysPlanFollows() async throws {
        let session = try storeKitSession()
        defer { session.clearTransactions() }
        let admin = try stack.admin()

        let app = stack.makeApp()
        _ = try await app.account.accessToken()
        let userID = try XCTUnwrap(app.account.userID)
        final class Sent { var batches: [[String]] = [] }
        let sent = Sent()
        // What the app does with side effects on: PurchaseStore.sync → AccountService.syncEntitlements.
        app.purchases.entitlementSink = { [weak app] signed in
            sent.batches.append(signed)
            await app?.account.syncEntitlements(signed)
        }

        try await session.buyProduct(identifier: PlanOption.monthly.productID)
        await app.purchases.refreshEntitlements()
        XCTAssertEqual(app.purchases.plan, .pro)
        XCTAssertEqual(sent.batches.last?.count, 1, "the signed transaction went to the account service")
        XCTAssertEqual(app.account.entitlement?.plan, .pro, "the backend verified it and saved the plan")
        let expires = try XCTUnwrap(app.account.entitlement?.expiresAt)
        XCTAssertEqual(expires.timeIntervalSinceNow, 30 * 86_400, accuracy: 3 * 86_400, "a month of Pro")

        let rows = try await admin.rows("entitlements", userID, select: "plan,product_id,environment")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["plan"] as? String, "pro")
        XCTAssertEqual(rows.first?["product_id"] as? String, PlanOption.monthly.productID)
        XCTAssertEqual(rows.first?["environment"] as? String, "Xcode")

        let quota = try await stack.relay(of: app).quota()
        XCTAssertEqual(quota.plan, .pro, "the relay meters Pro now")
        XCTAssertEqual(quota.meters.map(\.limit), [nil, nil, nil, nil])
    }

    /// Bought before signing in, so the backend got the purchase under the anonymous session; then signed in with
    /// an email code in the same launch (a new auth user). The relay must meter the account as Pro straight away,
    /// not from the next launch on.
    func testAPurchaseMadeBeforeSigningInFollowsTheAccount() async throws {
        let session = try storeKitSession()
        defer { session.clearTransactions() }
        let admin = try stack.admin()

        let app = stack.makeApp()
        // What the app does with side effects on: PurchaseStore.sync → AccountService.syncEntitlements.
        app.purchases.entitlementSink = { [weak app] signed in await app?.account.syncEntitlements(signed) }
        try await session.buyProduct(identifier: PlanOption.monthly.productID)
        await app.purchases.refreshEntitlements()
        XCTAssertTrue(app.account.isAnonymous, "the purchase went up under an anonymous session")
        XCTAssertEqual(app.account.entitlement?.plan, .pro)

        let email = newEmail("buyer")
        try await app.sendEmailCode(email)
        let code = try await admin.emailCode(for: email)
        try await app.verifyEmailCode(email: email, code: code)
        XCTAssertTrue(app.account.isSignedIn)
        let userID = try XCTUnwrap(app.account.userID)

        let relay = try stack.relay(of: app)
        let metered = try await LocalStack.eventually(timeout: 10) { try await relay.quota().plan == .pro }
        XCTAssertTrue(metered, "the relay meters the signed-in account as Pro")
        let rows = try await admin.rows("entitlements", userID, select: "plan")
        XCTAssertEqual(rows.map { $0["plan"] as? String }, ["pro"], "the purchase moved to the account")
        XCTAssertEqual(app.purchases.plan, .pro)
    }

    /// A StoreKit test session on Cramless.storekit without transactions (opt-in, as in StorePurchaseFlowTests).
    private func storeKitSession() throws -> SKTestSession {
        guard ProcessInfo.processInfo.environment["CRAMLESS_STOREKIT_TESTS"] == "1" else {
            throw XCTSkip("StoreKit purchases are opt-in: TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1")
        }
        let configuration = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cramless.storekit")
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }
}
