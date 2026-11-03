import XCTest
@testable import Cramless

/// Japanese and Chinese have no spaces. The lexicon used to make a whole sentence one "word", so the retriever found nothing for any question in them
/// (round 3: five Japanese questions, five empty results). Now a run of Han and kana is cut into words by the system's tokenizer.
final class CJKRetrievalTests: XCTestCase {

    private let japaneseQuestion = "御誓文の最初の案を書いたのは誰ですか？"
    private let japanesePassage = "五箇条の御誓文は由利公正が起草し、福岡孝弟が修正した。"

    private func content(_ text: String) -> Set<String> {
        Set(Lexicon.tokens(text).filter(\.isContent).map(\.stem))
    }

    func testASentenceInJapaneseIsMoreThanOneWord() {
        let tokens = Lexicon.tokens(japaneseQuestion)
        XCTAssertGreaterThan(tokens.count, 5)
        // Every token's range is its own text in the sentence.
        let chars = Array(japaneseQuestion)
        for token in tokens { XCTAssertEqual(String(chars[token.range]), token.word) }
        // Particles are stop words, the nouns are not.
        XCTAssertTrue(tokens.contains { $0.word == "の" && $0.isStopWord })
        XCTAssertTrue(tokens.contains { !$0.isStopWord })
    }

    func testAQuestionAndThePassageThatAnswersItShareAWord() {
        let shared = content(japaneseQuestion).intersection(content(japanesePassage))
        XCTAssertFalse(shared.isEmpty, "\(content(japaneseQuestion)) and \(content(japanesePassage))")
    }

    func testChineseIsCutToo() {
        let tokens = Lexicon.tokens("今天的天气很好，我们去公园吧")
        XCTAssertGreaterThan(tokens.count, 4)
        XCTAssertTrue(tokens.contains { $0.word == "的" && $0.isStopWord })
        XCTAssertTrue(content("明治维新是日本的现代化").intersection(content("日本的明治维新开始于一八六八年")).count >= 1)
    }

    func testLatinTextBesideJapaneseIsUnchanged() {
        let words = Lexicon.tokens("The Meiji Restoration (1868) was 明治維新 in Japan.").map(\.word)
        XCTAssertTrue(words.contains("meiji") && words.contains("restoration") && words.contains("1868") && words.contains("japan"))
        XCTAssertEqual(Lexicon.tokens("Cells divide, then grow.").map(\.word), ["cells", "divide", "then", "grow"])
    }

    func testTheRetrieverFindsTheJapanesePassage() throws {
        let lines = [
            "明治維新は江戸幕府が倒れ、明治政府が成立した一連の変革である。",
            "五箇条の御誓文は由利公正が起草し、福岡孝弟が修正し、木戸孝允が最終的に整えた。",
            "廃藩置県により藩が廃止され、県が置かれた。",
            "華族は旧公家や大名などに与えられた特権的な身分である。",
            "日露戦争は満洲と朝鮮の支配をめぐって一九〇四年に始まった。",
        ]
        let page = PageText(index: 0, label: "1", lines: lines.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) })
        let retriever = LocalRetriever(material: [TutorMaterial(sourceID: UUID(), title: "明治維新", kind: .text, pages: [page])])
        let ranked = retriever.recall(japaneseQuestion)
        XCTAssertFalse(ranked.isEmpty, "a Japanese question used to find nothing")
        let best = try XCTUnwrap(ranked.first)
        XCTAssertTrue(retriever.passages[best].text.contains("御誓文"), retriever.passages[best].text)
        let nobles = retriever.recall("華族になったのはどんな人たちですか？")
        XCTAssertTrue(nobles.first.map { retriever.passages[$0].text.contains("華族") } ?? false)
    }

    // MARK: Words and the offline tutor

    func testASentenceInJapaneseIsWorthSeveralWords() {
        XCTAssertEqual(Lexicon.cjkWords(in: "The cell divides."), 0)
        XCTAssertEqual(Lexicon.wordCount("The cell divides."), 3, "a text with spaces is counted as it always was")
        XCTAssertEqual(Lexicon.wordCount(""), 0)
        XCTAssertGreaterThanOrEqual(Lexicon.wordCount(japanesePassage), 8)
        XCTAssertGreaterThanOrEqual(Lexicon.wordCount("明治維新は江戸幕府が倒れた。"), 5, "one sentence was one word, and a 'sentence' of fewer than four words is not an answer")
    }

    private func japaneseNotes() -> [TutorMaterial] {
        [TutorMaterial(sourceID: UUID(), title: "明治維新", kind: .text, pages: [PageText(index: 0, label: "1", lines: TutorFixtures.lines([
            "明治維新は江戸幕府が倒れ、明治政府が成立した一連の変革である。",
            "五箇条の御誓文は由利公正が起草し、福岡孝弟が修正し、木戸孝允が最終的に整えた。",
            "廃藩置県により藩が廃止され、県が置かれた。",
            "華族は旧公家や大名などに与えられた特権的な身分である。",
            "日露戦争は満洲と朝鮮の支配をめぐって一九〇四年に始まった。",
        ]))])]
    }

    private let wordsOnly = OfflineSearch.Options(useContextualModel: false, useWordVectors: false)

    func testTheOfflineSearchReadsJapaneseSentences() throws {
        // Every Japanese sentence used to count as one word, so every one was "too short to say anything" and nothing was ever a candidate.
        let ranking = LocalRetriever(material: japaneseNotes()).rankSentences(for: "五箇条の御誓文を起草したのは誰ですか？", options: wordsOnly)
        XCTAssertFalse(ranking.candidates.isEmpty)
        XCTAssertTrue(try XCTUnwrap(ranking.candidates.first).sentence.contains("御誓文"), ranking.candidates.first?.sentence ?? "")
        XCTAssertTrue(ranking.isConvincing, "\(ranking.verdict)")
    }

    func testAJapaneseQuestionTheNotesDoNotAnswerIsNotAnswered() {
        let ranking = LocalRetriever(material: japaneseNotes()).rankSentences(for: "光合成はどこで行われますか？", options: wordsOnly)
        XCTAssertFalse(ranking.isConvincing, "\(ranking.verdict)")
    }

    func testTheContextualModelsSimilarityDecidesNothingForAJapaneseQuestion() {
        // The model's similarities run high for Japanese and Chinese (0.8 to 0.99 for lines that are not about the question), so the
        // words decide there: a sentence with a third of the question's words and a similarity of 0.9 is not an answer.
        var evidence = OfflineRanking.Evidence()
        evidence.sentenceCoverage = 0.3
        evidence.passageCoverage = 0.3
        evidence.sharedTerms = 1
        evidence.similarity = 0.9
        evidence.meaning = 1
        XCTAssertEqual(OfflineSearch.verdict(for: evidence, usedMeaning: true), .convincing)
        XCTAssertNotEqual(OfflineSearch.verdict(for: evidence, usedMeaning: true, wordsOnly: true), .convincing)
        evidence.sentenceCoverage = 0.6
        XCTAssertEqual(OfflineSearch.verdict(for: evidence, usedMeaning: true, wordsOnly: true), .convincing)
        evidence.sharedTerms = 0
        XCTAssertNotEqual(OfflineSearch.verdict(for: evidence, usedMeaning: true, wordsOnly: true), .convincing)
    }
}
