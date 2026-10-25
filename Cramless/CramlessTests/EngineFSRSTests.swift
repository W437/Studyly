import Foundation
import XCTest
@testable import Cramless

/// The FSRS-6 port against py-fsrs: every review of every history in `Fixtures/fsrs-reference.json` (written by
/// py-fsrs with fuzz off; the version is recorded in the file) must match to 1e-6.
final class EngineFSRSTests: XCTestCase {
    struct Fixture: Decodable {
        struct Review: Decodable {
            var at: Double
            var rating: Int
            var retrievabilityBefore: Double
            var state: Int
            var step: Int?
            var stability: Double
            var difficulty: Double
            var due: Double
        }

        struct Sample: Decodable {
            var at: Double
            var r: Double
        }

        struct History: Decodable {
            var name: String
            var desiredRetention: Double
            var maximumInterval: Int
            var learningSteps: [Double]
            var relearningSteps: [Double]
            var reviews: [Review]
            var retrievabilitySamples: [Sample]
        }

        struct Interval: Decodable {
            var retention: Double
            var stability: Double
            var interval: Int
        }

        var fsrsVersion: String
        var parameters: [Double]
        var histories: [History]
        var intervals: [Interval]
    }

    static func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: EngineFSRSTests.self).url(forResource: "fsrs-reference", withExtension: "json"),
                                "fsrs-reference.json missing from the test bundle")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testFixtureComesFromPyFSRS6() throws {
        let fixture = try Self.loadFixture()
        XCTAssertTrue(fixture.fsrsVersion.hasPrefix("6."), "reference vectors from py-fsrs \(fixture.fsrsVersion)")
        XCTAssertEqual(fixture.parameters.count, 21)
        for (a, b) in zip(fixture.parameters, FSRS.defaultParameters) { XCTAssertEqual(a, b, accuracy: 1e-12) }
        XCTAssertGreaterThanOrEqual(fixture.histories.count, 30)
    }

    func testEveryReviewMatchesPyFSRS() throws {
        let fixture = try Self.loadFixture()
        var checked = 0
        for history in fixture.histories {
            let fsrs = FSRS(desiredRetention: history.desiredRetention, learningSteps: history.learningSteps,
                            relearningSteps: history.relearningSteps, maximumInterval: history.maximumInterval)
            var memory = MemoryState.new
            for (i, ref) in history.reviews.enumerated() {
                let at = Date(timeIntervalSince1970: ref.at)
                let rating = try XCTUnwrap(Rating(rawValue: ref.rating))
                let label = "\(history.name) #\(i) (rating \(ref.rating))"
                XCTAssertEqual(fsrs.retrievability(of: memory, at: at), ref.retrievabilityBefore, accuracy: 1e-6, label)
                let outcome = fsrs.review(memory, rating: rating, at: at)
                memory = outcome.memory
                XCTAssertEqual(memory.state.rawValue, ref.state, label)
                XCTAssertEqual(memory.step, ref.step ?? 0, label)
                XCTAssertEqual(memory.stability, ref.stability, accuracy: 1e-6, label)
                XCTAssertEqual(memory.difficulty, ref.difficulty, accuracy: 1e-6, label)
                XCTAssertEqual(try XCTUnwrap(memory.due).timeIntervalSince1970, ref.due, accuracy: 1e-3, label)
                XCTAssertEqual(memory.lastReview, at, label)
                checked += 1
            }
            for sample in history.retrievabilitySamples {
                XCTAssertEqual(fsrs.retrievability(of: memory, at: Date(timeIntervalSince1970: sample.at)), sample.r,
                               accuracy: 1e-6, "\(history.name) R at \(sample.at)")
            }
        }
        XCTAssertGreaterThan(checked, 300)
    }

    func testIntervalsMatchPyFSRS() throws {
        for ref in try Self.loadFixture().intervals {
            XCTAssertEqual(FSRS(desiredRetention: ref.retention).nextInterval(stability: ref.stability), ref.interval,
                           "S \(ref.stability) at retention \(ref.retention)")
        }
    }

    func testRetrievabilityIsNinetyPercentAtStability() {
        let fsrs = FSRS()
        for s in [0.5, 3.0, 17.0, 240.0] {
            XCTAssertEqual(fsrs.retrievability(elapsedDays: s, stability: s), 0.9, accuracy: 1e-12)
        }
        XCTAssertEqual(fsrs.retrievability(elapsedDays: 0, stability: 4), 1, accuracy: 1e-12)
        XCTAssertEqual(fsrs.retrievability(of: .new, at: .now), 0)
    }

    /// The fuzz bounds, worked by hand from py-fsrs's `_get_fuzz_range`.
    func testFuzzRanges() {
        let fsrs = FSRS()
        XCTAssertEqual(fsrs.fuzzRange(intervalDays: 1), 1...1)
        XCTAssertEqual(fsrs.fuzzRange(intervalDays: 2), 2...2)
        XCTAssertEqual(fsrs.fuzzRange(intervalDays: 3), 2...4)      // delta 1.075
        XCTAssertEqual(fsrs.fuzzRange(intervalDays: 10), 8...12)    // delta 1.975
        XCTAssertEqual(fsrs.fuzzRange(intervalDays: 100), 93...107) // delta 6.975
        XCTAssertEqual(FSRS(maximumInterval: 100).fuzzRange(intervalDays: 100), 93...100)
    }

    func testRepsAndLapses() {
        let fsrs = FSRS()
        var m = MemoryState.new
        let t0 = EngineTest.iso("2026-01-05T09:00:00Z")
        m = fsrs.review(m, rating: .good, at: t0).memory
        m = fsrs.review(m, rating: .good, at: t0.addingTimeInterval(600)).memory
        XCTAssertEqual(m.state, .review)
        m = fsrs.review(m, rating: .again, at: m.due!).memory
        XCTAssertEqual(m.state, .relearning)
        XCTAssertEqual(m.reps, 3)
        XCTAssertEqual(m.lapses, 1)
        // An Again in relearning is not a second lapse.
        m = fsrs.review(m, rating: .again, at: m.due!).memory
        XCTAssertEqual(m.lapses, 1)
    }

    func testDesiredRetentionChangesIntervals() {
        XCTAssertLessThan(FSRS(desiredRetention: 0.95).nextInterval(stability: 30),
                          FSRS(desiredRetention: 0.9).nextInterval(stability: 30))
        XCTAssertGreaterThan(FSRS(desiredRetention: 0.8).nextInterval(stability: 30),
                             FSRS(desiredRetention: 0.9).nextInterval(stability: 30))
        XCTAssertEqual(FSRS().nextInterval(stability: 1e9), FSRS.defaultMaximumInterval)
    }
}
