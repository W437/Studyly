import UIKit
import XCTest
@testable import Cramless

/// What a tap on Cap does to his body: rolled afresh each time, bounded, and always back at rest.
final class CapPokeTests: XCTestCase {
    private func rolls(_ pose: CapPose, rapid: Int = 1, seeds: Range<UInt64> = 0..<200) -> [CapPoke] {
        seeds.map { seed in
            var dice = CapDice(seed: seed)
            return CapPoke.roll(for: pose, rapid: rapid, using: &dice)
        }
    }

    func testTheSameSeedGivesTheSamePokeAndAnotherGivesADifferentOne() {
        var a = CapDice(seed: 7), b = CapDice(seed: 7), c = CapDice(seed: 8)
        let first = CapPoke.roll(for: .nice, using: &a)
        XCTAssertEqual(first, CapPoke.roll(for: .nice, using: &b))
        XCTAssertNotEqual(first, CapPoke.roll(for: .nice, using: &c))
    }

    func testNoTwoTapsFeelTheSame() {
        for pose in CapPose.allCases {
            let distinct = Set(rolls(pose, seeds: 0..<40).map { "\($0.style) \(Int($0.presses[0].amount * 1000)) \(Int($0.hertz * 100)) \(Int($0.lean * 100))" })
            XCTAssertGreaterThan(distinct.count, 30, "\(pose): taps are too alike")
        }
    }

    func testAPokeStartsAndEndsAtRest() {
        for pose in CapPose.allCases {
            for poke in rolls(pose, seeds: 0..<60) {
                XCTAssertEqual(poke.frame(at: 0), CapFrame(), "\(pose) \(poke.style) isn't at rest at the tap")
                XCTAssertEqual(poke.frame(at: poke.duration), CapFrame(), "\(pose) \(poke.style) doesn't end at rest")
                XCTAssertEqual(poke.frame(at: poke.duration + 5), CapFrame())
                // And it has already eased to almost nothing a hair before the end, so no pop.
                let nearEnd = poke.frame(at: poke.duration - 0.01)
                XCTAssertEqual(nearEnd.scaleY, 1, accuracy: 0.003, "\(pose) \(poke.style) still squashed at its end")
                XCTAssertEqual(nearEnd.tilt, 0, accuracy: 0.3)
            }
        }
    }

    func testAPokeStaysInsideWhatLooksNatural() {
        for pose in CapPose.allCases {
            for poke in rolls(pose, rapid: 6, seeds: 0..<60) + rolls(pose, seeds: 0..<60) {
                XCTAssertGreaterThanOrEqual(poke.duration, 0.5)
                XCTAssertLessThanOrEqual(poke.duration, 1.7)
                var t = 0.0
                while t < poke.duration {
                    let f = poke.frame(at: t)
                    XCTAssertTrue((0.7...1.19).contains(f.scaleY), "\(pose) \(poke.style): height \(f.scaleY) at \(t)")
                    XCTAssertTrue((0.88...1.3).contains(f.scaleX), "\(pose) \(poke.style): width \(f.scaleX) at \(t)")
                    XCTAssertLessThan(abs(f.tilt), 14)
                    XCTAssertLessThan(abs(f.sway), 0.05)
                    XCTAssertTrue((0...0.2).contains(f.lift), "\(pose) \(poke.style): lift \(f.lift)")
                    XCTAssertTrue(f.scaleX.isFinite && f.scaleY.isFinite && f.tilt.isFinite)
                    t += 0.01
                }
            }
        }
    }

    func testHeIsSquashedAndThenSpringsPastWhereHeWas() {
        var dice = CapDice(seed: 3)
        var poke = CapPoke.roll(for: .study, using: &dice)
        poke.presses = [.init(start: 0, amount: 0.16, ramp: 0.07)]
        poke.fatness = 1
        poke.damping = 0.25
        poke.lean = 0
        poke.sway = 0
        poke.hop = 0
        poke.duration = 1.4
        let bottom = poke.frame(at: 0.07)
        XCTAssertEqual(bottom.scaleY, 0.84, accuracy: 0.01)
        XCTAssertGreaterThan(bottom.scaleX, 1.08, "squashed, so wider")
        let samples = stride(from: 0.08, to: 1.2, by: 0.01).map { poke.frame(at: $0).scaleY }
        XCTAssertGreaterThan(samples.max()!, 1.03, "he should overshoot and stretch after the press")
    }

    func testASleeperIsNudgedAndACheererBounces() {
        for poke in rolls(.sleep) + rolls(.sleepy) + rolls(.tuckIn) + rolls(.relax) {
            XCTAssertNotEqual(poke.style, .boing, "a sleeper doesn't bounce")
            XCTAssertNotEqual(poke.style, .wriggle)
            XCTAssertEqual(poke.hop, 0)
        }
        let cheerers = rolls(.celebrate)
        XCTAssertTrue(cheerers.contains { $0.style == .boing && $0.hop > 0.05 }, "a cheerer bounces sometimes")
        let sleepersPress = rolls(.sleep).map { $0.presses[0].amount }.reduce(0, +) / 200
        let cheerersPress = cheerers.filter { $0.style != .wriggle && $0.style != .wobble }.map { $0.presses[0].amount }
        XCTAssertLessThan(sleepersPress, cheerersPress.reduce(0, +) / Double(cheerersPress.count), "sleepers are pressed more gently")
    }

    func testEveryStyleTurnsUpAcrossTheCastAndEachIsUsed() {
        var styles: Set<CapPoke.Style> = []
        for pose in CapPose.allCases { styles.formUnion(rolls(pose, seeds: 0..<100).map(\.style)) }
        XCTAssertEqual(styles, Set(CapPoke.Style.allCases))
    }

    func testAQuickRunOfTapsGetsLivelierAndEndsInAShimmy() {
        let one = rolls(.study, rapid: 1).map { $0.presses[0].amount }.reduce(0, +)
        let five = rolls(.study, rapid: 5).map { $0.presses[0].amount }.reduce(0, +)
        XCTAssertGreaterThan(five, one * 1.1, "a run of taps squashes him harder")
        XCTAssertTrue(rolls(.study, rapid: 7).allSatisfy { $0.style == .wriggle }, "a long run turns into a shimmy")
        XCTAssertTrue(rolls(.study, rapid: 7).allSatisfy { $0.strength <= 1 })
    }

    func testTheHapticFollowsHowHardHeWasPressed() {
        for poke in rolls(.nice, seeds: 0..<80) {
            XCTAssertTrue((0...1).contains(poke.strength))
        }
        let soft = rolls(.sleep).map(\.strength).reduce(0, +)
        let firm = rolls(.celebrate).map(\.strength).reduce(0, +)
        XCTAssertLessThan(soft, firm)
    }

    func testTheLimiterLeavesNormalSquashesAloneAndNeverPassesItsCeiling() {
        for x in stride(from: 0.0, through: 0.18, by: 0.01) { XCTAssertEqual(CapPoke.limited(x, knee: 0.18, ceiling: 0.3), x, accuracy: 1e-12) }
        XCTAssertLessThan(CapPoke.limited(5, knee: 0.18, ceiling: 0.3), 0.30000001)
        XCTAssertGreaterThan(CapPoke.limited(0.4, knee: 0.18, ceiling: 0.3), CapPoke.limited(0.25, knee: 0.18, ceiling: 0.3))
        XCTAssertGreaterThan(CapPoke.limited(-5, knee: 0.18, ceiling: 0.3), -0.1801, "a stretch is held to well under a squash")
        XCTAssertEqual(CapPoke.limited(-0.05, knee: 0.18, ceiling: 0.3), -0.05, accuracy: 1e-12)
    }

    func testTheSpringIsOneAtTheStartAndDiesAway() {
        XCTAssertEqual(CapPoke.spring(0, hertz: 2.5, damping: 0.25), 1, accuracy: 1e-9)
        XCTAssertLessThan(CapPoke.spring(0.2, hertz: 2.5, damping: 0.25), 0, "it has swung through rest into a stretch by then")
        XCTAssertLessThan(abs(CapPoke.spring(2.5, hertz: 2.5, damping: 0.25)), 0.01)
    }

    func testTheDiceRepeatWithASeedAndTheSystemOnesDont() {
        var a = CapRNG(seed: 99), b = CapRNG(seed: 99)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
        var s1 = CapRNG(), s2 = CapRNG()
        XCTAssertNotEqual((0..<5).map { _ in s1.next() }, (0..<5).map { _ in s2.next() })
    }
}

/// What Cap says, and that he doesn't say it twice in a row.
final class CapSpeechTests: XCTestCase {
    private func english(_ text: LocalizedStringResource) -> String { String(localized: text) }

    func testThereAreLotsOfLines() {
        for pose in CapPose.allCases { XCTAssertGreaterThanOrEqual(CapLines.lines(for: pose).count, 16, "\(pose)") }
        XCTAssertGreaterThanOrEqual(CapLines.general.count, 36)
        XCTAssertGreaterThanOrEqual(CapLines.flustered.count, 10)
        XCTAssertGreaterThanOrEqual(CapLines.refreshed.count, 10)
        for part in CapDayPart.allCases { XCTAssertGreaterThanOrEqual(CapLinePool.time(part).lines.count, 5, "\(part)") }
        let total = CapLinePool.all.reduce(0) { $0 + $1.lines.count }
        XCTAssertGreaterThan(total, 400)
    }

    func testEveryLineIsShortWarmAndPlain() {
        let banned = ["disappoint", "should have", "you must", "have to", "behind", "guilt", "ashamed", "fail", "stupid", "lazy you"]
        for pool in CapLinePool.all {
            for resource in pool.lines {
                let line = english(resource)
                XCTAssertLessThanOrEqual(line.count, 46, "too long for a bubble: \(line)")
                XCTAssertGreaterThanOrEqual(line.count, 3, line)
                XCTAssertTrue(line.first?.isUppercase == true || line.first?.isNumber == true, "sentence case: \(line)")
                XCTAssertFalse(line.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x2000 },
                               "no emoji in the interface: \(line)")
                XCTAssertFalse(line.hasSuffix("  "), line)
                XCTAssertEqual(line, line.trimmingCharacters(in: .whitespaces))
                let lower = line.lowercased()
                for word in banned { XCTAssertFalse(lower.contains(word), "\"\(line)\" sounds like a guilt trip (\(word))") }
            }
        }
    }

    func testTheRefreshedLinesAreAPoolOfTheirOwn() {
        XCTAssertEqual(CapLinePool.refreshed.id, "refreshed")
        XCTAssertEqual(CapLinePool.refreshed.lines.count, CapLines.refreshed.count)
        XCTAssertTrue(CapLinePool.all.contains(.refreshed))
        // A tap never picks them: they are for the sky being refreshed.
        for roll in stride(from: 0.0, to: 1.0, by: 0.05) {
            for rapid in 0..<8 {
                XCTAssertNotEqual(CapSpeech.pool(for: .study, rapid: rapid, hour: 10, roll: roll), .refreshed)
            }
        }
    }

    func testNoLineIsSaidTwiceAnywhere() {
        var seen: [String: String] = [:]
        for pool in CapLinePool.all {
            for resource in pool.lines {
                let line = english(resource)
                if let other = seen[line] { XCTFail("\"\(line)\" is in \(pool.id) and \(other)") }
                seen[line] = pool.id
            }
        }
    }

    func testABagDealsEveryLineOnceBeforeAnyIsRepeated() {
        var bag = CapLineBag()
        var dice = CapDice(seed: 1)
        for round in 0..<3 {
            let dealt = (0..<18).map { _ in bag.draw(pool: "pose.wave", count: 18, using: &dice) }
            XCTAssertEqual(Set(dealt).count, 18, "round \(round) repeated a line before the pool was used up")
        }
    }

    func testANewRoundNeverStartsWithTheLastLineOfTheOneBefore() {
        for seed in 0..<300 {
            var bag = CapLineBag()
            var dice = CapDice(seed: UInt64(seed))
            var last = -1
            for _ in 0..<9 {
                let pick = bag.draw(pool: "p", count: 3, using: &dice)
                XCTAssertNotEqual(pick, last, "seed \(seed): the same line twice in a row")
                last = pick
            }
        }
    }

    func testAPoolOfOneAndAnEmptyOneDontBreakIt() {
        var bag = CapLineBag()
        var dice = CapDice(seed: 5)
        XCTAssertEqual(bag.draw(pool: "one", count: 1, using: &dice), 0)
        XCTAssertEqual(bag.draw(pool: "one", count: 1, using: &dice), 0)
        XCTAssertEqual(bag.draw(pool: "none", count: 0, using: &dice), 0)
    }

    func testTheBagCarriesOnAfterTheAppIsClosed() throws {
        var bag = CapLineBag()
        var dice = CapDice(seed: 11)
        let first = (0..<10).map { _ in bag.draw(pool: "g", count: 40, using: &dice) }
        var restored = try JSONDecoder().decode(CapLineBag.self, from: JSONEncoder().encode(bag))
        XCTAssertEqual(restored, bag)
        let next = restored.draw(pool: "g", count: 40, using: &dice)
        XCTAssertFalse(first.contains(next), "after relaunching he said a line he had just said")
    }

    func testAShrunkenPoolDoesntLeaveStaleIndicesBehind() {
        var bag = CapLineBag(seen: ["p": [0, 1, 2, 40]], last: ["p": 40])
        var dice = CapDice(seed: 2)
        let pick = bag.draw(pool: "p", count: 5, using: &dice)
        XCTAssertTrue((3...4).contains(pick), "lines that were already shown (0 to 2) are skipped; 40 no longer exists")
    }

    func testAQuickRunGetsTheFlusteredLines() {
        XCTAssertEqual(CapSpeech.pool(for: .study, rapid: 4, hour: 9, roll: 0.01), .flustered)
        XCTAssertEqual(CapSpeech.pool(for: .study, rapid: 9, hour: 9, roll: 0.99), .flustered)
        XCTAssertEqual(CapSpeech.pool(for: .study, rapid: 3, hour: 9, roll: 0.01), .pose(.study))
        XCTAssertEqual(CapSpeech.pool(for: .study, rapid: 1, hour: 9, roll: 0.70), .general)
        XCTAssertEqual(CapSpeech.pool(for: .study, rapid: 1, hour: 9, roll: 0.90), .time(.morning))
    }

    func testTheDayIsCutIntoPartsWithNoGaps() {
        let expected: [Int: CapDayPart] = [0: .night, 4: .night, 5: .morning, 11: .morning, 12: .afternoon, 16: .afternoon,
                                           17: .evening, 21: .evening, 22: .night, 23: .night]
        for (hour, part) in expected { XCTAssertEqual(CapDayPart(hour: hour), part, "hour \(hour)") }
        for hour in 0..<24 { XCTAssertTrue(CapDayPart.allCases.contains(CapDayPart(hour: hour))) }
    }

    func testMostOfWhatHeSaysIsAboutWhatHesDoing() {
        var tally: [String: Int] = [:]
        for seed in 0..<3000 {
            var dice = CapDice(seed: UInt64(seed))
            let roll = Double.random(in: 0..<1, using: &dice)
            tally[CapSpeech.pool(for: .sleep, rapid: 1, hour: 14, roll: roll).id, default: 0] += 1
        }
        XCTAssertGreaterThan(tally["pose.sleep", default: 0], 1900)
        XCTAssertGreaterThan(tally["general", default: 0], 300)
        XCTAssertGreaterThan(tally["time.afternoon", default: 0], 300)
    }

    func testABubbleStaysOnTheScreen() {
        // Room on both sides: it stays centred over him.
        XCTAssertEqual(CapSpeech.shift(capMidX: 200, bubbleWidth: 160, screenWidth: 402), 0)
        // Cap in the left corner of Today: the bubble slides right until it clears the margin.
        XCTAssertEqual(CapSpeech.shift(capMidX: 70, bubbleWidth: 180, screenWidth: 402), 102 - 70)
        // And the right edge.
        XCTAssertEqual(CapSpeech.shift(capMidX: 380, bubbleWidth: 180, screenWidth: 402), 402 - 12 - 90 - 380)
        // A bubble wider than the screen allows is centred rather than thrown off one side.
        XCTAssertEqual(CapSpeech.shift(capMidX: 50, bubbleWidth: 400, screenWidth: 402), 201 - 50)
    }

    func testHowLongABubbleStaysUpFollowsHowMuchThereIsToRead() {
        XCTAssertEqual(CapLine.seconds(forLength: 3), 1.9)
        XCTAssertEqual(CapLine.seconds(forLength: 200), 4.4)
        XCTAssertGreaterThan(CapLine.seconds(forLength: 40), CapLine.seconds(forLength: 15))
        for pool in CapLinePool.all {
            for (index, resource) in pool.lines.enumerated() {
                let line = CapLine(pool: pool.id, index: index, text: resource)
                XCTAssertTrue((1.9...4.4).contains(line.seconds))
            }
        }
    }

    @MainActor func testCapDealsALineFromThePoolForThePoseAndRemembersNothingInTests() {
        let touch = CapTouch.shared
        touch.configureForHarness(seed: 21)
        var said: Set<String> = []
        for _ in 0..<60 {
            let line = touch.line(for: .stargaze, rapid: 1, hour: 23)
            XCTAssertTrue(["pose.stargaze", "general", "time.night"].contains(line.pool), line.pool)
            said.insert(line.id)
        }
        XCTAssertGreaterThan(said.count, 20)
        XCTAssertEqual(touch.line(for: .study, rapid: 5).pool, "flustered")
    }
}

/// The + in the tab bar is a button: UIKit is told it can't be selected, and the action runs.
@MainActor
final class AddTabActionTests: XCTestCase {
    private final class Recorder: NSObject, UITabBarControllerDelegate {
        var selected: [String] = []
        var answers = true
        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool { answers }
        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            selected.append(selectedTab.title)
        }
    }

    private func controller() -> UITabBarController {
        let controller = UITabBarController()
        controller.tabs = ["Today", "Library", "Add"].map { title in
            UITab(title: title, image: nil, identifier: title) { _ in UIViewController() }
        }
        return controller
    }

    func testThePlusRunsTheActionAndIsNeverSelected() throws {
        let controller = controller()
        let recorder = Recorder()
        controller.delegate = recorder
        var runs = 0
        AddTabProxy.attach(to: controller, action: { runs += 1 })
        let proxy = try XCTUnwrap(controller.delegate as? AddTabProxy)
        XCTAssertFalse(proxy.tabBarController(controller, shouldSelectTab: controller.tabs[2]))
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(proxy.tabBarController(controller, shouldSelectTab: controller.tabs[0]))
        XCTAssertEqual(runs, 1, "an ordinary tab must not run the action")
    }

    func testEveryOtherQuestionGoesToTheDelegateItReplaced() throws {
        let controller = controller()
        let recorder = Recorder()
        recorder.answers = false
        controller.delegate = recorder
        AddTabProxy.attach(to: controller, action: {})
        let proxy = try XCTUnwrap(controller.delegate as? AddTabProxy)
        XCTAssertFalse(proxy.tabBarController(controller, shouldSelectTab: controller.tabs[1]), "the old delegate said no")
        XCTAssertTrue(proxy.responds(to: #selector(UITabBarControllerDelegate.tabBarController(_:didSelectTab:previousTab:))),
                      "calls the proxy doesn't answer itself must reach the old delegate")
        let delegate: any UITabBarControllerDelegate = proxy
        delegate.tabBarController?(controller, didSelectTab: controller.tabs[1], previousTab: controller.tabs[0])
        XCTAssertEqual(recorder.selected, ["Library"])
    }

    func testAttachingAgainKeepsOneProxyAndUpdatesItsAction() throws {
        let controller = controller()
        controller.delegate = Recorder()
        var first = 0, second = 0
        AddTabProxy.attach(to: controller, action: { first += 1 })
        let proxy = try XCTUnwrap(controller.delegate as? AddTabProxy)
        AddTabProxy.attach(to: controller, action: { second += 1 })
        XCTAssertTrue(controller.delegate === proxy, "a second proxy would wrap the first")
        _ = proxy.tabBarController(controller, shouldSelectTab: controller.tabs[2])
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    func testIfSwiftUISetsItsDelegateBackTheProxyStepsInFrontAgain() throws {
        let controller = controller()
        let original = Recorder()
        controller.delegate = original
        AddTabProxy.attach(to: controller, action: {})
        let proxy = try XCTUnwrap(controller.delegate as? AddTabProxy)
        let replacement = Recorder()
        controller.delegate = replacement
        // KVO calls back on the main actor; give it a turn.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(controller.delegate === proxy)
        XCTAssertTrue(proxy.original === replacement)
    }
}
