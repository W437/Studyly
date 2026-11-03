import XCTest
@testable import Cramless

/// Generating from a long reading through the router: the parts a free plan's 10-page scan needs (each a scan), the
/// questions shared out over them, what is kept when a later part can't be read, the reason a failed first part is
/// given, and the check that is asked again, leniently, when it rejects nearly everything.
@MainActor
final class GenerationPartsTests: XCTestCase {

    // MARK: Fixtures

    /// Pages of six sentences each, so every line is a question's own answer.
    private func pages(_ count: Int, linesPerPage: Int = 6) -> [PageText] {
        (0..<count).map { p in
            PageText(index: p, label: "\(p + 1)", lines: (0..<linesPerPage).map { l in
                TextLine(id: "p\(p).l\(l)", text: "Sentence \(l) on page \(p) says the duty of care runs to foreseeable plaintiffs only.", box: nil)
            })
        }
    }

    private func input(_ pages: [PageText], maxItems: Int = 24, title: String = "Palsgraf v. Long Island Railroad") -> GenerationInput {
        GenerationInput(course: "Torts", sourceTitle: title, level: "college", pages: pages, maxItems: maxItems)
    }

    private func relayApp(consent: Bool = true) -> (app: AppModel, relay: ScriptedRelay) {
        let app = AITestSupport.makeApp(mode: .relay, consent: consent)
        let relay = ScriptedRelay()
        app.ai.transportOverride = relay
        app.ai.resetUsage()
        return (app, relay)
    }

    private func freeQuota(used: Int) -> QuotaStatus {
        QuotaStatus(plan: .free, meters: [QuotaMeter(key: .scans, used: used, limit: 3, period: .week)])
    }

    /// An app that may send page photos, on a relay that also reads pages (a line of its own for each).
    private func scanApp() -> (app: AppModel, relay: ScriptedRelay) {
        let app = AITestSupport.makeApp(mode: .relay, consent: true, photos: true)
        let relay = ScriptedRelay()
        relay.onTranscribe = { request in
            TranscribeImageResponse(model: "scripted", lines: [LineInput(id: "p\(request.page).c0", text: "A line the cloud read on page \(request.page + 1).")])
        }
        app.ai.transportOverride = relay
        app.ai.resetUsage()
        return (app, relay)
    }

    // MARK: Parts

    func testAFourteenPageReadingGoesInTwoPartsOfSevenAndTakesTwoScans() async throws {
        let (app, relay) = relayApp()
        var details: [String] = []
        var parts: [(Int, Int)] = []
        let outcome = await app.ai.generateSet(input(pages(14))) { progress in
            if details.last != progress.detail { details.append(progress.detail) }
            parts.append((progress.part, progress.parts))
        }

        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [7, 7])
        XCTAssertEqual(relay.generateRequests.map(\.maxItems), [12, 12])
        XCTAssertEqual(relay.generateRequests.map { $0.pages.map(\.label) }, [(1...7).map(String.init), (8...14).map(String.init)])
        XCTAssertEqual(relay.checkRequests.count, 2, "each part is a normal generate and check")
        XCTAssertEqual(relay.checkRequests.map { $0.pages.count }, [7, 7], "a part's check sees only its own pages")

        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.checkedBy, .cloud)
        XCTAssertEqual(outcome.items.count, 24)
        XCTAssertEqual(Set(outcome.items.map(\.id)).count, 24, "item ids stay unique across parts")
        XCTAssertTrue(outcome.items.allSatisfy { !$0.anchors.isEmpty })
        XCTAssertEqual(outcome.note, "Read in 2 parts (2 of your free scans this week).")
        XCTAssertNil(outcome.suggestion)
        XCTAssertNil(outcome.limitReached)
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .read])
        XCTAssertEqual(outcome.parts.map { [$0.firstPage, $0.lastPage] }, [["1", "7"], ["8", "14"]])
        XCTAssertEqual(outcome.parts.map(\.kept), [12, 12])
        // Topics are merged by name, whatever the case the second part spelled them in: "duty" and "Duty" are one topic and the
        // first spelling is kept, on the topic and on the items.
        XCTAssertEqual(outcome.topics.map(\.name), ["Torts", "duty"])
        XCTAssertTrue(outcome.items.allSatisfy { ["Torts", "duty"].contains($0.topic) })
        // The processing screen is told which part is under way.
        XCTAssertTrue(details.contains("Part 1 of 2"), "\(details)")
        XCTAssertTrue(details.contains("Part 2 of 2"), "\(details)")
        XCTAssertEqual(parts.last?.0, 2)
        XCTAssertEqual(parts.last?.1, 2)
        // Each part counted as a scan for this week.
        XCTAssertEqual(app.ai.quotaState(for: .generate), .available(remaining: 1))
    }

    func testAReadingThatFitsOneScanIsOneRequestOfAtMostTwentyQuestions() async {
        let (app, relay) = relayApp()
        let outcome = await app.ai.generateSet(input(pages(10)))
        XCTAssertEqual(relay.generateRequests.count, 1)
        XCTAssertEqual(relay.generateRequests.first?.maxItems, 20, "a free reading never splits to reach a higher count")
        XCTAssertEqual(outcome.parts.count, 1)
        XCTAssertNil(outcome.note, "one part says nothing about parts")

        let (small, smallRelay) = relayApp()
        _ = await small.ai.generateSet(input(pages(2), maxItems: 8))
        XCTAssertEqual(smallRelay.generateRequests.first?.maxItems, 8)
    }

    func testAPaidReadingAboveTwentyIsTwoRequestsOfAtMostTwenty() async {
        let (app, relay) = relayApp()
        app.ai.setServerQuota(QuotaStatus(plan: .pro, meters: [QuotaMeter(key: .scans, used: 0, limit: nil, period: .week)]))
        let outcome = await app.ai.generateSet(input(pages(10), maxItems: 39))
        XCTAssertEqual(relay.generateRequests.map(\.maxItems), [20, 19])
        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [5, 5])
        XCTAssertEqual(outcome.items.count, 39)
        XCTAssertEqual(outcome.note, "Read in 2 parts.", "a paid plan has no scans to count")
    }

    func testTheFreeScansRunningOutBetweenPartsKeepsTheFinishedPartAndNamesThePagesWaiting() async throws {
        let (app, relay) = relayApp()
        app.ai.setServerQuota(freeQuota(used: 2))   // one scan left this week
        let outcome = await app.ai.generateSet(input(pages(14)))

        XCTAssertEqual(relay.generateRequests.count, 1, "no request for a scan the week doesn't have")
        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [10], "the one scan reads a whole scan's worth of pages, not seven")
        XCTAssertEqual(relay.generateRequests.first?.maxItems, 20, "the questions go to the part that can run")
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.items.count, 20)
        XCTAssertEqual(outcome.note, "Cloud AI read pages 1 to 10. Pages 11 to 14 are waiting: this week's free scans are used up.")
        XCTAssertEqual(outcome.limitReached, .scans)
        guard case .upgrade(.scans, _)? = outcome.suggestion else { return XCTFail("\(String(describing: outcome.suggestion))") }
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .notStarted])
        XCTAssertEqual(outcome.parts.map(\.pageIndexes), [Array(0..<10), Array(10..<14)])
    }

    func testTwoScansLeftReadTwentyOfTwentyFivePagesAndNameTheFiveWaiting() async throws {
        let (app, relay) = relayApp()
        app.ai.setServerQuota(freeQuota(used: 1))   // two scans left
        let outcome = await app.ai.generateSet(input(pages(25)))

        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [10, 10], "was 9 and 8: seventeen pages for two scans")
        XCTAssertEqual(relay.generateRequests.map(\.maxItems), [12, 12])
        XCTAssertEqual(outcome.items.count, 24)
        XCTAssertEqual(outcome.note, "Cloud AI read pages 1 to 20. Pages 21 to 25 are waiting: this week's free scans are used up.")
        XCTAssertEqual(outcome.limitReached, .scans)
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .read, .notStarted])
        XCTAssertEqual(outcome.parts.map(\.pageCount), [10, 10, 5])
        XCTAssertEqual(app.ai.quotaState(for: .generate), .exhausted)
    }

    func testAShortPartNextToALongPageIsAskedAndTheScansAreNotReadAsUsedUp() async throws {
        // One long page and ten of a few words: eight questions used to share out as [8, 0], and the part with no questions was read as
        // "the week's scans are used up" (a paywall card and a note), although three scans were left.
        let (app, relay) = relayApp()
        app.ai.setServerQuota(freeQuota(used: 0))
        let long = PageText(index: 0, label: "1", lines: (0..<50).map { l in
            TextLine(id: "p0.l\(l)", text: "Sentence \(l) on the long page says the duty of care runs to foreseeable plaintiffs only, as the court held in the case, and "
                     + "it said so at length, again and again, in so many words.", box: nil)
        })
        let short = (1...10).map { p in
            PageText(index: p, label: "\(p + 1)", lines: [TextLine(id: "p\(p).l0", text: "A short page number \(p) here", box: nil)])
        }
        let outcome = await app.ai.generateSet(input([long] + short, maxItems: 8))

        XCTAssertEqual(relay.generateRequests.map(\.maxItems), [5, 3])
        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [1, 10])
        XCTAssertEqual(outcome.items.count, 8)
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .read])
        XCTAssertNil(outcome.limitReached, "no scan was refused or left out")
        XCTAssertNil(outcome.suggestion, "no paywall card")
        XCTAssertEqual(outcome.note, "Read in 2 parts (2 of your free scans this week).")
    }

    func testAPageReadingAndTheQuestionsWrittenAfterItAreOneScan() async throws {
        let (app, relay) = scanApp()
        app.ai.setServerQuota(freeQuota(used: 0))
        // The formulas read: three pages, one request each, and one scan in all (the relay's window).
        for page in 0..<3 {
            let result = await app.ai.transcribeImage(base64JPEG: "aGk=", page: page, label: "\(page + 1)")
            guard case .lines = result else { return XCTFail("\(result)") }
        }
        XCTAssertEqual(relay.transcribeRequests.count, 3)
        XCTAssertEqual(app.ai.serverQuota?.meter(.scans)?.used, 1)
        XCTAssertEqual(app.ai.quotaState(for: .generate), .available(remaining: 2))
        XCTAssertEqual(app.ai.freeCloudUsesLeft(for: .generate), 2)

        // The questions for 14 pages: part 1 rides on the window, part 2 opens a scan. Two scans, not three.
        let outcome = await app.ai.generateSet(input(pages(14)))
        XCTAssertEqual(relay.generateRequests.count, 2)
        XCTAssertEqual(app.ai.serverQuota?.meter(.scans)?.used, 2)
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .read])
        XCTAssertNil(outcome.limitReached)
        XCTAssertEqual(app.ai.quotaState(for: .generate), .available(remaining: 1))
    }

    func testTheLastScanCanReadTheFormulasAndThenWriteTheQuestionsAfterThem() async throws {
        let (app, relay) = scanApp()
        app.ai.setServerQuota(freeQuota(used: 2))   // one scan left
        guard case .lines = await app.ai.transcribeImage(base64JPEG: "aGk=", page: 0, label: "1") else { return XCTFail() }
        XCTAssertEqual(app.ai.serverQuota?.meter(.scans)?.used, 3, "the reading took the last scan")
        // The week's scans are counted as used, yet the question-writing that follows rides on the one just opened.
        XCTAssertEqual(app.ai.quotaState(for: .generate), .available(remaining: 0))
        XCTAssertFalse(app.ai.route(.generate).limitReached != nil, "not a limit")

        let outcome = await app.ai.generateSet(input(pages(7)))
        XCTAssertEqual(relay.generateRequests.count, 1, "the questions for seven pages are one part")
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertNil(outcome.limitReached)
        XCTAssertNil(outcome.suggestion)
        XCTAssertEqual(outcome.items.count, 20)
        XCTAssertEqual(app.ai.serverQuota?.meter(.scans)?.used, 3, "no fourth scan")
        // The ride is spent with that request: the next one needs a scan the week doesn't have.
        XCTAssertEqual(app.ai.quotaState(for: .generate), .exhausted)

        // With fourteen pages the ride pays for the first part only; the pages after it wait and are named.
        let (again, second) = scanApp()
        again.ai.setServerQuota(freeQuota(used: 2))
        guard case .lines = await again.ai.transcribeImage(base64JPEG: "aGk=", page: 0, label: "1") else { return XCTFail() }
        let long = await again.ai.generateSet(input(pages(14)))
        XCTAssertEqual(second.generateRequests.map { $0.pages.count }, [10])
        XCTAssertEqual(long.note, "Cloud AI read pages 1 to 10. Pages 11 to 14 are waiting: this week's free scans are used up.")
        XCTAssertEqual(long.limitReached, .scans)
    }

    func testARideEndsWithTheWindowTheWeekOrAGenerate() {
        let opened = Date(timeIntervalSince1970: 1_790_000_000)
        let week = "2026-W44"
        var window = ScanWindow()
        XCTAssertFalse(window.canRideGenerate(at: opened, week: week), "nothing is open before a reading")
        XCTAssertTrue(window.record(.transcribe, pages: 1, at: opened, week: week, pageCap: 10), "a reading opens a scan")
        XCTAssertTrue(window.canRideGenerate(at: opened.addingTimeInterval(29 * 60), week: week))
        XCTAssertFalse(window.canRideGenerate(at: opened.addingTimeInterval(31 * 60), week: week), "a window lasts 30 minutes")
        XCTAssertFalse(window.canRideGenerate(at: opened.addingTimeInterval(60), week: "2026-W45"), "and a week")
        // More readings ride, up to the plan's pages; one more than that opens a new scan.
        XCTAssertFalse(window.record(.transcribe, pages: 8, at: opened.addingTimeInterval(10), week: week, pageCap: 10))
        XCTAssertTrue(window.record(.transcribe, pages: 2, at: opened.addingTimeInterval(20), week: week, pageCap: 10), "11 pages: a second scan")
        // A question-writing request rides once and closes the window: the next one is a scan of its own.
        XCTAssertFalse(window.record(.generate, pages: 7, at: opened.addingTimeInterval(30), week: week, pageCap: 10))
        XCTAssertFalse(window.canRideGenerate(at: opened.addingTimeInterval(40), week: week))
        XCTAssertTrue(window.record(.generate, pages: 7, at: opened.addingTimeInterval(50), week: week, pageCap: 10))
        XCTAssertTrue(window.record(.generate, pages: 7, at: opened.addingTimeInterval(60), week: week, pageCap: 10), "two generates are two scans")
        // A reading after a generate opens a new scan too.
        XCTAssertTrue(window.record(.transcribe, pages: 1, at: opened.addingTimeInterval(70), week: week, pageCap: 10))
    }

    func testTheRelayRefusingPartOneForTheWeeksScansThenTheIPhoneWritingTheSetKeepsTheLimitAndSaysSo() async throws {
        let (app, relay) = relayApp()
        relay.onGenerate = { _, _ in
            throw RelayError.quotaExceeded(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .scans, used: 3, limit: 3, period: .week)]),
                                           message: "That's this week's 3 AI scans on the free plan.")
        }
        let one = #"{"topics": [], "questions": [{"kind": "flashcard", "topic": "", "prompt": "Cytokinesis", "answer": "The division of the cytoplasm.", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]}]}"#
        app.ai.probe = FixedOnDeviceProbe(.ready)
        app.ai.onDevice = ScriptedOnDeviceBackend([.json(one)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)

        XCTAssertEqual(relay.generateRequests.count, 1)
        XCTAssertEqual(outcome.origin, .onDevice)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.limitReached, .scans, "the paywall card stays")
        guard case .upgrade(.scans, _)? = outcome.suggestion else { return XCTFail("\(String(describing: outcome.suggestion))") }
        XCTAssertEqual(outcome.note, "You've used this week's free Cloud AI scans, so your iPhone's AI wrote these.")
    }

    func testTheRelayRefusingALaterPartForTheWeeksScansKeepsTheFinishedParts() async throws {
        let (app, relay) = relayApp()
        relay.onGenerate = { request, call in
            if call == 2 {
                throw RelayError.quotaExceeded(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .scans, used: 3, limit: 3, period: .week)]),
                                               message: "That's this week's 3 AI scans on the free plan.")
            }
            return ScriptedRelay.response(for: request, call: call)
        }
        let outcome = await app.ai.generateSet(input(pages(14)))
        XCTAssertEqual(relay.generateRequests.count, 2)
        XCTAssertEqual(outcome.items.count, 12)
        XCTAssertEqual(outcome.limitReached, .scans)
        XCTAssertEqual(outcome.note, "Cloud AI read pages 1 to 7. Pages 8 to 14 are waiting: this week's free scans are used up.")
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .notStarted])
    }

    func testALaterPartFailingKeepsTheFinishedPartsAndSaysWhichPagesWereSkipped() async {
        let (app, relay) = relayApp()
        relay.onGenerate = { request, call in
            if call == 2 { throw RelayError.offline }
            return ScriptedRelay.response(for: request, call: call)
        }
        let outcome = await app.ai.generateSet(input(pages(25)))   // three parts: 9, 8 and 8 pages
        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [9, 8], "the third part isn't tried after the network failed")
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.items.count, 8)
        XCTAssertEqual(outcome.note, "Cloud AI read pages 1 to 9, but couldn't read pages 10 to 25 this time. Try those pages again later.")
        XCTAssertNil(outcome.limitReached)
        XCTAssertNil(outcome.suggestion)
        XCTAssertEqual(outcome.parts.map(\.status), [.read, .failed, .notStarted])
    }

    func testAPartWhoseQuestionsDontMatchThePageDoesNotStopTheNext() async {
        let (app, relay) = relayApp()
        relay.onGenerate = { request, call in
            var response = ScriptedRelay.response(for: request, call: call)
            if call == 1 { response.items = response.items.map { var item = $0; item.anchors = ["p99.l0"]; return item } }
            return response
        }
        let outcome = await app.ai.generateSet(input(pages(14)))
        XCTAssertEqual(relay.generateRequests.count, 2)
        XCTAssertEqual(outcome.items.count, 12)
        XCTAssertEqual(outcome.note, "Cloud AI read pages 8 to 14, but couldn't read pages 1 to 7 this time. Try those pages again later.")
        XCTAssertEqual(outcome.parts.map(\.status), [.failed, .read])
    }

    func testTheRelayStillRefusingThePageCountHalvesThePartsOnce() async {
        let (app, relay) = relayApp()
        relay.onGenerate = { request, call in
            // The relay's rule differs from the app's: it takes no more than 5 pages for this account.
            if request.pages.count > 5 { throw RelayError.entitlementRequired }
            return ScriptedRelay.response(for: request, call: call)
        }
        let outcome = await app.ai.generateSet(input(pages(14)))
        XCTAssertEqual(relay.generateRequests.map { $0.pages.count }, [7, 5, 5, 4], "refused once, then parts of at most 5")
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.parts.count, 3)
        XCTAssertEqual(outcome.note, "Read in 3 parts (3 of your free scans this week).")

        // Refused again at the halved size: not a loop. The next tier answers, and the note says why.
        let (stubborn, always) = relayApp()
        always.onGenerate = { _, _ in throw RelayError.entitlementRequired }
        let rules = await stubborn.ai.generateSet(input(pages(14)))
        XCTAssertEqual(always.generateRequests.map { $0.pages.count }, [7, 5], "halved once and no more")
        XCTAssertEqual(rules.origin, .rules)
        XCTAssertTrue(rules.fellBack)
    }

    // MARK: Why the first part failed

    func testAFirstPartThatFailsFallsBackAndTheNoteSaysWhy() async {
        let cases: [(RelayError, String)] = [
            (.offline, "Cloud AI couldn't be reached, so these are basic questions from the offline rules."),
            (.accountPending, "Cloud AI is getting ready, so these are basic questions from the offline rules. Try again in a minute."),
            (.quotaExceeded(QuotaStatus(plan: .free, meters: []), message: "That's all the cloud AI for today. It starts again at midnight."),
             "That's all the cloud AI for today. It starts again at midnight. These are basic questions from the offline rules."),
            (.entitlementRequired, "Cloud AI couldn't take a reading this long, so these are basic questions from the offline rules."),
        ]
        for (error, note) in cases {
            let (app, relay) = relayApp()
            relay.onGenerate = { _, _ in throw error }
            let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
            XCTAssertEqual(outcome.origin, .rules, "\(error)")
            XCTAssertTrue(outcome.fellBack, "\(error)")
            XCTAssertEqual(outcome.note, note, "\(error)")
            XCTAssertFalse(outcome.items.isEmpty)
        }
    }

    func testCloudQuestionsThatAllMissTheirLinesAreSaidSoToo() async {
        let (app, relay) = relayApp()
        relay.onGenerate = { request, call in
            var response = ScriptedRelay.response(for: request, call: call)
            response.items = response.items.map { var item = $0; item.anchors = ["nowhere"]; return item }
            return response
        }
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertEqual(outcome.note, "Cloud AI's questions didn't match your page, so these are basic questions from the offline rules.")
    }

    func testAnOnDeviceSetAfterAFailedCloudAttemptSaysWhy() async {
        let (app, relay) = relayApp()
        relay.onGenerate = { _, _ in throw RelayError.offline }
        let one = #"{"topics": [], "questions": [{"kind": "flashcard", "topic": "", "prompt": "Cytokinesis", "answer": "The division of the cytoplasm.", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]}]}"#
        app.ai.probe = FixedOnDeviceProbe(.ready)
        app.ai.onDevice = ScriptedOnDeviceBackend([.json(one)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .onDevice)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.note, "Cloud AI couldn't be reached, so your iPhone's AI wrote these.")

        // Cloud AI never tried (not allowed yet): no note about it.
        let (quiet, _) = relayApp(consent: false)
        quiet.ai.probe = FixedOnDeviceProbe(.ready)
        quiet.ai.onDevice = ScriptedOnDeviceBackend([.json(one)])
        let plain = await quiet.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(plain.origin, .onDevice)
        XCTAssertNil(plain.note)
    }

    // MARK: Strings the relay limits are cut by code points

    func testEveryStringTheRelayLimitsIsCutByCodePointsNotCharacters() async throws {
        // 150 decomposed "é" are 150 characters and 300 code points; the relay counts the 300.
        let decomposed = { (characters: Int) in String(repeating: "e\u{0301}", count: characters) }
        XCTAssertEqual(decomposed(150).count, 150)
        let (app, relay) = scanApp()
        app.ai.setServerQuota(freeQuota(used: 0))
        let label = String(repeating: "👍🏽", count: 40)   // 80 code points
        let page = PageText(index: 0, label: label, lines: pages(1)[0].lines + [
            TextLine(id: "p0.l90", text: decomposed(120), box: nil),   // a heading, long enough to be cut
        ])
        let outcome = await app.ai.generateSet(GenerationInput(course: decomposed(150), sourceTitle: decomposed(200), level: "college", pages: [page],
                                                               maxItems: 8))
        XCTAssertEqual(outcome.origin, .cloud)

        let generate = try XCTUnwrap(relay.generateRequests.first)
        XCTAssertLessThanOrEqual(generate.course.unicodeScalars.count, RelayLimits.course)
        XCTAssertLessThanOrEqual(generate.sourceTitle.unicodeScalars.count, RelayLimits.title)
        XCTAssertEqual(generate.course.unicodeScalars.count, 200, "300 code points cut to the relay's 200")
        XCTAssertEqual(generate.sourceTitle.unicodeScalars.count, 300, "400 code points cut to the relay's 300")
        XCTAssertEqual(generate.pages.first?.label.unicodeScalars.count, RelayLimits.label, "80 code points cut to the relay's 40")
        XCTAssertEqual(generate.pages.first?.label, String(repeating: "👍🏽", count: 20), "between characters, never through a skin tone")

        let check = try XCTUnwrap(relay.checkRequests.first)
        XCTAssertEqual(check.sourceTitle?.unicodeScalars.count, RelayLimits.checkTitle, "the check takes at most 200")
        XCTAssertEqual(check.pages.first?.label.unicodeScalars.count, RelayLimits.label)
        for heading in check.headings ?? [] { XCTAssertLessThanOrEqual(heading.unicodeScalars.count, RelayLimits.heading) }

        // A page reading's label too, and the course name the mistake patterns and the cards from a chat carry.
        _ = await app.ai.transcribeImage(base64JPEG: "aGk=", page: 0, label: label)
        XCTAssertEqual(relay.transcribeRequests.first?.label.unicodeScalars.count, RelayLimits.label)
        let mistakes = [MistakeInput(itemId: "i4", topic: "Phases", prompt: "Describe what happens in anaphase.", expected: "Anaphase",
                                     given: "Telophase", misses: 2)]
        _ = await app.ai.confusions(course: decomposed(150), mistakes: mistakes)
        XCTAssertEqual(relay.confusionsRequests.first?.course.unicodeScalars.count, RelayLimits.course)
        let chat = [TutorMessage(role: .user, text: "What is mitosis?"),
                    TutorMessage(role: .assistant, text: "Mitosis is how a cell divides into two identical daughter cells.")]
        _ = await app.ai.cardsFromChat(course: decomposed(150), messages: chat, maxItems: 6)
        XCTAssertEqual(relay.cardsFromChatRequests.first?.course?.unicodeScalars.count, RelayLimits.course)
        // And a line longer than the relay takes is cut to what it takes, keeping its id.
        let giant = PageText(index: 0, label: "1", lines: [TextLine(id: "p0.l0", text: String(repeating: "word ", count: 1_000), box: nil)])
        _ = await app.ai.generateSet(GenerationInput(course: "Torts", sourceTitle: "T", level: "college", pages: [giant], maxItems: 8))
        let lastGenerate = try XCTUnwrap(relay.generateRequests.last)
        XCTAssertEqual(lastGenerate.pages.first?.lines.first?.id, "p0.l0")
        XCTAssertLessThanOrEqual(lastGenerate.pages.first?.lines.first?.text.unicodeScalars.count ?? 0, RelayLimits.lineText)
    }

    func testCardsFromAChatGoWithTheLastSixtyMessagesThatSaySomething() async throws {
        let (app, relay) = relayApp()
        // 80 messages: a reply that only drafted cards has no text (the relay refuses an empty message), one is longer than it takes.
        let messages = (0..<80).map { i in
            TutorMessage(role: i % 2 == 0 ? .user : .assistant,
                         text: i == 21 || i == 61 ? "" : i == 30 ? String(repeating: "x", count: 9_000) : "Message \(i) about the cell cycle.")
        }
        let outcome = await app.ai.cardsFromChat(course: "Bio 101", messages: messages)
        XCTAssertEqual(outcome.origin, .cloud, "the relay is asked, not skipped for a request it would have refused")
        let sent = try XCTUnwrap(relay.cardsFromChatRequests.first)
        XCTAssertEqual(sent.messages.count, 60)
        XCTAssertTrue(sent.messages.allSatisfy { !$0.text.isEmpty && $0.text.unicodeScalars.count <= RelayLimits.messageText })
        XCTAssertEqual(sent.messages.first?.text, "Message 18 about the cell cycle.", "78 say something; the last 60 of them")
        XCTAssertEqual(sent.messages.last?.text, "Message 79 about the cell cycle.")
        XCTAssertEqual(sent.messages.first { $0.text.hasPrefix("xxx") }?.text.unicodeScalars.count, 8_000)

        // Nothing in the thread says anything: nothing to send, and the offline rules answer.
        let (quiet, silent) = relayApp()
        let none = await quiet.ai.cardsFromChat(course: "Bio 101", messages: [TutorMessage(role: .assistant, text: ""), TutorMessage(role: .assistant, text: "")])
        XCTAssertTrue(silent.cardsFromChatRequests.isEmpty)
        XCTAssertEqual(none.origin, .rules)
    }

    func testTheMistakesOfAMixUpAreCutToWhatTheRelayTakes() async throws {
        let (app, relay) = relayApp()
        let mistakes = (0..<45).map { i in
            MistakeInput(itemId: "i\(i)", topic: "Phases", prompt: "Describe what happens in anaphase.", expected: "Anaphase",
                         given: String(repeating: "Telophase ", count: 1_000), misses: 2)
        }
        _ = await app.ai.confusions(course: "Bio 101", mistakes: mistakes)
        let sent = try XCTUnwrap(relay.confusionsRequests.first)
        XCTAssertEqual(sent.mistakes.count, RelayLimits.mistakes)
        XCTAssertTrue(sent.mistakes.allSatisfy { $0.given.unicodeScalars.count <= RelayLimits.contextAnswer })
    }

    // MARK: The language the questions are written in

    /// An English chemistry worksheet, photographed: the recogniser read this Polish at 63%, and Cloud AI wrote the questions in Polish.
    static let equations = "start: [H2] = [2] = 0.200 M, no HH. Find equil I] E H2 0.200 -X 0.200-x 12 0.200 -X 0.200-X HI Kc = (2x)\" / (0.200 - x)° = 50.0 "
        + "take sqrt of both sides: 2x/(0.200-x) = 7.07 2x= 1.414 - 7.07x 9.07x=1.414 x = 0.156 LIH2]=[12]=0.044M| [[HI] = 0.312M] 3) mix: "
        + "[H2] = 0.50 [12] = 0.50 [HI] = 5.0 Q = (5.0)° / (0.50) (0.50) = 100 Q > Kaso shifts LEFT (toward reactants) "
        + "An = n(gas products) - w(gas reactants)"

    func testAnEquationSheetIsNotWrittenUpInARareLanguageTheRecogniserGuessedFromItsSymbols() async throws {
        // One line, as the recogniser of the photo gave it.
        let page = PageText(index: 0, label: "1", lines: [TextLine(id: "p0.l0", text: Self.equations, box: nil)])
        let (app, relay) = relayApp()
        _ = await app.ai.generateSet(GenerationInput(course: "Chemistry", sourceTitle: "Equilibrium worksheet", level: "college", pages: [page],
                                                     maxItems: 8))
        let request = try XCTUnwrap(relay.generateRequests.first)
        XCTAssertNotEqual(request.language, "pl")
        XCTAssertEqual(request.language, LocalGenerator.deviceLanguage(), "no other source in the course said: the device's")

        // The course's other sources are in Spanish: the questions are too.
        let (spanish, spanishRelay) = relayApp()
        _ = await spanish.ai.generateSet(GenerationInput(course: "Química", sourceTitle: "Hoja", level: "college", pages: [page], maxItems: 8,
                                                         courseLanguage: "es"))
        XCTAssertEqual(spanishRelay.generateRequests.first?.language, "es")

        // A real paragraph in another language still says what it is, whatever the course says.
        let polish = PageText(index: 0, label: "1", lines: [TextLine(id: "p0.l0", text: OfflineLanguageTests.polishParagraph, box: nil)])
        let (other, otherRelay) = relayApp()
        _ = await other.ai.generateSet(GenerationInput(course: "Biologia", sourceTitle: "Mitoza", level: "college", pages: [polish], maxItems: 8,
                                                       courseLanguage: "en"))
        XCTAssertEqual(otherRelay.generateRequests.first?.language, "pl")
    }

    // MARK: The check

    func testTheCheckCarriesTheSourcesTitleAndItsHeadings() async throws {
        let (app, relay) = relayApp()
        var lines = pages(1)[0].lines
        lines.insert(TextLine(id: "p0.l99", text: "The Question of Duty", box: nil), at: 3)
        let outcome = await app.ai.generateSet(input([PageText(index: 0, label: "1", lines: lines)], maxItems: 8))
        XCTAssertEqual(outcome.origin, .cloud)
        let check = try XCTUnwrap(relay.checkRequests.first)
        XCTAssertEqual(check.sourceTitle, "Palsgraf v. Long Island Railroad")
        XCTAssertEqual(check.headings, ["The Question of Duty"])
        XCTAssertNil(check.lenient, "the first pass is strict")
        // The wire form leaves absent fields out, so build 2's relay and this one's read the same request.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.cramless.encode(CheckRequest(pages: [], items: []))) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["pages", "items"])
    }

    func testAPalsgrafLikeRejectionIsAskedAgainLeniently() async throws {
        let (app, relay) = relayApp()
        relay.onCheck = { request, call in
            // Strict: every question "unsupported" because the cited lines never name the judge. Lenient: all fine.
            CheckResponse(model: "scripted", verdicts: request.items.map {
                call == 1 ? CheckVerdict(id: $0.id, verdict: .unsupported, reason: "The cited lines do not identify Cardozo.")
                    : CheckVerdict(id: $0.id, verdict: .supported, reason: "")
            })
        }
        let outcome = await app.ai.generateSet(input(pages(4), maxItems: 16))
        XCTAssertEqual(relay.checkRequests.count, 2)
        XCTAssertNil(relay.checkRequests[0].lenient)
        XCTAssertEqual(relay.checkRequests[1].lenient, true)
        XCTAssertEqual(relay.checkRequests[1].sourceTitle, "Palsgraf v. Long Island Railroad")
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.checkedBy, .cloud, "the lenient pass was believed")
        XCTAssertEqual(outcome.items.count, 16)
        XCTAssertTrue(outcome.dropped.isEmpty)
        XCTAssertNil(outcome.note)
    }

    func testARejectionThatStaysTotalIsCheckedOnThisIPhoneInsteadOfFailingTheCloudAttempt() async throws {
        let (app, relay) = relayApp()
        relay.onCheck = { request, _ in
            CheckResponse(model: "scripted", verdicts: request.items.map {
                CheckVerdict(id: $0.id, verdict: .unsupported, reason: "The cited lines do not identify Cardozo as the judge.")
            })
        }
        let outcome = await app.ai.generateSet(input(pages(4), maxItems: 16))
        XCTAssertEqual(relay.checkRequests.count, 2, "once strict, once lenient, never a third")
        XCTAssertEqual(outcome.origin, .cloud, "the cloud attempt is not thrown away")
        XCTAssertFalse(outcome.fellBack)
        XCTAssertEqual(outcome.checkedBy, .rules)
        XCTAssertEqual(outcome.items.count, 16, "the questions the page backs are kept")
        XCTAssertEqual(outcome.note, "Cloud AI wrote these; your iPhone checked them against the page because the second pass rejected everything.")
    }

    func testTheLocalCheckStillDropsWhatThePageDoesNotBack() async {
        let (app, relay) = relayApp()
        relay.onGenerate = { request, call in
            var response = ScriptedRelay.response(for: request, call: call)
            // Four answers the page doesn't hold.
            for i in 0..<4 { response.items[i].answer = "Photosynthesis turns sunlight into sugar in the chloroplasts." }
            return response
        }
        relay.onCheck = { request, _ in
            CheckResponse(model: "scripted", verdicts: request.items.map { CheckVerdict(id: $0.id, verdict: .unsupported, reason: "no") })
        }
        let outcome = await app.ai.generateSet(input(pages(4), maxItems: 16))
        XCTAssertEqual(outcome.items.count, 12)
        XCTAssertEqual(outcome.dropped.count, 4)
        XCTAssertEqual(outcome.checkedBy, .rules)
    }

    func testAnOrdinaryCheckIsOneRequest() async {
        let (app, relay) = relayApp()
        relay.onCheck = { request, _ in
            // Two of sixteen rejected: nothing suspicious.
            CheckResponse(model: "scripted", verdicts: request.items.enumerated().map {
                CheckVerdict(id: $0.element.id, verdict: $0.offset < 2 ? .unsupported : .supported, reason: "")
            })
        }
        let outcome = await app.ai.generateSet(input(pages(4), maxItems: 16))
        XCTAssertEqual(relay.checkRequests.count, 1)
        XCTAssertEqual(outcome.items.count, 14)
        XCTAssertEqual(outcome.dropped.count, 2)
        XCTAssertEqual(outcome.checkedBy, .cloud)
    }
}

/// A relay whose answers a test scripts per call. By default a generate writes up to `maxItems` flashcards, one per line,
/// each answered by its own line, and a check finds everything supported.
final class ScriptedRelay: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _generate: [GenerateRequest] = []
    private var _check: [CheckRequest] = []
    var onGenerate: (@Sendable (GenerateRequest, Int) throws -> GenerateResponse)?
    var onCheck: (@Sendable (CheckRequest, Int) throws -> CheckResponse)?
    var onLecture: (@Sendable (LectureRequest) throws -> LectureResponse)?
    var onTranscribe: (@Sendable (TranscribeImageRequest) throws -> TranscribeImageResponse)?
    private var _lecture: [LectureRequest] = []
    private var _transcribe: [TranscribeImageRequest] = []
    private var _confusions: [ConfusionsRequest] = []
    private var _cards: [CardsFromChatRequest] = []

    var generateRequests: [GenerateRequest] { lock.withLock { _generate } }
    var checkRequests: [CheckRequest] { lock.withLock { _check } }
    var lectureRequests: [LectureRequest] { lock.withLock { _lecture } }
    var transcribeRequests: [TranscribeImageRequest] { lock.withLock { _transcribe } }
    var confusionsRequests: [ConfusionsRequest] { lock.withLock { _confusions } }
    var cardsFromChatRequests: [CardsFromChatRequest] { lock.withLock { _cards } }

    /// Part `call` (1-based) of a reading: ids restart at i1 in every response, as the relay's do.
    static func response(for request: GenerateRequest, call: Int) -> GenerateResponse {
        let lines = request.pages.flatMap(\.lines).filter { $0.text.split(separator: " ").count >= 4 }
        let topic = call == 2 ? "duty" : (call >= 3 ? "Damages" : "Torts")
        let items = lines.prefix(request.maxItems).enumerated().map { index, line in
            GeneratedItem(id: "i\(index + 1)", kind: .flashcard, topic: call == 2 && index % 2 == 1 ? "Duty" : topic,
                          prompt: "What does \(line.id) say?", answer: line.text, anchors: [line.id])
        }
        let names = Array(NSOrderedSet(array: items.map(\.topic))) as? [String] ?? []
        return GenerateResponse(title: "Palsgraf", model: "scripted", topics: names.map { GeneratedTopic(name: $0, summary: "") },
                                items: Array(items))
    }

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse {
        let call = lock.withLock { () -> Int in _generate.append(request); return _generate.count }
        return try (onGenerate ?? { Self.response(for: $0, call: $1) })(request, call)
    }

    func check(_ request: CheckRequest) async throws -> CheckResponse {
        let call = lock.withLock { () -> Int in _check.append(request); return _check.count }
        if let onCheck { return try onCheck(request, call) }
        return CheckResponse(model: "scripted", verdicts: request.items.map { CheckVerdict(id: $0.id, verdict: .supported, reason: "") })
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse { throw RelayError.upstream("not scripted") }
    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: RelayError.upstream("not scripted")) }
    }
    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse {
        lock.withLock { _confusions.append(request) }
        return try RelayFixtures.load(ConfusionsResponse.self, "confusions")
    }
    func lecture(_ request: LectureRequest) async throws -> LectureResponse {
        lock.withLock { _lecture.append(request) }
        guard let onLecture else { throw RelayError.upstream("not scripted") }
        return try onLecture(request)
    }
    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse {
        lock.withLock { _cards.append(request) }
        return try RelayFixtures.load(CardsFromChatResponse.self, "cards-from-chat")
    }
    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse {
        lock.withLock { _transcribe.append(request) }
        guard let onTranscribe else { throw RelayError.upstream("not scripted") }
        return try onTranscribe(request)
    }
    func quota() async throws -> QuotaStatus { throw RelayError.upstream("not scripted") }
}
