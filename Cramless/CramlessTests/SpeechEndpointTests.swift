import XCTest
@testable import Cramless

/// When a spoken answer is over. Pure: a clock of seconds, and what was heard when.
final class SpeechEndpointTests: XCTestCase {
    func testEndsAfterASilenceThatFollowsSpeech() {
        var endpoint = SpeechEndpoint(.answer)
        XCTAssertNil(endpoint.ending(at: 3), "nothing said yet: no silence to count")
        endpoint.heardWords(at: 3)
        XCTAssertNil(endpoint.ending(at: 4.4))
        endpoint.heardWords(at: 4.4)
        XCTAssertNil(endpoint.ending(at: 5.8), "the words went on")
        XCTAssertEqual(endpoint.ending(at: 5.9), .silence)
    }

    func testEndsWhenNothingIsSaid() {
        let endpoint = SpeechEndpoint(.answer)
        XCTAssertNil(endpoint.ending(at: 14.9))
        XCTAssertEqual(endpoint.ending(at: 15), .noSpeech)
    }

    func testTheCap() {
        var endpoint = SpeechEndpoint(.answer)
        var time = 0.0
        while time < 45 {
            XCTAssertNil(endpoint.ending(at: time))
            endpoint.heardWords(at: time)
            time += 1
        }
        endpoint.heardWords(at: 45)
        XCTAssertEqual(endpoint.ending(at: 45), .cap, "someone who goes on and on is still cut off")
    }

    func testAVoiceKeepsTheTurnOpenBeforeTheWordsArrive() {
        var endpoint = SpeechEndpoint(.answer)
        // A quiet room, then a voice: the recogniser's first words are still on their way.
        for t in stride(from: 0.0, to: 1.0, by: 0.1) { endpoint.level(0.1, at: t) }
        XCTAssertFalse(endpoint.hasHeardSpeech)
        endpoint.level(0.6, at: 1.0)
        XCTAssertTrue(endpoint.hasHeardSpeech)
        endpoint.level(0.6, at: 2.0)
        XCTAssertNil(endpoint.ending(at: 3.4), "1.4 s since the voice")
        XCTAssertEqual(endpoint.ending(at: 3.5), .silence)
    }

    func testASteadyNoiseIsNotAVoice() {
        var endpoint = SpeechEndpoint(.answer)
        // A loud bus: high, but no higher than the place itself.
        for t in stride(from: 0.0, to: 14.9, by: 0.1) {
            endpoint.level(0.7, at: t)
            XCTAssertFalse(endpoint.hasHeardSpeech, "\(t)")
        }
        XCTAssertEqual(endpoint.ending(at: 15), .noSpeech)
    }

    func testAVoiceOverANoiseStillCounts() {
        var endpoint = SpeechEndpoint(.answer)
        for t in stride(from: 0.0, to: 2.0, by: 0.1) { endpoint.level(0.5, at: t) }
        endpoint.level(0.85, at: 2)
        XCTAssertTrue(endpoint.hasHeardSpeech)
    }

    func testTheFloorComesDownAtOnceAndGoesUpSlowly() {
        var endpoint = SpeechEndpoint(.answer)
        endpoint.level(0.9, at: 0)
        endpoint.level(0.1, at: 0.1)
        endpoint.level(0.4, at: 0.2)
        XCTAssertTrue(endpoint.hasHeardSpeech, "against the quiet just heard")
    }

    func testAReplyIsShort() {
        var endpoint = SpeechEndpoint(.reply)
        endpoint.heardWords(at: 1)
        XCTAssertNil(endpoint.ending(at: 1.9))
        XCTAssertEqual(endpoint.ending(at: 2), .silence)
        XCTAssertEqual(SpeechEndpoint(.reply).ending(at: 7), .noSpeech)
    }

    func testTeachingGoesOnUntilDoneOrTwoMinutes() {
        var endpoint = SpeechEndpoint(.teaching)
        XCTAssertNil(endpoint.ending(at: 60), "no silence to wait out, and no giving up")
        endpoint.heardWords(at: 61)
        XCTAssertNil(endpoint.ending(at: 119))
        XCTAssertEqual(endpoint.ending(at: 120), .cap)
    }
}

final class HeardWordsTests: XCTestCase {
    func testVolatileReplacesAndFinalSettles() {
        var words = HeardWords()
        XCTAssertTrue(words.volatile("Sister"))
        XCTAssertTrue(words.volatile("Sister chromatids"))
        XCTAssertFalse(words.volatile("Sister chromatids"), "nothing new: the silence goes on counting")
        XCTAssertEqual(words.text, "Sister chromatids")
        words.final("Sister chromatids separate.")
        XCTAssertEqual(words.text, "Sister chromatids separate.")
        words.volatile("Then")
        XCTAssertEqual(words.text, "Sister chromatids separate. Then")
        words.final("")
        XCTAssertEqual(words.text, "Sister chromatids separate.")
        XCTAssertFalse(words.isEmpty)
    }
}
