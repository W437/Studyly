import XCTest
@testable import Cramless

/// The String Catalogs: plural forms resolve, pass-through text stays as it is, and docs/l10n/plurals.json never
/// names a key the app no longer uses.
final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func catalogKeys(_ path: String) throws -> Set<String> {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(path))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en", path)
        return Set((json["strings"] as? [String: Any] ?? [:]).keys)
    }

    func testPluralFormsResolve() {
        XCTAssertEqual(String(localized: "\(1) minutes"), "1 minute")
        XCTAssertEqual(String(localized: "\(3) minutes"), "3 minutes")
        XCTAssertEqual(String(localized: "\(1) freezes saved"), "1 freeze saved")
        XCTAssertEqual(String(localized: "\(2) of \(4) seats"), "2 of 4 seats")
        XCTAssertEqual(String(localized: "\(1) of \(1) seats"), "1 of 1 seat", "the plural follows the second number")
        XCTAssertEqual(String(localized: "\(1) free AI scans left this week"), "1 free AI scan left this week")
        XCTAssertEqual(String(localized: "AI notes for \(2) lecture left this week"), "AI notes for 2 lectures left this week")
        XCTAssertEqual(String(localized: "Cap kept \(3) lectures that were cut off."), "Cap kept 3 lectures that were cut off.")
    }

    func testVerbatimTextIsShownAsItIs() {
        XCTAssertEqual(String(localized: LocalizedStringResource.verbatim("Bio 101 · %@ 100%")), "Bio 101 · %@ 100%")
        XCTAssertEqual(String(localized: LocalizedStringResource.verbatim("")), "")
    }

    func testThePluralTableOnlyNamesKeysTheAppUses() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("docs/l10n/plurals.json"))
        let table = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = try catalogKeys("Cramless/Resources/Localizable.xcstrings")
            .union(catalogKeys("CramlessWidgets/Localizable.xcstrings"))
        for key in table.keys where !key.hasPrefix("_") {
            XCTAssertTrue(keys.contains(key), "plurals.json names \"\(key)\", which no code uses any more")
        }
    }

    func testEveryCatalogParsesAndCarriesTheAppsCopy() throws {
        let app = try catalogKeys("Cramless/Resources/Localizable.xcstrings")
        XCTAssertGreaterThan(app.count, 500)
        XCTAssertTrue(app.contains("Accessibility"), "a Settings page title passed to a component is localizable")
        XCTAssertTrue(app.contains("%@"), "the pass-through key")
        XCTAssertGreaterThan(try catalogKeys("CramlessWidgets/Localizable.xcstrings").count, 20)
    }
}
