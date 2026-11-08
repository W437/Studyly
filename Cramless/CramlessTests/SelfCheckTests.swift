import XCTest
@testable import Cramless

/// Marking an own-words answer yourself: when the rules' verdict may stand and when it may not, the mode a grade carries through the
/// router's ladder, why no model graded it, what the ticks come to, and the words that say so.
///
/// The answers are for the sample's "why do cells divide by mitosis?" (key ideas: growth and repair; genetically identical cells; the
/// same number of chromosomes). The test of 276 graded answers can't be replayed without its items; these are one of each kind.
@MainActor
final class SelfCheckTests: XCTestCase {

    private func subject(_ id: String = "i1") -> GradeSubject { GradeSubject(item: AITestSupport.fixtureItem(id)) }

    /// Right in other words, so the rules find two of the three ideas.
    private let paraphrase = "So that living things can get bigger and fix wounds, and both new cells are a perfect copy with all the same chromosomes."
    /// Right in other words the rules don't know at all.
    private let paraphraseNoHits = "So that organisms can get bigger and fix wounds, and both cells have matching genes."
    private let terse = "Growth and repair."
    private let partly = "To grow, mostly."
    private let misconception = "Cells divide so they can make sex cells."
    private let correct = "To grow and heal, making genetically identical cells with the same number of chromosomes."

    // MARK: What the rules may still say

    func testTheRulesStandOnlyWhereTheyAreRight() {
        let s = subject()
        func trusted(_ answer: String) -> Bool {
            SelfCheck.trustsRules(LocalGrader.grade(s, answer: .text(answer)), subject: s, answer: answer)
        }
        // "Correct" is right 88% of the time; an answer that is nothing to mark has nothing to get wrong.
        XCTAssertTrue(trusted(correct))
        XCTAssertTrue(trusted("I don't know."))
        XCTAssertTrue(trusted("No idea, sorry."))
        XCTAssertTrue(trusted("idk"))
        XCTAssertTrue(trusted("banana"), "nothing in common with the question or its answer")
        XCTAssertTrue(trusted("?"), "no word at all")
        // Everything else the rules say about a paraphrase, a terse answer or a partly right one is a guess.
        XCTAssertFalse(trusted(paraphrase))
        XCTAssertFalse(trusted(paraphraseNoHits))
        XCTAssertFalse(trusted(terse))
        XCTAssertFalse(trusted(partly))
        XCTAssertFalse(trusted(misconception))
        // An answer in another language shares no word with the question whatever it says: not "off the subject", the person's to mark.
        XCTAssertFalse(trusted("Para que el cuerpo pueda crecer y reparar tejidos, y las celulas nuevas sean copias exactas."))
        XCTAssertFalse(trusted("כדי שהגוף יוכל לגדול ולתקן רקמות והתאים החדשות יהיו עותקים זהים"))
        XCTAssertTrue(SelfCheck.readsAsEnglish(paraphrase))
        XCTAssertTrue(SelfCheck.readsAsEnglish("banana"), "too short to tell: let through")
    }

    func testAnExplicitDontKnowCarriesAtMostOneOtherWord() {
        for answer in ["I don't know", "i dont know.", "IDK", "dunno", "No idea, sorry.", "I have no idea what this is about",
                       "I don't know what mitosis is", "I don't know the answer to this question", "no clue", "I forgot"] {
            XCTAssertTrue(SelfCheck.isDontKnow(answer), answer)
        }
        for answer in ["I don't know, maybe growth?", "Not sure, I think it's about growth", "They grow", "", "know",
                       "I forgot the details but it helps cells grow and heal"] {
            XCTAssertFalse(SelfCheck.isDontKnow(answer), answer)
        }
    }

    func testTheTicksStartFromWhatTheRulesFoundAndTheirScoreIsTheShareTicked() {
        let s = subject()
        let ideas = s.keyIdeas
        XCTAssertEqual(ideas.map(\.id), ["k1", "k2", "k3"])
        let found = LocalGrader.grade(s, answer: .text(paraphrase))
        XCTAssertEqual(SelfCheck.startingTicks(of: found, ideas: ideas), ["k2", "k3"])
        XCTAssertEqual(SelfCheck.startingTicks(of: LocalGrader.grade(s, answer: .text(paraphraseNoHits)), ideas: ideas), [])
        XCTAssertEqual(SelfCheck.score(ticked: ["k1", "k2", "k3"], of: ideas), 1)
        XCTAssertEqual(SelfCheck.score(ticked: ["k2", "k3"], of: ideas), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(SelfCheck.score(ticked: [], of: ideas), 0)
        XCTAssertEqual(SelfCheck.score(ticked: ["not an idea"], of: ideas), 0, "only the item's own ideas count")
        XCTAssertEqual(SelfCheck.score(ticked: ["k1"], of: []), 0, "no ideas, no score")
    }

    func testTheRatingComesFromTheTicks() {
        let ideas = subject().keyIdeas
        func rating(_ ticked: Set<String>, ms: Int = 40_000) -> Rating {
            AppModel.rating(forScore: SelfCheck.score(ticked: ticked, of: ideas), kind: .recall, durationMs: ms)
        }
        XCTAssertEqual(rating(["k1", "k2", "k3"]), .good, "all of them is right")
        XCTAssertEqual(rating(["k1", "k2", "k3"], ms: 20_000), .easy, "right and quick, as for a graded answer")
        XCTAssertEqual(rating(["k2", "k3"]), .hard, "some of them is partly")
        XCTAssertEqual(rating(["k1"]), .again)
        XCTAssertEqual(rating([]), .again, "none of them is not yet")
    }

    // MARK: Through the router, with no model

    func testOfflineOwnWordsAnswersAreSelfChecksUnlessTheRulesCanBeTrusted() {
        let app = AITestSupport.makeApp(mode: .local)
        struct Row { var answer: String; var mode: GradeMode; var verdict: GradeResponse.Verdict?; var ticks: Set<String> }
        let rows: [Row] = [
            Row(answer: paraphrase, mode: .selfCheck, verdict: nil, ticks: ["k2", "k3"]),
            Row(answer: paraphraseNoHits, mode: .selfCheck, verdict: nil, ticks: []),
            Row(answer: terse, mode: .selfCheck, verdict: nil, ticks: ["k1"]),
            Row(answer: partly, mode: .selfCheck, verdict: nil, ticks: ["k1"]),
            Row(answer: misconception, mode: .selfCheck, verdict: nil, ticks: []),
            Row(answer: "I don't know, maybe growth?", mode: .selfCheck, verdict: nil, ticks: ["k1"]),
            Row(answer: correct, mode: .verdict, verdict: .correct, ticks: ["k1", "k2", "k3"]),
            Row(answer: "I don't know.", mode: .verdict, verdict: .incorrect, ticks: []),
            Row(answer: "No idea, sorry.", mode: .verdict, verdict: .incorrect, ticks: []),
            Row(answer: "banana", mode: .verdict, verdict: .incorrect, ticks: []),
            Row(answer: "   ", mode: .verdict, verdict: .incorrect, ticks: []),
        ]
        for row in rows {
            let g = app.ai.instantGrade(subject(), answer: .text(row.answer))
            XCTAssertEqual(g.mode, row.mode, row.answer)
            if let verdict = row.verdict { XCTAssertEqual(g.verdict, verdict, row.answer) }
            XCTAssertEqual(SelfCheck.startingTicks(of: g, ideas: subject().keyIdeas), row.ticks, row.answer)
            XCTAssertEqual(g.selfCheckReason != nil, row.mode == .selfCheck, row.answer)
            XCTAssertEqual(g.gradedBy, .rules, row.answer)
        }
    }

    func testExactChecksAreNeverSelfChecks() {
        let app = AITestSupport.makeApp(mode: .local)
        let wrong: [(String, AnswerInput)] = [("i11", .blanks(["anaphase"])), ("i7", .choice(0)),
                                              ("i14", .labels(["a", "b", "c", "d"]))]
        for (id, answer) in wrong {
            let g = app.ai.instantGrade(subject(id), answer: answer)
            XCTAssertEqual(g.mode, .verdict, id)
            XCTAssertEqual(g.verdict, .incorrect, id)
            XCTAssertNil(g.selfCheckReason, id)
        }
    }

    func testTheReasonLineComesFromWhatTheRouteKnows() {
        func reason(_ app: AppModel) -> SelfCheckReason? { app.ai.instantGrade(subject(), answer: .text(paraphrase)).selfCheckReason }
        XCTAssertEqual(reason(AITestSupport.makeApp(mode: .relay, consent: false)), .cloudOff)
        XCTAssertEqual(reason(AITestSupport.makeApp(mode: .mock, consent: false)), nil, "mock counts as consented: a model is allowed")
        XCTAssertEqual(reason(AITestSupport.makeApp(mode: .local)), .deviceUnavailable)
        XCTAssertEqual(reason(AITestSupport.makeApp(mode: .relay, consent: true, age: .under13)), .deviceUnavailable)

        let limited = AITestSupport.makeApp(mode: .relay, consent: true)
        limited.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .grades, used: 20, limit: 20, period: .day)]))
        XCTAssertEqual(reason(limited), .freeLimit)
        let g = limited.ai.instantGrade(subject(), answer: .text(paraphrase))
        XCTAssertEqual(g.limitReached, .grades)
        guard case .upgrade(.grades, let line)? = g.suggestion else { return XCTFail("the paywall card: \(String(describing: g.suggestion))") }
        XCTAssertEqual(line, AIFreeLimits.cardLine(for: .grades, deviceKeepsWorking: false))
        XCTAssertTrue(line.contains("mark your answers yourself"), line)
        XCTAssertFalse(line.contains("Quick check"), "the rules no longer grade these")
    }

    func testTheWordsSayWhyInPlainWords() {
        XCTAssertEqual(SessionCopy.selfCheckLine(.cloudOff), "Cloud AI is off, so you mark this one.")
        XCTAssertEqual(SessionCopy.selfCheckLine(.freeLimit), "You've used today's free AI checks, so you mark this one.")
        XCTAssertEqual(SessionCopy.selfCheckLine(.offline), "No connection, so you mark this one.")
        XCTAssertEqual(SessionCopy.selfCheckLine(.deviceUnavailable), "Your iPhone's AI is off or unavailable, so you mark this one.")
        XCTAssertEqual(SessionCopy.selfCheckLine(nil), SessionCopy.selfCheckLine(.deviceUnavailable))
        XCTAssertEqual(SessionCopy.markedByYou, "Marked by you")
        XCTAssertEqual(SessionCopy.selfCheckPill, "Check it yourself")
        XCTAssertEqual(String(localized: SessionCopy.selfCheckHeadline), "Compare with the answer.")
        for reason in [SelfCheckReason.cloudOff, .freeLimit, .offline, .unreachable, .deviceUnavailable] {
            let line = SessionCopy.selfCheckLine(reason)
            XCTAssertTrue(line.hasSuffix("so you mark this one."), line)
            XCTAssertFalse(line.contains("!"), line)
        }
    }

    // MARK: Through the router, with a model

    func testWhileAModelIsAllowedTheRulesGradeIsProvisionalAndTheModelsIsFinal() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        var seen: [GradeOutcome] = []
        for await o in app.ai.grade(subject(), answer: .text(paraphrase)) { seen.append(o) }
        XCTAssertEqual(seen.map(\.mode), [.provisional, .verdict])
        XCTAssertEqual(seen.map(\.gradedBy), [.rules, .cloud])
        XCTAssertEqual(transport.calls, ["grade"])
    }

    func testAnIDontKnowNeedsNoSecondOpinion() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        var seen: [GradeOutcome] = []
        for await o in app.ai.grade(subject(), answer: .text("I don't know.")) { seen.append(o) }
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.mode, .verdict)
        XCTAssertEqual(seen.first?.verdict, .incorrect)
        XCTAssertTrue(transport.calls.isEmpty, "a model is not asked about an answer that says nothing")
    }

    func testWhenTheModelDoesNotAnswerTheAnswerBecomesASelfCheck() async {
        for (failure, reason) in [(RelayError.offline, SelfCheckReason.offline), (.upstream("down"), .unreachable)] {
            let app = AITestSupport.makeApp(mode: .relay, consent: true)
            let transport = RecordingTransport()
            transport.failures["grade"] = failure
            app.ai.transportOverride = transport
            var seen: [GradeOutcome] = []
            for await o in app.ai.grade(subject(), answer: .text(paraphrase)) { seen.append(o) }
            XCTAssertEqual(seen.map(\.mode), [.provisional, .selfCheck], "\(failure)")
            XCTAssertEqual(seen.last?.selfCheckReason, reason, "\(failure)")
            XCTAssertEqual(seen.last?.gradedBy, .rules)
            XCTAssertEqual(SelfCheck.startingTicks(of: seen.last!, ideas: subject().keyIdeas), ["k2", "k3"], "the rules' finds stay ticked")
            XCTAssertNil(seen.last?.limitReached, "a lost connection is no free limit")
        }
    }

    func testWhenTheModelDoesNotAnswerARightAnswerStaysRight() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        transport.failures["grade"] = .offline
        app.ai.transportOverride = transport
        let g = await app.ai.gradeNow(subject(), answer: .text(correct))
        XCTAssertEqual(g.mode, .verdict, "the rules call it correct, which they are right about 88% of the time")
        XCTAssertEqual(g.verdict, .correct)
    }

    func testTheModelsGradeIsAlwaysFinalAndNeverASelfCheck() async {
        let app = AITestSupport.makeApp(mode: .mock)
        let again = await app.ai.gradeAgain(subject(), answer: .text(paraphrase))
        XCTAssertEqual(again.mode, .verdict)
        XCTAssertEqual(again.gradedBy, .cloud)
        XCTAssertNil(again.selfCheckReason)
    }

    // MARK: Grade again

    func testGradeAgainWithNoModelLeavesTheAnswerWithThePerson() async {
        let app = AITestSupport.makeApp(mode: .local)
        let first = app.ai.instantGrade(subject(), answer: .text(paraphrase))
        XCTAssertEqual(first.mode, .selfCheck)
        let again = await app.ai.gradeAgain(subject(), answer: .text(paraphrase), previous: first)
        XCTAssertEqual(again.mode, .selfCheck)
        XCTAssertEqual(again.selfCheckReason, .deviceUnavailable)
    }

    func testGradeAgainIsOfferedOnceAModelCouldGradeIt() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: false)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        let s = subject()
        XCTAssertFalse(app.ai.canGradeAgain(s, answer: .text(paraphrase)), "Cloud AI is off")
        let first = app.ai.instantGrade(s, answer: .text(paraphrase))
        XCTAssertEqual(first.selfCheckReason, .cloudOff)
        XCTAssertEqual(first.suggestion, .allowCloud(feature: AIJob.grade.feature), "the banner offers to turn it on")

        app.allowCloudAI()
        XCTAssertTrue(app.ai.canGradeAgain(s, answer: .text(paraphrase)))
        XCTAssertFalse(app.ai.canGradeAgain(s, answer: .choice(1)), "an exact check has nothing to grade again")
        XCTAssertFalse(app.ai.canGradeAgain(s, answer: .text("   ")))
        let again = await app.ai.gradeAgain(s, answer: .text(paraphrase), previous: first)
        XCTAssertEqual(again.mode, .verdict)
        XCTAssertEqual(again.gradedBy, .cloud)
        XCTAssertEqual(transport.calls, ["grade"])
    }

    // MARK: One set of facts for every route

    /// Cloud AI off or its free checks used, this iPhone's model there, and an answer it can't read (too long, or not English). The
    /// offline grade used to route without those facts: it showed the rules' verdict as provisional for a moment, announced it, and
    /// then flipped to a self-check whose "Grade again" button found no tier when tapped.
    func testTheOfflineGradeTheRefinementAndTheGradeAgainButtonAskTheRouteTheSameQuestion() async {
        let s = subject()
        let long = Array(repeating: paraphrase, count: 8).joined(separator: " ")
        XCTAssertGreaterThan(long.split(separator: " ").count, 120)
        // Mostly Spanish, with one word of the key ideas' vocabulary, so the rules can't call it off the subject.
        let spanglish = "Para que el cuerpo pueda crecer y reparar los tejidos dañados, y para que las células hijas reciban los mismos chromosomes que la célula madre."
        func cloudOff() -> AppModel { AITestSupport.makeApp(mode: .relay, consent: false) }
        func limitReached() -> AppModel {
            let app = AITestSupport.makeApp(mode: .relay, consent: true)
            app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .grades, used: 20, limit: 20, period: .day)]))
            return app
        }
        for (why, make) in [("Cloud AI is off", cloudOff), ("the free checks are used", limitReached)] {
            let app = make()
            app.ai.probe = FixedOnDeviceProbe(.ready)
            let backend = ScriptedOnDeviceBackend([])
            app.ai.onDevice = backend
            for answer in [long, spanglish] {
                let first = app.ai.instantGrade(s, answer: .text(answer))
                XCTAssertEqual(first.mode, .selfCheck, "\(why): no model can read it, so it is the person's to mark at once")
                XCTAssertFalse(app.ai.canGradeAgain(s, answer: .text(answer)), "\(why): so the button would find no tier")
                var seen: [GradeOutcome] = []
                for await o in app.ai.grade(s, answer: .text(answer)) { seen.append(o) }
                XCTAssertEqual(seen.map(\.mode), [.selfCheck], "\(why): and the rules' verdict never shows as provisional first")
                let again = await app.ai.gradeAgain(s, answer: .text(answer), previous: first)
                XCTAssertEqual(again.mode, .selfCheck, why)
            }
            XCTAssertEqual(backend.callCount, 0, "the model is never given what it can't read")
            // An ordinary answer is another matter: the model is on the route, and so is the button.
            XCTAssertEqual(app.ai.instantGrade(s, answer: .text(paraphrase)).mode, .provisional, why)
            XCTAssertTrue(app.ai.canGradeAgain(s, answer: .text(paraphrase)), why)
        }
        // With Cloud AI there, the same long answer has a tier (the cloud reads anything), and the button is real.
        let cloud = AITestSupport.makeApp(mode: .relay, consent: true)
        cloud.ai.probe = FixedOnDeviceProbe(.ready)
        cloud.ai.transportOverride = RecordingTransport()
        XCTAssertEqual(cloud.ai.instantGrade(s, answer: .text(long)).mode, .provisional)
        XCTAssertTrue(cloud.ai.canGradeAgain(s, answer: .text(long)))
    }

    // MARK: A model that takes too long

    /// Relays a hanging grade: the call never comes back until it is cancelled.
    private final class HangingGradeTransport: RelayTransport, @unchecked Sendable {
        let base = RecordingTransport()
        var calls: [String] { base.calls }
        func generate(_ request: GenerateRequest) async throws -> GenerateResponse { try await base.generate(request) }
        func check(_ request: CheckRequest) async throws -> CheckResponse { try await base.check(request) }
        func grade(_ request: GradeRequest) async throws -> GradeResponse {
            _ = try await base.grade(request)
            try await Task.sleep(for: .seconds(120))
            throw RelayError.upstream("never")
        }
        func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> { base.tutor(request) }
        func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse { try await base.confusions(request) }
        func lecture(_ request: LectureRequest) async throws -> LectureResponse { try await base.lecture(request) }
        func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse { try await base.cardsFromChat(request) }
        func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse { try await base.transcribeImage(request) }
        func quota() async throws -> QuotaStatus { try await base.quota() }
    }

    func testAModelThatTakesTooLongIsLetGoAndTheAnswerBecomesASelfCheck() async {
        XCTAssertEqual(SelfCheck.modelWait, .seconds(8), "Continue waits this long for a model, and no longer")
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = HangingGradeTransport()
        app.ai.transportOverride = transport
        var seen: [GradeOutcome] = []
        let started = Date()
        for await o in app.ai.grade(subject(), answer: .text(paraphrase), wait: .milliseconds(80)) { seen.append(o) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "the stream ends when the wait does, not when the relay does")
        XCTAssertEqual(seen.map(\.mode), [.provisional, .selfCheck])
        XCTAssertEqual(seen.last?.selfCheckReason, .unreachable, "\(SessionCopy.selfCheckLine(.unreachable))")
        XCTAssertEqual(seen.last?.gradedBy, .rules)
        XCTAssertEqual(SelfCheck.startingTicks(of: seen.last!, ideas: subject().keyIdeas), ["k2", "k3"], "what the rules found stays ticked")
        XCTAssertEqual(transport.calls, ["grade"])

        // A right answer the rules can be trusted with stays right when the model is let go.
        var right: [GradeOutcome] = []
        for await o in app.ai.grade(subject(), answer: .text(correct), wait: .milliseconds(80)) { right.append(o) }
        XCTAssertEqual(right.map(\.mode), [.provisional, .verdict])
        XCTAssertEqual(right.last?.verdict, .correct)

        // A model that answers in time is used, whatever the wait.
        let quick = AITestSupport.makeApp(mode: .relay, consent: true)
        quick.ai.transportOverride = RecordingTransport()
        var graded: [GradeOutcome] = []
        for await o in quick.ai.grade(subject(), answer: .text(paraphrase), wait: .seconds(30)) { graded.append(o) }
        XCTAssertEqual(graded.map(\.mode), [.provisional, .verdict])
        XCTAssertEqual(graded.last?.gradedBy, .cloud)

        // Callers with no one waiting (`gradeNow`) are not given a clock.
        let patient = AITestSupport.makeApp(mode: .relay, consent: true)
        patient.ai.transportOverride = RecordingTransport()
        let now = await patient.ai.gradeNow(subject(), answer: .text(paraphrase))
        XCTAssertEqual(now.gradedBy, .cloud)
    }

    // MARK: A limit reported while this iPhone grades

    func testAFreeLimitTheRelayReportsWhileThisIPhoneGradesStillShowsItsPaywallCard() async {
        let s = subject()
        let model = #"{"ideas":[{"id":"K1","present":true,"quote":"get bigger"},{"id":"K2","present":true,"quote":"perfect copy"},{"id":"K3","present":true,"quote":"same chromosomes"}],"feedback":"Good.","fix":""}"#
        // About eighty words: past what the iPhone's model is given first, so the cloud is asked first, says the free checks are used,
        // and this iPhone's model then answers.
        let eighty = Array(repeating: paraphrase, count: 4).joined(separator: " ")
        XCTAssertTrue((61...120).contains(eighty.split(separator: " ").count))
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        transport.failures["grade"] = .quotaExceeded(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .grades, used: 20, limit: 20, period: .day)]),
                                                     message: "The relay's words.")
        app.ai.transportOverride = transport
        app.ai.probe = FixedOnDeviceProbe(.ready)
        app.ai.onDevice = ScriptedOnDeviceBackend([.json(model), .json(model)])

        var seen: [GradeOutcome] = []
        for await o in app.ai.grade(s, answer: .text(eighty)) { seen.append(o) }
        XCTAssertEqual(transport.calls, ["grade"])
        XCTAssertEqual(seen.map(\.mode), [.provisional, .verdict])
        guard let graded = seen.last else { return XCTFail("no grade") }
        XCTAssertEqual(graded.gradedBy, .onDevice, "this iPhone's model graded it")
        XCTAssertEqual(graded.limitReached, .grades, "and the limit the relay reported is not dropped: the card shows with this answer")
        XCTAssertEqual(graded.suggestion, .upgrade(.grades, message: "The relay's words."))
        XCTAssertEqual(app.ai.usage.cloudUsed(.grades), 0, "a refused request is no use of the free checks, and the iPhone's own never count")

        // "Grade again" is the same.
        let again = await app.ai.gradeAgain(s, answer: .text(paraphrase), previous: seen.first)
        XCTAssertEqual(again.gradedBy, .onDevice)
        XCTAssertEqual(again.limitReached, .grades)
    }

    // MARK: What the person's own mark logs

    func testTheScoreLoggedStandsForTheRatingThePersonEndedWith() {
        // Their own score is kept when it is in the rating's band (nothing was changed, or the change was a small one)...
        XCTAssertEqual(Grading.score(standingFor: .again, near: 1.0 / 3), 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(Grading.score(standingFor: .hard, near: 2.0 / 3), 2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(Grading.score(standingFor: .good, near: 1), 1)
        XCTAssertEqual(Grading.score(standingFor: .easy, near: 1), 1)
        // ...and otherwise it is one that stands for what they chose.
        XCTAssertEqual(Grading.score(standingFor: .good, near: 0), 0.9, "0 or 1 of 3 ticked, then Counts as Good")
        XCTAssertEqual(Grading.score(standingFor: .good, near: 1.0 / 3), 0.9)
        XCTAssertEqual(Grading.score(standingFor: .hard, near: 0), 0.67)
        XCTAssertEqual(Grading.score(standingFor: .easy, near: 2.0 / 3), 1)
        XCTAssertEqual(Grading.score(standingFor: .again, near: 1), 0, "all ticked, then Counts as Again")
        XCTAssertEqual(Grading.score(standingFor: .again, near: 2.0 / 3), 0)
        // Whatever they chose, the log agrees with it: the rating gives back, and "right" is the same by score and by rating.
        for rating in Rating.allCases {
            for ticks in stride(from: 0.0, through: 1.0, by: 1.0 / 3) {
                let score = Grading.score(standingFor: rating, near: ticks)
                XCTAssertTrue((0...1).contains(score), "\(rating) \(ticks)")
                XCTAssertEqual(rating.rawValue >= Rating.hard.rawValue, score >= Grading.againBelow, "\(rating) at \(ticks) logged as \(score)")
                if rating != .easy {
                    XCTAssertEqual(Grading.rating(forScore: score, kind: .recall, durationMs: 90_000), rating,
                                   "\(rating) at \(ticks) logged as \(score)")
                }
            }
        }
    }

    func testContinueWaitsForAMarkUnlessTheRulesFoundSomethingToAgreeWith() {
        let s = subject()
        func canContinue(_ answer: String, touched: Bool = false) -> Bool {
            let found = LocalGrader.grade(s, answer: .text(answer))
            return SelfCheck.canContinue(changedByPerson: touched, rulesFoundIdeas: !SelfCheck.startingTicks(of: found, ideas: s.keyIdeas).isEmpty)
        }
        XCTAssertFalse(canContinue(paraphraseNoHits), "no tick found, none touched: nothing is marked")
        XCTAssertTrue(canContinue(paraphraseNoHits, touched: true), "a tick changed, or None of these chosen")
        XCTAssertTrue(canContinue(paraphrase), "the rules found two ideas: those ticks are something to agree with")
        XCTAssertFalse(SelfCheck.canContinue(changedByPerson: false, rulesFoundIdeas: false))
    }

    /// The relay refuses a request with one string over its limit, whole, and the grade would quietly come from the offline rules.
    func testTheCloudGradeRequestIsCutToTheRelaysLimits() async throws {
        let long = Array(repeating: paraphrase, count: 200).joined(separator: " ")
        XCTAssertGreaterThan(long.unicodeScalars.count, RelayLimits.gradeResponse)
        var s = subject()
        s.sourceExcerpt = String(repeating: "Mitosis makes two identical cells. ", count: 500)
        XCTAssertGreaterThan((s.sourceExcerpt ?? "").unicodeScalars.count, RelayLimits.gradeExcerpt)
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        for await _ in app.ai.grade(s, answer: .text(long)) {}
        let request = try XCTUnwrap(transport.gradeRequests.first, "the cloud was asked")
        XCTAssertEqual(request.response.unicodeScalars.count, RelayLimits.gradeResponse)
        XCTAssertEqual(request.sourceExcerpt?.unicodeScalars.count, RelayLimits.gradeExcerpt)
        XCTAssertEqual(request.keyIdeas.map(\.id), s.keyIdeas.map(\.id))
    }
}
