import XCTest
@testable import Cramless

/// The memory sky's layout and light: the same library always draws the same sky, stars stay put as days pass and
/// as items are added, nothing overlaps, and brightness follows recall.
final class SkyEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// A library: `courses` courses, each with `topics` topics of `perTopic` items, plus `loose` items with no topic.
    private func world(courses: Int = 3, topics: Int = 4, perTopic: Int = 7, loose: Int = 3, exams: Bool = true)
        -> (items: [ItemSnapshot], topics: [TopicSnapshot], courses: [SkyCourse], exams: [ExamSnapshot]) {
        var items: [ItemSnapshot] = [], topicList: [TopicSnapshot] = [], courseList: [SkyCourse] = [], examList: [ExamSnapshot] = []
        let colors = CourseColor.allCases
        for c in 0..<courses {
            let course = SkyCourse(id: StableRandom.uuid("course-\(c)"), name: "Course \(c)", color: colors[c % colors.count],
                                   sortOrder: c, createdAt: start)
            courseList.append(course)
            for t in 0..<topics {
                let topic = TopicSnapshot(id: StableRandom.uuid("topic-\(c)-\(t)"), courseID: course.id, name: "Topic \(t)", sortOrder: t)
                topicList.append(topic)
                for i in 0..<perTopic {
                    items.append(item("item-\(c)-\(t)-\(i)", course: course.id, topic: topic.id, minute: i))
                }
            }
            for i in 0..<loose {
                items.append(item("loose-\(c)-\(i)", course: course.id, topic: nil, minute: i))
            }
            if exams {
                examList.append(ExamSnapshot(id: StableRandom.uuid("exam-\(c)"), courseID: course.id, title: "Exam \(c)",
                                             date: start.addingTimeInterval(Double(c + 3) * 86_400),
                                             scope: [topicList[topicList.count - topics].id, topicList[topicList.count - topics + 1].id]))
            }
        }
        return (items, topicList, courseList, examList)
    }

    private func item(_ name: String, course: UUID, topic: UUID?, minute: Int) -> ItemSnapshot {
        ItemSnapshot(id: StableRandom.uuid(name), topicID: topic, courseID: course, memory: .new,
                     createdAt: start.addingTimeInterval(Double(minute) * 60))
    }

    private func layout(_ w: (items: [ItemSnapshot], topics: [TopicSnapshot], courses: [SkyCourse], exams: [ExamSnapshot]),
                        aspect: Double = 1.4) -> SkyLayout {
        SkyEngine.layout(items: w.items, topics: w.topics, courses: w.courses, exams: w.exams, aspect: aspect)
    }

    private func positions(_ layout: SkyLayout) -> [UUID: SkyPoint] {
        Dictionary(uniqueKeysWithValues: layout.stars.map { ($0.id, $0.point) })
    }

    // MARK: Layout

    func testTheSameLibraryDrawsTheSameSky() {
        let w = world()
        XCTAssertEqual(layout(w), layout(w))
        // Input order doesn't matter.
        XCTAssertEqual(layout(w), layout((w.items.reversed(), w.topics.reversed(), w.courses.reversed(), w.exams.reversed())))
    }

    func testEveryItemIsAStarInItsTopicsConstellation() {
        let w = world()
        let sky = layout(w)
        XCTAssertEqual(sky.stars.count, w.items.count)
        XCTAssertEqual(Set(sky.stars.map(\.id)).count, w.items.count)
        let topicOf = Dictionary(uniqueKeysWithValues: w.items.map { ($0.id, $0.topicID) })
        for c in sky.constellations {
            for i in c.stars {
                XCTAssertEqual(sky.stars[i].constellation, sky.constellations.firstIndex { $0.id == c.id })
                XCTAssertEqual(topicOf[sky.stars[i].id] ?? nil, c.topicID)
                XCTAssertLessThanOrEqual(sky.stars[i].point.distance(to: c.center), c.radius, "a star outside its room")
            }
        }
        // Three courses, four topics each, and one field each for the items without a topic.
        XCTAssertEqual(sky.constellations.count, 3 * 5)
        XCTAssertEqual(sky.constellations.filter { $0.topicID == nil }.count, 3)
    }

    func testStarsKeepTheirPlaceAsMemoriesChange() {
        var w = world()
        let before = layout(w)
        for i in w.items.indices {
            w.items[i].memory = MemoryState(state: .review, stability: Double(i % 30) + 1, difficulty: 5,
                                            due: start, lastReview: start, reps: 3, lapses: 0, step: 0)
        }
        XCTAssertEqual(layout(w), before, "the sky's shape never depends on how well things are remembered")
    }

    func testAddingItemsMovesNothingUntilATopicDoubles() {
        var w = world(perTopic: 5)
        let before = positions(layout(w))
        // Five items keep room for eight: two more fit without moving anything.
        let course = w.courses[1].id, topic = w.topics[5].id
        w.items.append(item("new-1", course: course, topic: topic, minute: 99))
        w.items.append(item("new-2", course: course, topic: topic, minute: 100))
        w.items.append(item("loose-new", course: course, topic: nil, minute: 101))
        let after = positions(layout(w))
        for (id, point) in before {
            XCTAssertEqual(after[id], point, "a star moved when an item was added")
        }
        XCTAssertEqual(after.count, before.count + 3)
    }

    func testConstellationsAndCoursesNeverOverlap() {
        let sky = layout(world(courses: 6, topics: 6, perTopic: 9))
        let cs = sky.constellations
        for a in cs.indices {
            for b in cs.indices where b > a {
                let gap = cs[a].courseID == cs[b].courseID ? SkyEngine.constellationGap : SkyEngine.courseGap
                XCTAssertGreaterThanOrEqual(cs[a].center.distance(to: cs[b].center) + 1e-6, cs[a].radius + cs[b].radius + gap * 0.999,
                                            "\(cs[a].name) and \(cs[b].name) overlap")
            }
        }
        for c in cs {
            XCTAssertGreaterThanOrEqual(c.center.x - c.radius, 0)
            XCTAssertGreaterThanOrEqual(c.center.y - c.radius, 0)
            XCTAssertLessThanOrEqual(c.center.x + c.radius, sky.width)
            XCTAssertLessThanOrEqual(c.center.y + c.radius, sky.height)
        }
    }

    func testCoursesArePackedToTheShapeTheSkyIsDrawnAt() {
        let w = world(courses: 8, topics: 3, perTopic: 6, exams: false)
        let tall = layout(w, aspect: 2.0), wide = layout(w, aspect: 0.5)
        XCTAssertGreaterThan(tall.height / tall.width, wide.height / wide.width)
        XCTAssertEqual(tall.height / tall.width, 2.0, accuracy: 1.0)
        XCTAssertEqual(wide.height / wide.width, 0.5, accuracy: 0.35)
    }

    func testRoomDoublesWithTheTopic() {
        XCTAssertEqual(SkyEngine.reservedRadius(1), 3)
        XCTAssertEqual(SkyEngine.reservedRadius(4), 3)
        XCTAssertEqual(SkyEngine.reservedRadius(5), 8.0.squareRoot() + 1)
        XCTAssertEqual(SkyEngine.reservedRadius(8), 8.0.squareRoot() + 1)
        XCTAssertEqual(SkyEngine.reservedRadius(9), 5)
    }

    // MARK: Lines

    func testLinesAreATreeAndALoopFromSixStars() {
        for n in 1...14 {
            let points = (0..<n).map { SkyEngine.spiralPoint($0, id: StableRandom.uuid("p\($0)"), turn: 0) }
            let lines = SkyEngine.lines(points)
            XCTAssertEqual(lines.count, n < 2 ? 0 : (n >= 6 ? n : n - 1), "\(n) points")
            // Connected: every point is reached from the first.
            var reached: Set<Int> = n > 0 ? [0] : []
            var grew = true
            while grew {
                grew = false
                for l in lines where reached.contains(l.a) != reached.contains(l.b) {
                    reached.formUnion([l.a, l.b])
                    grew = true
                }
            }
            XCTAssertEqual(reached.count, n)
        }
    }

    func testOnlyTopicsHaveLinesAndOnlyTheirFirstTwelveStars() {
        let sky = layout(world(courses: 1, topics: 2, perTopic: 20, loose: 8))
        for c in sky.constellations {
            if c.topicID == nil {
                XCTAssertTrue(c.lines.isEmpty, "a field has no lines")
            } else {
                let first = c.stars.lowerBound
                XCTAssertTrue(c.lines.allSatisfy { $0.a < first + SkyEngine.lineStars && $0.b < first + SkyEngine.lineStars })
                XCTAssertEqual(c.lines.count, SkyEngine.lineStars)
            }
        }
    }

    // MARK: Regions

    func testEnclosingCircleIsTheSmallestOne() {
        let two = SkyEngine.enclosingCircle([SkyPoint(x: 0, y: 0), SkyPoint(x: 4, y: 0)], seed: 1)
        XCTAssertEqual(two.radius, 2, accuracy: 1e-9)
        XCTAssertEqual(two.center.x, 2, accuracy: 1e-9)
        let triangle = [SkyPoint(x: 0, y: 0), SkyPoint(x: 2, y: 0), SkyPoint(x: 1, y: 3.0.squareRoot())]
        XCTAssertEqual(SkyEngine.enclosingCircle(triangle, seed: 7).radius, 2 / 3.0.squareRoot(), accuracy: 1e-9)
        // A square's corners, with points inside: the circle through the corners.
        var square = [SkyPoint(x: 0, y: 0), SkyPoint(x: 2, y: 0), SkyPoint(x: 2, y: 2), SkyPoint(x: 0, y: 2)]
        square += (0..<50).map { SkyPoint(x: 0.2 + Double($0 % 7) * 0.2, y: 0.3 + Double($0 % 5) * 0.3) }
        let c = SkyEngine.enclosingCircle(square, seed: 3)
        XCTAssertEqual(c.radius, 2.0.squareRoot(), accuracy: 1e-9)
        for p in square { XCTAssertLessThanOrEqual(c.center.distance(to: p), c.radius + 1e-9) }
    }

    func testExamRegionsHoldTheStarsTheyCover() {
        let w = world()
        let sky = layout(w)
        XCTAssertEqual(sky.regions.count, 3)
        for region in sky.regions {
            let exam = w.exams.first { $0.id == region.examID }!
            let covered = sky.constellations.filter { $0.topicID.map(exam.scope.contains) == true }
            XCTAssertEqual(covered.count, 2)
            for c in covered {
                for i in c.stars {
                    XCTAssertLessThanOrEqual(region.center.distance(to: sky.stars[i].point) + SkyEngine.regionMargin,
                                             region.radius + 1e-6, "a star outside its exam's region")
                }
            }
            // Snug: the region is no bigger than the stars and the margin need.
            let farthest = covered.flatMap { c in sky.stars[c.stars].map { region.center.distance(to: $0.point) } }.max()!
            XCTAssertEqual(region.radius, farthest + SkyEngine.regionMargin, accuracy: 1e-6)
        }
        // An exam with no scope covers its whole course.
        var whole = w
        whole.exams = [ExamSnapshot(id: StableRandom.uuid("final"), courseID: w.courses[0].id, title: "Final",
                                    date: start, scope: [])]
        let skyWhole = layout(whole)
        let region = skyWhole.regions[0]
        for star in skyWhole.stars where skyWhole.constellations[star.constellation].courseID == w.courses[0].id {
            XCTAssertLessThanOrEqual(region.center.distance(to: star.point), region.radius)
        }
    }

    // MARK: Light

    func testBrightnessFollowsRecall() {
        XCTAssertEqual(SkyEngine.brightness(recall: 0.2), 0)
        XCTAssertEqual(SkyEngine.brightness(recall: 0.35), 0)
        XCTAssertEqual(SkyEngine.brightness(recall: 0.97), 1)
        XCTAssertEqual(SkyEngine.brightness(recall: 1), 1)
        var last = -1.0
        for r in stride(from: 0.0, through: 1.0, by: 0.01) {
            let b = SkyEngine.brightness(recall: r)
            XCTAssertGreaterThanOrEqual(b, last)
            last = b
        }
        XCTAssertEqual(SkyEngine.flicker(stability: 0.5), 1)
        XCTAssertEqual(SkyEngine.flicker(stability: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(SkyEngine.flicker(stability: 10.0.squareRoot()), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SkyEngine.flicker(stability: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(SkyEngine.flicker(stability: 40), 0)
    }

    func testStarsDimAsTheyFadeAndNewOnesAreHollow() {
        let w = world(courses: 1, topics: 1, perTopic: 3, loose: 0, exams: false)
        let sky = layout(w)
        let ids = w.items.map(\.id)
        let fresh = MemoryState(state: .review, stability: 20, difficulty: 5, due: nil, lastReview: start, reps: 4)
        let fragile = MemoryState(state: .review, stability: 0.6, difficulty: 7, due: nil, lastReview: start, reps: 1)
        var items = w.items
        items[0].memory = fresh
        items[1].memory = fragile
        let index = Dictionary(uniqueKeysWithValues: sky.stars.enumerated().map { ($1.id, $0) })

        let today = SkyEngine.light(sky, items: items, at: start)
        XCTAssertEqual(today.brightness[index[ids[0]]!], 1, accuracy: 1e-9)
        XCTAssertEqual(today.brightness[index[ids[1]]!], 1, accuracy: 1e-9, "missed a minute ago still counts as recalled")
        XCTAssertGreaterThan(today.flicker[index[ids[1]]!], 0.9, "but a fragile memory won't keep still")
        XCTAssertEqual(today.flicker[index[ids[0]]!], 0)
        XCTAssertTrue(today.hollow[index[ids[2]]!])
        XCTAssertEqual(today.brightness[index[ids[2]]!], 0)
        XCTAssertFalse(today.isDim(index[ids[2]]!), "a hollow star is new, not fading")

        let later = SkyEngine.light(sky, items: items, at: start.addingTimeInterval(9 * 86_400))
        XCTAssertTrue(later.isDim(index[ids[1]]!), "nine days on, the fragile memory has faded")
        XCTAssertFalse(later.isDim(index[ids[0]]!))
        XCTAssertLessThan(later.brightness[index[ids[1]]!], 0.5)
        let c = sky.constellations[0]
        XCTAssertEqual(later.brightCount(c), 1)
        XCTAssertEqual(later.dimCount(c), 1)
        XCTAssertNotNil(later.meanRecall(c))
    }

    func testASessionRelightsWhatChangedAndEndedRight() {
        let a = StableRandom.uuid("a"), b = StableRandom.uuid("b"), c = StableRandom.uuid("c")
        let d = StableRandom.uuid("d"), e = StableRandom.uuid("e")
        let relight = SkyEngine.relights([
            // a: missed at first, then right: relit, and it began dim. Not a save: the right answer came at high recall.
            SkyReview(itemID: a, wasCorrect: false, recallBefore: 0.5), SkyReview(itemID: a, wasCorrect: true, recallBefore: 0.95),
            // b: right while fading: a save, and relit.
            SkyReview(itemID: b, wasCorrect: true, recallBefore: 0.4),
            // c: saved, then missed on the repeat: the person saw "Saved it.", but the star isn't relit.
            SkyReview(itemID: c, wasCorrect: true, recallBefore: 0.5), SkyReview(itemID: c, wasCorrect: false, recallBefore: 0.95),
            // d: a first look, right: lit for the first time, never a save.
            SkyReview(itemID: d, wasCorrect: true, wasNew: true, recallBefore: 0),
            // e: already bright and right again: kept bright, not relit.
            SkyReview(itemID: e, wasCorrect: true, recallBefore: 0.95),
        ])
        XCTAssertEqual(relight.relit, [a, b, d])
        XCTAssertEqual(relight.lit, [d])
        XCTAssertEqual(relight.saved, [b, c])
        XCTAssertEqual(relight.from[a] ?? -1, SkyEngine.brightness(recall: 0.5), accuracy: 1e-12)
        XCTAssertEqual(relight.from[d], 0)
        XCTAssertNil(relight.from[e])
        XCTAssertEqual(SkyEngine.relights([]), .none)
        XCTAssertTrue(SkyEngine.relights([]).isEmpty)
    }

    func testASaveIsTheSameRuleAsTheOutcomes() {
        // `SkyReview.isSave` must agree with `ReviewOutcome.isSave` at the edges of its definition.
        XCTAssertTrue(SkyReview(itemID: UUID(), wasCorrect: true, recallBefore: 0.69).isSave)
        XCTAssertFalse(SkyReview(itemID: UUID(), wasCorrect: true, recallBefore: 0.7).isSave)
        XCTAssertFalse(SkyReview(itemID: UUID(), wasCorrect: false, recallBefore: 0.3).isSave)
        XCTAssertFalse(SkyReview(itemID: UUID(), wasCorrect: true, wasNew: true, recallBefore: 0).isSave, "a first look is never a save")
        XCTAssertFalse(SkyReview(itemID: UUID(), wasCorrect: true, recallBefore: 0.4, isRight: false).isSave, "an Almost is not a save")
    }

    // MARK: Speed

    func testLayoutOfTenThousandItems() {
        let w = world(courses: 12, topics: 20, perTopic: 40, loose: 34, exams: true)
        XCTAssertGreaterThanOrEqual(w.items.count, 10_000)
        measure { _ = layout(w) }
    }
}
