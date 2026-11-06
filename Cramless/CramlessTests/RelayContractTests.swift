import XCTest
@testable import Cramless

/// Every canned reply decodes with the app's contract types. A renamed or retyped field fails here, not in a
/// session. The relay's tests validate the same files against its schemas.
final class RelayContractTests: XCTestCase {
    func testEveryFixtureDecodes() throws {
        XCTAssertNoThrow(try RelayFixtures.load(GenerateResponse.self, "generate"))
        XCTAssertNoThrow(try RelayFixtures.load(CheckResponse.self, "check"))
        for name in ["grade-partial", "grade-correct", "grade-incorrect"] {
            XCTAssertNoThrow(try RelayFixtures.load(GradeResponse.self, name), name)
        }
        for name in ["tutor-hints", "tutor-explain", "tutor-error"] {
            let script = try RelayFixtures.load(TutorScript.self, name)
            XCTAssertFalse(script.events.isEmpty, name)
            XCTAssertTrue(script.events.allSatisfy { $0.tutorEvent != nil }, name)
        }
        XCTAssertNoThrow(try RelayFixtures.load(ConfusionsResponse.self, "confusions"))
        XCTAssertNoThrow(try RelayFixtures.load(ConfusionsResponse.self, "confusions-lookalike"))
        XCTAssertNoThrow(try RelayFixtures.load(LectureResponse.self, "lecture"))
        XCTAssertNoThrow(try RelayFixtures.load(CardsFromChatResponse.self, "cards-from-chat"))
        XCTAssertNoThrow(try RelayFixtures.load(TranscribeImageResponse.self, "transcribe-image"))
        XCTAssertNoThrow(try RelayFixtures.load(QuotaStatus.self, "quota-free"))
        XCTAssertNoThrow(try RelayFixtures.load(QuotaStatus.self, "quota-pro"))
        XCTAssertNoThrow(try RelayFixtures.load(EntitlementResponse.self, "entitlement"))
        XCTAssertNoThrow(try RelayFixtures.load(SquadInvite.self, "squad-invite"))
        XCTAssertNoThrow(try RelayFixtures.load(SquadMembers.self, "squad-members"))
        XCTAssertNoThrow(try RelayFixtures.load(SquadRedeemResponse.self, "squad-redeem"))
        XCTAssertNoThrow(try RelayFixtures.load(AccountDeleteResponse.self, "account-delete"))
        XCTAssertNoThrow(try RelayFixtures.load(RelayErrorBody.self, "error-quota"))
    }

    func testSampleItemsAnchorToRealLines() throws {
        let lines = Set(try XCTUnwrap(SamplePage.ocr()).lines.map(\.id))
        let generated = try RelayFixtures.load(GenerateResponse.self, "generate")
        for item in generated.items {
            XCTAssertFalse(item.anchors.isEmpty, item.id)
            for anchor in item.anchors { XCTAssertTrue(lines.contains(anchor), "\(item.id) → \(anchor)") }
        }
        let checked = SamplePage.checkedItems()
        XCTAssertEqual(checked.dropped.map(\.id), ["i8"])
        XCTAssertEqual(checked.items.first { $0.id == "i2" }?.answer.contains("same number of chromosomes"), true)
    }

    func testTheTutorRequestAddsMaterialsAsAnOptionalFieldAndKeepsTheRestAsItWas() throws {
        var request = try fixtureRequest(TutorRequest.self, "tutor")
        XCTAssertNil(request.materials, "a request from before the field decodes")
        let before = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder.cramless.encode(request)) as? [String: Any])
        XCTAssertEqual(Set(before.keys), ["mode", "minor", "course", "messages", "sources"], "nothing new on the wire unless there is something to say")

        request.materials = ["Cardiac cycle (6 pages)", "Lecture 7 (38 min)", "Classmate deck (21 cards)"]
        let after = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder.cramless.encode(request)) as? [String: Any])
        XCTAssertEqual(Set(after.keys), ["mode", "minor", "course", "messages", "sources", "materials"])
        XCTAssertEqual(after["materials"] as? [String], request.materials)
        XCTAssertEqual(try JSONDecoder.cramless.decode(TutorRequest.self, from: JSONEncoder.cramless.encode(request)), request)
        // A hundred passages are the most a request holds; the older relay took twelve.
        XCTAssertEqual(TutorSelection.tutor.maxPassages, 100)
        XCTAssertEqual(TutorSelection.legacyTutorLimit, 12)
    }

    func testTheCheckRequestsNewFieldsAreOptionalAndLeftOutWhenAbsent() throws {
        let plain = CheckRequest(pages: [], items: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.cramless.encode(plain)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["pages", "items"], "build 2's request, byte for byte in its keys")

        let full = CheckRequest(pages: [], items: [], sourceTitle: "Palsgraf", headings: ["The Question of Duty"], lenient: true)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.cramless.encode(full)) as? [String: Any])
        XCTAssertEqual(wire["sourceTitle"] as? String, "Palsgraf")
        XCTAssertEqual(wire["headings"] as? [String], ["The Question of Duty"])
        XCTAssertEqual(wire["lenient"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder.cramless.decode(CheckRequest.self, from: JSONEncoder.cramless.encode(full)), full)
        // An older request (no new fields) still decodes.
        XCTAssertEqual(try JSONDecoder.cramless.decode(CheckRequest.self, from: JSONEncoder.cramless.encode(plain)), plain)
    }

    func testTheCheckContextIsCutToTheRelaysLimits() {
        let long = String(repeating: "x", count: 300)
        let context = CheckRequest.context(title: "  \(long)  ", headings: ["Chapter 1", "chapter 1", "", "  ", long] + (0..<100).map { "Heading \($0)" })
        XCTAssertEqual(context.title?.count, 200)
        XCTAssertEqual(context.headings?.count, 60)
        XCTAssertEqual(context.headings?.first, "Chapter 1")
        XCTAssertEqual(context.headings?[1].count, 120, "each heading is cut to 120")
        XCTAssertEqual(Set(context.headings ?? []).count, 60, "no repeats, whatever the case")
        let none = CheckRequest.context(title: "  ", headings: [])
        XCTAssertNil(none.title)
        XCTAssertNil(none.headings)
    }

    func testTheCheckContextIsCutByCodePointsBecauseTheRelayCountsThose() {
        // 150 decomposed "é" are 150 characters and 300 code points: `prefix(200)` kept all of them and the relay refused the request.
        let decomposed = { (characters: Int) in String(repeating: "e\u{0301}", count: characters) }
        XCTAssertEqual(decomposed(150).count, 150)
        XCTAssertEqual(decomposed(150).prefix(200).unicodeScalars.count, 300)
        let thumbs = String(repeating: "👍🏽", count: 100)   // 100 characters, 200 code points
        let context = CheckRequest.context(title: "  " + decomposed(150) + "  ", headings: [decomposed(100), thumbs] + (0..<80).map { "Heading \($0)" })
        XCTAssertEqual(context.title?.unicodeScalars.count, RelayLimits.checkTitle)
        XCTAssertEqual(context.title?.count, 100, "cut between characters")
        XCTAssertEqual(context.headings?.count, RelayLimits.headings)
        XCTAssertEqual(context.headings?[0].unicodeScalars.count, RelayLimits.heading)
        XCTAssertEqual(context.headings?[0].count, 60)
        XCTAssertEqual(context.headings?[1].unicodeScalars.count, RelayLimits.heading)
        XCTAssertEqual(context.headings?[1], String(repeating: "👍🏽", count: 60), "never through a skin tone")
        // Strings inside the limits are untouched.
        XCTAssertEqual(CheckRequest.context(title: "Palsgraf", headings: ["The Question of Duty"]).title, "Palsgraf")
    }

    func testGradingMixUpsCardsFromAChatAndResearchAreCutToTheRelaysLimits() {
        // 200 decomposed "é" are 200 characters and 400 code points.
        let long = { (characters: Int) in String(repeating: "e\u{0301}", count: characters) }
        let scalars = { (text: String) in text.unicodeScalars.count }

        let idea = KeyIdea(id: String(repeating: "k", count: 100), label: long(200), terms: Array(repeating: long(200), count: 50))
        let grade = GradeRequest(kind: .recall, level: String(repeating: "c", count: 60), prompt: long(3000), modelAnswer: long(5000),
                                 keyIdeas: Array(repeating: idea, count: 15), response: long(7000), sourceExcerpt: long(7000)).fitted()
        XCTAssertEqual(scalars(grade.level ?? ""), 40)
        XCTAssertEqual(scalars(grade.prompt), 4_000)
        XCTAssertEqual(scalars(grade.modelAnswer), 8_000)
        XCTAssertEqual(scalars(grade.response), 12_000, "an answer pasted from a page")
        XCTAssertEqual(scalars(grade.sourceExcerpt ?? ""), 12_000, "the lines a question was made from")
        XCTAssertEqual(grade.keyIdeas.count, 12)
        XCTAssertEqual(scalars(grade.keyIdeas[0].id), 80)
        XCTAssertEqual(scalars(grade.keyIdeas[0].label), 300)
        XCTAssertEqual(grade.keyIdeas[0].terms.count, 40)
        XCTAssertEqual(scalars(grade.keyIdeas[0].terms[0]), 300)
        let small = GradeRequest(kind: .recall, level: "college", prompt: "Why?", modelAnswer: "Because.", keyIdeas: [KeyIdea(id: "k1", label: "A", terms: ["a"])],
                                 response: "Since.", sourceExcerpt: nil)
        XCTAssertEqual(small.fitted(), small, "inside the limits, nothing changes")

        let mistake = MistakeInput(itemId: "i1", topic: long(200), prompt: long(3000), expected: long(5000), given: long(5000), misses: 20_000)
        let confusions = ConfusionsRequest(course: long(200), mistakes: Array(repeating: mistake, count: 45)).fitted()
        XCTAssertEqual(scalars(confusions.course), 200)
        XCTAssertEqual(confusions.mistakes.count, 40)
        XCTAssertEqual(scalars(confusions.mistakes[0].topic), 300)
        XCTAssertEqual(scalars(confusions.mistakes[0].prompt), 4_000)
        XCTAssertEqual(scalars(confusions.mistakes[0].expected), 8_000)
        XCTAssertEqual(scalars(confusions.mistakes[0].given), 8_000)
        XCTAssertEqual(confusions.mistakes[0].misses, 10_000)

        let thread = (0..<80).map { TutorMessage(role: $0 % 2 == 0 ? .user : .assistant, text: $0 % 9 == 4 ? "" : "Message \($0).") }
        let cards = CardsFromChatRequest(course: long(200), messages: thread + [TutorMessage(role: .user, text: long(5000))], maxItems: 50).fitted()
        XCTAssertEqual(scalars(cards.course ?? ""), 200)
        XCTAssertEqual(cards.messages.count, 60, "the last sixty that say something")
        XCTAssertTrue(cards.messages.allSatisfy { !$0.text.isEmpty && scalars($0.text) <= 8_000 })
        XCTAssertEqual(scalars(cards.messages.last?.text ?? ""), 8_000)
        XCTAssertEqual(cards.messages[cards.messages.count - 2].text, "Message 79.")
        XCTAssertEqual(cards.maxItems, 20)
        XCTAssertEqual(CardsFromChatRequest(course: nil, messages: [TutorMessage(role: .user, text: "Hi")], maxItems: 0).fitted().maxItems, 1)
        // A reply that only drafted cards has no text, and the relay refuses an empty message: it is left out, not sent.
        XCTAssertEqual(RelayLimits.fit([TutorMessage(role: .user, text: "Make cards"), TutorMessage(role: .assistant, text: ""),
                                        TutorMessage(role: .assistant, text: "Done.")], last: 60).map(\.text), ["Make cards", "Done."])
        XCTAssertTrue(RelayLimits.fit([TutorMessage(role: .assistant, text: "")], last: 60).isEmpty)

        let research = ResearchRequest(minor: false, topic: long(250), focus: long(250), course: long(200)).fitted()
        XCTAssertEqual(scalars(research.topic), 200)
        XCTAssertEqual(scalars(research.focus ?? ""), 300)
        XCTAssertEqual(scalars(research.course ?? ""), 200)
    }

    func testTheLimitsAreTheRelaysRequestSchemas() {
        // supabase/functions/_shared/schemas/requests.json: PageInput.label 40, GenerateRequest.course 200, sourceTitle (ShortText) 300,
        // CheckRequest.sourceTitle 200, headings 60 of 120, LineInput.text 4000, lecture course 200, title 300, segment text 4000,
        // flag text 2000, TranscribeImageRequest.label 40.
        XCTAssertEqual(RelayLimits.label, 40)
        XCTAssertEqual(RelayLimits.course, 200)
        XCTAssertEqual(RelayLimits.title, 300)
        XCTAssertEqual(RelayLimits.checkTitle, 200)
        XCTAssertEqual(RelayLimits.headings, 60)
        XCTAssertEqual(RelayLimits.heading, 120)
        XCTAssertEqual(RelayLimits.lineText, 4000)
        XCTAssertEqual(RelayLimits.flagText, 2000)
        // GradeRequest.level 40, response and sourceExcerpt 12000; ConfusionsRequest.mistakes 40 (topic 300); CardsFromChatRequest.messages
        // 60 of 1 to 8000; ResearchRequest.topic 200, focus 300; PageInput.lines 800.
        XCTAssertEqual(RelayLimits.level, 40)
        XCTAssertEqual(RelayLimits.gradeResponse, 12_000)
        XCTAssertEqual(RelayLimits.gradeExcerpt, 12_000)
        XCTAssertEqual(RelayLimits.mistakes, 40)
        XCTAssertEqual(RelayLimits.mistakeTopic, 300)
        XCTAssertEqual(RelayLimits.chatMessages, 60)
        XCTAssertEqual(RelayLimits.messageText, 8_000)
        XCTAssertEqual(RelayLimits.researchTopic, 200)
        XCTAssertEqual(RelayLimits.researchFocus, 300)
        XCTAssertEqual(RelayLimits.pageLines, 800)
    }

    /// `lookAlike` is sent only when true, so a request for a mix-up reads as it always did, and an older relay never sees it.
    func testLookAlikeIsSentOnlyWhenTrue() throws {
        let mistake = MistakeInput(itemId: "i7", topic: "Phases", prompt: "Which phase?", expected: "Metaphase", given: "", misses: 0)
        func body(_ request: ConfusionsRequest) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        }
        XCTAssertNil(try body(ConfusionsRequest(course: "Bio", mistakes: [mistake]))["lookAlike"])
        XCTAssertEqual(try body(ConfusionsRequest(course: "Bio", mistakes: [mistake], lookAlike: true))["lookAlike"] as? Bool, true)
        XCTAssertEqual(ConfusionsRequest(course: "Bio", mistakes: [mistake], lookAlike: true).fitted().lookAlike, true, "fitting keeps it")
    }
}
