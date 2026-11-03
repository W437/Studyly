import XCTest
@testable import Cramless

/// A calculation's answer is a number and its key ideas describe the method: a right number must be right. Measured in the 14-day tests,
/// 94 of 94 right numeric answers that had been marked wrong or partly right are accepted here, and no wrong one.
@MainActor
final class NumericAnswerTests: XCTestCase {

    private func agrees(_ model: String, _ typed: String) -> Bool {
        NumericAnswer.agrees(modelAnswer: model, typed: typed)
    }

    func testAPercentAndItsFractionAreTheSameAnswer() {
        let model = "0.50 (50%, dimensionless)"
        for typed in ["50%", "0.5", "It is 0.50", "50 percent", "1/2", "0.500", "The efficiency is 50%.", "50", "eta = 0.5"] {
            XCTAssertTrue(agrees(model, typed), typed)
        }
        for typed in ["0.25", "5%", "25%", "half", "", "no idea"] {
            XCTAssertFalse(agrees(model, typed), typed)
        }
        XCTAssertTrue(agrees("50% (dimensionless).", "0.5"))
    }

    func testTheSignMatters() {
        let model = "−2 J/K"
        for typed in ["-2 J/K", "−2", "–2 J/K", "minus 2", "The change is -2.0 J/K"] {
            XCTAssertTrue(agrees(model, typed), typed)
        }
        for typed in ["2 J/K", "+2", "20", "-2 kJ/K", "2"] {
            XCTAssertFalse(agrees(model, typed), typed)
        }
        XCTAssertTrue(agrees("+2 J/K", "2 J/K"))
        XCTAssertFalse(agrees("+2 J/K", "-2 J/K"))
    }

    func testAUnitThatContradictsTheModelAnswerIsNotTheSameQuantity() {
        let model = "500 J per cycle"
        for typed in ["500 J", "500", "500 J/cycle", "500J", "W = 500 J per cycle", "500.0 J"] {
            XCTAssertTrue(agrees(model, typed), typed)
        }
        for typed in ["500 kJ", "5000 J", "50 J", "5.00 kJ"] {
            XCTAssertFalse(agrees(model, typed), typed)
        }
        XCTAssertTrue(agrees("0.300 M", "0.30 mol/L"))
        XCTAssertFalse(agrees("0.300 M", "0.300 mM"))
        XCTAssertFalse(agrees("0.300 M", "0.03 M"))
    }

    func testSeparatorsAndYears() {
        XCTAssertTrue(agrees("1,200", "1200"))
        XCTAssertTrue(agrees("1200", "1,200 J"))
        XCTAssertTrue(agrees("0.5", "0,5"))
        XCTAssertFalse(agrees("1200", "1.200"))
        XCTAssertTrue(agrees("1803", "in 1803"))
        XCTAssertFalse(agrees("1803", "1830"))
    }

    func testOnlyAnAnswerThatIsNothingButAQuantityIsDecidedHere() {
        let notQuantities: [(String, String)] = [
            ("Type 2 diabetes", "2"), ("21 January 1793", "1793"), ("dS > 0.", "0"), ("W(1, 4) = 4.", "4"), ("Cv = 3R.", "3"),
            ("1 ATP and 2 CO2.", "2"), ("The efficiency is 0.5, or 50%.", "0.5"), ("0, its starting distance.", "0"),
            ("5 May 1789, at Versailles", "1789"), ("T = 600 K, W = 300 J", "300"), ("300 J and 600 K", "300"), ("", "5"),
        ]
        for (model, typed) in notQuantities {
            XCTAssertFalse(agrees(model, typed), "\(model) / \(typed)")
        }
    }

    func testALongAnswerCountsByItsLastNumber() {
        let long = "Using the efficiency formula with the temperatures of 600 and 300 kelvin the engine absorbs heat and rejects some of it so the work is"
        XCTAssertTrue(agrees("300 J per cycle", long + " 300 J."))
        XCTAssertFalse(agrees("300 J per cycle", "The engine absorbs 300 J of heat from the hot reservoir over the full cycle, rejects most of it to the cold side, and so the net work output is 120 J."))
        XCTAssertTrue(agrees("300 J per cycle", "It does 300 J."))
    }

    // MARK: In the grader and the router

    private func subject(_ answer: String) -> GradeSubject {
        GradeSubject(kind: .apply, prompt: "A Carnot engine operates between 600 K and 300 K. What is its efficiency?", modelAnswer: answer,
                     keyIdeas: [KeyIdea(id: "k1", label: "Use η = 1 − Tc/TH", terms: ["Tc/TH", "1 − Tc/TH"]),
                                KeyIdea(id: "k2", label: "Substitute temperatures in kelvin", terms: ["kelvin"])])
    }

    func testARightNumberIsCorrectWhateverTheKeyIdeasSayAndNoModelIsAsked() {
        let s = subject("0.50 (50%, dimensionless)")
        let grade = LocalGrader.grade(s, answer: .text("50%"))
        XCTAssertEqual(grade.verdict, .correct)
        XCTAssertEqual(grade.hitIdeaIDs, ["k1", "k2"])
        XCTAssertTrue(grade.missing.isEmpty)
        XCTAssertGreaterThanOrEqual(grade.confidence, 0.9)
        XCTAssertNil(AIRouter.refinableText(s, .text("50%")), "an exact number has nothing for a model to refine")
    }

    func testAWrongNumberIsNotDecidedByTheNumberCheck() {
        let s = subject("0.50 (50%, dimensionless)")
        let grade = LocalGrader.grade(s, answer: .text("0.25"))
        XCTAssertNotEqual(grade.verdict, .correct)
        XCTAssertEqual(AIRouter.refinableText(s, .text("0.25")), "0.25", "a different number still goes to a model when one is allowed")
    }

    func testWordsAnswersAreGradedAsBefore() {
        let s = GradeSubject(kind: .recall, prompt: "Why is mitosis important?", modelAnswer: "It lets organisms grow and repair tissue.",
                             keyIdeas: [KeyIdea(id: "k1", label: "Growth", terms: ["grow", "growth"]), KeyIdea(id: "k2", label: "Repair", terms: ["repair"])])
        let grade = LocalGrader.grade(s, answer: .text("So the body can grow and repair tissue"))
        XCTAssertEqual(grade.verdict, .correct)
        XCTAssertEqual(AIRouter.refinableText(s, .text("So the body can grow")), "So the body can grow")
    }
}
