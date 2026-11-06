import CoreHaptics
import SwiftData
import XCTest
@testable import Cramless

/// The synthesized sounds, their cues and haptics, and the switches around them.
final class CLSynthTests: XCTestCase {
    func testEveryCueHasItsOwnKey() {
        let keys = CLCue.all.map(\.key)
        XCTAssertEqual(keys.count, 27)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(CLCue.right(combo: 12).key, "right8", "a long run holds at the top of the scale")
        XCTAssertEqual(CLCue.right(combo: 0).key, "right1")
        XCTAssertEqual(CLCue.cardOut(9).key, "cardOut1")
    }

    func testKeysNameTheirCuesBack() {
        XCTAssertEqual(CLCue.all.map { CLCue(key: $0.key) }, CLCue.all)
        XCTAssertNil(CLCue(key: "fanfare"))
        XCTAssertNil(CLCue(key: "rightish"))
    }

    func testARunClimbsCMajorPentatonic() {
        let expected = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51]
        for (i, frequency) in expected.enumerated() {
            XCTAssertEqual(CLSynth.score(for: .right(combo: i + 1)).notes.map(\.frequency), [frequency])
        }
        XCTAssertEqual(CLSynth.score(for: .right(combo: 30)).notes.first?.frequency, 1318.51)
        let quiet = CLSynth.score(for: .right(combo: 1)), loud = CLSynth.score(for: .right(combo: 8))
        XCTAssertLessThan(quiet.gain, loud.gain, "a longer run is a little louder")
        XCTAssertLessThan(quiet.sharpness, loud.sharpness, "and its tap a little crisper")
    }

    func testRenderingIsDeterministic() {
        for palette in CLSynth.Palette.all {
            let synth = CLSynth(palette: palette)
            XCTAssertEqual(synth.render(.saved), synth.render(.saved), palette.id)
            XCTAssertEqual(synth.render(.right(combo: 3)), synth.render(.right(combo: 3)), palette.id)
        }
    }

    func testEverySoundStaysUnderTheCeilingAndStartsAndEndsSilent() {
        for palette in CLSynth.Palette.all {
            let synth = CLSynth(palette: palette)
            for cue in CLCue.all {
                let samples = synth.render(cue)
                XCTAssertFalse(samples.isEmpty, "\(palette.id) \(cue.key)")
                let peak = samples.map { abs($0) }.max() ?? 0
                XCTAssertLessThanOrEqual(Double(peak), CLSynth.ceiling + 1e-6, "\(palette.id) \(cue.key)")
                XCTAssertGreaterThan(Double(peak), 0.05, "\(palette.id) \(cue.key) is audible")
                XCTAssertEqual(samples.first ?? 1, 0, accuracy: 1e-6, "no click at the start: \(palette.id) \(cue.key)")
                XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.01, "no click at the end: \(palette.id) \(cue.key)")
            }
        }
    }

    func testTheLoudestCueIsTheFinish() {
        let synth = CLSynth(palette: .marimba)
        let peak = { (cue: CLCue) in synth.render(cue).map { abs($0) }.max() ?? 0 }
        XCTAssertGreaterThan(peak(.done), peak(.notYet))
        XCTAssertGreaterThan(peak(.done), peak(.flip))
    }

    func testTheSessionMixFitsItsTimeline() throws {
        let synth = CLSynth(palette: .kalimba)
        let samples = synth.mix(CLSynth.sampleSession)
        let last = try XCTUnwrap(CLSynth.sampleSession.last)
        XCTAssertGreaterThan(Double(samples.count) / CLSynth.sampleRate, last.time)
        XCTAssertLessThan(Double(samples.count) / CLSynth.sampleRate, last.time + 2.5)
        XCTAssertLessThanOrEqual(Double(samples.map { abs($0) }.max() ?? 0), CLSynth.ceiling + 1e-6)
    }

    func testWAVHeader() {
        let data = CLSynth.wav([0, 0.5, -0.5, 1])
        XCTAssertEqual(data.count, 44 + 8)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        let last = data.suffix(2).withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        XCTAssertEqual(Int16(littleEndian: last), 32_767)
    }

    func testQuietHoursWrapMidnight() {
        let start = 22 * 60, end = 7 * 60
        XCTAssertTrue(CLSound.isQuiet(minute: 23 * 60, start: start, end: end))
        XCTAssertTrue(CLSound.isQuiet(minute: 6 * 60 + 59, start: start, end: end))
        XCTAssertFalse(CLSound.isQuiet(minute: 7 * 60, start: start, end: end))
        XCTAssertFalse(CLSound.isQuiet(minute: 12 * 60, start: start, end: end))
        XCTAssertTrue(CLSound.isQuiet(minute: 13 * 60, start: 13 * 60, end: 14 * 60))
        XCTAssertFalse(CLSound.isQuiet(minute: 13 * 60, start: 13 * 60, end: 13 * 60), "an empty window is never quiet")
    }

    func testPalettesByName() {
        XCTAssertEqual(CLSynth.Palette.named("glass")?.name, "Glass")
        XCTAssertNil(CLSynth.Palette.named("tuba"))
        XCTAssertEqual(Set(CLSynth.Palette.all.map(\.id)).count, 3)
    }
}

@MainActor
final class FeelPolicyTests: XCTestCase {
    override func tearDown() async throws {
        AudioFocus.release(.speech)
        AudioFocus.release(.microphone)
        AudioFocus.release(.playback)
    }

    func testALecturePlayingSilencesEffectsUntilItLetsGo() {
        XCTAssertTrue(AudioFocus.allowsEffects)
        AudioFocus.claim(.playback)
        XCTAssertFalse(AudioFocus.allowsEffects)
        AudioFocus.release(.playback)
        XCTAssertTrue(AudioFocus.allowsEffects)
    }

    func testSpeechAndTheMicrophoneSilenceEffectsUntilTheyLetGo() {
        XCTAssertTrue(AudioFocus.allowsEffects)
        AudioFocus.claim(.speech)
        XCTAssertFalse(AudioFocus.allowsEffects)
        AudioFocus.claim(.microphone)
        AudioFocus.release(.speech)
        XCTAssertFalse(AudioFocus.allowsEffects, "the microphone still holds it")
        AudioFocus.release(.microphone)
        XCTAssertTrue(AudioFocus.allowsEffects)
    }

    func testEachNoteGetsATapAndTheFinishASwell() {
        for cue in CLCue.all {
            let score = CLSynth.score(for: cue)
            let events = CLHapticPatterns.events(for: score)
            XCTAssertEqual(events.filter { $0.type == .hapticTransient }.count, score.notes.count, cue.key)
            XCTAssertEqual(zip(events, score.notes).map { $0.0.relativeTime }, score.notes.map(\.time), cue.key)
        }
        XCTAssertEqual(CLHapticPatterns.events(for: CLSynth.score(for: .done)).filter { $0.type == .hapticContinuous }.count, 1)
        XCTAssertTrue(CLHapticPatterns.events(for: CLSynth.score(for: .right(combo: 1))).allSatisfy { $0.type == .hapticTransient })
    }

    func testSoundsDefaultOnAndSurviveAnOlderSettingsFile() throws {
        XCTAssertTrue(AppSettings().sounds)
        let old = try XCTUnwrap(#"{"haptics":false}"#.data(using: .utf8))
        let decoded = try JSONDecoder.cramless.decode(AppSettings.self, from: old)
        XCTAssertTrue(decoded.sounds)
        XCTAssertFalse(decoded.haptics)
        var off = AppSettings()
        off.sounds = false
        let round = try JSONDecoder.cramless.decode(AppSettings.self, from: JSONEncoder.cramless.encode(off))
        XCTAssertFalse(round.sounds)
    }

    func testTheSettingsDriveTheSoundEngine() throws {
        let app = AppModel(container: try Persistence.makeContainer(inMemory: true),
                           defaults: UserDefaults(suiteName: "capling.tests.\(UUID().uuidString)")!)
        app.settings.sounds = false
        XCTAssertFalse(CLSound.shared.isEnabled)
        app.settings.sounds = true
        XCTAssertTrue(CLSound.shared.isEnabled)
        app.settings.quietHoursStart = 21 * 60
        XCTAssertEqual(CLSound.shared.quietHours?.start, 21 * 60)
        XCTAssertEqual(DataExport.archive(app: app).profile.sounds, true)
    }
}

/// Ids that repeat, and the inputs for "Saved it" and answers applied later.
@MainActor
final class GroundworkTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    private func item(memory: MemoryState? = nil) -> StudyItem {
        let course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
        let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "Question?",
                             answer: "Answer", now: clock.now)
        if let memory { item.memory = memory }
        app.context.insert(item)
        course.items.append(item)
        app.save()
        return item
    }

    private func learned(stability: Double, lastReviewDaysAgo: Int) -> MemoryState {
        let last = cal.adding(days: -lastReviewDaysAgo, to: clock.now)
        return MemoryState(state: .review, stability: stability, difficulty: 5, due: last.addingTimeInterval(stability * 86_400),
                           lastReview: last, reps: 3, lapses: 0, step: 0)
    }

    func testNamedUUIDsRepeatAndLookLikeVersion4() {
        let a = StableRandom.uuid("demo#7")
        XCTAssertEqual(a, StableRandom.uuid("demo#7"))
        XCTAssertNotEqual(a, StableRandom.uuid("demo#8"))
        XCTAssertEqual(a.uuidString[a.uuidString.index(a.uuidString.startIndex, offsetBy: 14)], "4")
    }

    func testSeededModelIDsRepeatAndOthersStayRandom() {
        let first = ModelID.seeded("demo") { (ModelID.make(), ModelID.make()) }
        let again = ModelID.seeded("demo") { (ModelID.make(), ModelID.make()) }
        XCTAssertEqual(first.0, again.0)
        XCTAssertEqual(first.1, again.1)
        XCTAssertNotEqual(first.0, first.1)
        XCTAssertNotEqual(ModelID.make(), ModelID.make())
        let course = ModelID.seeded("demo") { Course(name: "Bio 101") }
        XCTAssertEqual(course.id, first.0, "models take their default id from the sequence")
    }

    func testTheDemoWorldIsTheSameOnEveryLaunch() throws {
        SampleData.seed(into: app)
        let ids = Set(app.fetch(FetchDescriptor<StudyItem>()).map(\.id))
        let other = try StudyTestApp.make(clock: clock, calendar: cal)
        SampleData.seed(into: other)
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(other.fetch(FetchDescriptor<StudyItem>()).map(\.id)), ids)
    }

    func testRightOnAFadingMemoryIsASave() throws {
        let fading = item(memory: learned(stability: 2, lastReviewDaysAgo: 30))
        let outcome = try XCTUnwrap(app.recordReview(itemID: fading.id, rating: .good))
        XCTAssertLessThan(outcome.recallBefore, ReviewOutcome.fadingRecall)
        XCTAssertTrue(outcome.isSave)
    }

    func testStrongMemoriesWrongAnswersAndFirstLooksAreNotSaves() throws {
        let strong = item(memory: learned(stability: 60, lastReviewDaysAgo: 2))
        let kept = try XCTUnwrap(app.recordReview(itemID: strong.id, rating: .good))
        XCTAssertGreaterThan(kept.recallBefore, 0.9)
        XCTAssertFalse(kept.isSave)

        let fading = item(memory: learned(stability: 2, lastReviewDaysAgo: 30))
        XCTAssertFalse(try XCTUnwrap(app.recordReview(itemID: fading.id, rating: .again)).isSave)

        let fresh = item()
        XCTAssertFalse(try XCTUnwrap(app.recordReview(itemID: fresh.id, rating: .good)).isSave)
    }

    func testOnlyAGoodOrEasyAnswerSavesAFadingMemory() throws {
        // "Hard" is "Almost.": the person had it with difficulty. The screen doesn't say "Saved it.", so it isn't a save.
        for (rating, saves) in [(Rating.again, false), (.hard, false), (.good, true), (.easy, true)] {
            let fading = item(memory: learned(stability: 2, lastReviewDaysAgo: 30))
            let outcome = try XCTUnwrap(app.recordReview(itemID: fading.id, rating: rating))
            XCTAssertLessThan(outcome.recallBefore, ReviewOutcome.fadingRecall)
            XCTAssertEqual(outcome.isSave, saves, "\(rating)")
        }
    }

    func testAnAnswerAppliedLaterCountsOnItsOwnDayOnce() throws {
        let card = item()
        let late = cal.date(bySettingHour: 23, minute: 50, second: 0, of: cal.adding(days: -1, to: clock.now))!
        let key = cal.dayKey(for: late)
        let reviewID = UUID()
        let outcome = try XCTUnwrap(app.recordReview(itemID: card.id, rating: .good, at: late, dayKey: key, reviewID: reviewID))
        XCTAssertEqual(outcome.logID, reviewID)

        let yesterday = try XCTUnwrap(app.dayRecord(key: key))
        XCTAssertEqual(yesterday.itemsReviewed, 1)
        XCTAssertEqual(yesterday.sessions, 1, "the answer keeps yesterday's streak")
        XCTAssertNil(app.dayRecord(key: cal.dayKey(for: clock.now)), "today is untouched")
        let log = try XCTUnwrap(app.fetch(FetchDescriptor<ReviewLog>()).first)
        XCTAssertEqual(log.reviewedAt, late)
        XCTAssertEqual(card.lastReview, late, "scheduled from when it was answered")

        XCTAssertNil(app.recordReview(itemID: card.id, rating: .good, at: late, dayKey: key, reviewID: reviewID),
                     "the same answer twice is recorded once")
        XCTAssertEqual(app.fetch(FetchDescriptor<ReviewLog>()).count, 1)
        XCTAssertEqual(yesterday.itemsReviewed, 1)
    }
}
