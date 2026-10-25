import SwiftUI
import XCTest
@testable import Cramless

/// The sky's geometry and wording: the camera frames, pans and zooms; a tap finds its constellation; the words say
/// what the sky shows; the renderer's plan and playback do what their rules say.
final class SkyCameraTests: XCTestCase {
    private let size = CGSize(width: 390, height: 800)

    private func layout(width: Double = 40, height: Double = 60) -> SkyLayout {
        var layout = SkyLayout()
        layout.width = width
        layout.height = height
        return layout
    }

    func testTheWholeSkyIsCentredAndFits() {
        let sky = layout()
        let camera = SkyCamera.fit(sky, in: size)
        // 40 × 60 units into 390 × 800: width limits it.
        XCTAssertEqual(camera.scale, 390 / 40, accuracy: 1e-9)
        let middle = camera.screen(SkyPoint(x: 20, y: 30), in: size)
        XCTAssertEqual(middle.x, 195, accuracy: 1e-6)
        XCTAssertEqual(middle.y, 400, accuracy: 1e-6)
        // Every corner of the sky is on screen.
        for corner in [SkyPoint(x: 0, y: 0), SkyPoint(x: 40, y: 60)] {
            let p = camera.screen(corner, in: size)
            XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5).contains(p))
        }
    }

    func testASmallSkyStaysSmall() {
        let camera = SkyCamera.fit(layout(width: 6, height: 6), in: size)
        XCTAssertEqual(camera.scale, SkyCamera.largestFit, "a few stars are not spread to the edges")
    }

    func testInsetsFrameTheSkyInWhatIsLeft() {
        let sky = layout(width: 30, height: 30)
        let camera = SkyCamera.fit(sky, in: size, top: 100, bottom: 300)
        let middle = camera.screen(SkyPoint(x: 15, y: 15), in: size)
        // The free part runs from 100 to 500: its middle is 300.
        XCTAssertEqual(middle.y, 300, accuracy: 1e-6)
        XCTAssertEqual(middle.x, 195, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(camera.screen(SkyPoint(x: 15, y: 30), in: size).y, 500 + 1e-6)
    }

    func testScreenAndLayoutAreInverses() {
        let camera = SkyCamera(center: SkyPoint(x: 12.5, y: 7), scale: 23)
        for p in [SkyPoint(x: 0, y: 0), SkyPoint(x: 10, y: 20), SkyPoint(x: -3, y: 40)] {
            let back = camera.layoutPoint(camera.screen(p, in: size), in: size)
            XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
        }
    }

    func testPanFollowsTheFinger() {
        let camera = SkyCamera(center: SkyPoint(x: 20, y: 30), scale: 10)
        let before = camera.screen(SkyPoint(x: 18, y: 31), in: size)
        let moved = camera.panned(by: CGSize(width: 40, height: -25))
        let after = moved.screen(SkyPoint(x: 18, y: 31), in: size)
        XCTAssertEqual(after.x - before.x, 40, accuracy: 1e-9)
        XCTAssertEqual(after.y - before.y, -25, accuracy: 1e-9)
    }

    func testZoomKeepsTheStarUnderTheFingerAndStaysInLimits() {
        let sky = layout()
        let fit = SkyCamera.fit(sky, in: size)
        let anchor = CGPoint(x: 100, y: 250)
        let under = fit.layoutPoint(anchor, in: size)
        let zoomed = fit.zoomed(by: 3, around: anchor, in: size, fit: fit)
        XCTAssertEqual(zoomed.scale, fit.scale * 3, accuracy: 1e-9)
        let still = zoomed.screen(under, in: size)
        XCTAssertEqual(still.x, anchor.x, accuracy: 1e-6)
        XCTAssertEqual(still.y, anchor.y, accuracy: 1e-6)
        XCTAssertEqual(fit.zoomed(by: 1000, around: anchor, in: size, fit: fit).scale, fit.scale * SkyCamera.zoomIn, accuracy: 1e-9)
        XCTAssertEqual(fit.zoomed(by: 0.001, around: anchor, in: size, fit: fit).scale, fit.scale * SkyCamera.zoomOut, accuracy: 1e-9)
    }

    func testFocusFillsMostOfTheFreeAreaWithoutOverflowing() {
        let c = SkyLayout.Constellation(id: UUID(), courseID: UUID(), topicID: UUID(), name: "Meiosis",
                                        center: SkyPoint(x: 14, y: 22), radius: 4, stars: 0..<0, lines: [])
        let camera = SkyCamera.focus(c, in: size, top: 100, bottom: 260)
        let free = size.height - 100 - 260
        let diameter = 2 * c.radius * camera.scale
        XCTAssertLessThanOrEqual(diameter, min(size.width, free) + 1e-6)
        XCTAssertGreaterThan(diameter, min(size.width, free) * 0.7)
        let middle = camera.screen(c.center, in: size)
        XCTAssertEqual(middle.y, 100 + free / 2, accuracy: 1e-6)
    }

    func testMixingGoesFromOneCameraToTheOther() {
        let a = SkyCamera(center: SkyPoint(x: 0, y: 0), scale: 10)
        let b = SkyCamera(center: SkyPoint(x: 8, y: -4), scale: 40)
        XCTAssertEqual(a.mixed(with: b, 0), a)
        XCTAssertEqual(a.mixed(with: b, 1).scale, 40, accuracy: 1e-9)
        XCTAssertEqual(a.mixed(with: b, 0.5).scale, 20, accuracy: 1e-9, "zoom moves evenly: halfway is the geometric middle")
        XCTAssertEqual(a.mixed(with: b, 0.5).center.x, 4, accuracy: 1e-9)
    }

    func testAClusterOfStarsIsFramedCloserAndAWideSpreadIsNot() throws {
        let sky = layout(width: 60, height: 90)
        let fit = SkyCamera.fit(sky, in: size, top: 100, bottom: 100)
        // A handful of stars in one corner: a closer camera, with every one of them in view and clear of the chrome.
        let cluster = [SkyPoint(x: 8, y: 10), SkyPoint(x: 12, y: 14), SkyPoint(x: 10, y: 9), SkyPoint(x: 13, y: 12)]
        let close = try XCTUnwrap(SkyCamera.framing(cluster, padding: 3, in: size, top: 100, bottom: 100, comparedTo: fit))
        XCTAssertGreaterThan(close.scale, fit.scale * 1.3)
        for p in cluster {
            let at = close.screen(p, in: size)
            XCTAssertGreaterThanOrEqual(at.x, 0); XCTAssertLessThanOrEqual(at.x, size.width)
            XCTAssertGreaterThanOrEqual(at.y, 100); XCTAssertLessThanOrEqual(at.y, size.height - 100)
        }
        // Their middle sits at the middle of the free part of the view.
        let middle = close.screen(SkyPoint(x: 10.5, y: 11.5), in: size)
        XCTAssertEqual(middle.x, size.width / 2, accuracy: 1e-6)
        XCTAssertEqual(middle.y, 100 + (size.height - 200) / 2, accuracy: 1e-6)
        // Stars spread over the sky are hardly closer than the whole sky, so there is nothing to visit.
        XCTAssertNil(SkyCamera.framing([SkyPoint(x: 2, y: 3), SkyPoint(x: 58, y: 88), SkyPoint(x: 30, y: 45)], padding: 3,
                                       in: size, top: 100, bottom: 100, comparedTo: fit))
        XCTAssertNil(SkyCamera.framing([], padding: 3, in: size, comparedTo: fit))
        // A single star is framed no closer than 40 points per spacing.
        let one = try XCTUnwrap(SkyCamera.framing([SkyPoint(x: 5, y: 5)], padding: 1, in: size, comparedTo: fit))
        XCTAssertEqual(one.scale, 40)
    }

    func testClampingKeepsTheCentreInsideTheSky() {
        let sky = layout()
        let far = SkyCamera(center: SkyPoint(x: -50, y: 500), scale: 10).clamped(to: sky)
        XCTAssertEqual(far.center.x, 0)
        XCTAssertEqual(far.center.y, 60)
    }
}

final class SkyHitTests: XCTestCase {
    private let size = CGSize(width: 400, height: 600)

    private func constellation(_ x: Double, _ y: Double, radius: Double) -> SkyLayout.Constellation {
        .init(id: UUID(), courseID: UUID(), topicID: UUID(), name: "c", center: SkyPoint(x: x, y: y), radius: radius, stars: 0..<0, lines: [])
    }

    private func layout(_ cs: [SkyLayout.Constellation]) -> SkyLayout {
        var layout = SkyLayout()
        layout.constellations = cs
        return layout
    }

    func testATapInsideAConstellationFindsIt() {
        let sky = layout([constellation(10, 10, radius: 3), constellation(30, 10, radius: 3)])
        let camera = SkyCamera(center: SkyPoint(x: 20, y: 10), scale: 10)
        let second = camera.screen(SkyPoint(x: 30, y: 10), in: size)
        XCTAssertEqual(SkyHit.constellation(at: second, camera: camera, size: size, layout: sky), 1)
        let first = camera.screen(SkyPoint(x: 10.5, y: 10.5), in: size)
        XCTAssertEqual(SkyHit.constellation(at: first, camera: camera, size: size, layout: sky), 0)
    }

    func testEmptySkyFindsNothing() {
        let sky = layout([constellation(10, 10, radius: 3)])
        let camera = SkyCamera(center: SkyPoint(x: 10, y: 10), scale: 10)
        XCTAssertNil(SkyHit.constellation(at: CGPoint(x: 390, y: 590), camera: camera, size: size, layout: sky))
    }

    func testATinyConstellationStillHasAFingerSizedTarget() {
        // Drawn 4 points across, but a tap 20 points from its middle still finds it; 30 points away doesn't.
        let sky = layout([constellation(10, 10, radius: 1)])
        let camera = SkyCamera(center: SkyPoint(x: 10, y: 10), scale: 2)
        let middle = camera.screen(SkyPoint(x: 10, y: 10), in: size)
        XCTAssertEqual(SkyHit.constellation(at: CGPoint(x: middle.x + 20, y: middle.y), camera: camera, size: size, layout: sky), 0)
        XCTAssertNil(SkyHit.constellation(at: CGPoint(x: middle.x + 30, y: middle.y), camera: camera, size: size, layout: sky))
    }

    func testOverlappingTargetsGoToTheNearerMiddle() {
        let sky = layout([constellation(10, 10, radius: 4), constellation(14, 10, radius: 4)])
        let camera = SkyCamera(center: SkyPoint(x: 12, y: 10), scale: 10)
        let nearSecond = camera.screen(SkyPoint(x: 13, y: 10), in: size)
        XCTAssertEqual(SkyHit.constellation(at: nearSecond, camera: camera, size: size, layout: sky), 1)
        let nearFirst = camera.screen(SkyPoint(x: 11, y: 10), in: size)
        XCTAssertEqual(SkyHit.constellation(at: nearFirst, camera: camera, size: size, layout: sky), 0)
    }
}

/// The plan, the playback and the flare's curves.
final class SkyRenderingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func scene(stability: Double, daysOn: Double) -> (SkyScene, [ItemSnapshot]) {
        let course = SkyCourse(id: StableRandom.uuid("c"), name: "Biology", color: .mint, sortOrder: 0, createdAt: start)
        let topic = TopicSnapshot(id: StableRandom.uuid("t"), courseID: course.id, name: "Meiosis", sortOrder: 0)
        var items: [ItemSnapshot] = []
        for i in 0..<12 {
            var memory = MemoryState.new
            if i < 9 {
                memory = MemoryState(state: .review, stability: stability, difficulty: 5, due: start, lastReview: start, reps: 3)
            }
            items.append(ItemSnapshot(id: StableRandom.uuid("i\(i)"), topicID: topic.id, courseID: course.id, memory: memory,
                                      createdAt: start.addingTimeInterval(Double(i))))
        }
        let layout = SkyEngine.layout(items: items, topics: [topic], courses: [course], exams: [], aspect: 1.5)
        let light = SkyEngine.light(layout, items: items, at: start.addingTimeInterval(daysOn * 86_400))
        return (SkyScene(layout: layout, light: light, courseColors: [course.id: .mint], courseNames: [course.id: "Biology"],
                         examDates: [:], dimSeconds: [0], date: start), items)
    }

    func testThePlanBatchesStarsByStateAndLeavesHollowOnesAlone() {
        let (scene, _) = scene(stability: 30, daysOn: 0)
        let plan = SkyPlan(scene)
        XCTAssertEqual(plan.group.count, 12)
        XCTAssertEqual(plan.group.filter { $0 == SkyPlan.hollow }.count, 3)
        for g in plan.group where g != SkyPlan.hollow {
            XCTAssertLessThan(Int(g), SkyPlan.groupCount)
            let decoded = SkyPlan.decode(Int(g))
            XCTAssertEqual(decoded.color, SkyPlan.colors.firstIndex(of: .mint))
            XCTAssertGreaterThanOrEqual(decoded.step, SkyPlan.dimSteps, "a fresh memory is a bright star")
        }
    }

    func testDimStarsLandInTheDimSteps() {
        let (scene, _) = scene(stability: 1, daysOn: 12)
        let plan = SkyPlan(scene)
        for (i, g) in plan.group.enumerated() where g != SkyPlan.hollow {
            XCTAssertTrue(scene.light.isDim(i))
            XCTAssertLessThan(SkyPlan.decode(Int(g)).step, SkyPlan.dimSteps)
        }
    }

    func testStepsSplitAtTheDimEdge() {
        let edge = SkyEngine.brightness(recall: ReviewOutcome.fadingRecall)
        XCTAssertEqual(SkyPlan.step(brightness: edge - 0.001, dim: true), SkyPlan.dimSteps - 1)
        XCTAssertEqual(SkyPlan.step(brightness: edge, dim: false), SkyPlan.dimSteps)
        XCTAssertEqual(SkyPlan.step(brightness: 1, dim: false), SkyPlan.steps - 1)
        XCTAssertEqual(SkyPlan.step(brightness: 0, dim: true), 0)
    }

    func testGroupsDecodeWhatTheyEncode() {
        for ci in 0..<SkyPlan.colors.count {
            for step in 0..<SkyPlan.steps {
                for restless in 0...1 {
                    for phase in 0..<3 {
                        let g = ((ci * SkyPlan.steps + step) * 2 + restless) * 3 + phase
                        let d = SkyPlan.decode(g)
                        XCTAssertEqual([d.color, d.step, d.restless ? 1 : 0, d.phase], [ci, step, restless, phase])
                    }
                }
            }
        }
    }

    func testRestlessStarsFlutterAndSteadyOnesBreathe() {
        // Steady: within ±7% of full, and the same across the three phases' average.
        for t in stride(from: 0.0, to: 8.0, by: 0.37) {
            for phase in 0..<3 {
                XCTAssertEqual(SkyRenderer.twinkle(phase: phase, restless: false, time: t, animated: true), 1, accuracy: 0.071)
                let r = SkyRenderer.twinkle(phase: phase, restless: true, time: t, animated: true)
                XCTAssertGreaterThanOrEqual(r, 0.69)
                XCTAssertLessThanOrEqual(r, 1.0)
            }
        }
        // Still: no change over time, and a restless star is a little dimmer than a steady one.
        XCTAssertEqual(SkyRenderer.twinkle(phase: 1, restless: false, time: 3, animated: false), 1)
        XCTAssertEqual(SkyRenderer.twinkle(phase: 1, restless: true, time: 3, animated: false), 0.86)
        XCTAssertEqual(SkyRenderer.twinkle(phase: 1, restless: true, time: 9, animated: false), 0.86)
    }

    func testPlaybackIgnitesEveryRelitStarOnceInOrder() {
        let (scene, items) = scene(stability: 30, daysOn: 0)
        let ids = items.prefix(5).map(\.id)
        let relight = SkyRelight(relit: Set(ids), lit: [], saved: [ids[0]], from: Dictionary(uniqueKeysWithValues: ids.map { ($0, 0.2) }))
        let playback = SkyPlayback(start: 10, relight: relight, layout: scene.layout)
        let playing = scene.layout.stars.indices.filter { playback.isPlaying($0, at: 10) }
        XCTAssertEqual(Set(playing.map { scene.layout.stars[$0].id }), Set(ids))
        XCTAssertEqual(playback.progress(playing[0], at: 9), 0, "not started")
        XCTAssertEqual(playback.progress(playing[0], at: 10 + SkyPlayback.igniteSeconds + 0.1), 1, "finished")
        XCTAssertFalse(playback.isDone(at: 10))
        XCTAssertTrue(playback.isDone(at: playback.end))
        // They light in order: at any moment an earlier star is at least as far along as a later one.
        for t in stride(from: 10.0, through: playback.end, by: 0.2) {
            let progress = playing.map { playback.progress($0, at: t) }
            XCTAssertEqual(progress, progress.sorted(by: >), "at \(t)")
        }
        // A star that isn't in the relight never plays.
        let other = scene.layout.stars.indices.first { !playing.contains($0) }!
        XCTAssertFalse(playback.isPlaying(other, at: 10))
    }

    func testTheFlaresCurves() {
        XCTAssertEqual(SkyFlareView.bloom(0), 0, accuracy: 1e-9)
        XCTAssertEqual(SkyFlareView.bloom(0.32), 1, accuracy: 1e-9)
        XCTAssertEqual(SkyFlareView.bloom(0.9), 1)
        let peak = stride(from: 0.0, through: 0.32, by: 0.01).map(SkyFlareView.bloom).max()!
        XCTAssertGreaterThan(peak, 1.0, "a little overshoot")
        XCTAssertLessThan(peak, 1.25, "but a gentle one")
        XCTAssertEqual(SkyFlareView.fade(0.5), 1)
        XCTAssertEqual(SkyFlareView.fade(SkyFlareView.duration), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(SkyFlareView.fade(0.9), 0)
    }
}

/// What the screen and VoiceOver say.
final class SkyCopyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func scene() -> SkyScene {
        let course = SkyCourse(id: StableRandom.uuid("c"), name: "Biology 101", color: .mint, sortOrder: 0, createdAt: start)
        let topic = TopicSnapshot(id: StableRandom.uuid("t"), courseID: course.id, name: "Meiosis", sortOrder: 0)
        var items: [ItemSnapshot] = []
        for i in 0..<8 {
            var memory = MemoryState.new
            if i < 5 {
                // Three fresh, two fading by the time we look.
                memory = MemoryState(state: .review, stability: i < 3 ? 40 : 1, difficulty: 5, due: start, lastReview: start, reps: 3)
            }
            items.append(ItemSnapshot(id: StableRandom.uuid("i\(i)"), topicID: topic.id, courseID: course.id, memory: memory,
                                      createdAt: start.addingTimeInterval(Double(i))))
        }
        let layout = SkyEngine.layout(items: items, topics: [topic], courses: [course], exams: [], aspect: 1)
        let light = SkyEngine.light(layout, items: items, at: start.addingTimeInterval(10 * 86_400))
        return SkyScene(layout: layout, light: light, courseColors: [course.id: .mint], courseNames: [course.id: "Biology 101"],
                        examDates: [:], dimSeconds: [43], date: start)
    }

    func testTheSkyIsSummarisedForVoiceOver() {
        let s = scene()
        let text = SkyCopy.summary(s)
        XCTAssertTrue(text.contains("8"), text)
        XCTAssertTrue(text.contains("1"), text)
        XCTAssertTrue(text.contains("3 bright"), text)
        XCTAssertTrue(text.contains("2 dim"), text)
        XCTAssertTrue(text.contains("3 not yet lit"), text)
        XCTAssertEqual(s.brightCount + s.dimCount + s.hollowCount, s.starCount)
    }

    func testAnEmptySkySaysHowToFillIt() {
        let empty = SkyScene(layout: .empty, light: SkyLight(), courseColors: [:], courseNames: [:], examDates: [:], dimSeconds: [], date: start)
        XCTAssertTrue(SkyCopy.summary(empty).contains("empty"))
        XCTAssertTrue(empty.isEmpty)
    }

    func testAConstellationIsDescribedByNameCourseAndState() {
        let text = SkyCopy.label(0, in: scene())
        XCTAssertTrue(text.hasPrefix("Meiosis, Biology 101."), text)
        XCTAssertTrue(text.contains("3 of 8 stars bright"), text)
        XCTAssertTrue(text.contains("2 dim"), text)
        XCTAssertTrue(text.contains("3 not yet lit"), text)
        XCTAssertTrue(text.contains("Recall about"), text)
    }

    func testTheDetailLineSaysHowAConstellationIsDoing() {
        XCTAssertEqual(SkyCopy.detail(0, in: scene()), "3 of 8 bright · 2 dim · 3 not yet lit")
    }

    func testMinutesToRelightFollowTheDimStarsAndStayInRange() {
        var s = scene()
        s.dimSeconds = [0]
        XCTAssertEqual(s.minutesToRelight(0), 3, "nothing dim: a short practice round")
        s.dimSeconds = [45]
        XCTAssertEqual(s.minutesToRelight(0), 2, "at least two minutes")
        s.dimSeconds = [250]
        XCTAssertEqual(s.minutesToRelight(0), 5, "rounded up")
        s.dimSeconds = [5000]
        XCTAssertEqual(s.minutesToRelight(0), 15, "at most fifteen")
        XCTAssertEqual(s.minutesToRelight(9), 3, "no such constellation")
    }
}

/// The sky drawn for real: images from the renderer, checked for what they must contain.
@MainActor
final class SkyImageTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func scene(courses: Int = 2, perCourse: Int = 30, daysOn: Double = 0) -> SkyScene {
        var items: [ItemSnapshot] = [], topics: [TopicSnapshot] = [], courseList: [SkyCourse] = []
        for c in 0..<courses {
            let course = SkyCourse(id: StableRandom.uuid("c\(c)"), name: "Course \(c)", color: CourseColor.allCases[c], sortOrder: c, createdAt: start)
            courseList.append(course)
            for t in 0..<3 {
                let topic = TopicSnapshot(id: StableRandom.uuid("t\(c)\(t)"), courseID: course.id, name: "Topic \(t)", sortOrder: t)
                topics.append(topic)
                for i in 0..<(perCourse / 3) {
                    let id = StableRandom.uuid("i\(c)\(t)\(i)")
                    let memory = i % 5 == 0 ? MemoryState.new
                        : MemoryState(state: .review, stability: 3 + Double(i % 7) * 4, difficulty: 5, due: start, lastReview: start, reps: 3)
                    items.append(ItemSnapshot(id: id, topicID: topic.id, courseID: course.id, memory: memory,
                                              createdAt: start.addingTimeInterval(Double(i))))
                }
            }
        }
        let layout = SkyEngine.layout(items: items, topics: topics, courses: courseList, exams: [], aspect: 1.4)
        let light = SkyEngine.light(layout, items: items, at: start.addingTimeInterval(daysOn * 86_400))
        return SkyScene(layout: layout, light: light, courseColors: Dictionary(uniqueKeysWithValues: courseList.map { ($0.id, $0.color) }),
                        courseNames: Dictionary(uniqueKeysWithValues: courseList.map { ($0.id, $0.name) }), examDates: [:],
                        dimSeconds: Array(repeating: 0, count: layout.constellations.count), date: start)
    }

    private func image<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 560)) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    /// RGBA bytes of an image.
    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// How many pixels are much brighter than the night behind them.
    private func litPixels(_ image: CGImage, above level: Int = 120) -> Int {
        let p = pixels(image)
        var n = 0
        for i in stride(from: 0, to: p.count, by: 4) where Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) > level * 3 / 1 { n += 1 }
        return n
    }

    func testAStarFieldIsDrawnOnTheNight() throws {
        let picture = try image(SkyStill(scene: scene()))
        XCTAssertEqual(picture.width, 390)
        XCTAssertGreaterThan(litPixels(picture), 40, "bright stars are on the picture")
        // The corners are the night colour: dark, and the top is darker than the bottom.
        let p = pixels(picture)
        func sum(_ x: Int, _ y: Int) -> Int { let i = (y * picture.width + x) * 4; return Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) }
        XCTAssertLessThan(sum(2, 2), 120)
        XCTAssertLessThan(sum(2, 2), sum(2, picture.height - 3))
    }

    func testAnEmptySkyIsOnlyTheNight() throws {
        let empty = SkyScene(layout: .empty, light: SkyLight(), courseColors: [:], courseNames: [:], examDates: [:], dimSeconds: [], date: start)
        XCTAssertEqual(litPixels(try image(SkyStill(scene: empty))), 0)
    }

    func testEveryStarOfAManyStarSkyIsHandledQuickly() throws {
        let big = scene(courses: 6, perCourse: 900)
        XCTAssertGreaterThan(big.starCount, 5_000)
        let clock = ContinuousClock()
        var picture: CGImage?
        let took = try clock.measure { picture = try image(SkyStill(scene: big), size: CGSize(width: 390, height: 800)) }
        XCTAssertGreaterThan(litPixels(try XCTUnwrap(picture)), 500)
        XCTAssertLessThan(took, .seconds(8), "an unoptimized debug build, drawn on the CPU")
    }

    func testFocusDimsTheConstellationsThatAreNotFocused() throws {
        let s = scene()
        let plain = pixels(try image(SkyStill(scene: s)))
        let focused = pixels(try image(SkyStill(scene: s, focus: 0)))
        let focusedStars = s.layout.constellations[0].stars
        // Add up the brightness of the picture; with a constellation focused the rest fades, so it is darker overall.
        func total(_ p: [UInt8]) -> Int { stride(from: 0, to: p.count, by: 4).reduce(0) { $0 + Int(p[$1]) + Int(p[$1 + 1]) + Int(p[$1 + 2]) } }
        XCTAssertGreaterThan(focusedStars.count, 0)
        XCTAssertLessThan(total(focused), total(plain))
    }

    func testDifferentiateWithoutColorChangesThePicture() throws {
        let s = scene()
        let plain = pixels(try image(SkyStill(scene: s)))
        let marked = pixels(try image(SkyStill(scene: s, differentiate: true)))
        XCTAssertNotEqual(plain, marked, "bright stars carry a cross")
    }

    func testTheNightSkyOfTheWelcomeScreenIsDrawnWithTheSkysStars() throws {
        // At a fixed moment (the stars breathe with the clock), the same stars are drawn the same way every time.
        func still() -> some View {
            Canvas { g, size in NightSky.draw(&g, size: size, count: 14, depth: 0.72, time: 0, animated: false) }
                .background(CLColor.night)
        }
        let size = CGSize(width: 300, height: 400)
        let picture = try image(still(), size: size)
        XCTAssertGreaterThan(litPixels(picture, above: 90), 20, "bright stars are on the picture")
        XCTAssertEqual(pixels(picture), pixels(try image(still(), size: size)))
        // The live view draws too.
        XCTAssertGreaterThan(litPixels(try image(NightSky(count: 14).background(CLColor.night), size: size), above: 90), 10)
        // Their places are the prototype's scatter.
        let first = NightSky.position(0, depth: 0.72), second = NightSky.position(1, depth: 0.72)
        XCTAssertEqual(first.x, 0.11, accuracy: 1e-9)
        XCTAssertEqual(second.x, 0.48, accuracy: 1e-9)
    }
}
