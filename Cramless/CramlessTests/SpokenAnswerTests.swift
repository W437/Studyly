import XCTest
@testable import Cramless

/// What a person said out loud, read as a command or an answer, and what Cap says back. Pure.
final class SpokenAnswerTests: XCTestCase {
    private let options = ["Prophase", "Metaphase", "Anaphase", "Telophase"]

    private func choice(_ heard: String) -> SpokenAnswer.Reading { SpokenAnswer.read(heard, expecting: .choice(options: options)) }
    private func words(_ heard: String) -> SpokenAnswer.Reading { SpokenAnswer.read(heard, expecting: .words) }
    private func rating(_ heard: String) -> SpokenAnswer.Reading { SpokenAnswer.read(heard, expecting: .rating) }

    func testLettersHoweverTheRecogniserWritesThem() {
        for heard in ["A", "a.", "A", "Hey"] { XCTAssertEqual(choice(heard), .choice(0), heard) }
        for heard in ["B", "B.", "Be", "bee", "It's B.", "I think it's B", "the answer is B", "Option B", "letter b", "B I think", "B please"] {
            XCTAssertEqual(choice(heard), .choice(1), heard)
        }
        for heard in ["C", "See", "sea", "Answer C"] { XCTAssertEqual(choice(heard), .choice(2), heard) }
        for heard in ["D", "Dee", "D is the answer", "D is correct"] { XCTAssertEqual(choice(heard), .choice(3), heard) }
    }

    func testPlaces() {
        for heard in ["the first one", "First", "number one", "one", "1"] { XCTAssertEqual(choice(heard), .choice(0), heard) }
        for heard in ["the second one", "second", "number two", "two", "2", "To"] { XCTAssertEqual(choice(heard), .choice(1), heard) }
        XCTAssertEqual(choice("the third one"), .choice(2))
        XCTAssertEqual(choice("the last one"), .choice(3))
        XCTAssertEqual(choice("fourth"), .choice(3))
    }

    func testAPlaceOrALetterBeyondTheOptionsIsNotAnOption() {
        let two = SpokenAnswer.Expecting.choice(options: ["Mitosis", "Meiosis"])
        XCTAssertEqual(SpokenAnswer.read("C", expecting: two), .words("C"))
        XCTAssertEqual(SpokenAnswer.read("the fourth one", expecting: two), .words("the fourth one"))
    }

    func testAnOptionsOwnWords() {
        XCTAssertEqual(choice("anaphase"), .choice(2))
        XCTAssertEqual(choice("Anaphase."), .choice(2))
        XCTAssertEqual(choice("I think it's telophase"), .choice(3))
        let long = ["The sister chromatids separate", "The nuclear envelope re-forms", "The spindle starts forming"]
        XCTAssertEqual(SpokenAnswer.read("the nuclear envelope reforms", expecting: .choice(options: long)), .choice(1))
        XCTAssertEqual(SpokenAnswer.read("the spindle starts", expecting: .choice(options: long)), .choice(2))
    }

    func testAnOptionThatIsALetterOrANumberIsAnOptionFirst() {
        let numbers = SpokenAnswer.Expecting.choice(options: ["3", "2", "1", "4"])
        XCTAssertEqual(SpokenAnswer.read("2", expecting: numbers), .choice(1), "the option's own words, not the second place by chance")
        XCTAssertEqual(SpokenAnswer.read("1", expecting: numbers), .choice(2))
    }

    func testWordsThatPointToTwoOptionsAreNotAnAnswer() {
        let alike = ["Sister chromatids separate early", "Sister chromatids separate late"]
        XCTAssertEqual(SpokenAnswer.read("sister chromatids", expecting: .choice(options: alike)), .words("sister chromatids"))
    }

    func testALetterHasToBeTheWholeOfIt() {
        // "a cell wall" is an article and two words, not option A.
        let options = SpokenAnswer.Expecting.choice(options: ["The cell membrane", "A cell wall", "The nucleus"])
        XCTAssertEqual(SpokenAnswer.read("a cell wall", expecting: options), .choice(1))
        XCTAssertEqual(words("a cell wall"), .words("a cell wall"))
    }

    func testCommandsAreTheWholeOfWhatWasSaid() {
        for heard in ["Repeat", "repeat that", "Please repeat the question", "say that again", "Can you say that again?", "Pardon?", "one more time", "Again"] {
            XCTAssertEqual(words(heard), .command(.repeatQuestion), heard)
        }
        for heard in ["Skip", "skip this one", "Next.", "okay skip", "pass", "next question"] {
            XCTAssertEqual(words(heard), .command(.skip), heard)
        }
        for heard in ["Stop", "stop studying", "I'm done", "that's enough", "End the session."] {
            XCTAssertEqual(words(heard), .command(.stop), heard)
        }
        let answer = "The spindle fibres stop pulling and the cell moves on to the next phase"
        XCTAssertEqual(words(answer), .words(answer), "an answer that holds the words stays an answer")
    }

    func testIDontKnow() {
        for heard in ["I don't know", "I don’t know.", "no idea", "I'm not sure", "idk", "I don't remember", "no clue"] {
            XCTAssertEqual(words(heard), .dontKnow, heard)
            XCTAssertEqual(choice(heard), .dontKnow, heard)
        }
        XCTAssertEqual(words("maybe growth, I don't know, and repair of tissue"), .words("maybe growth, I don't know, and repair of tissue"),
                       "a hedge with an attempt in it is an answer")
    }

    func testRatings() {
        for heard in ["got it", "Got it.", "I got it", "Yes", "yeah", "knew it", "I knew that", "Right", "okay got it"] {
            XCTAssertEqual(rating(heard), .rating(.good), heard)
        }
        for heard in ["again", "Again.", "no", "Nope", "not yet", "missed it", "I didn't get it", "I got it wrong", "wrong"] {
            XCTAssertEqual(rating(heard), .rating(.again), heard)
        }
        for heard in ["hard", "that was hard", "almost", "kind of"] { XCTAssertEqual(rating(heard), .rating(.hard), heard) }
        for heard in ["easy", "that was easy", "too easy"] { XCTAssertEqual(rating(heard), .rating(.easy), heard) }
        XCTAssertEqual(rating("repeat that"), .command(.repeatQuestion))
        XCTAssertEqual(rating("skip"), .command(.skip))
        XCTAssertEqual(rating("purple monkey"), .nothing)
    }

    func testNothingSaid() {
        XCTAssertEqual(words(""), .nothing)
        XCTAssertEqual(words("   "), .nothing)
        XCTAssertEqual(choice("..."), .nothing)
    }

    func testABareAnswerForAFillIn() {
        XCTAssertEqual(SpokenAnswer.bareAnswer("I think it's anaphase."), "anaphase")
        XCTAssertEqual(SpokenAnswer.bareAnswer("The answer is sister chromatids"), "sister chromatids")
        XCTAssertEqual(SpokenAnswer.bareAnswer("Anaphase"), "anaphase")
        XCTAssertEqual(SpokenAnswer.bareAnswer("It's"), "it's", "nothing left: the words stand")
    }

    /// What this Mac's models wrote when a voice said each phrase (`scripts/speech_live/run.sh answers`, 6 Nov 2026, both engines).
    func testWhatARecogniserReallyWrites() {
        XCTAssertEqual(choice("B"), .choice(1))
        XCTAssertEqual(choice("Capital B."), .choice(1))
        XCTAssertEqual(choice("It's me"), .choice(1), "what dictation made of \"It's B\"")
        XCTAssertEqual(choice("Capital C"), .choice(2))
        XCTAssertEqual(choice("See"), .choice(2))
        XCTAssertEqual(choice("I think it's see"), .choice(2))
        XCTAssertEqual(choice("And C."), .words("And C."), "not the whole of it: Cap asks again")
        XCTAssertEqual(choice("It's a"), .choice(0))
        XCTAssertEqual(choice("K"), .choice(0))
        XCTAssertEqual(choice("Auction D"), .choice(3))
        XCTAssertEqual(choice("Option B."), .choice(1))
        XCTAssertEqual(choice("The answer is B."), .choice(1))
        XCTAssertEqual(choice("The first one"), .choice(0))
        XCTAssertEqual(choice("The 1st one."), .choice(0))
        XCTAssertEqual(choice("Second,"), .choice(1))
        XCTAssertEqual(choice("Number three."), .choice(2))
        XCTAssertEqual(choice("The last"), .choice(3))
        XCTAssertEqual(choice("I don't know"), .dontKnow)
        XCTAssertEqual(rating("Got it"), .rating(.good))
        XCTAssertEqual(rating("Again"), .rating(.again))
        XCTAssertEqual(rating("That was hard"), .rating(.hard))
        XCTAssertEqual(rating("Easy"), .rating(.easy))
        XCTAssertEqual(words("Skip"), .command(.skip))
        XCTAssertEqual(words("Stop"), .command(.stop))
        XCTAssertEqual(words("Repeat that"), .command(.repeatQuestion))
        XCTAssertEqual(words("Say that again"), .command(.repeatQuestion))
    }
}

final class SpokenVerdictTests: XCTestCase {
    private let ideas = [KeyIdea(id: "k1", label: "Chromatids separate", terms: ["separate"]),
                         KeyIdea(id: "k2", label: "Spindle fibres pull", terms: ["pull"]),
                         KeyIdea(id: "k3", label: "Moves to the poles", terms: ["poles"])]

    private func grade(_ verdict: GradeResponse.Verdict, hit: [String] = [], missing: [String] = []) -> GradeOutcome {
        GradeOutcome(score: verdict == .correct ? 1 : 0.5, verdict: verdict, confidence: 0.9, marks: [], hitIdeaIDs: hit,
                     missing: ideas.filter { missing.contains($0.id) }.map { MissingIdea(id: $0.id, label: $0.label) },
                     feedback: "", fix: "", gradedBy: .cloud, model: "m")
    }

    func testRight() {
        XCTAssertEqual(SpokenVerdict.ownWords(grade(.correct, hit: ["k1", "k2", "k3"]), ideas: ideas, modelAnswer: "x"), "Nice! You got every key idea.")
        XCTAssertEqual(SpokenVerdict.ownWords(grade(.correct, hit: ["k1"]), ideas: Array(ideas.prefix(1)), modelAnswer: "x"), "Nice!")
        XCTAssertEqual(SpokenVerdict.exact(grade(.correct), rightAnswer: "Anaphase"), "Nice!")
    }

    func testSaved() {
        XCTAssertEqual(SpokenVerdict.exact(grade(.correct), rightAnswer: "Anaphase", saved: true), "Saved it.")
        XCTAssertEqual(SpokenVerdict.ownWords(grade(.correct, hit: ["k1"]), ideas: Array(ideas.prefix(1)), modelAnswer: "x", saved: true), "Saved it.")
        XCTAssertEqual(SpokenVerdict.rated(.good, saved: true), "Saved it.")
    }

    func testPartlyNamesWhatWasHitAndMissedJoinedWithAnd() {
        let line = SpokenVerdict.ownWords(grade(.partial, hit: ["k1"], missing: ["k2", "k3"]), ideas: ideas, modelAnswer: "x")
        XCTAssertEqual(line, "Almost. You got chromatids separate. You missed spindle fibres pull and moves to the poles.")
    }

    func testMoreThanTwoAreCounted() {
        XCTAssertEqual(SpokenVerdict.named(["One", "Two", "Three", "Four"]), "one, two and 2 more")
        XCTAssertEqual(SpokenVerdict.named(["One"]), "one")
        XCTAssertEqual(SpokenVerdict.named([]), "")
    }

    func testNotYetGivesTheAnswer() {
        XCTAssertEqual(SpokenVerdict.ownWords(grade(.incorrect, missing: ["k1"]), ideas: ideas, modelAnswer: "They separate"),
                       "Not yet. Here's the answer: They separate.")
        XCTAssertEqual(SpokenVerdict.exact(grade(.incorrect), rightAnswer: "Anaphase"), "Not yet. The answer is Anaphase.")
    }

    func testNoVerdictWhenItIsThePersonsToSay() {
        XCTAssertEqual(SpokenVerdict.dontKnow(answer: "Anaphase"), "Here's the answer: Anaphase.")
        XCTAssertEqual(SpokenVerdict.howDidItGo(answer: "Anaphase"), "Here's the answer: Anaphase. Did you have it? Say got it, or again.")
    }

    func testTheEnd() {
        XCTAssertEqual(SpokenVerdict.summary(answered: 12, right: 9), "That's it. 9 of 12 right the first time.")
        XCTAssertEqual(SpokenVerdict.summary(answered: 0, right: 0), "Okay. We'll stop here.")
    }
}
