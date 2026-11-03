import XCTest
@testable import Cramless

/// Lecture notes, mistake patterns, cards from a chat and page-photo reading: the rules' answers and the router's
/// ladder for each.
@MainActor
final class AILectureTests: XCTestCase {

    private var lecture: LocalLectureNotes.Result {
        LocalLectureNotes.make(title: "Lecture 6: Cell division", segments: AITestSupport.lectureSegments, flags: [], maxItems: 8)
    }

    func testSectionsByTopicAndTime() {
        let r = lecture
        XCTAssertEqual(r.sections.map(\.title), ["Prophase", "Nuclear envelope", "Metaphase", "Anaphase", "Telophase"])
        // In order, back to back, every segment in exactly one section.
        XCTAssertEqual(r.sections.flatMap(\.segmentIDs), AITestSupport.lectureSegments.map(\.id))
        for (a, b) in zip(r.sections, r.sections.dropFirst()) { XCTAssertLessThan(a.end, b.start + 0.001) }
        XCTAssertEqual(r.sections.first?.start, 178)
        // The intro's filler doesn't become a note.
        XCTAssertEqual(r.sections.first?.bullets, ["The chromatin condenses, and you can finally see chromosomes under the microscope."])
        XCTAssertTrue(r.keyTerms.contains("prophase"))
        XCTAssertFalse(r.keyTerms.contains("envelope"), "a word already inside a key term isn't repeated")
        XCTAssertEqual(r.notes.origin, "rules")
    }

    func testFlaggedMomentsAndTheirQuestions() throws {
        let r = lecture
        let flag = try XCTUnwrap(r.examFlags.first)
        XCTAssertEqual(flag.time, 725)
        XCTAssertEqual(flag.why, "The lecturer said it will be on the midterm.")
        XCTAssertTrue(r.summary.contains("Flagged for the midterm: anaphase is where the sister chromatids get pulled apart."), r.summary)
        let question = try XCTUnwrap(r.items.first)
        XCTAssertEqual(question.kind, .recall)
        XCTAssertEqual(question.prompt, "Your lecturer said this will be on the midterm: what happens in anaphase?")
        XCTAssertEqual(question.anchors, ["s5"])
        let ids = Set(AITestSupport.lectureSegments.map(\.id))
        XCTAssertTrue(r.items.allSatisfy { !$0.anchors.isEmpty && Set($0.anchors).isSubset(of: ids) })
        // A tapped flag says so.
        let tapped = LocalLectureNotes.make(title: "L", segments: AITestSupport.lectureSegments,
                                            flags: [ExamFlag(id: "t", time: 470, reason: .tapped, text: "")])
        XCTAssertTrue(tapped.examFlags.contains { $0.time == 470 && $0.why == "You flagged this moment." })
    }

    func testRouterLectureNotesOfflineAndInMock() async {
        let input = LectureInput(course: "Bio 101", title: "Lecture 6: Cell division", segments: AITestSupport.lectureSegments, flags: [])
        let offlineApp = AITestSupport.makeApp(mode: .local)
        let offline = await offlineApp.ai.lectureNotes(input)
        XCTAssertEqual(offline.origin, .rules)
        XCTAssertEqual(offline.notes.sections.count, 5)
        XCTAssertNotNil(offline.note)

        let mockApp = AITestSupport.makeApp(mode: .mock)
        let mock = await mockApp.ai.lectureNotes(input)
        defer { withExtendedLifetime((offlineApp, mockApp)) {} }
        XCTAssertEqual(mock.origin, .cloud)
        XCTAssertEqual(mock.title, "Lecture 6: Cell division")
        XCTAssertEqual(mock.items.map(\.id), ["l1", "l2", "l3"], "the fixture's anchors s5, s3, s4 are real segments")
        XCTAssertEqual(mock.notes.origin, "cloud")
    }

    func testLectureNotesQuotaFallsBack() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        app.ai.transportOverride = RecordingTransport()
        app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .lectures, used: 1, limit: 1, period: .week)]))
        let outcome = await app.ai.lectureNotes(LectureInput(course: "Bio 101", title: "Lecture 6", segments: AITestSupport.lectureSegments, flags: []))
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertEqual(outcome.limitReached, .lectures)
    }

    // MARK: Lecture size and what the cloud left over

    func testALectureAsksForTenQuestionsAndSaysHowManyIdeasWereLeftOver() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let relay = ScriptedRelay()
        relay.onLecture = { request in
            LectureResponse(model: "scripted", title: request.title, summary: "A lecture.",
                            sections: [LectureNotes.Section(id: "n1", title: "Mitosis", start: 178, end: 1040, bullets: ["Cells divide."])],
                            keyTerms: ["mitosis"], examFlags: [],
                            items: [GeneratedItem(id: "l1", kind: .flashcard, topic: "Mitosis", prompt: "Anaphase", answer: "Sister chromatids are pulled apart.",
                                                  anchors: ["s5"])],
                            leftOut: 3)
        }
        app.ai.transportOverride = relay
        let input = LectureInput(course: "Bio 101", title: "Lecture 6", segments: AITestSupport.lectureSegments, flags: [])
        XCTAssertEqual(input.maxItems, 10)
        let outcome = await app.ai.lectureNotes(input)
        XCTAssertEqual(relay.lectureRequests.first?.maxItems, 10)
        XCTAssertEqual(outcome.origin, .cloud)
        XCTAssertEqual(outcome.leftOut, 3)
        XCTAssertEqual(outcome.note, "3 more ideas in the lecture weren't turned into questions.")
        XCTAssertFalse(outcome.needsCloud)

        // Nothing left over, or the relay doesn't say (build 2's relay never does): no note. (A fresh week's free lecture.)
        let other = AITestSupport.makeApp(mode: .relay, consent: true)
        let silent = ScriptedRelay()
        silent.onLecture = { request in
            LectureResponse(model: "scripted", title: request.title, summary: "", sections: [], keyTerms: [], examFlags: [], items: [])
        }
        other.ai.transportOverride = silent
        let quiet = await other.ai.lectureNotes(input)
        XCTAssertEqual(quiet.origin, .cloud)
        XCTAssertNil(quiet.note)
        XCTAssertNil(quiet.leftOut)
    }

    func testLectureResponsesWithAndWithoutLeftOutDecode() throws {
        let base = try RelayFixtures.load(LectureResponse.self, "lecture")
        XCTAssertNil(base.leftOut, "the shipped fixtures predate the field")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.cramless.encode(base)) as? [String: Any])
        XCTAssertNil(json["leftOut"], "absent when not set")
        json["leftOut"] = 4
        let decoded = try JSONDecoder.cramless.decode(LectureResponse.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.leftOut, 4)
    }

    // MARK: The offline quality bar

    func testTitlesThatNameNoTopicAreNotGood() {
        let stems = (0..<6).map { _ in Set(Lexicon.contentStems("valve open")) } + [Set(Lexicon.contentStems("prophase"))]
        XCTAssertTrue(LocalLectureNotes.isGoodTitle("Prophase", earlier: [], sectionStems: stems))
        XCTAssertTrue(LocalLectureNotes.isGoodTitle("Nuclear envelope", earlier: ["Prophase"], sectionStems: stems))
        XCTAssertTrue(LocalLectureNotes.isGoodTitle("Ejection volume", earlier: [], sectionStems: stems))
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Noticed", earlier: [], sectionStems: stems), "a past-tense verb")
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Diagram", earlier: [], sectionStems: stems), "a filler")
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Prophase", earlier: ["prophase"], sectionStems: stems), "a repeat")
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Ejection volume", earlier: ["Ejection Volume"], sectionStems: stems), "a repeat of two words")
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Part 3", earlier: [], sectionStems: stems))
        XCTAssertFalse(LocalLectureNotes.isGoodTitle(nil, earlier: [], sectionStems: stems), "no title was found")
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Hi", earlier: [], sectionStems: stems), "too short")
        // A word nearly every section says names none of them ("Valve" in six of seven), but one of two or three is fine.
        XCTAssertFalse(LocalLectureNotes.isGoodTitle("Valve", earlier: [], sectionStems: stems))
        XCTAssertTrue(LocalLectureNotes.isGoodTitle("Valve", earlier: [], sectionStems: Array(stems.prefix(3))))
    }

    func testTheCardiacLecturesJunkSectionsAreFoldedIntoTheirNeighbours() {
        // The titles the offline rules gave the 47-minute cardiac-cycle lecture in the user test.
        let names: [String?] = ["Contraction", "Ejection volume", "Noticed", "Pressure", "Pressure", "Diagram", "Systole", "Heart", "Contraction", "Physicians"]
        let groups: [[TranscriptSegment]] = names.indices.map { i in
            // "pressure" in nine sections of ten and "heart" in all, "contraction" in seven, "systole" in five.
            var text = "the valve opens and closes during the beat of the heart"
            if i != 9 { text += " as the pressure changes" }
            if i < 7 { text += " with a contraction" }
            if i % 2 == 0 { text += " in systole" }
            return [TranscriptSegment(id: "s\(i)", start: Double(i) * 60, end: Double(i) * 60 + 59, text: text)]
        }
        let (kept, titles) = LocalLectureNotes.applyingQualityBar(groups, names)
        XCTAssertEqual(titles, ["Contraction", "Ejection volume", "Systole", "Physicians"])
        // Nothing is lost: every segment is in exactly one section, in order, and each junk section went into the one before.
        XCTAssertEqual(kept.flatMap { $0.map(\.id) }, (0..<10).map { "s\($0)" })
        XCTAssertEqual(kept.map { $0.map(\.id) }, [["s0"], ["s1", "s2", "s3", "s4", "s5"], ["s6", "s7", "s8"], ["s9"]])
    }

    func testAJunkFirstSectionJoinsTheNextOneAndNoGoodSectionAtAllIsThin() {
        func group(_ i: Int) -> [TranscriptSegment] { [TranscriptSegment(id: "s\(i)", start: Double(i) * 60, end: Double(i) * 60 + 59, text: "so the thing is that")] }
        let (kept, titles) = LocalLectureNotes.applyingQualityBar([group(0), group(1), group(2)], ["Noticed", "Mitosis", "Diagram"])
        XCTAssertEqual(titles, ["Mitosis"])
        XCTAssertEqual(kept.map { $0.map(\.id) }, [["s0", "s1", "s2"]])
        let (all, none) = LocalLectureNotes.applyingQualityBar([group(0), group(1)], ["Noticed", nil])
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(none.count, 1)
        XCTAssertNil(none[0])
    }

    /// Talk with no topic in it: every section would be "Part n".
    private var chatter: [TranscriptSegment] {
        (0..<6).map { i in
            TranscriptSegment(id: "s\(i)", start: Double(i) * 125, end: Double(i) * 125 + 100,
                              text: "So yeah, that is the way we do it, and then we go on to the next one, you know, and so on.")
        }
    }

    func testTheGoodExampleKeepsItsFiveSectionsAndTheBarOnlyTightensTheRest() {
        let r = LocalLectureNotes.make(title: "Lecture 6", segments: AITestSupport.lectureSegments, flags: [], qualityBar: true)
        XCTAssertFalse(r.thin)
        XCTAssertEqual(r.sections.map(\.title), ["Prophase", "Nuclear envelope", "Metaphase", "Anaphase", "Telophase"])
        XCTAssertEqual(r.sections.map(\.segmentIDs), LocalLectureNotes.make(title: "Lecture 6", segments: AITestSupport.lectureSegments, flags: []).sections.map(\.segmentIDs))
    }

    func testOfflineNotesAreNotOfferedForATranscriptWithNoTopicsAndTheOutcomeAsksForCloudAI() async throws {
        XCTAssertTrue(LocalLectureNotes.make(title: "L", segments: chatter, flags: [], qualityBar: true).thin)
        let input = LectureInput(course: "Bio 101", title: "Lecture 9", segments: chatter, flags: [])

        // Cloud AI exists but isn't allowed yet: the offer.
        let asking = AITestSupport.makeApp(mode: .relay, consent: false)
        asking.ai.transportOverride = RecordingTransport()
        let outcome = await asking.ai.lectureNotes(input)
        XCTAssertTrue(outcome.needsCloud)
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.notes.sections.isEmpty)
        XCTAssertEqual(outcome.suggestion, .allowCloud(feature: AIJob.lecture.feature))
        XCTAssertEqual(outcome.note, "The offline rules can't make good notes from this lecture. Cloud AI can.")

        // No relay in this build, or a child: nothing to offer, and no promise.
        for (mode, age) in [(AppConfig.AIMode.local, AppSettings.AgeBand.adult), (.relay, .under13)] {
            let app = AITestSupport.makeApp(mode: mode, consent: true, age: age)
            app.ai.transportOverride = RecordingTransport()
            let plain = await app.ai.lectureNotes(input)
            XCTAssertTrue(plain.needsCloud)
            XCTAssertNil(plain.suggestion)
            XCTAssertEqual(plain.note, "The offline rules can't make good notes from this lecture.")
        }

        // Cloud AI allowed but not reachable.
        let offline = AITestSupport.makeApp(mode: .relay, consent: true)
        let relay = RecordingTransport()
        relay.failures["lecture"] = .offline
        offline.ai.transportOverride = relay
        let failed = await offline.ai.lectureNotes(input)
        XCTAssertTrue(failed.needsCloud)
        XCTAssertTrue(failed.fellBack)
        XCTAssertEqual(failed.note, "The offline rules can't make good notes from this lecture. Cloud AI couldn't be reached. Try again later.")

        // This week's free lecture notes are used up.
        let used = AITestSupport.makeApp(mode: .relay, consent: true)
        used.ai.transportOverride = RecordingTransport()
        used.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .lectures, used: 1, limit: 1, period: .week)]))
        let limited = await used.ai.lectureNotes(input)
        XCTAssertTrue(limited.needsCloud)
        XCTAssertEqual(limited.limitReached, .lectures)
        XCTAssertEqual(limited.note, "The offline rules can't make good notes from this lecture. This week's free lecture notes are used up. "
                       + "Cloud AI can write them once they reset, or with Capling Pro.")
    }

    func testTheNoteSaysWhatIsTrueWhenOnlyThisIPhonesModelCameUpEmpty() async {
        let input = LectureInput(course: "Bio 101", title: "Lecture 9", segments: chatter, flags: [])
        // Cloud AI is off (never allowed); this iPhone's model is ready and gives nothing usable. The old note said "Cloud AI couldn't be
        // reached", although Cloud AI was never asked.
        let off = AITestSupport.makeApp(mode: .relay, consent: false)
        let relay = RecordingTransport()
        off.ai.transportOverride = relay
        off.ai.probe = FixedOnDeviceProbe(.ready)
        off.ai.onDevice = ScriptedOnDeviceBackend(Array(repeating: .failure(OnDeviceError.unusable), count: 12))
        let outcome = await off.ai.lectureNotes(input)
        XCTAssertTrue(outcome.needsCloud)
        XCTAssertTrue(outcome.fellBack, "the iPhone's model was tried and wrote nothing")
        XCTAssertEqual(outcome.note, "The offline rules can't make good notes from this lecture. Cloud AI can.")
        XCTAssertEqual(outcome.suggestion, .allowCloud(feature: AIJob.lecture.feature))
        XCTAssertTrue(relay.calls.isEmpty, "Cloud AI was never asked")

        // Cloud AI off and nothing to offer (a build without a relay): no promise either.
        let local = AITestSupport.makeApp(mode: .local)
        local.ai.probe = FixedOnDeviceProbe(.ready)
        local.ai.onDevice = ScriptedOnDeviceBackend(Array(repeating: .failure(OnDeviceError.unusable), count: 12))
        let plain = await local.ai.lectureNotes(input)
        XCTAssertTrue(plain.fellBack)
        XCTAssertEqual(plain.note, "The offline rules can't make good notes from this lecture.")
    }

    func testTheNoteNamesWhyCloudAIDidNotWriteTheNotes() async {
        let input = LectureInput(course: "Bio 101", title: "Lecture 9", segments: chatter, flags: [])
        let base = "The offline rules can't make good notes from this lecture."
        let cases: [(RelayError, String)] = [
            (.offline, "\(base) Cloud AI couldn't be reached. Try again later."),
            (.accountPending, "\(base) Cloud AI is getting ready. Try again in a minute."),
            (.upstream("The model is busy."), "\(base) Cloud AI couldn't be reached. Try again later."),
            (.quotaExceeded(nil, message: "That's all the cloud AI for today. It starts again at midnight."),
             "\(base) That's all the cloud AI for today. It starts again at midnight."),
        ]
        for (error, note) in cases {
            let app = AITestSupport.makeApp(mode: .relay, consent: true)
            let relay = RecordingTransport()
            relay.failures["lecture"] = error
            app.ai.transportOverride = relay
            let outcome = await app.ai.lectureNotes(input)
            XCTAssertEqual(relay.calls, ["lecture"], "\(error)")
            XCTAssertTrue(outcome.needsCloud, "\(error)")
            XCTAssertEqual(outcome.note, note, "\(error)")
        }
    }

    func testTheRelayRefusingTheLectureForTheWeeksFreeNotesThenThisIPhoneWritingThemKeepsTheLimit() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let relay = RecordingTransport()
        relay.failures["lecture"] = .quotaExceeded(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .lectures, used: 1, limit: 1, period: .week)]),
                                                   message: "That's this week's free lecture notes.")
        app.ai.transportOverride = relay
        app.ai.probe = FixedOnDeviceProbe(.ready)
        let section = #"{"title": "Prophase", "bullets": ["The chromatin condenses and chromosomes become visible under the microscope."]}"#
        app.ai.onDevice = ScriptedOnDeviceBackend([.json(section)] + Array(repeating: .failure(OnDeviceError.unusable), count: 10))
        let outcome = await app.ai.lectureNotes(LectureInput(course: "Bio 101", title: "Lecture 6: Cell division",
                                                             segments: AITestSupport.lectureSegments, flags: []))

        XCTAssertEqual(relay.calls, ["lecture"])
        XCTAssertEqual(outcome.origin, .onDevice, "the free limit removes the cloud only")
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.limitReached, .lectures)
        guard case .upgrade(.lectures, _)? = outcome.suggestion else { return XCTFail("\(String(describing: outcome.suggestion))") }
        XCTAssertFalse(outcome.needsCloud)
    }

    func testEveryStringOfALectureRequestIsCutByCodePointsToTheRelaysLimits() async throws {
        let relay = ScriptedRelay()
        relay.onLecture = { _ in try RelayFixtures.load(LectureResponse.self, "lecture") }
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        app.ai.transportOverride = relay
        let decomposed = { (characters: Int) in String(repeating: "e\u{0301}", count: characters) }
        let segments = (0..<3).map { i in
            TranscriptSegment(id: "s\(i)", start: Double(i) * 100, end: Double(i) * 100 + 90, text: String(repeating: "word ", count: 1_200))   // 6,000 code points
        }
        let outcome = await app.ai.lectureNotes(LectureInput(course: decomposed(150), title: decomposed(200), segments: segments,
                                                             flags: [ExamFlag(id: "f1", time: 10, reason: .tapped, text: String(repeating: "flag ", count: 600))]))
        XCTAssertEqual(outcome.origin, .cloud)
        let request = try XCTUnwrap(relay.lectureRequests.first)
        XCTAssertEqual(request.course.unicodeScalars.count, RelayLimits.course, "300 code points cut to 200")
        XCTAssertEqual(request.title.unicodeScalars.count, RelayLimits.title, "400 code points cut to 300")
        XCTAssertTrue(request.segments.allSatisfy { $0.text.unicodeScalars.count <= RelayLimits.lineText })
        XCTAssertEqual(request.segments.map(\.id), ["s0", "s1", "s2"])
        XCTAssertTrue(request.flags.allSatisfy { $0.text.unicodeScalars.count <= RelayLimits.flagText })
    }

    func testALectureInAnotherLanguageGetsNoOfflineNotesAndSaysWhy() async {
        let spanish = [
            "Hoy vamos a hablar de la mitosis, que es el proceso por el cual una célula se divide en dos células hijas idénticas.",
            "Primero la profase: los cromosomas se condensan y la envoltura nuclear se rompe, y esto es importante para el examen.",
            "Después viene la metafase, en la que los cromosomas se alinean en el centro de la célula antes de separarse.",
        ].enumerated().map { TranscriptSegment(id: "s\($0.offset + 1)", start: Double($0.offset) * 125, end: Double($0.offset) * 125 + 100, text: $0.element) }
        let input = LectureInput(course: "Biología", title: "Clase 6", segments: spanish, flags: [])

        let asking = AITestSupport.makeApp(mode: .relay, consent: false)
        asking.ai.transportOverride = RecordingTransport()
        let outcome = await asking.ai.lectureNotes(input)
        XCTAssertTrue(outcome.needsCloud)
        XCTAssertTrue(outcome.items.isEmpty)
        XCTAssertTrue(outcome.notes.sections.isEmpty)
        XCTAssertEqual(outcome.suggestion, .allowCloud(feature: AIJob.lecture.feature))
        XCTAssertEqual(outcome.note, "This lecture doesn't look like English, and the offline rules only make notes from English lectures. Cloud AI can.")

        let offline = AITestSupport.makeApp(mode: .local)
        let plain = await offline.ai.lectureNotes(input)
        XCTAssertTrue(plain.needsCloud)
        XCTAssertNil(plain.suggestion)
        XCTAssertEqual(plain.note, "This lecture doesn't look like English, and the offline rules only make notes from English lectures.")
    }

    func testNoTranscriptYetIsStillTheOldPath() async {
        let app = AITestSupport.makeApp(mode: .local)
        let outcome = await app.ai.lectureNotes(LectureInput(course: "Bio 101", title: "Lecture 9", segments: [], flags: []))
        XCTAssertFalse(outcome.needsCloud)
        XCTAssertEqual(outcome.note, "There's no transcript to make notes from yet.")
    }

    // MARK: Confusions

    private let mistakes = [
        MistakeInput(itemId: "i4", topic: "Phases of mitosis", prompt: "Describe what happens in anaphase.", expected: "Anaphase",
                     given: "Telophase", misses: 2),
        MistakeInput(itemId: "i11", topic: "Phases of mitosis", prompt: "During ____, new nuclear envelopes form.",
                     expected: "Telophase", given: "anaphase", misses: 2),
    ]

    func testLocalConfusionsFindTheSwap() throws {
        let found = LocalConfusions.find(mistakes)
        let swap = try XCTUnwrap(found.first)
        XCTAssertEqual(swap.name, "Telophase vs anaphase")
        XCTAssertEqual(Set(swap.itemIds), ["i4", "i11"])
        XCTAssertEqual(swap.questions.count, 2)
        XCTAssertTrue(swap.questions.allSatisfy { $0.choices.filter(\.correct).count == 1 })

        let weak = LocalConfusions.find([
            MistakeInput(itemId: "a", topic: "Meiosis", prompt: "How many cells?", expected: "Four", given: "Eight", misses: 2),
            MistakeInput(itemId: "b", topic: "Meiosis", prompt: "How many divisions?", expected: "Two", given: "One", misses: 1),
        ])
        XCTAssertEqual(weak.first?.name, "Meiosis")
    }

    func testRouterConfusions() async {
        let offlineApp = AITestSupport.makeApp(mode: .local), mockApp = AITestSupport.makeApp(mode: .mock)
        defer { withExtendedLifetime((offlineApp, mockApp)) {} }
        let offline = await offlineApp.ai.confusions(course: "Bio 101", mistakes: mistakes)
        XCTAssertEqual(offline.origin, .rules)
        XCTAssertEqual(offline.confusions.first?.name, "Telophase vs anaphase")

        let mock = await mockApp.ai.confusions(course: "Bio 101", mistakes: mistakes,
                                                                          anchorTexts: GroundingCheck.texts(of: [AITestSupport.samplePage]))
        XCTAssertEqual(mock.origin, .cloud)
        XCTAssertEqual(mock.confusions.first?.name, "Anaphase vs telophase")
        XCTAssertEqual(mock.confusions.first?.questions.count, 3)

        // A cloud confusion about items it wasn't given is not believed: the rules answer instead.
        let strangers = [MistakeInput(itemId: "x1", topic: "T", prompt: "P", expected: "A", given: "B", misses: 3)]
        let unrelated = await mockApp.ai.confusions(course: "Bio 101", mistakes: strangers)
        XCTAssertEqual(unrelated.origin, .rules)
    }

    // MARK: Cards from a chat

    private let chat = [
        TutorMessage(role: .user, text: "What's the difference between mitosis and cytokinesis?"),
        TutorMessage(role: .assistant, text: "Short version: mitosis splits the nucleus, cytokinesis splits the rest of the cell. Cytokinesis is the division of the cytoplasm. Quick check: which one happens first?"),
    ]

    func testLocalCardsFromChat() {
        let cards = LocalCardsFromChat.cards(messages: chat, maxItems: 6)
        XCTAssertEqual(cards.map(\.prompt), ["Cytokinesis", "What's the difference between mitosis and cytokinesis?"])
        XCTAssertEqual(cards.first?.answer, "The division of the cytoplasm.")
        XCTAssertTrue(cards.allSatisfy { $0.kind == .flashcard })
    }

    func testRouterCardsFromChat() async {
        let offlineApp = AITestSupport.makeApp(mode: .local), mockApp = AITestSupport.makeApp(mode: .mock)
        defer { withExtendedLifetime((offlineApp, mockApp)) {} }
        let offline = await offlineApp.ai.cardsFromChat(course: "Bio 101", messages: chat)
        XCTAssertEqual(offline.origin, .rules)
        XCTAssertEqual(offline.items.count, 2)
        let mock = await mockApp.ai.cardsFromChat(course: "Bio 101", messages: chat)
        XCTAssertEqual(mock.origin, .cloud)
        XCTAssertEqual(mock.items.map(\.id), ["m1", "m2"])
    }

    // MARK: Page photos

    func testPhotosNeedTheirOwnSwitch() async throws {
        let without = AITestSupport.makeApp(mode: .mock, consent: true, photos: false)
        let refused = await without.ai.transcribeImage(base64JPEG: "abc", page: 0, label: "1")
        XCTAssertEqual(refused, .notAllowed(.allowPhotos))
        XCTAssertEqual(AISuggestion.allowPhotos.sheet, .consent(.photos))

        let with = AITestSupport.makeApp(mode: .mock, consent: true, photos: true)
        guard case .lines(let lines, let model) = await with.ai.transcribeImage(base64JPEG: "abc", page: 0, label: "1") else {
            return XCTFail("expected lines")
        }
        XCTAssertEqual(model, "mock")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.box == nil }, "cloud transcription has no geometry")

        let offlineApp = AITestSupport.makeApp(mode: .local, consent: true, photos: true)
        defer { withExtendedLifetime((without, with, offlineApp)) {} }
        let offline = await offlineApp.ai.transcribeImage(base64JPEG: "abc", page: 0, label: "1")
        XCTAssertEqual(offline, .notAllowed(nil), "no relay in this build: nothing to suggest")

        let url = try XCTUnwrap(SamplePage.imageURL)
        guard case .lines = await with.ai.transcribeImage(at: url, page: 0, label: "87") else { return XCTFail("expected lines") }
    }

    func testConsentChangesGoThroughAppModel() {
        let app = AITestSupport.makeApp(mode: .relay)
        XCTAssertFalse(app.hasCloudConsent)
        app.allowCloudAI(sendPhotos: true)
        XCTAssertEqual(app.settings.cloudConsentVersion, AIConsent.currentVersion)
        XCTAssertTrue(AIConsent.photosGranted(app.settings))
        app.withdrawCloudAI()
        XCTAssertFalse(app.hasCloudConsent)
        XCTAssertFalse(app.settings.sendPhotos, "photos go off with Cloud AI")
        // The harness grants the current version; a change to what is sent or who processes it is a new version, so everyone is asked again.
        XCTAssertEqual(AIConsent.currentVersion, 3)
    }
}
