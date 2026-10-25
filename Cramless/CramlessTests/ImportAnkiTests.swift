import XCTest
@testable import Cramless

/// Anki packages built in the test (SQLite collection + the test's ZIP writer): basic, reversed and cloze notes,
/// scheduling carried over, media dropped, the newest-format error, and committing into a course.
@MainActor
final class ImportAnkiTests: CaptureTestCase {
    private let crt = Date(timeIntervalSince1970: TimeInterval(AnkiFixture.crt))
    private let lastReview = Date(timeIntervalSince1970: 1_708_000_000)

    private func makePackage(name: String = "collection.anki21") throws -> URL {
        let notes = [
            AnkiFixture.Note(id: 1, model: 1001, fields: ["Anaphase", "Sister chromatids <b>separate</b> and move to opposite poles.<img src=\"a.png\">"]),
            AnkiFixture.Note(id: 2, model: 1002, fields: ["During {{c1::telophase::phase}}, the {{c2::nuclear envelope}} re-forms.", "Mitosis ends here."]),
            AnkiFixture.Note(id: 3, model: 1003, fields: ["la biblioteca", "the library"]),
            AnkiFixture.Note(id: 4, model: 1001, fields: ["[sound:lecture.mp3]", "Only a sound on the front"]),
        ]
        let cards = [
            // A review card: 21-day interval, default ease, due 100 days after the collection was made.
            AnkiFixture.Card(id: 11, note: 1, type: 2, queue: 2, due: 100, ivl: 21, factor: 2500, reps: 5, lapses: 1),
            AnkiFixture.Card(id: 21, note: 2, ord: 0),
            // An intraday learning card: due is a Unix timestamp.
            AnkiFixture.Card(id: 22, note: 2, ord: 1, type: 1, queue: 1, due: 1_760_000_000, factor: 2500, reps: 1),
            // Suspended review card at the minimum ease.
            AnkiFixture.Card(id: 31, note: 3, deck: 2002, ord: 0, type: 2, queue: -1, due: 120, ivl: 30, factor: 1300, reps: 9, lapses: 4),
            // A card scheduled by Anki's FSRS: its own stability and difficulty win.
            AnkiFixture.Card(id: 32, note: 3, deck: 2002, ord: 1, type: 2, queue: 2, due: 130, ivl: 40, factor: 2500, reps: 4,
                             data: "{\"s\":45.5,\"d\":3.2,\"dr\":0.9}"),
            AnkiFixture.Card(id: 41, note: 4),
        ]
        let collection = try AnkiFixture.collection(at: root.appending(path: "collection-\(UUID().uuidString).sqlite"),
                                                    notes: notes, cards: cards,
                                                    revlog: [(Int64(lastReview.timeIntervalSince1970 * 1000), 11)])
        return try temporaryFile("Biology.apkg", data: AnkiFixture.package(collection: collection, name: name))
    }

    func testPreviewReadsCardsClozesAndScheduling() throws {
        let preview = try DeckImporter.preview(fileAt: makePackage())
        XCTAssertEqual(preview.format, .anki)
        XCTAssertEqual(preview.count, 5, "the media-only card is left out")
        XCTAssertEqual(preview.title, "Unit 3", "two subdecks: their shared parent")
        XCTAssertTrue(preview.warnings.contains { $0.contains("2 images and sounds weren't imported") }, "\(preview.warnings)")
        XCTAssertTrue(preview.warnings.contains { $0.contains("nothing but media") }, "\(preview.warnings)")
        XCTAssertEqual(preview.scheduledCount, 4)
        XCTAssertEqual(preview.suspendedCount, 1)

        let basic = preview.cards[0]
        XCTAssertEqual(basic.kind, .flashcard)
        XCTAssertEqual(basic.front, "Anaphase")
        XCTAssertEqual(basic.back, "Sister chromatids separate and move to opposite poles.")
        XCTAssertEqual(basic.topic, "Mitosis")

        let review = try XCTUnwrap(basic.memory)
        XCTAssertEqual(review.state, .review)
        XCTAssertEqual(review.stability, 21, accuracy: 0.001, "stability ≈ interval")
        XCTAssertEqual(review.difficulty, 5, accuracy: 0.001, "ease 2.5 → difficulty 5")
        XCTAssertEqual(try XCTUnwrap(review.due).timeIntervalSince(crt), 100 * 86_400, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(review.lastReview).timeIntervalSince1970, lastReview.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(review.reps, 5)
        XCTAssertEqual(review.lapses, 1)

        let cloze1 = preview.cards[1]
        XCTAssertEqual(cloze1.kind, .cloze)
        XCTAssertEqual(cloze1.cloze?.text, "During {{telophase}}, the nuclear envelope re-forms.")
        XCTAssertEqual(cloze1.cloze?.answers, ["telophase"])
        XCTAssertEqual(cloze1.back, "telophase")
        XCTAssertEqual(cloze1.front, "Fill in the blank. Hint: phase.")
        XCTAssertEqual(cloze1.explanation, "Mitosis ends here.")
        XCTAssertNil(cloze1.memory, "a new card arrives new")

        let cloze2 = preview.cards[2]
        XCTAssertEqual(cloze2.cloze?.text, "During telophase, the {{nuclear envelope}} re-forms.")
        let learning = try XCTUnwrap(cloze2.memory)
        XCTAssertEqual(learning.state, .learning)
        XCTAssertEqual(try XCTUnwrap(learning.due).timeIntervalSince1970, 1_760_000_000, accuracy: 1)

        let suspended = preview.cards[3]
        XCTAssertEqual(suspended.front, "la biblioteca")
        XCTAssertEqual(suspended.back, "the library")
        XCTAssertTrue(suspended.suspended)
        XCTAssertEqual(suspended.topic, "Vocabulary")
        XCTAssertEqual(try XCTUnwrap(suspended.memory).difficulty, 10, accuracy: 0.001, "ease 1.3 → difficulty 10")
        XCTAssertEqual(try XCTUnwrap(suspended.memory).lapses, 4)

        let reversed = preview.cards[4]
        XCTAssertEqual(reversed.front, "the library", "card 2 of a reversed note shows the back first")
        XCTAssertEqual(reversed.back, "la biblioteca")
        let fsrs = try XCTUnwrap(reversed.memory)
        XCTAssertEqual(fsrs.stability, 45.5, accuracy: 0.001)
        XCTAssertEqual(fsrs.difficulty, 3.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(fsrs.lastReview).timeIntervalSince(crt), (130 - 40) * 86_400, accuracy: 1,
                       "no review log: due minus the interval")
    }

    func testOlderPackagesUseCollectionAnki2() throws {
        let preview = try DeckImporter.preview(fileAt: makePackage(name: "collection.anki2"))
        XCTAssertEqual(preview.count, 5)
    }

    func testNewestFormatOnlyFailsWithHowToExportAgain() throws {
        let stub = try AnkiFixture.collection(at: root.appending(path: "stub.sqlite"),
                                              notes: [.init(id: 1, model: 1001, fields: ["Please update to the latest Anki version, then import the .colpkg/.apkg file again.", ""])],
                                              cards: [.init(id: 1, note: 1)])
        let package = ZipWriter.archive([
            .init(name: "collection.anki21b", data: Data(repeating: 0x28, count: 4096), deflate: false),
            .init(name: "collection.anki2", data: try Data(contentsOf: stub), deflate: true),
            .init(name: "media", data: Data([0x28, 0xB5, 0x2F, 0xFD]), deflate: false),
        ])
        let url = try temporaryFile("New.apkg", data: package)
        XCTAssertThrowsError(try DeckImporter.preview(fileAt: url)) { error in
            XCTAssertEqual(error as? CaptureError, .ankiNewestFormat)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           "This deck uses Anki's newest format. In Anki, export again with 'Support older Anki versions' turned on.")
        }
        // The stub alone (an odd package with only the "please update" note) says the same.
        let stubOnly = try temporaryFile("Stub.apkg", data: AnkiFixture.package(collection: stub, name: "collection.anki2"))
        XCTAssertThrowsError(try DeckImporter.preview(fileAt: stubOnly)) { error in
            XCTAssertEqual(error as? CaptureError, .ankiNewestFormat)
        }
    }

    func testAPackageWithoutACollectionSaysSo() throws {
        let url = try temporaryFile("Empty.apkg", data: ZipWriter.archive([.init(name: "media", data: Data("{}".utf8), deflate: false)]))
        XCTAssertThrowsError(try DeckImporter.preview(fileAt: url)) { XCTAssertEqual($0 as? CaptureError, .ankiNoCollection) }
    }

    func testCommitKeepsSchedulingAndSkipsDuplicates() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let url = try makePackage()
        let preview = try DeckImporter.preview(fileAt: url)
        let outcome = app.commitImport(preview, to: course, file: url)
        XCTAssertEqual(outcome.added, 5)
        XCTAssertEqual(outcome.duplicates, 0)
        let source = try XCTUnwrap(app.source(outcome.sourceID))
        XCTAssertEqual(source.kind, .anki)
        XCTAssertEqual(source.status, .ready)
        XCTAssertEqual(source.title, "Unit 3 (Anki)")
        let kept = try XCTUnwrap(source.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: kept).path), "the deck file is kept on device")

        let items = course.liveItems
        XCTAssertEqual(items.count, 5)
        XCTAssertTrue(items.allSatisfy { $0.origin == .anki })
        XCTAssertEqual(items.filter { $0.status == .active }.count, 4)
        XCTAssertEqual(items.filter { $0.status == .suspended }.count, 1)
        let anaphase = try XCTUnwrap(items.first { $0.prompt == "Anaphase" })
        XCTAssertEqual(anaphase.memory.state, .review)
        XCTAssertEqual(anaphase.memory.stability, 21, accuracy: 0.001)
        XCTAssertEqual(anaphase.sourceRef?.sourceID, source.id)
        let cloze = try XCTUnwrap(items.first { $0.kind == .cloze && $0.answer == "telophase" })
        XCTAssertEqual(cloze.cloze?.answers, ["telophase"])
        XCTAssertEqual(Set(course.liveTopics.map(\.name)), ["Mitosis", "Vocabulary"])

        let again = app.commitImport(preview, to: course)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.duplicates, 5)
    }

    // MARK: Pure pieces

    func testHTMLBecomesPlainTextAndMediaIsCounted() {
        let plain = AnkiText.plain("<div>Line one<br>Line&nbsp;two &amp; <i>three</i></div><ul><li>a</li><li>b</li></ul>[sound:x.mp3]<img src='p.jpg'/> &#233;t&#xE9; &lt;tag&gt;")
        XCTAssertEqual(plain.text, "Line one\nLine two & three\n• a\n• b\nété <tag>")
        XCTAssertEqual(plain.media, 2)
    }

    func testClozeConversion() {
        XCTAssertEqual(AnkiText.clozeNumbers(in: "{{c1::a}} {{c3::b}} {{c1::c}}"), [1, 3])
        let both = AnkiText.cloze("{{c1::Mitosis}} makes {{c1::two}} cells", number: 1)
        XCTAssertEqual(both?.text, "{{Mitosis}} makes {{two}} cells")
        XCTAssertEqual(both?.answers, ["Mitosis", "two"])
        XCTAssertNil(AnkiText.cloze("{{c1::Mitosis}}", number: 2), "no deletion with that number")
        let nested = AnkiText.cloze("{{c1::The {{c2::spindle}} pulls}} chromatids", number: 2)
        XCTAssertEqual(nested?.text, "The {{spindle}} pulls chromatids")
        let outer = AnkiText.cloze("{{c1::The {{c2::spindle}} pulls}} chromatids", number: 1)
        XCTAssertEqual(outer?.text, "{{The spindle pulls}} chromatids")
        XCTAssertEqual(outer?.answers, ["The spindle pulls"])
    }

    func testTemplateSides() {
        let typed = AnkiText.sides(question: "{{Front}}\n\n{{type:Back}}", answer: "{{Front}}<hr id=answer>{{type:Back}}")
        XCTAssertEqual(typed.front, ["Front"])
        XCTAssertEqual(typed.back, ["Back"])
        let optional = AnkiText.sides(question: "{{#Add Reverse}}{{Back}}{{/Add Reverse}}", answer: "{{FrontSide}}<hr>{{Front}}<br>{{Notes}}")
        XCTAssertEqual(optional.front, ["Back"])
        XCTAssertEqual(optional.back, ["Front"])
        XCTAssertEqual(optional.extra, ["Notes"])
    }

    func testEaseToDifficulty() {
        XCTAssertEqual(AnkiImporter.difficulty(fromEase: 2500), 5, accuracy: 0.001)
        XCTAssertEqual(AnkiImporter.difficulty(fromEase: 1300), 10, accuracy: 0.001)
        XCTAssertEqual(AnkiImporter.difficulty(fromEase: 3700), 1, accuracy: 0.001)
        XCTAssertEqual(AnkiImporter.difficulty(fromEase: 0), 5, accuracy: 0.001)
        XCTAssertLessThan(AnkiImporter.difficulty(fromEase: 3000), 5)
    }

    func testFilteredDeckUsesTheOriginalDue() {
        let s = AnkiImporter.Schedule(type: 2, queue: 2, due: -100_000, ivl: 10, factor: 2500, reps: 3, lapses: 0, odue: 50, odid: 99)
        let memory = AnkiImporter.memory(s, collectionCreated: crt, lastReview: nil)
        XCTAssertEqual(try XCTUnwrap(memory?.due).timeIntervalSince(crt), 50 * 86_400, accuracy: 1)
    }
}
