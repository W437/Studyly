import DeclaredAgeRange
import XCTest
@testable import Cramless

/// When the age check asks (once, while the band is unknown), and what each answer means for asking again. The question itself is
/// the system's and only a device answers it; this is the part that decides around it.
final class AgeCheckTests: XCTestCase {
    private func record(_ outcome: AgeCheck.Outcome, attempts: Int = 1) -> AgeCheck.Record {
        AgeCheck.Record(outcome: outcome, askedAt: Date(timeIntervalSince1970: 1_800_000_000), attempts: attempts)
    }

    func testAskedOnceWhileTheBandIsUnknown() {
        XCTAssertTrue(AgeCheck.shouldAsk(band: .unknown, record: nil), "never asked: ask")
        for band in [AppSettings.AgeBand.adult, .teen, .under13] {
            XCTAssertFalse(AgeCheck.shouldAsk(band: band, record: nil), "\(band) is already known")
        }
    }

    func testAnAnswerADeclineOrNoAnswerIsFinal() {
        XCTAssertFalse(AgeCheck.shouldAsk(band: .unknown, record: record(.shared)))
        XCTAssertFalse(AgeCheck.shouldAsk(band: .unknown, record: record(.declined)), "no nagging after Don't share")
        XCTAssertFalse(AgeCheck.shouldAsk(band: .unknown, record: record(.unavailable)), "the system has no answer here")
    }

    func testAPassingFailureIsTriedAgainThreeTimesInAll() {
        XCTAssertTrue(AgeCheck.shouldAsk(band: .unknown, record: record(.failed, attempts: 1)))
        XCTAssertTrue(AgeCheck.shouldAsk(band: .unknown, record: record(.failed, attempts: 2)))
        XCTAssertFalse(AgeCheck.shouldAsk(band: .unknown, record: record(.failed, attempts: AgeCheck.maxAttempts)))
    }

    func testWhatTheSystemSaysBecomesAnOutcome() {
        XCTAssertEqual(AgeCheck.outcome(of: AgeRangeService.Response.declinedSharing), .declined)
        XCTAssertEqual(AgeCheck.outcome(of: AgeRangeService.Error.notAvailable), .unavailable)
        XCTAssertEqual(AgeCheck.outcome(of: AgeRangeService.Error.invalidRequest), .unavailable)
        XCTAssertEqual(AgeCheck.outcome(of: URLError(.notConnectedToInternet)), .failed)
    }

    func testTheRecordIsKeptOnThisIPhone() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "capling.tests.\(UUID().uuidString)"))
        XCTAssertNil(AgeCheck.record(in: defaults))
        AgeCheck.store(record(.declined), in: defaults)
        XCTAssertEqual(AgeCheck.record(in: defaults), record(.declined))
        XCTAssertNotNil(defaults.data(forKey: "capling.ageRange.v1"))
    }

    /// A declined or unanswered check leaves the band unknown, so the level the person gave still decides (no level: adult rules).
    func testWithoutAnAnswerTheBandFallsBackAsBefore() {
        XCTAssertEqual(AgeRange.resolved(declared: nil, current: .unknown, level: nil), .unknown)
        XCTAssertEqual(AgeRange.resolved(declared: nil, current: .unknown, level: .highSchool), .teen)
        XCTAssertEqual(AgeRange.resolved(declared: .teen, current: .unknown, level: nil), .teen)
        var settings = AppSettings()
        settings.ageBand = AgeRange.band(lowerBound: 13, upperBound: 17)
        XCTAssertTrue(settings.isMinor, "a shared 13 to 17 turns on the under-18 rules")
        settings.ageBand = AgeRange.band(lowerBound: 18, upperBound: nil)
        XCTAssertFalse(settings.isMinor)
    }
}
