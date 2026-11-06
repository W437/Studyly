import XCTest
@testable import Cramless

/// Today's sky band (and the welcome's world): where everything sits on each screen, the field of background stars, the clouds
/// behind each course, how a tilt moves the layers, the shooting stars, and aiming a tap at a star (the full sky's).
final class HeroWorldGeometryTests: XCTestCase {
    private let phone = HeroWorldGeometry.band(width: 402, topInset: 62, compact: false)

    func testTheBandIsTheSameOnEveryPhone() {
        for (width, top) in [(375.0, 20.0), (393.0, 59.0), (402.0, 62.0), (440.0, 62.0)] {
            let band = HeroWorldGeometry.band(width: width, topInset: top, compact: false)
            XCTAssertEqual(band.band, HeroWorldGeometry.bandHeight)
            XCTAssertEqual(band.height, top + 188, "188 points under the status bar")
            XCTAssertEqual(band.style, .band)
        }
        XCTAssertEqual(phone.height, 250, "250 on an iPhone 17 Pro")
        XCTAssertEqual(HeroWorldGeometry.band(width: 375, topInset: 20, compact: false).height, 208, "208 on an SE")
    }

    func testTheSELeavesRoomForTheDaysCard() {
        // An iPhone SE: 667 points tall, 49 of them the tab bar.
        let se = HeroWorldGeometry.band(width: 375, topInset: 20, compact: false)
        XCTAssertGreaterThanOrEqual(667 - 49 - se.height, 380)
    }

    func testCapStandsOnTheShoreAt96Points() {
        XCTAssertEqual(phone.capSize, 96)
        XCTAssertLessThan(phone.capSize, phone.band - 60, "he fits under the greeting")
    }

    func testTheLargestTextSizesGetALowBandWithNoCap() {
        let compact = HeroWorldGeometry.band(width: 402, topInset: 62, compact: true)
        XCTAssertEqual(compact.band, HeroWorldGeometry.compactBand)
        XCTAssertEqual(compact.capSize, 0)
        XCTAssertFalse(compact.reflects)
    }

    func testTheSkyIsTheFreePartBetweenTheStatusBarAndTheHills() {
        XCTAssertGreaterThanOrEqual(phone.skyTop, phone.topInset)
        XCTAssertEqual(phone.skyTop, phone.topInset + 8)
        XCTAssertLessThan(phone.skyBottom, phone.farHills, "no star sits below the hills' crest")
        XCTAssertEqual(phone.skyBottom - phone.skyTop, phone.skyHeight, accuracy: 0.001)
        XCTAssertEqual(phone.insetTop, Double(phone.skyTop))
        XCTAssertEqual(phone.insetBottom, Double(phone.height - phone.skyBottom), accuracy: 0.001)
        XCTAssertEqual(phone.skyAspect, Double(phone.skyHeight / phone.width), accuracy: 1e-9)
        XCTAssertEqual(phone.skyAspect, 0.32, accuracy: 0.03, "a wide, low sky")
    }

    func testTheGroundIsLayeredFromFarToNearAndTheBandsLakeIsAStrip() {
        XCTAssertEqual(phone.farHills, phone.height - 46)
        XCTAssertEqual(phone.midHills, phone.height - 30)
        XCTAssertEqual(phone.lakeTop, phone.height - 16)
        XCTAssertEqual(phone.lakeDepth, 12)
        XCTAssertFalse(phone.reflects, "too thin to mirror the stars")
        XCTAssertEqual(phone.glowReach, 110)
        XCTAssertEqual(phone.scrimReach, 66)
        for geometry in [phone, HeroWorldGeometry.band(width: 402, topInset: 62, compact: true)] {
            XCTAssertLessThan(geometry.farHills, geometry.midHills)
            XCTAssertLessThan(geometry.midHills, geometry.lakeTop + 0.001)
            XCTAssertLessThan(geometry.lakeTop, geometry.height)
        }
    }

    func testTheWelcomesWorldIsUnchanged() {
        // `WelcomeView` builds its own geometry: its numbers are the world's, not the band's.
        let world = HeroWorldGeometry(width: 402, height: 62 + 450, topInset: 62, compact: false)
        XCTAssertEqual(world.style, .world)
        XCTAssertEqual(world.skyTop, 62 + 12)
        XCTAssertEqual(world.farHills, world.height - 84)
        XCTAssertEqual(world.midHills, world.height - 52)
        XCTAssertEqual(world.lakeTop, world.height - 50)
        XCTAssertEqual(world.lakeDepth, 34)
        XCTAssertEqual(world.capSize, min(196, max(120, 402 * 0.46)))
        XCTAssertTrue(world.reflects)
        XCTAssertEqual(world.glowReach, 190)
        XCTAssertEqual(world.scrimReach, 104)
        let compact = HeroWorldGeometry(width: 402, height: 62 + 230, topInset: 62, compact: true)
        XCTAssertEqual(compact.farHills, compact.height - 28)
        XCTAssertEqual(compact.lakeTop, compact.height - 14)
    }

    func testTheSkyAspectBeforeMeasuringIsAPhonesBand() {
        XCTAssertEqual(TodaySnapshot.skyAspect, phone.skyAspect, "the default for a screen that isn't measured yet is a phone's")
        let compact = HeroWorldGeometry.bandSkyAspect(width: 402, topInset: 62, compact: true)
        XCTAssertNotEqual(compact, phone.skyAspect, "the compact band's sky is laid out for its own shape")
        XCTAssertLessThan(compact, 0.5, "and is still wide and low")
    }

    func testHeroCameraMayStartFurtherInThanTheFullScreen() {
        var layout = SkyLayout()
        layout.width = 6
        layout.height = 4
        let size = CGSize(width: 402, height: 400)
        let ordinary = SkyCamera.fit(layout, in: size)
        let hero = SkyCamera.fit(layout, in: size, largest: 40)
        XCTAssertEqual(ordinary.scale, SkyCamera.largestFit)
        XCTAssertEqual(hero.scale, 40)
        // A sky that fills its room is the same in both.
        layout.width = 30
        layout.height = 20
        XCTAssertEqual(SkyCamera.fit(layout, in: size).scale, SkyCamera.fit(layout, in: size, largest: 40).scale)
    }
}

final class HeroDustTests: XCTestCase {
    func testTheSameSeedMakesTheSameSkyAndAnotherMakesAnother() {
        XCTAssertEqual(HeroDust.make(), HeroDust.make())
        XCTAssertNotEqual(HeroDust.make(seed: 1), HeroDust.make(seed: 2))
    }

    func testThereAreManyStarsAndEveryOneIsInsideTheSky() {
        let dust = HeroDust.make()
        XCTAssertEqual(dust.motes.count, 240)
        for mote in dust.motes {
            XCTAssertTrue((0...1).contains(mote.x) && (0...1).contains(mote.y))
            XCTAssertTrue((0...2).contains(mote.depth))
            XCTAssertTrue((0.3...2.5).contains(mote.radius), "radius \(mote.radius)")
            XCTAssertTrue((0.1...1).contains(mote.alpha), "alpha \(mote.alpha)")
            XCTAssertTrue(mote.period >= 2.6 && mote.period <= 6.2)
        }
    }

    func testThreeDepthsAllTurnUpAndTheFarOnesAreTheMost() {
        let counts = (0...2).map { depth in HeroDust.make().motes.filter { $0.depth == depth }.count }
        XCTAssertTrue(counts.allSatisfy { $0 > 10 }, "\(counts)")
        XCTAssertGreaterThan(counts[0], counts[2])
    }

    func testAFewStarsGlintAndTheyAreTheBrightOnes() {
        let dust = HeroDust.make()
        let glinting = dust.motes.filter(\.glints)
        XCTAssertTrue((6...10).contains(glinting.count), "\(glinting.count)")
        XCTAssertTrue(glinting.allSatisfy { $0.depth == 2 && $0.alpha > 0.8 && $0.y <= 0.7 })
    }

    func testTheSkyThinsTowardTheHorizon() {
        let motes = HeroDust.make().motes
        XCTAssertGreaterThan(motes.filter { $0.y < 0.5 }.count, motes.filter { $0.y >= 0.5 }.count)
    }

    func testStarsBreatheWhileAnimatedAndStandStillWhenNot() {
        let mote = HeroDust.make().motes[3]
        XCTAssertEqual(HeroDust.twinkle(mote, time: 12.3, animated: false), 1)
        let values = stride(from: 0.0, to: 12.0, by: 0.25).map { HeroDust.twinkle(mote, time: $0, animated: true) }
        XCTAssertGreaterThanOrEqual(values.min()!, 0.55)
        XCTAssertLessThanOrEqual(values.max()!, 1.01)
        XCTAssertGreaterThan(values.max()! - values.min()!, 0.2)
    }

    func testDeeperLayersFollowATiltFurther() {
        XCTAssertEqual(HeroDust.parallax, HeroDust.parallax.sorted())
        XCTAssertEqual(HeroDust.zoomFollow, HeroDust.zoomFollow.sorted())
        XCTAssertGreaterThan(HeroDust.parallax[2], HeroDust.parallax[0] * 2)
    }
}

final class HeroCloudTests: XCTestCase {
    private func scene(courses: Int, topics: Int = 3, perTopic: Int = 6) -> SkyScene {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var items: [ItemSnapshot] = [], topicList: [TopicSnapshot] = [], courseList: [SkyCourse] = []
        let colors = CourseColor.allCases
        for c in 0..<courses {
            let course = SkyCourse(id: StableRandom.uuid("hc-course-\(c)"), name: "Course \(c)", color: colors[c % colors.count],
                                   sortOrder: c, createdAt: start)
            courseList.append(course)
            for t in 0..<topics {
                let topic = TopicSnapshot(id: StableRandom.uuid("hc-topic-\(c)-\(t)"), courseID: course.id, name: "Topic \(c).\(t)", sortOrder: t)
                topicList.append(topic)
                for i in 0..<perTopic {
                    items.append(ItemSnapshot(id: StableRandom.uuid("hc-item-\(c)-\(t)-\(i)"), topicID: topic.id, courseID: course.id,
                                              memory: .new, createdAt: start.addingTimeInterval(Double(i) * 60)))
                }
            }
        }
        let layout = SkyEngine.layout(items: items, topics: topicList, courses: courseList, exams: [], aspect: 0.7)
        return SkyScene(layout: layout, light: SkyLight(), courseColors: Dictionary(uniqueKeysWithValues: courseList.map { ($0.id, $0.color) }),
                        courseNames: [:], examDates: [:], dimSeconds: Array(repeating: 0, count: layout.constellations.count), date: start)
    }

    func testThereIsOneCloudForEachCourseInTheirOrderAndColour() {
        let scene = scene(courses: 4)
        let clouds = HeroCloud.clouds(for: scene)
        XCTAssertEqual(clouds.count, 4)
        XCTAssertEqual(Set(clouds.map(\.courseID)).count, 4)
        for cloud in clouds {
            let first = scene.layout.constellations.first { $0.courseID == cloud.courseID }!
            XCTAssertEqual(cloud.color, scene.color(of: first))
        }
    }

    func testACloudReachesPastEveryConstellationOfItsCourse() {
        let scene = scene(courses: 3)
        for cloud in HeroCloud.clouds(for: scene) {
            for c in scene.layout.constellations where c.courseID == cloud.courseID {
                XCTAssertLessThanOrEqual(cloud.center.distance(to: c.center) + c.radius, cloud.radius,
                                         "a constellation sticks out of its cloud")
            }
        }
    }

    func testAnEmptySkyHasNoClouds() {
        XCTAssertTrue(HeroCloud.clouds(for: .empty).isEmpty)
    }
}

final class HeroTiltTests: XCTestCase {
    func testHoldingThePhoneStillIsTheMiddle() {
        var filter = HeroTiltFilter()
        for _ in 0..<90 { filter.update(side: 0.4, lean: -0.2, dt: 1.0 / 30) }
        XCTAssertEqual(filter.x, 0, accuracy: 0.001)
        XCTAssertEqual(filter.y, 0, accuracy: 0.001)
    }

    func testTiltingAwayFromWhereItWasHeldMovesTheLayers() {
        var filter = HeroTiltFilter()
        filter.update(side: 0, lean: 0, dt: 1.0 / 30)
        for _ in 0..<30 { filter.update(side: 0.2, lean: -0.15, dt: 1.0 / 30) }
        XCTAssertGreaterThan(filter.x, 0.3)
        XCTAssertLessThan(filter.y, -0.2)
        for _ in 0..<30 { filter.update(side: -0.2, lean: 0.15, dt: 1.0 / 30) }
        XCTAssertLessThan(filter.x, 0)
    }

    func testAPhoneHeldUprightDoesNotJitterWhateverItsAnglesDo() {
        // Held upright, gravity points down the screen: (0, -1, 0). Roll and pitch angles are unstable there (gimbal lock), which
        // is why the filter takes the gravity vector: its sideways and forward parts barely move for a hand's tremor.
        var filter = HeroTiltFilter()
        var worst = 0.0
        for k in 0..<300 {
            let tremor = 0.004 * sin(Double(k) * 1.3)
            filter.update(side: tremor, lean: -tremor * 0.7, dt: 1.0 / 30)
            worst = max(worst, abs(filter.x), abs(filter.y))
        }
        XCTAssertLessThan(worst, 0.06, "a steady hand barely moves the world")
    }

    func testItNeverMovesPastTheFullTilt() {
        var filter = HeroTiltFilter()
        filter.update(side: 0, lean: 0, dt: 1.0 / 30)
        for _ in 0..<300 { filter.update(side: 3, lean: -3, dt: 1.0 / 30) }
        XCTAssertLessThanOrEqual(abs(filter.x), 1)
        XCTAssertLessThanOrEqual(abs(filter.y), 1)
    }

    func testAPhoneHeldAtANewAngleBecomesTheNewMiddle() {
        var filter = HeroTiltFilter()
        filter.update(side: 0, lean: 0, dt: 1.0 / 30)
        for _ in 0..<(30 * 20) { filter.update(side: 0.25, lean: 0.1, dt: 1.0 / 30) }
        XCTAssertEqual(filter.x, 0, accuracy: 0.02, "after twenty seconds at the new angle it is the middle again")
    }

    func testItSmoothsAJerk() {
        var filter = HeroTiltFilter()
        filter.update(side: 0, lean: 0, dt: 1.0 / 30)
        filter.update(side: 0.3, lean: 0, dt: 1.0 / 30)
        XCTAssertLessThan(filter.x, 0.25, "one reading doesn't jump the world")
        XCTAssertGreaterThan(filter.x, 0)
    }

    func testResetStartsOver() {
        var filter = HeroTiltFilter()
        filter.update(side: 0, lean: 0, dt: 1.0 / 30)
        filter.update(side: 0.3, lean: 0.3, dt: 1.0 / 30)
        filter.reset()
        XCTAssertEqual(filter, HeroTiltFilter())
    }

    func testTheSwayWithNoSensorIsSlowWideAndStartsAtRest() {
        XCTAssertEqual(HeroTilt.idleSway(at: 0).x, 0, accuracy: 1e-9)
        let xs = stride(from: 0.0, to: 60.0, by: 0.5).map { HeroTilt.idleSway(at: $0).x }
        XCTAssertGreaterThan(xs.max()! - xs.min()!, 1.0)
        XCTAssertTrue(xs.allSatisfy { abs($0) <= 1 })
        // No jerks: neighbouring half-seconds never differ by much.
        for (a, b) in zip(xs, xs.dropFirst()) { XCTAssertLessThan(abs(a - b), 0.2) }
    }
}

final class HeroShootingStarTests: XCTestCase {
    func testNothingCrossesBeforeTheWorldHasSettled() {
        for t in stride(from: 0.0, to: 5.0, by: 0.05) { XCTAssertNil(HeroShootingStar.streak(at: t)) }
    }

    func testAStarCrossesNowAndThenAndNeverTwoAtOnce() {
        var crossings = 0
        var wasCrossing = false
        for t in stride(from: 0.0, to: 120.0, by: 0.05) {
            let streak = HeroShootingStar.streak(at: t)
            if streak != nil, !wasCrossing { crossings += 1 }
            wasCrossing = streak != nil
        }
        XCTAssertTrue((4...7).contains(crossings), "\(crossings) in two minutes")
    }

    func testAFlightRunsFromNothingToItsEndInAboutAFifthOfAMinute() {
        let times = stride(from: 5.0, to: 60.0, by: 0.01).filter { HeroShootingStar.streak(at: $0) != nil }
        let first = try! XCTUnwrap(times.first)
        let streak = HeroShootingStar.streak(at: first + 0.02)!
        XCTAssertLessThan(streak.progress, 0.1)
        let flight = times.prefix { $0 < first + HeroShootingStar.flight + 0.1 }
        XCTAssertEqual(Double(flight.count) * 0.01, HeroShootingStar.flight, accuracy: 0.05)
        for t in flight {
            let s = HeroShootingStar.streak(at: t)!
            XCTAssertTrue((0...1).contains(s.progress))
            XCTAssertTrue((0...1).contains(s.from.x) && (0...1).contains(s.from.y))
            XCTAssertGreaterThan(s.to.y, s.from.y, "it falls")
        }
    }

    func testTheSameMinuteIsTheSameEveryTime() {
        for t in stride(from: 5.0, to: 80.0, by: 0.3) {
            XCTAssertEqual(HeroShootingStar.streak(at: t), HeroShootingStar.streak(at: t))
        }
        // The first moment each slot's star is up: where they start differs from one to the next.
        var starts: [CGPoint] = []
        for slot in 0..<10 {
            let slotStart = 5 + Double(slot) * HeroShootingStar.period
            if let found = stride(from: slotStart, to: slotStart + HeroShootingStar.period, by: 0.05).compactMap({ HeroShootingStar.streak(at: $0) }).first {
                starts.append(found.from)
            }
        }
        XCTAssertEqual(starts.count, 10, "one in every slot")
        XCTAssertGreaterThan(Set(starts.map { Int($0.x * 1000) }).count, 5, "they don't all start in the same place")
    }
}

final class SkyHitNearestStarTests: XCTestCase {
    private let size = CGSize(width: 400, height: 600)

    private func sky() -> SkyLayout {
        var layout = SkyLayout()
        layout.stars = [
            .init(id: UUID(), point: SkyPoint(x: 10, y: 10), constellation: 0),
            .init(id: UUID(), point: SkyPoint(x: 12, y: 10), constellation: 0),
            .init(id: UUID(), point: SkyPoint(x: 30, y: 10), constellation: 1),
        ]
        layout.constellations = [
            .init(id: UUID(), courseID: UUID(), topicID: UUID(), name: "a", center: SkyPoint(x: 11, y: 10), radius: 2, stars: 0..<2, lines: []),
            .init(id: UUID(), courseID: UUID(), topicID: UUID(), name: "b", center: SkyPoint(x: 30, y: 10), radius: 2, stars: 2..<3, lines: []),
        ]
        return layout
    }

    func testATapNearAStarFindsItsConstellation() {
        let layout = sky()
        let camera = SkyCamera(center: SkyPoint(x: 20, y: 10), scale: 10)
        let star = camera.screen(SkyPoint(x: 12, y: 10), in: size)
        XCTAssertEqual(SkyHit.nearestStar(at: CGPoint(x: star.x + 25, y: star.y + 10), camera: camera, size: size, layout: layout), 0)
        let other = camera.screen(SkyPoint(x: 30, y: 10), in: size)
        XCTAssertEqual(SkyHit.nearestStar(at: CGPoint(x: other.x - 30, y: other.y), camera: camera, size: size, layout: layout), 1)
    }

    func testATapFarFromEveryStarFindsNothing() {
        let layout = sky()
        let camera = SkyCamera(center: SkyPoint(x: 20, y: 10), scale: 10)
        XCTAssertNil(SkyHit.nearestStar(at: CGPoint(x: 200, y: 500), camera: camera, size: size, layout: layout))
        let star = camera.screen(SkyPoint(x: 12, y: 10), in: size)
        XCTAssertNil(SkyHit.nearestStar(at: CGPoint(x: star.x, y: star.y + 60), camera: camera, size: size, layout: layout))
    }

    func testBetweenTwoShapesItGoesToTheNearerStar() {
        let layout = sky()
        let camera = SkyCamera(center: SkyPoint(x: 20, y: 10), scale: 10)
        // x = 20 is 80 points from the first constellation's near star and 100 from the second's: out of reach; nearer to a star wins.
        let nearFirst = camera.screen(SkyPoint(x: 15, y: 10), in: size)
        XCTAssertEqual(SkyHit.nearestStar(at: nearFirst, camera: camera, size: size, layout: layout, reach: 40), 0)
        let nearSecond = camera.screen(SkyPoint(x: 27, y: 10), in: size)
        XCTAssertEqual(SkyHit.nearestStar(at: nearSecond, camera: camera, size: size, layout: layout, reach: 40), 1)
    }

    func testTheReachIsInPointsNotInStarSpacings() {
        let layout = sky()
        let wide = SkyCamera(center: SkyPoint(x: 20, y: 10), scale: 40)
        let star = wide.screen(SkyPoint(x: 30, y: 10), in: size)
        XCTAssertEqual(SkyHit.nearestStar(at: CGPoint(x: star.x + 39, y: star.y), camera: wide, size: size, layout: layout), 1)
        XCTAssertNil(SkyHit.nearestStar(at: CGPoint(x: star.x + 41, y: star.y), camera: wide, size: size, layout: layout))
    }
}
