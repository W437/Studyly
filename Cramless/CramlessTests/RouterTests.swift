import UIKit
import XCTest
@testable import Cramless

/// The routing function against an oracle table and over its whole input matrix, then the router service end to
/// end: consent gating, the generate pipeline in mock mode, fallbacks, quota, and requests built after a wait.
@MainActor
final class RouterTests: XCTestCase {

    // MARK: The oracle

    private func context(_ job: AIJob, mode: AppConfig.AIMode = .relay, consent: Bool = true, photos: Bool = false,
                         device: OnDeviceAvailability = .available, fits: Bool = true, quota: AIQuotaState = .available(remaining: 5),
                         plan: Plan = .free, age: AIAgeGate = .adult, strongest: Bool = false,
                         preferCloud: Bool = false) -> AIRouteContext {
        AIRouteContext(job: job, mode: mode, consent: consent, sendPhotos: photos, onDevice: device, fitsOnDevice: fits,
                       quota: quota, plan: plan, age: age, strongest: strongest, preferCloud: preferCloud)
    }

    func testOracleTable() {
        let off = OnDeviceAvailability.unavailable(.deviceNotEligible)
        let cloud = AISuggestion.allowCloud(feature: AIJob.generate.feature)
        let rows: [(String, AIRouteContext, [AITier], AISuggestion?, QuotaMeter.Key?)] = [
            ("generate: everything allowed", context(.generate), [.cloud, .onDevice], nil, nil),
            ("generate: no consent", context(.generate, consent: false), [.onDevice], cloud, nil),
            ("generate: no consent, no device", context(.generate, consent: false, device: off), [], cloud, nil),
            ("generate: local build", context(.generate, mode: .local, consent: false, device: off), [], nil, nil),
            ("generate: mock is a relay", context(.generate, mode: .mock), [.cloud, .onDevice], nil, nil),
            ("generate: not English", context(.generate, fits: false), [.cloud], nil, nil),
            ("generate: free limit reached", context(.generate, quota: .exhausted), [],
             .upgrade(.scans, message: AIFreeLimits.message(for: .scans)), .scans),
            ("generate: paid plan ignores the count", context(.generate, quota: .exhausted, plan: .pro), [.cloud, .onDevice], nil, nil),
            ("generate: under 13", context(.generate, age: .child), [.onDevice], nil, nil),
            ("grade: short answer, device first", context(.grade), [.onDevice, .cloud], nil, nil),
            ("grade: long or shaky, cloud first", context(.grade, preferCloud: true), [.cloud, .onDevice], nil, nil),
            ("grade: grade again", context(.grade, strongest: true), [.cloud, .onDevice], nil, nil),
            ("grade: no consent, device can grade", context(.grade, consent: false), [.onDevice], nil, nil),
            ("grade: no consent, no device", context(.grade, consent: false, device: off), [],
             .allowCloud(feature: AIJob.grade.feature), nil),
            ("grade: limit", context(.grade, quota: .exhausted), [], .upgrade(.grades, message: AIFreeLimits.message(for: .grades)), .grades),
            ("tutor: minor", context(.tutor, age: .minor), [.cloud, .onDevice], nil, nil),
            ("confusions: cloud only", context(.confusions), [.cloud], nil, nil),
            ("confusions: no consent", context(.confusions, consent: false), [], .allowCloud(feature: AIJob.confusions.feature), nil),
            ("confusions: unmetered even when others are spent", context(.confusions, quota: .exhausted), [.cloud], nil, nil),
            ("photos: switch off", context(.transcribeImage), [], .allowPhotos, nil),
            ("photos: switch on", context(.transcribeImage, photos: true), [.cloud], nil, nil),
            ("photos: no consent", context(.transcribeImage, consent: false, photos: true), [],
             .allowCloud(feature: AIJob.transcribeImage.feature), nil),
            ("lecture: device busy (transient)", context(.lecture, device: .unavailable(.lowPower)), [.cloud], nil, nil),
            ("cards: everything", context(.cardsFromChat), [.cloud, .onDevice], nil, nil),
        ]
        for (name, ctx, tiers, suggestion, limit) in rows {
            let route = AIRouting.route(ctx)
            XCTAssertEqual(route.tiers, tiers, name)
            XCTAssertEqual(route.suggestion, suggestion, name)
            XCTAssertEqual(route.limitReached, limit, name)
        }
        XCTAssertEqual(AIRouting.route(context(.tutor, age: .minor)).forcedTutorMode, .hints)
        XCTAssertEqual(AIRouting.route(context(.tutor, age: .child)).forcedTutorMode, .hints)
        XCTAssertNil(AIRouting.route(context(.tutor)).forcedTutorMode)
    }

    func testInvariantsOverTheWholeMatrix() {
        let modes: [AppConfig.AIMode] = [.relay, .local, .mock]
        let devices: [OnDeviceAvailability] = [.available, .unavailable(.deviceNotEligible), .unavailable(.modelNotReady)]
        let quotas: [AIQuotaState] = [.unmetered, .available(remaining: 1), .exhausted]
        var checked = 0
        for job in AIJob.allCases { for mode in modes { for consent in [true, false] { for photos in [true, false] {
        for device in devices { for fits in [true, false] { for quota in quotas { for plan in [Plan.free, .pro] {
        for age in AIAgeGate.allCases { for strongest in [true, false] { for preferCloud in [true, false] {
            let c = AIRouteContext(job: job, mode: mode, consent: consent, sendPhotos: photos, onDevice: device, fitsOnDevice: fits,
                                   quota: quota, plan: plan, age: age, strongest: strongest, preferCloud: preferCloud)
            let r = AIRouting.route(c)
            let label = "\(c)"
            XCTAssertFalse(r.tiers.contains(.rules), label)
            XCTAssertEqual(Set(r.tiers).count, r.tiers.count, label)
            if r.tiers.contains(.cloud) {
                XCTAssertNotEqual(mode, .local, label)
                XCTAssertTrue(consent, label)
                XCTAssertNotEqual(age, .child, label)
                if job == .transcribeImage { XCTAssertTrue(photos, label) }
            }
            if r.tiers.contains(.onDevice) {
                XCTAssertEqual(device, .available, label)
                XCTAssertTrue(fits, label)
                XCTAssertTrue(job.runsOnDevice, label)
            }
            XCTAssertFalse(r.tiers.contains(.privateCloud), "dormant: \(label)")
            if job.meter != nil, plan == .free, quota == .exhausted {
                XCTAssertTrue(r.tiers.isEmpty, label)
                XCTAssertEqual(r.limitReached, job.meter, label)
            } else {
                XCTAssertNil(r.limitReached, label)
            }
            if case .allowCloud = r.suggestion {
                XCTAssertFalse(consent, label)
                XCTAssertNotEqual(mode, .local, label)
                XCTAssertNotEqual(age, .child, label)
            }
            if age == .child, case .allowCloud = r.suggestion { XCTFail("never ask a child: \(label)") }
            if job == .tutor, age != .adult { XCTAssertEqual(r.forcedTutorMode, .hints, label) }
            checked += 1
        }}}}}}}}}}}
        XCTAssertGreaterThan(checked, 10_000)
    }

    // MARK: Consent gating

    func testNoCloudCallWithoutConsent() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: false)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport

        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertTrue(transport.calls.isEmpty, "\(transport.calls)")
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertGreaterThanOrEqual(outcome.items.count, 8)
        XCTAssertEqual(outcome.suggestion, .allowCloud(feature: AIJob.generate.feature))
        XCTAssertEqual(outcome.note, "Basic questions from the offline rules. Turn on Cloud AI for better ones.")
        XCTAssertEqual(outcome.suggestion?.sheet, .consent(.cloudAI(feature: AIJob.generate.feature)))

        let subject = GradeSubject(item: AITestSupport.fixtureItem("i1"))
        _ = await app.ai.gradeNow(subject, answer: .text("So the body can grow and repair tissue, making two identical cells."))
        _ = await app.ai.gradeAgain(subject, answer: .text("So the body can grow."))
        _ = await app.ai.tutorReply(TutorInput(messages: [TutorMessage(role: .user, text: "What happens in anaphase?")], course: nil,
                                               material: AITestSupport.material))
        _ = await app.ai.lectureNotes(LectureInput(course: "Bio 101", title: "Lecture 6", segments: AITestSupport.lectureSegments, flags: []))
        _ = await app.ai.cardsFromChat(course: nil, messages: [TutorMessage(role: .assistant, text: "Cytokinesis is the division of the cytoplasm.")])
        let photo = await app.ai.transcribeImage(base64JPEG: "x", page: 0, label: "1")
        XCTAssertEqual(photo, .notAllowed(.allowCloud(feature: AIJob.transcribeImage.feature)))
        await app.ai.refreshQuota()
        XCTAssertTrue(transport.calls.isEmpty, "\(transport.calls)")

        // Allowed: the same job now goes to the relay, generate then check.
        app.allowCloudAI()
        let cloud = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(transport.calls, ["generate", "check"])
        XCTAssertEqual(cloud.origin, .cloud)
        XCTAssertNil(cloud.note)
    }

    func testUnderThirteenNeverGoesToTheCloudOrIsAsked() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true, age: .under13)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertNil(outcome.suggestion)
    }

    // MARK: Generate end to end

    func testMockGenerateRunsEveryPhaseAndAppliesTheCheck() async throws {
        let app = AITestSupport.makeApp(mode: .mock)
        var phases: [GenerationPhase] = []
        var final: GenerationOutcome?
        for await update in app.ai.generateSet(AITestSupport.sampleInput) {
            switch update {
            case .progress(let p): if phases.last != p.phase { phases.append(p.phase) }
            case .finished(let o): final = o
            }
        }
        XCTAssertEqual(phases, [.reading, .findingKeyIdeas, .writingQuestions, .checking])
        let outcome = try XCTUnwrap(final)
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.checkedBy, .cloud)
        XCTAssertEqual(outcome.items.count, 15)
        XCTAssertEqual(outcome.dropped.map(\.item.id), ["i8"])
        XCTAssertTrue(outcome.dropped[0].reason.contains("never mentions sex cells"))
        XCTAssertEqual(outcome.items.first { $0.id == "i2" }?.answer,
                       "Both new cells have the same DNA, and the same number of chromosomes, as the parent cell.")
        XCTAssertEqual(outcome.topics.count, 4)
    }

    func testCloudFailureFallsBackToTheRules() async {
        let app = AITestSupport.makeApp(mode: .mock)
        var input = AITestSupport.sampleInput
        input.pages[0].lines.append(TextLine(id: "p0.l40", text: "#fail", box: nil))
        let outcome = await app.ai.generateSet(input)
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.note, "Cloud AI couldn't be reached, so these are basic questions from the offline rules.")
        XCTAssertFalse(outcome.items.isEmpty)
    }

    func testPhasesNeverGoBackWhenATierFallsBack() async throws {
        // The fixture's anchors ("p0.l…") aren't lines of this page ("q0.l…"): the cloud gets as far as checking,
        // every item fails the anchor check, and the rules take over without the steps going backwards.
        let app = AITestSupport.makeApp(mode: .mock)
        let lines = AITestSupport.sampleLines.map { TextLine(id: $0.id.replacingOccurrences(of: "p0.", with: "q0."), text: $0.text, box: $0.box) }
        let input = GenerationInput(course: "Bio 101", sourceTitle: "Biology textbook", pages: [PageText(index: 0, label: "87", lines: lines)])
        var seen: [GenerationProgress] = []
        var final: GenerationOutcome?
        for await update in app.ai.generateSet(input) {
            switch update {
            case .progress(let p): seen.append(p)
            case .finished(let o): final = o
            }
        }
        let phases = seen.map(\.phase)
        XCTAssertEqual(phases, phases.sorted(), "\(phases)")
        XCTAssertTrue(seen.contains { $0.origin == .cloud && $0.phase == .checking })
        XCTAssertEqual(seen.last?.origin, .rules)
        let outcome = try XCTUnwrap(final)
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertTrue(outcome.items.allSatisfy { $0.anchors.allSatisfy { $0.hasPrefix("q0.") } })
    }

    func testCheckFailureStillChecksOnTheDevice() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        transport.failures["check"] = .offline
        app.ai.transportOverride = transport
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.checkedBy, .rules)
        XCTAssertFalse(outcome.items.isEmpty)
    }

    // MARK: After any wait

    func testConsentWithdrawnDuringTheWaitStopsTheCheck() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        transport.duringGenerate = { app.withdrawCloudAI() }
        app.ai.transportOverride = transport
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(transport.calls, ["generate"], "no check request after consent was withdrawn")
        XCTAssertEqual(outcome.checkedBy, .rules)
    }

    func testConsentWithdrawnDuringTheOnDeviceAttemptStopsTheCloudGrade() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        app.ai.probe = FixedOnDeviceProbe(.ready)
        // This iPhone's model fails, but only after the person turned Cloud AI off.
        app.ai.onDevice = HookBackend { app.withdrawCloudAI() }
        let outcome = await app.ai.gradeNow(GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: .text("They grow."))
        XCTAssertTrue(transport.calls.isEmpty, "\(transport.calls)")
        XCTAssertEqual(outcome.gradedBy, .rules)
    }

    func testUnderThirteenNeverAsksTheServerForQuota() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true, age: .under13)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        await app.ai.refreshQuota()
        XCTAssertTrue(transport.calls.isEmpty)
        let consented = AITestSupport.makeApp(mode: .relay, consent: true)
        consented.ai.transportOverride = transport
        await consented.ai.refreshQuota()
        XCTAssertEqual(transport.calls, ["quota"])
    }

    func testCloudScansCountBeforeTheServerHasBeenAsked() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        app.ai.resetUsage()
        for _ in 0..<3 { _ = await app.ai.generateSet(AITestSupport.sampleInput) }
        XCTAssertEqual(transport.calls.filter { $0 == "generate" }.count, 3)
        XCTAssertEqual(app.ai.quotaState(for: .generate), .exhausted)
        let fourth = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(fourth.limitReached, .scans)
        XCTAssertEqual(fourth.origin, .rules)
        XCTAssertEqual(transport.calls.filter { $0 == "generate" }.count, 3, "no fourth request")
        // A fresh count from the server already includes these: the two are never added.
        app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .scans, used: 3, limit: 3, period: .week)]))
        XCTAssertEqual(app.ai.quotaStatus.meter(.scans)?.used, 3)
    }

    func testPagePhotosGoOnlyWithTheirSwitch() async throws {
        let imageURL = try XCTUnwrap(SamplePage.imageURL)
        var input = AITestSupport.sampleInput
        input.pages[0].imageURL = imageURL

        let app = AITestSupport.makeApp(mode: .relay, consent: true, photos: false)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        _ = await app.ai.generateSet(input)
        XCTAssertNil(transport.generateRequests.first?.pages.first?.image)

        app.setSendPhotos(true)
        _ = await app.ai.generateSet(input)
        let image = try XCTUnwrap(transport.generateRequests.last?.pages.first?.image)
        let data = try XCTUnwrap(Data(base64Encoded: image))
        XCTAssertNotNil(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(UIImage(data: data)!.size.width, UIImage(data: data)!.size.height), 1300)
        // The check pass never carries photos.
        XCTAssertTrue(transport.checkRequests.allSatisfy { $0.pages.allSatisfy { $0.image == nil } })
    }

    // MARK: Grading through the router

    func testGradeGivesTheInstantGradeThenTheRefinedOne() async throws {
        let app = AITestSupport.makeApp(mode: .mock)
        let answer = "So the body can grow and repair tissue, making two identical cells."
        var outcomes: [GradeOutcome] = []
        for await o in app.ai.grade(GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: .text(answer)) { outcomes.append(o) }
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes[0].gradedBy, .rules)
        XCTAssertFalse(outcomes[0].isRefined)
        let refined = outcomes[1]
        XCTAssertEqual(refined.gradedBy, .cloud)
        XCTAssertEqual(refined.verdict, .partial)
        XCTAssertEqual(refined.missing.map(\.label), ["Same number of chromosomes"])
        XCTAssertEqual(AITestSupport.marked(refined, in: answer), ["grow and repair tissue", "two identical cells"])
    }

    func testCloudQuotesNotInTheAnswerAreNeverMarked() {
        let answer = "Cells grow, and the copies are identical."
        let local = LocalGrader.grade(GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: .text(answer))
        let response = GradeResponse(model: "m", score: 0.67, verdict: .partial, confidence: 0.8,
                                     hits: [GradeHit(ideaId: "k1", quote: "grow and repair tissue"),
                                            GradeHit(ideaId: "k2", quote: "the copies are identical"),
                                            GradeHit(ideaId: "k9", quote: "Cells")],
                                     missing: ["k3"], feedback: "f", fix: "x")
        let o = AIRouter.outcome(from: response, subject: GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: answer, local: local)
        XCTAssertEqual(o.hitIdeaIDs, ["k1", "k2"], "an idea the item doesn't have is ignored")
        // k1's quote isn't in the answer, so k1 keeps the offline grader's own mark ("grow"); k2's quote is.
        XCTAssertEqual(AITestSupport.marked(o, in: answer), ["grow", "the copies are identical"])
    }

    func testExactAnswersAreNeverSentToAModel() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        var count = 0
        for await o in app.ai.grade(GradeSubject(item: AITestSupport.fixtureItem("i7")), answer: .choice(1)) {
            count += 1
            XCTAssertEqual(o.verdict, .correct)
        }
        XCTAssertEqual(count, 1)
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testGradeAgainUsesTheStrongestTierAndSaysIfItAgrees() async {
        let app = AITestSupport.makeApp(mode: .mock)
        let subject = GradeSubject(item: AITestSupport.fixtureItem("i1"))
        let answer = AnswerInput.text("So the body can grow and repair tissue, making two identical cells.")
        let first = app.ai.instantGrade(subject, answer: answer)
        let again = await app.ai.gradeAgain(subject, answer: answer, previous: first)
        XCTAssertEqual(again.gradedBy, .cloud)
        XCTAssertEqual(again.agreesWithPrevious, true)

        let offline = AITestSupport.makeApp(mode: .local)
        let local = await offline.ai.gradeAgain(subject, answer: answer, previous: first)
        XCTAssertEqual(local.gradedBy, .rules)
        XCTAssertEqual(local.agreesWithPrevious, true)
    }

    // MARK: Quota

    func testServerLimitReachedShowsUpAsAFlagAndSendsNothing() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .grades, used: 20, limit: 20, period: .day)]))
        let subject = GradeSubject(item: AITestSupport.fixtureItem("i1"))
        let instant = app.ai.instantGrade(subject, answer: .text("grow"))
        XCTAssertEqual(instant.limitReached, .grades)
        XCTAssertEqual(instant.suggestion?.sheet, .paywall(.feature(AIFreeLimits.message(for: .grades))))
        var count = 0
        for await _ in app.ai.grade(subject, answer: .text("grow")) { count += 1 }
        XCTAssertEqual(count, 1, "no refinement once the limit is reached")
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testQuotaErrorFromTheRelayIsAbsorbed() async {
        let app = AITestSupport.makeApp(mode: .mock)
        let outcome = await app.ai.gradeNow(GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: .text("grow #quota"))
        XCTAssertEqual(outcome.limitReached, .grades)
        XCTAssertEqual(app.ai.quotaStatus.meter(.grades)?.used, 20)
        XCTAssertEqual(app.ai.quotaState(for: .grade), .exhausted)
    }

    func testPaidFairUseCeilingFallsBackWithoutThePaywall() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        transport.failures["grade"] = .quotaExceeded(QuotaStatus(plan: .pro, meters: [QuotaMeter(key: .grades, used: 1500, limit: nil, period: .day)]),
                                                     message: "That's the fair-use limit for graded answers today. It resets at midnight.")
        app.ai.transportOverride = transport
        app.ai.setServerQuota(QuotaStatus(plan: .pro, meters: []))
        let outcome = await app.ai.gradeNow(GradeSubject(item: AITestSupport.fixtureItem("i1")),
                                            answer: .text("So the body can grow and repair tissue, making two identical cells."))
        XCTAssertEqual(transport.calls, ["grade"])
        XCTAssertEqual(outcome.gradedBy, .rules)
        XCTAssertNil(outcome.limitReached)
        if case .upgrade = outcome.suggestion { XCTFail("a paid plan never sees the paywall") }
    }

    func testAFreeLimitCarriesTheRelaysOwnWords() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        transport.failures["grade"] = .quotaExceeded(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .grades, used: 20, limit: 20, period: .day)]),
                                                     message: "The relay's words.")
        app.ai.transportOverride = transport
        let outcome = await app.ai.gradeNow(GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: .text("They grow."))
        XCTAssertEqual(outcome.limitReached, .grades)
        XCTAssertEqual(outcome.suggestion, .upgrade(.grades, message: "The relay's words."))
        // The next answer is stopped on this iPhone, with the same words.
        let next = app.ai.instantGrade(GradeSubject(item: AITestSupport.fixtureItem("i1")), answer: .text("They grow."))
        XCTAssertEqual(next.limitReached, .grades)
        XCTAssertEqual(app.ai.lastSuggestion, .upgrade(.grades, message: "The relay's words."))
    }

    func testOnDeviceUseCountsAgainstTheFreeLimitAndTheRulesNever() async {
        let app = AITestSupport.makeApp(mode: .local)
        app.ai.resetUsage()
        app.ai.probe = FixedOnDeviceProbe(.ready)
        let grade = #"{"ideas":[{"id":"K1","present":true,"quote":"grow"},{"id":"K2","present":false,"quote":""},{"id":"K3","present":false,"quote":""}],"feedback":"Good start.","fix":"Add more."}"#
        app.ai.onDevice = ScriptedOnDeviceBackend(Array(repeating: .json(grade), count: 5))
        let subject = GradeSubject(item: AITestSupport.fixtureItem("i1"))

        // The rules alone are never counted.
        _ = app.ai.instantGrade(subject, answer: .text("grow"))
        _ = LocalGrader.grade(subject, answer: .text("grow"))
        XCTAssertEqual(app.ai.usage.used(.grades), 0)

        app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .grades, used: 18, limit: 20, period: .day)]))
        let first = await app.ai.gradeNow(subject, answer: .text("They grow."))
        XCTAssertEqual(first.gradedBy, .onDevice)
        let second = await app.ai.gradeNow(subject, answer: .text("They grow."))
        XCTAssertEqual(second.gradedBy, .onDevice)
        XCTAssertEqual(app.ai.usage.used(.grades), 2)
        let third = await app.ai.gradeNow(subject, answer: .text("They grow."))
        XCTAssertEqual(third.gradedBy, .rules)
        XCTAssertEqual(third.limitReached, .grades)
        XCTAssertEqual(app.ai.quotaStatus.meter(.grades)?.used, 20)
    }

    func testLedgerRollsOverAtTheEndOfItsPeriod() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z")!
        var ledger = AIUsageLedger()
        ledger.record(.grades, now: monday, calendar: calendar)
        ledger.record(.scans, now: monday, calendar: calendar)
        let tuesday = monday.addingTimeInterval(86_400)
        ledger.roll(to: tuesday, calendar: calendar)
        XCTAssertEqual(ledger.used(.grades), 0, "daily meters reset each day")
        XCTAssertEqual(ledger.used(.scans), 1, "weekly meters keep counting within the week")
        ledger.roll(to: monday.addingTimeInterval(7 * 86_400), calendar: calendar)
        XCTAssertEqual(ledger.used(.scans), 0)
    }

    func testWeeksStartOnMondayLikeTheServer() {
        // The relay counts weeks from Monday in the person's time zone, whatever the locale's first weekday.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1   // a US locale: Sunday first
        let sunday = ISO8601DateFormatter().date(from: "2026-10-25T15:00:00Z")!
        let monday = ISO8601DateFormatter().date(from: "2026-10-26T15:00:00Z")!
        let saturday = ISO8601DateFormatter().date(from: "2026-10-24T15:00:00Z")!
        XCTAssertEqual(AIUsageLedger.weekKey(saturday, calendar: calendar), AIUsageLedger.weekKey(sunday, calendar: calendar))
        XCTAssertNotEqual(AIUsageLedger.weekKey(sunday, calendar: calendar), AIUsageLedger.weekKey(monday, calendar: calendar))
        var ledger = AIUsageLedger()
        ledger.record(.scans, now: sunday, calendar: calendar)
        ledger.roll(to: monday, calendar: calendar)
        XCTAssertEqual(ledger.used(.scans), 0)
    }

    func testFreeLimitMessagesMatchTheRelaysCopy() {
        // fixtures/error-quota.json is the relay's own words for the grades limit.
        let body = try? RelayFixtures.load(RelayErrorBody.self, "error-quota")
        XCTAssertEqual(AIFreeLimits.message(for: .grades), body?.error.message)
    }

    func testPaidPlanIsUnmetered() {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        app.ai.setServerQuota(QuotaStatus(plan: .pro, meters: [QuotaMeter(key: .grades, used: 500, limit: nil, period: .day)]))
        XCTAssertEqual(app.ai.quotaState(for: .grade), .unmetered)
        XCTAssertEqual(app.ai.quotaState(for: .confusions), .unmetered)
        XCTAssertNil(app.ai.quotaStatus.meter(.grades)?.limit)
    }

    // MARK: Mock mode

    func testMockModeCountsAsConsentedUnlessTheHarnessAsksOtherwise() {
        let app = AITestSupport.makeApp(mode: .mock, consent: false)
        XCTAssertTrue(app.ai.hasCloudConsent)
        XCTAssertTrue(app.ai.route(.generate).usesCloud)
        let relay = AITestSupport.makeApp(mode: .relay, consent: false)
        XCTAssertFalse(relay.ai.hasCloudConsent)
    }
}
