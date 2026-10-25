import SwiftUI
import XCTest
@testable import Cramless

/// Smaller pictures cut from the sky (an exam's region, a constellation's glyph), the heatmap's stars, the sparkle,
/// and what the renderer lights: Phase 5's pieces, tested without a screen where they can be.
final class SkyDerivedTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private struct World {
        var items: [ItemSnapshot]
        var topics: [TopicSnapshot]
        var courses: [SkyCourse]
        var exams: [ExamSnapshot]
    }

    /// Two courses of three topics. An exam on the first course's first two topics, and one whose scope has nothing in
    /// it (no region). In each topic two items are fresh, two are fading and two were never studied.
    private func world(perTopic: Int = 6) -> World {
        var items: [ItemSnapshot] = [], topics: [TopicSnapshot] = [], courses: [SkyCourse] = []
        for c in 0..<2 {
            let course = SkyCourse(id: StableRandom.uuid("c\(c)"), name: "Course \(c)", color: CourseColor.allCases[c], sortOrder: c,
                                   createdAt: start)
            courses.append(course)
            for t in 0..<3 {
                let topic = TopicSnapshot(id: StableRandom.uuid("t\(c)\(t)"), courseID: course.id, name: "Topic \(c)\(t)", sortOrder: t)
                topics.append(topic)
                for i in 0..<perTopic {
                    var memory = MemoryState.new
                    if i % 3 != 2 {
                        memory = MemoryState(state: .review, stability: i % 3 == 0 ? 40 : 1, difficulty: 5, due: start, lastReview: start, reps: 3)
                    }
                    items.append(ItemSnapshot(id: StableRandom.uuid("i\(c)\(t)\(i)"), topicID: topic.id, courseID: course.id, memory: memory,
                                              createdAt: start.addingTimeInterval(Double(i))))
                }
            }
        }
        let exams = [
            ExamSnapshot(id: StableRandom.uuid("e0"), courseID: courses[0].id, title: "Exam 0", date: start,
                         scope: [topics[0].id, topics[1].id]),
            ExamSnapshot(id: StableRandom.uuid("e-empty"), courseID: courses[1].id, title: "Nothing", date: start,
                         scope: [StableRandom.uuid("no-such-topic")]),
        ]
        return World(items: items, topics: topics, courses: courses, exams: exams)
    }

    /// The sky a month after everything was last reviewed: the stable memories still shine, the weak ones have faded.
    /// (FSRS forgets slowly: a memory that lasts a day is still about 70% at nine days, and 59% at thirty.)
    private func scene(_ w: World, daysOn: Double = 30) -> SkyScene {
        let layout = SkyEngine.layout(items: w.items, topics: w.topics, courses: w.courses, exams: w.exams, aspect: 1)
        let light = SkyEngine.light(layout, items: w.items, at: start.addingTimeInterval(daysOn * 86_400))
        return SkyScene(layout: layout, light: light, courseColors: Dictionary(uniqueKeysWithValues: w.courses.map { ($0.id, $0.color) }),
                        courseNames: Dictionary(uniqueKeysWithValues: w.courses.map { ($0.id, $0.name) }), examDates: [:],
                        dimSeconds: Array(repeating: 0, count: layout.constellations.count), date: start)
    }

    /// Three constellations, A, B and C, by hand. The exam covers A and C. B is not in it, but its stars sit in the
    /// middle of the exam's circle, which is the case a test of "is it inside the circle" gets wrong.
    private func handmade() -> (scene: SkyScene, examID: UUID, course: UUID) {
        let course = StableRandom.uuid("hm-course"), examID = StableRandom.uuid("hm-exam")
        func star(_ name: String, _ x: Double, _ y: Double, in constellation: Int) -> SkyLayout.Star {
            SkyLayout.Star(id: StableRandom.uuid(name), point: SkyPoint(x: x, y: y), constellation: constellation)
        }
        func constellation(_ name: String, _ index: Int, at center: SkyPoint) -> SkyLayout.Constellation {
            let first = 3 * index
            return SkyLayout.Constellation(id: StableRandom.uuid("hm-topic-\(name)"), courseID: course, topicID: StableRandom.uuid("hm-topic-\(name)"),
                                           name: name, center: center, radius: 2.5, stars: first..<(first + 3),
                                           lines: [.init(a: first, b: first + 1), .init(a: first + 1, b: first + 2)])
        }
        var layout = SkyLayout()
        layout.stars = [
            star("a0", 4, 10, in: 0), star("a1", 6, 8, in: 0), star("a2", 6, 12, in: 0),
            star("b0", 10, 10, in: 1), star("b1", 11, 10, in: 1), star("b2", 10, 11, in: 1),
            star("c0", 14, 9, in: 2), star("c1", 15, 11, in: 2), star("c2", 14, 12, in: 2),
        ]
        layout.constellations = [constellation("A", 0, at: SkyPoint(x: 5.3, y: 10)), constellation("B", 1, at: SkyPoint(x: 10.3, y: 10.3)),
                                 constellation("C", 2, at: SkyPoint(x: 14.3, y: 10.7))]
        layout.regions = [SkyLayout.Region(examID: examID, courseID: course, title: "Exam", center: SkyPoint(x: 10, y: 10), radius: 7.5,
                                           covers: [0, 2])]
        layout.width = 20
        layout.height = 20
        var light = SkyLight()
        for i in 0..<9 {
            light.recall.append(0.5 + 0.05 * Double(i))
            light.brightness.append(0.1 * Double(i))
            light.hollow.append(i == 4)
            light.flicker.append(0)
        }
        let scene = SkyScene(layout: layout, light: light, courseColors: [course: .mint], courseNames: [course: "Course"], examDates: [:],
                             dimSeconds: [0, 0, 0], date: start)
        return (scene, examID, course)
    }

    // MARK: An exam's region

    func testARegionCoversItsOwnConstellationsEvenWhenAnotherSitsInsideTheCircle() throws {
        let (sky, examID, _) = handmade()
        let region = try XCTUnwrap(sky.region(of: examID))
        XCTAssertEqual(region.layout.constellations.map(\.name), ["A", "C"], "B is inside the circle, not in the exam")
        XCTAssertEqual(region.starCount, 6)
        XCTAssertEqual(region.layout.regions.map(\.covers), [[0, 1]], "renumbered for the smaller sky")
        XCTAssertEqual(region.layout.constellations.map(\.stars), [0..<3, 3..<6])
        XCTAssertEqual(region.layout.constellations[1].lines, [.init(a: 3, b: 4), .init(a: 4, b: 5)], "lines follow their stars")
        // Nothing moved relative to anything else: the circle's middle is now the square's middle.
        XCTAssertEqual(region.layout.regions[0].center, SkyPoint(x: 7.5, y: 7.5))
        XCTAssertEqual(region.layout.stars[0].point, SkyPoint(x: 1.5, y: 7.5), "a0 was (4, 10)")
        XCTAssertEqual(region.layout.stars[3].point, SkyPoint(x: 11.5, y: 6.5), "c0 was (14, 9)")
        XCTAssertEqual(region.layout.width, 15)
        XCTAssertEqual(region.layout.height, 15)
        // Each star keeps its own light: c0 was the seventh star of nine.
        XCTAssertEqual(region.light.recall[3], sky.light.recall[6])
        XCTAssertEqual(region.light.brightness[3], sky.light.brightness[6])
        XCTAssertEqual(region.light.hollow, [false, false, false, false, false, false])
        XCTAssertEqual(sky.light.hollow[4], true, "b1 is the unlit one, and it was left out")
    }

    func testTheRendererLightsWhatTheRegionCoversNotWhatSitsInsideIt() throws {
        let (sky, examID, _) = handmade()
        let lit = try XCTUnwrap(SkyRenderer.litConstellations(frame(sky, litRegion: examID)))
        XCTAssertEqual(lit, [true, false, true])
        // B's middle is nearer the circle's middle than A's or C's, so a test of position would have lit it.
        let region = sky.layout.regions[0]
        let near = sky.layout.constellations.map { $0.center.distance(to: region.center) }
        XCTAssertLessThan(near[1], near[0])
        XCTAssertLessThan(near[1], near[2])
    }

    func testARegionOfTheGeneratedSkyHoldsExactlyItsExamsTopicsInASquare() throws {
        let w = world()
        let sky = scene(w)
        let examID = w.exams[0].id
        let region = try XCTUnwrap(sky.region(of: examID))
        let original = try XCTUnwrap(sky.layout.regions.first { $0.examID == examID })

        XCTAssertEqual(Set(region.layout.constellations.compactMap(\.topicID)), [StableRandom.uuid("t00"), StableRandom.uuid("t01")])
        XCTAssertEqual(region.layout.constellations.count, 2, "the course's third topic is not in the exam")
        XCTAssertEqual(region.starCount, 12)
        XCTAssertEqual(region.layout.width, 2 * original.radius, accuracy: 1e-9)
        XCTAssertEqual(region.layout.height, region.layout.width)
        XCTAssertEqual(region.layout.regions.count, 1)
        let r = original.radius
        XCTAssertEqual(region.layout.regions[0].center.x, r, accuracy: 1e-9)
        XCTAssertEqual(region.layout.regions[0].center.y, r, accuracy: 1e-9)
        XCTAssertEqual(region.layout.regions[0].radius, r)
        for star in region.layout.stars {
            XCTAssertLessThanOrEqual(star.point.distance(to: SkyPoint(x: r, y: r)), r + 1e-9, "inside the circle")
        }
    }

    func testARegionRecordsTheConstellationsItsExamCoversAndOnlyThose() throws {
        let w = world()
        let sky = scene(w)
        let region = try XCTUnwrap(sky.layout.regions.first { $0.examID == w.exams[0].id })
        let covered = region.covers.map { sky.layout.constellations[$0] }
        XCTAssertEqual(Set(covered.compactMap(\.topicID)), [StableRandom.uuid("t00"), StableRandom.uuid("t01")])
        XCTAssertEqual(region.covers, region.covers.sorted(), "in layout order")
        for c in covered { XCTAssertEqual(c.courseID, w.courses[0].id) }
        // An exam with no scope covers the whole course.
        var whole = w
        whole.exams = [ExamSnapshot(id: StableRandom.uuid("e-all"), courseID: w.courses[1].id, title: "All", date: start, scope: [])]
        let all = scene(whole)
        XCTAssertEqual(all.layout.regions.first?.covers.count, 3)
    }

    func testARegionKeepsEachStarsLightAndItsLines() throws {
        let w = world()
        let sky = scene(w)
        let region = try XCTUnwrap(sky.region(of: w.exams[0].id))
        let byID = Dictionary(uniqueKeysWithValues: sky.layout.stars.enumerated().map { ($1.id, $0) })
        for (i, star) in region.layout.stars.enumerated() {
            let was = try XCTUnwrap(byID[star.id])
            XCTAssertEqual(region.light.brightness[i], sky.light.brightness[was])
            XCTAssertEqual(region.light.hollow[i], sky.light.hollow[was])
            XCTAssertEqual(region.light.recall[i], sky.light.recall[was])
            XCTAssertTrue(region.layout.constellations[star.constellation].stars.contains(i))
        }
        for c in region.layout.constellations {
            let original = try XCTUnwrap(sky.layout.constellations.first { $0.id == c.id })
            XCTAssertEqual(c.lines.count, original.lines.count)
            for line in c.lines {
                XCTAssertTrue(c.stars.contains(line.a) && c.stars.contains(line.b), "a line joins stars of its own constellation")
            }
        }
        XCTAssertEqual(region.courseColors, sky.courseColors)
    }

    func testAnExamWithNothingStudiedInItsScopeHasNoRegion() {
        let w = world()
        let sky = scene(w)
        XCTAssertNil(sky.region(of: w.exams[1].id))
        XCTAssertNil(sky.region(of: UUID()))
        XCTAssertNil(SkyScene.empty.region(of: w.exams[0].id))
    }

    // MARK: A constellation's glyph

    func testAGlyphFitsTheUnitSquareCentredAndKeepsItsShape() throws {
        let sky = scene(world())
        for index in sky.layout.constellations.indices {
            let c = sky.layout.constellations[index]
            let glyph = try XCTUnwrap(sky.glyph(of: index))
            XCTAssertEqual(glyph.stars.count, c.stars.count)
            XCTAssertEqual(glyph.lines.count, c.lines.count)
            let xs = glyph.stars.map(\.x), ys = glyph.stars.map(\.y)
            for v in xs + ys {
                XCTAssertGreaterThanOrEqual(v, 0.14 - 1e-9)
                XCTAssertLessThanOrEqual(v, 0.86 + 1e-9)
            }
            XCTAssertEqual((xs.min()! + xs.max()!) / 2, 0.5, accuracy: 1e-9, "centred across")
            XCTAssertEqual((ys.min()! + ys.max()!) / 2, 0.5, accuracy: 1e-9, "and down")
            // The longer side spans all the room; the shape is the constellation's own.
            XCTAssertEqual(max(xs.max()! - xs.min()!, ys.max()! - ys.min()!), 0.72, accuracy: 1e-9)
            let original = c.stars.map { sky.layout.stars[$0].point }
            let width = original.map(\.x).max()! - original.map(\.x).min()!
            let height = original.map(\.y).max()! - original.map(\.y).min()!
            XCTAssertEqual((xs.max()! - xs.min()!) * height, (ys.max()! - ys.min()!) * width, accuracy: 1e-9, "same proportions")
            for line in glyph.lines { XCTAssertTrue(glyph.stars.indices.contains(line.a) && glyph.stars.indices.contains(line.b)) }
        }
    }

    func testAGlyphCountsMatchTheSkysLight() throws {
        let sky = scene(world())
        var checked = 0
        for index in sky.layout.constellations.indices {
            let c = sky.layout.constellations[index]
            let counts = try XCTUnwrap(sky.glyph(of: index)).counts
            XCTAssertEqual(counts.bright, sky.light.brightCount(c))
            XCTAssertEqual(counts.dim, sky.light.dimCount(c))
            XCTAssertEqual(counts.hollow, c.stars.filter { sky.light.hollow[$0] }.count)
            XCTAssertEqual(counts.bright + counts.dim + counts.hollow, c.stars.count, "every star is one of the three")
            checked += 1
        }
        XCTAssertEqual(checked, 6)
        // A month on: of each topic's six items two are stable, two have faded, two were never studied.
        let first = try XCTUnwrap(sky.glyph(of: 0)).counts
        XCTAssertEqual([first.bright, first.dim, first.hollow], [2, 2, 2])
    }

    func testAGlyphOfOneStarSitsInTheMiddleAndOutOfRangeHasNone() throws {
        var w = world(perTopic: 1)
        w.exams = []
        let sky = scene(w)
        let glyph = try XCTUnwrap(sky.glyph(of: 0))
        XCTAssertEqual(glyph.stars.count, 1)
        XCTAssertEqual(glyph.stars[0].x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(glyph.stars[0].y, 0.5, accuracy: 1e-9)
        XCTAssertNil(sky.glyph(of: 99))
        XCTAssertNil(sky.glyph(of: -1))
    }

    // MARK: The heatmap's stars

    func testHeatmapStarsGrowAndBrightenWithTheMinutes() throws {
        let marks = try (1...4).map { try XCTUnwrap(ProgressPresentation.starMark(.level($0))) }
        for (a, b) in zip(marks, marks.dropFirst()) {
            XCTAssertLessThan(a.size, b.size)
            XCTAssertLessThan(a.opacity, b.opacity)
        }
        XCTAssertEqual(marks.map(\.shape), [.dot, .dot, .sparkle, .sparkle], "a sparkle from the third step")
        XCTAssertEqual(marks.map(\.glow), [false, false, false, true], "a glow only at the top")
        XCTAssertEqual(marks[3].size, 1)
        let empty = try XCTUnwrap(ProgressPresentation.starMark(.empty))
        XCTAssertLessThan(empty.size, marks[0].size, "an unstudied day is the smallest dot")
        XCTAssertEqual(empty.shape, .dot)
        XCTAssertEqual(try XCTUnwrap(ProgressPresentation.starMark(.frozen)).shape, .dot)
        XCTAssertNil(ProgressPresentation.starMark(.future), "a day to come is a faint ring")
    }

    func testEveryHeatmapStepDiffersInSizeNotJustColour() throws {
        let steps: [ProgressPresentation.CellStyle] = [.empty, .level(1), .level(2), .level(3), .level(4)]
        let sizes = try steps.map { try XCTUnwrap(ProgressPresentation.starMark($0)).size }
        XCTAssertEqual(Set(sizes).count, sizes.count, "no two steps are the same size")
        XCTAssertEqual(sizes, sizes.sorted(), "and they only grow")
    }

    // MARK: The sparkle

    func testTheSparkleIsAFourPointStarFillingTheShorterSide() {
        let path = SparkleShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 60))
        XCTAssertEqual(path.boundingRect.height, 60, accuracy: 1e-6)
        XCTAssertEqual(path.boundingRect.width, 60, accuracy: 1e-6)
        XCTAssertEqual(path.boundingRect.midX, 50, accuracy: 1e-6, "centred")
        var points: [CGPoint] = []
        var closes = 0
        path.forEach { element in
            switch element {
            case .move(let p), .line(let p): points.append(p)
            case .closeSubpath: closes += 1
            default: break
            }
        }
        XCTAssertEqual(points.count, 8)
        XCTAssertEqual(closes, 1)
        let centre = CGPoint(x: 50, y: 30)
        for (i, p) in points.enumerated() {
            XCTAssertEqual(hypot(p.x - centre.x, p.y - centre.y), i % 2 == 0 ? 30 : 30 * 0.36, accuracy: 1e-6, "point \(i)")
        }
        XCTAssertEqual(points[0].y, 0, accuracy: 1e-6, "the first point is the top")
    }

    // MARK: What the renderer lights

    private func frame(_ sky: SkyScene, focus: Int? = nil, litRegion: UUID? = nil, recede: Double = 0.32) -> SkyFrame {
        SkyFrame(scene: sky, plan: SkyPlan(sky), camera: SkyCamera.fit(sky.layout, in: CGSize(width: 300, height: 300)), time: 0,
                 animated: false, differentiate: false, focus: focus, litRegion: litRegion, recede: recede, playback: nil, labels: false)
    }

    func testFocusLightsOneConstellationAndAnExamsRegionLightsItsOwn() throws {
        let w = world()
        let sky = scene(w)
        XCTAssertNil(SkyRenderer.litConstellations(frame(sky)), "nothing focused: every star shines")
        let focused = try XCTUnwrap(SkyRenderer.litConstellations(frame(sky, focus: 2)))
        XCTAssertEqual(focused.enumerated().filter(\.element).map(\.offset), [2])

        let examID = w.exams[0].id
        let lit = try XCTUnwrap(SkyRenderer.litConstellations(frame(sky, litRegion: examID)))
        let litTopics = Set(sky.layout.constellations.enumerated().filter { lit[$0.offset] }.compactMap(\.element.topicID))
        XCTAssertEqual(litTopics, [StableRandom.uuid("t00"), StableRandom.uuid("t01")])
        XCTAssertEqual(lit.count, sky.layout.constellations.count)
        XCTAssertNil(SkyRenderer.litConstellations(frame(sky, litRegion: UUID())), "no such region: nothing is dimmed")
        // A focus wins over a region, and one that doesn't exist falls through to it.
        XCTAssertEqual(try XCTUnwrap(SkyRenderer.litConstellations(frame(sky, focus: 0, litRegion: examID))).filter { $0 }.count, 1)
        XCTAssertEqual(try XCTUnwrap(SkyRenderer.litConstellations(frame(sky, focus: 99, litRegion: examID))).filter { $0 }.count, 2)
    }
}

/// The renderer's pictures: a region lit with the rest hidden, the outline sky, a region's still and a glyph.
@MainActor
final class SkyPictureTests: XCTestCase {
    private let size = CGSize(width: 300, height: 300)

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func image<V: View>(_ view: V, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    /// The pixels whose red, green and blue add up to more than `level` and that `inside` accepts, by (x, y).
    private func bright(_ image: CGImage, above level: Int = 330, where inside: (Int, Int) -> Bool = { _, _ in true }) -> Int {
        let p = pixels(image)
        var n = 0
        for y in 0..<image.height {
            for x in 0..<image.width where inside(x, y) {
                let i = (y * image.width + x) * 4
                if Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) > level { n += 1 }
            }
        }
        return n
    }

    /// Six topics of nine fresh items, and an exam on the first two.
    private func world() -> (SkyScene, UUID) {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var items: [ItemSnapshot] = [], topics: [TopicSnapshot] = []
        let course = SkyCourse(id: StableRandom.uuid("c"), name: "C", color: .mint, sortOrder: 0, createdAt: start)
        for t in 0..<6 {
            let topic = TopicSnapshot(id: StableRandom.uuid("t\(t)"), courseID: course.id, name: "T\(t)", sortOrder: t)
            topics.append(topic)
            for i in 0..<9 {
                items.append(ItemSnapshot(id: StableRandom.uuid("i\(t)-\(i)"), topicID: topic.id, courseID: course.id,
                                          memory: MemoryState(state: .review, stability: 60, difficulty: 5, due: start, lastReview: start, reps: 3),
                                          createdAt: start.addingTimeInterval(Double(i))))
            }
        }
        let exam = ExamSnapshot(id: StableRandom.uuid("e"), courseID: course.id, title: "E", date: start, scope: [topics[0].id, topics[1].id])
        let layout = SkyEngine.layout(items: items, topics: topics, courses: [course], exams: [exam], aspect: 1)
        let light = SkyEngine.light(layout, items: items, at: start)
        return (SkyScene(layout: layout, light: light, courseColors: [course.id: .mint], courseNames: [course.id: "C"], examDates: [:],
                         dimSeconds: Array(repeating: 0, count: layout.constellations.count), date: start), exam.id)
    }

    private func sky(_ scene: SkyScene, litRegion: UUID?, recede: Double) -> some View {
        Canvas { g, s in
            SkyRenderer.draw(&g, size: s, frame: SkyFrame(
                scene: scene, plan: SkyPlan(scene), camera: SkyCamera.fit(scene.layout, in: s), time: 0, animated: false,
                differentiate: false, focus: nil, litRegion: litRegion, recede: recede, playback: nil, labels: false))
        }
        .background(Color(hex: 0x070D1B))
    }

    func testWithTheRestHiddenNothingOutsideTheRegionIsDrawn() throws {
        let (scene, examID) = world()
        let region = try XCTUnwrap(scene.layout.regions.first { $0.examID == examID })
        let camera = SkyCamera.fit(scene.layout, in: size)
        let middle = camera.screen(region.center, in: size)
        let mx = Double(middle.x), my = Double(middle.y)
        let reach = Double(region.radius) * Double(camera.scale)
        let outside: (Int, Int) -> Bool = { x, y in hypot(Double(x) - mx, Double(y) - my) > reach + 4 }

        let shown = try image(sky(scene, litRegion: examID, recede: 0.32), size: size)
        let hidden = try image(sky(scene, litRegion: examID, recede: 0), size: size)
        let everything = try image(sky(scene, litRegion: nil, recede: 1), size: size)
        XCTAssertGreaterThan(bright(everything, where: outside), 40, "the whole sky has stars outside the circle")
        XCTAssertGreaterThan(bright(shown, above: 150, where: outside), 0, "dimmed, they are still there")
        XCTAssertEqual(bright(hidden, where: outside), 0, "hidden, they are gone")
        XCTAssertGreaterThan(bright(hidden, where: { x, y in !outside(x, y) }), 15, "the region itself still shines")
    }

    func testTheOutlineSkyDrawsRingsBelowTheTitleAndNothingAboveIt() throws {
        let top = 100.0
        func outline() throws -> CGImage {
            try image(Canvas { g, s in
                SkyRenderer.drawOutline(&g, size: s, top: top, bottom: 20, time: 0, animated: false)
            }.background(Color(hex: 0x0B1426)), size: CGSize(width: 390, height: 300))
        }
        let picture = try outline()
        XCTAssertGreaterThan(bright(picture, above: 170), 60, "the rings")
        XCTAssertEqual(bright(picture, above: 120, where: { _, y in Double(y) < top - 6 }), 0, "the title's room stays clear")
        XCTAssertEqual(pixels(picture), pixels(try outline()), "the same every time")
    }

    func testARegionStillAndAGlyphAreDrawn() throws {
        let (scene, examID) = world()
        let region = try XCTUnwrap(scene.region(of: examID))
        let still = try image(SkyRegionStill(scene: region), size: CGSize(width: 96, height: 96))
        XCTAssertGreaterThan(bright(still, above: 250), 10, "the region's stars")
        let glyph = try XCTUnwrap(scene.glyph(of: 0))
        let tile = try image(SkyGlyphView(glyph: glyph, size: 60), size: CGSize(width: 60, height: 60))
        XCTAssertGreaterThan(bright(tile, above: 250), 6, "the constellation's stars")
    }
}

/// The audio engine is built when a sound is first prepared or played, never at launch, so a stalled audio service
/// can't hold up the first screen.
@MainActor
final class CLSoundLaunchTests: XCTestCase {
    func testMakingTheSoundEngineSettingItUpAndSuspendingItTouchesNoAudio() {
        let sound = CLSound()
        XCTAssertFalse(sound.hasAudioGraph)
        sound.isEnabled = false
        sound.quietHours = (start: 22 * 60, end: 7 * 60)
        sound.palette = .standard
        sound.suspend()
        sound.prepare()
        XCTAssertFalse(sound.hasAudioGraph, "settings, a backgrounding and a prepare with sounds off build nothing")
        sound.play(.saved)
        XCTAssertFalse(sound.hasAudioGraph, "a cue with sounds off builds nothing")
        sound.isEnabled = true
        XCTAssertFalse(sound.hasAudioGraph, "even with sounds on, nothing is built until one is wanted")
    }

    /// A screen that is about to play sounds warms them while nothing else is moving: the first sound of a launch took 163 ms of the
    /// main thread to synthesise and start the engine (a debug build), and the welcome's first star stuttered.
    func testWarmingTheSoundsRendersThemBeforeTheyAreWanted() async {
        let sound = CLSound()
        sound.isEnabled = false
        await sound.prewarm([.right(combo: 1)])
        XCTAssertEqual(sound.renderedCount, 0, "with sounds off it renders nothing and builds nothing")
        XCTAssertFalse(sound.hasAudioGraph)

        sound.isEnabled = true
        await sound.prewarm([.right(combo: 1), .right(combo: 2), .flourish, .right(combo: 1)])
        XCTAssertEqual(sound.renderedCount, 3, "each cue once, ready before a touch")
        await sound.prewarm([.right(combo: 2)])
        XCTAssertEqual(sound.renderedCount, 3, "and asking again renders nothing more")
    }
}
