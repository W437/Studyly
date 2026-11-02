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
