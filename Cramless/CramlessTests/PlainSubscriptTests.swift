import XCTest
@testable import Cramless

/// Cloud vision writes a subscript c as U+A700 (a tone mark); the app turns it into a plain "c".
final class PlainSubscriptTests: XCTestCase {

    func testASubscriptCWrittenAsAToneMarkBecomesAPlainC() {
        XCTAssertEqual("η = 1 − T\u{A700}/Tₕ".withPlainSubscriptC, "η = 1 − Tc/Tₕ")
        XCTAssertEqual("Q\u{A700} > 0 is the heat taken from the engine".withPlainSubscriptC, "Qc > 0 is the heat taken from the engine")
    }

    func testRealSubscriptsAndOrdinaryTextAreLeftAlone() {
        XCTAssertEqual("Qₕ, V₁ and Sₐ".withPlainSubscriptC, "Qₕ, V₁ and Sₐ")
        XCTAssertEqual("A catalyst does not change K.".withPlainSubscriptC, "A catalyst does not change K.")
        XCTAssertEqual("".withPlainSubscriptC, "")
    }
}
