import XCTest
@testable import Cramless

/// The welcome screen's sky: the constellation, how touches play out, where a finger finds a star, the shapes of its motion, and
/// Cap's lines.
final class WelcomeSkyTests: XCTestCase {
    // MARK: The constellation

    func testTheCapIsSevenStarsInOneConstellation() {
        let layout = WelcomeSky.layout
        XCTAssertEqual(layout.stars.count, 7)
        XCTAssertEqual(layout.constellations.count, 1)
        XCTAssertEqual(layout.constellations[0].stars, 0..<7)
        XCTAssertEqual(Set(layout.stars.map(\.id)).count, 7, "every star has its own id")
        for line in layout.constellations[0].lines {
            XCTAssertTrue((0..<7).contains(line.a) && (0..<7).contains(line.b) && line.a != line.b, "\(line)")
        }
        XCTAssertEqual(Set(layout.constellations[0].lines).count, layout.constellations[0].lines.count, "no line twice")
        for p in WelcomeSky.points {
            XCTAssertTrue((0...layout.width).contains(p.x) && (0...layout.height).contains(p.y), "\(p) is inside the layout")
        }
    }

    func testEveryStarIsOnALineSoNoneIsAnOrphan() {
        let used = Set(WelcomeSky.lines.flatMap { [$0.a, $0.b] })
        XCTAssertEqual(used, Set(0..<WelcomeSky.count))
    }

    func testStarsAreFarEnoughApartToBeTouchedOneByOne() {
        // At the smallest sensible size (30 points a spacing) two stars are still a finger's width apart.
        var closest = Double.infinity
        for (i, a) in WelcomeSky.points.enumerated() {
            for b in WelcomeSky.points[(i + 1)...] { closest = min(closest, a.distance(to: b)) }
        }
        XCTAssertGreaterThanOrEqual(closest * 30, 30, "no two stars closer than a thumb at the smallest size")
    }

    func testTheSweepRunsLeftToRight() {
        // The stars are indexed left to right (the tassel hangs down from its corner, so its last star may sit a hair left of the one
        // above it), which is the order the rest ignite in: a sweep across the cap that ends on the tassel.
        let xs = WelcomeSky.points.map(\.x)
        XCTAssertTrue(zip(xs, xs.dropFirst()).allSatisfy { $1 >= $0 - 0.2 }, "\(xs)")
        XCTAssertEqual(xs.first, xs.min())
        XCTAssertGreaterThan(xs[WelcomeSky.count - 2], 5, "and ends on the tassel")
    }

    // MARK: Touches

    func testTheThirdStarLightsTheRestOfTheCap() {
        var state = WelcomeSkyState()
        XCTAssertEqual(state.light(1), .lit(star: 1, count: 1))
        XCTAssertEqual(state.light(4), .lit(star: 4, count: 2))
        XCTAssertFalse(state.isFinished)
        XCTAssertEqual(state.light(0), .finale(star: 0, rest: [2, 3, 5, 6]), "in the order they ignite: left to right")
        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.count, 7)
        XCTAssertEqual(state.litSet, Set(0..<7))
    }

    func testALitStarOrAStarThatIsNotOneDoesNothing() {
        var state = WelcomeSkyState()
        state.light(2)
        XCTAssertEqual(state.light(2), .ignored)
        XCTAssertEqual(state.light(-1), .ignored)
        XCTAssertEqual(state.light(7), .ignored)
        XCTAssertEqual(state.count, 1)
    }

    func testOnceItIsLitNothingMoreHappens() {
        var state = WelcomeSkyState()
        for star in [3, 5, 6] { state.light(star) }
        XCTAssertEqual(state.light(1), .ignored)
        XCTAssertNil(state.suggestion)
    }

    func testCapLightsTheBackCornerFirstAndNeverRepeats() {
        var state = WelcomeSkyState()
        XCTAssertEqual(state.suggestion, 1)
        state.light(1)
        XCTAssertEqual(state.suggestion, 4)
        state.light(4)
        state.light(0)
        XCTAssertEqual(Set(WelcomeSky.suggested), Set(0..<7), "the suggestions cover every star")
        XCTAssertEqual(WelcomeSky.suggested.count, 7, "once each")
    }

    func testWhateverIsTouchedFirstCapPicksUpFromThere() {
        var state = WelcomeSkyState()
        state.light(1)
        state.light(4)
        XCTAssertEqual(state.suggestion, 0, "the next of his order that is still dark")
        var other = WelcomeSkyState()
        other.light(0)
        XCTAssertEqual(other.suggestion, 1)
    }

    // MARK: Where a finger finds a star

    func testAFingerFindsTheNearestStarWithinReach() {
        let size = CGSize(width: 390, height: 360)
        let camera = SkyCamera.fit(WelcomeSky.layout, in: size, top: 0, bottom: 0, largest: 46)
        for (i, p) in WelcomeSky.points.enumerated() {
            let at = camera.screen(p, in: size)
            XCTAssertEqual(WelcomeStage.nearestStar(to: at, camera: camera, size: size), i)
            XCTAssertEqual(WelcomeStage.nearestStar(to: CGPoint(x: at.x + 20, y: at.y - 15), camera: camera, size: size), i, "a loose touch still finds it")
        }
        XCTAssertNil(WelcomeStage.nearestStar(to: CGPoint(x: 2, y: 2), camera: camera, size: size), "empty sky finds nothing")
    }

    func testBetweenTwoStarsTheCloserWins() {
        let size = CGSize(width: 390, height: 360)
        let camera = SkyCamera.fit(WelcomeSky.layout, in: size, top: 0, bottom: 0, largest: 46)
        let a = camera.screen(WelcomeSky.points[1], in: size), b = camera.screen(WelcomeSky.points[2], in: size)
        let nearA = CGPoint(x: a.x + (b.x - a.x) * 0.3, y: a.y + (b.y - a.y) * 0.3)
        let nearB = CGPoint(x: a.x + (b.x - a.x) * 0.7, y: a.y + (b.y - a.y) * 0.7)
        XCTAssertEqual(WelcomeStage.nearestStar(to: nearA, camera: camera, size: size), 1)
        XCTAssertEqual(WelcomeStage.nearestStar(to: nearB, camera: camera, size: size), 2)
    }

    // MARK: The look

    func testTheFaintStarsAreFewAndTheSameEveryLaunch() {
        let field = WelcomeLook.starField()
        XCTAssertEqual(field, WelcomeLook.starField(), "a seed, not dice")
        XCTAssertLessThanOrEqual(field.count, 60, "a quiet sky")
        XCTAssertTrue(field.allSatisfy { (0...1).contains($0.x) && (0..<1).contains($0.y) && (0..<3).contains($0.group) && (0..<3).contains($0.tier) })
        XCTAssertEqual(Set(field.map(\.group)), [0, 1, 2], "three slow twinkles")
        XCTAssertTrue(field.contains { $0.tier == 2 }, "a few brighter ones")
        let behind = field.filter { (0.2...0.8).contains($0.x) && (0.1...0.62).contains($0.y) }
        XCTAssertTrue(behind.allSatisfy { $0.tier == 0 }, "the ones behind the constellation are the faintest, so its shape reads")
    }

    func testAStarSwellsAndSettlesAsItIgnites() {
        XCTAssertEqual(WelcomeLook.ignition(after: -0.5), .dark, "not yet")
        XCTAssertEqual(WelcomeLook.ignition(after: WelcomeLook.igniteSeconds), .settled)
        XCTAssertEqual(WelcomeLook.ignition(after: 5), .settled)
        var peak = 0.0
        var previousBrightness = -1.0
        for k in 0...90 {
            let e = WelcomeLook.ignition(after: Double(k) / 100)
            peak = max(peak, e.core)
            XCTAssertGreaterThanOrEqual(e.brightness, previousBrightness - 1e-9, "it only gets brighter")
            previousBrightness = e.brightness
            XCTAssertTrue((0.6...1.6).contains(e.core) && (0...1).contains(e.brightness) && (0...1).contains(e.ringAlpha) && e.halo >= 0)
        }
        XCTAssertEqual(peak, 1.5, accuracy: 0.05, "a swell of half again, no more")
        XCTAssertEqual(WelcomeLook.ignition(after: 0.85).glintAlpha, 0, "the glint is gone by half a second")
        XCTAssertLessThan(WelcomeLook.ignition(after: 0.85).ringAlpha, 0.01, "so is the ring by the end")
        XCTAssertEqual(WelcomeLook.ignition(after: 0.85).halo, WelcomeLook.restingHalo, accuracy: 0.05, "and the glow rests where it started")
    }

    func testALineDrawsInHalfASecond() {
        XCTAssertEqual(WelcomeLook.lineProgress(after: -1), 0)
        XCTAssertEqual(WelcomeLook.lineProgress(after: 0), 0)
        XCTAssertEqual(WelcomeLook.lineProgress(after: WelcomeLook.lineSeconds), 1)
        XCTAssertEqual(WelcomeLook.lineProgress(after: 2), 1)
        let steps = (0...10).map { WelcomeLook.lineProgress(after: Double($0) * 0.05) }
        XCTAssertEqual(steps, steps.sorted(), "it only grows")
    }

    func testTheGlowRisesQuicklyAndFadesAway() {
        XCTAssertEqual(WelcomeLook.glow(after: -0.1), 0)
        XCTAssertEqual(WelcomeLook.glow(after: 0.5), 0.2, accuracy: 0.001)
        XCTAssertEqual(WelcomeLook.glow(after: WelcomeLook.glowSeconds), 0)
        XCTAssertLessThan(WelcomeLook.glow(after: 1.5), 0.2)
        XCTAssertGreaterThan(WelcomeLook.glow(after: 1.0), WelcomeLook.glow(after: 1.8))
    }

    func testRipplesAndTheHintStayInTheirRanges() {
        XCTAssertNil(WelcomeLook.ripple(after: -0.1))
        XCTAssertNil(WelcomeLook.ripple(after: WelcomeLook.rippleSeconds))
        for k in 0..<80 {
            let r = try! XCTUnwrap(WelcomeLook.ripple(after: Double(k) / 100))
            XCTAssertTrue((3...34.001).contains(r.radius) && (0...0.38).contains(r.alpha))
        }
        for k in 0..<200 {
            let h = WelcomeLook.hint(at: Double(k) / 10)
            XCTAssertTrue((7...23.001).contains(h.radius) && (0...0.55).contains(h.alpha), "\(h)")
        }
        XCTAssertNotNil(WelcomeLook.shooting(after: 0.3))
        XCTAssertNil(WelcomeLook.shooting(after: WelcomeLook.shootingSeconds))
    }

    func testTheBreathingStaysGentle() {
        for star in 0..<7 {
            for k in 0..<100 {
                let b = WelcomeLook.breath(star: star, time: Double(k) / 7)
                XCTAssertTrue((0.4...1.001).contains(b), "star \(star): \(b)")
            }
        }
        for group in 0..<3 {
            XCTAssertTrue((0.67...1.01).contains(WelcomeLook.twinkle(group: group, time: 3.7)))
        }
    }

    // MARK: The stage

    @MainActor
    func testTheStagePlaysTheWholeWelcomeWithMotion() {
        let sounds = CLSound.shared.isEnabled
        CLSound.shared.isEnabled = false
        defer { CLSound.shared.isEnabled = sounds }
        let stage = WelcomeStage()
        XCTAssertNil(stage.speech)
        XCTAssertNil(stage.litAt[1])
        XCTAssertNil(stage.hint, "no ring until Cap has said hello")

        stage.light(1, byCap: false, at: CGPoint(x: 100, y: 100))
        let first = try! XCTUnwrap(stage.litAt[1])
        XCTAssertGreaterThan(first, -1, "it ignites now, with a ceremony")
        XCTAssertEqual(stage.ripples.count, 1)
        XCTAssertEqual(stage.speech?.id, 1, "he says the first line")
        stage.light(4, byCap: true, at: CGPoint(x: 200, y: 100))
        XCTAssertEqual(stage.speech?.id, 2)
        XCTAssertNil(stage.finaleAt, "no finale yet")

        stage.light(0, byCap: false, at: CGPoint(x: 150, y: 100))
        XCTAssertTrue(stage.isFinished)
        let finale = try! XCTUnwrap(stage.finaleAt)
        let third = try! XCTUnwrap(stage.litAt[0])
        XCTAssertGreaterThan(finale, third, "the glow starts just after the third star")
        // The rest ignite one after another, left to right.
        let rest = [2, 3, 5, 6].map { try! XCTUnwrap(stage.litAt[$0]) }
        XCTAssertEqual(rest, rest.sorted())
        XCTAssertEqual(rest[0] - third, WelcomeLook.sweepDelay, accuracy: 0.001)
        XCTAssertEqual(rest[1] - rest[0], WelcomeLook.sweepGap, accuracy: 0.001)
        XCTAssertFalse(stage.celebrated, "the words answer a beat later, after his last line")
        XCTAssertLessThanOrEqual(stage.ripples.count, 4)
    }

    @MainActor
    func testWithReduceMotionTheStarsSimplyLight() {
        let sounds = CLSound.shared.isEnabled
        CLSound.shared.isEnabled = false
        defer { CLSound.shared.isEnabled = sounds }
        let stage = WelcomeStage()
        stage.setCalm(true)
        stage.light(1, byCap: false, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(stage.litAt[1], -.infinity, "lit at once, no ignition to play")
        XCTAssertTrue(stage.ripples.isEmpty, "no ripples")
        stage.light(4, byCap: false)
        stage.light(0, byCap: false)
        XCTAssertTrue(stage.isFinished)
        XCTAssertTrue(stage.litAt.allSatisfy { $0 == -.infinity }, "the whole cap, with no sweep")
    }

    @MainActor
    func testATouchOnEmptySkyOnlyRipples() {
        let stage = WelcomeStage()
        stage.tap(at: CGPoint(x: 3, y: 3), camera: SkyCamera.fit(WelcomeSky.layout, in: CGSize(width: 390, height: 360)), size: CGSize(width: 390, height: 360))
        XCTAssertEqual(stage.state.count, 0)
        XCTAssertEqual(stage.ripples.count, 1)
        XCTAssertNil(stage.speech)
        XCTAssertTrue(stage.litAt.allSatisfy { $0 == nil })
    }

    // MARK: Cap's lines

    func testCapsLinesFollowTheVoice() {
        for line in WelcomeCopy.all {
            let text = String(localized: line)
            XCTAssertLessThanOrEqual(text.count, 40, "short: \(text)")
            XCTAssertTrue(text.first?.isUppercase == true, "sentence case: \(text)")
            XCTAssertTrue(".?".contains(text.last!), "a whole sentence: \(text)")
            XCTAssertFalse(text.contains("!"), "warm, not shouting: \(text)")
            XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "no emoji: \(text)")
        }
    }

    func testTheWelcomeFinishesByItselfInUnderTwentySeconds() {
        // Hello, then "tap one", then a star of his own, then a star every few seconds until the third.
        let alone = WelcomeCopy.introAt + WelcomeCopy.hintAfter + WelcomeCopy.lightAfter + 2 * WelcomeCopy.nextAfter
        XCTAssertLessThan(alone, 20)
        XCTAssertLessThan(WelcomeCopy.introAt, WelcomeCopy.hintAfter, "he greets before he nudges")
    }
}
