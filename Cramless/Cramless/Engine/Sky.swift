import Foundation

// The memory sky: every studied item is a star, every topic a constellation, every course a patch of sky, every
// exam a faint region around what it covers. Stars are bright while an item is remembered and dim as it fades;
// answering relights them. Pure: the views draw a `SkyLayout` lit by a `SkyLight`.

// MARK: - Inputs

/// A course, as the sky needs it (items, topics and exams come as the engine's usual snapshots).
struct SkyCourse: Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var color: CourseColor
    var sortOrder: Int
    var createdAt: Date
}

/// One answer, as the sky counts it.
struct SkyReview: Sendable, Equatable {
    var itemID: UUID
    var wasCorrect: Bool
    /// The item had never been studied before this answer.
    var wasNew: Bool = false
    /// Probability of recall at the moment of the answer (0 for a first look).
    var recallBefore: Double = 1

    /// Rated Good or Easy: right, not just right enough ("Almost." is a Hard).
    var isRight = true

    /// The same rule as `ReviewOutcome.isSave`.
    var isSave: Bool { wasCorrect && isRight && !wasNew && recallBefore < ReviewOutcome.fadingRecall }
}

// MARK: - Layout

struct SkyPoint: Sendable, Equatable, Hashable {
    var x: Double
    var y: Double

    func distance(to p: SkyPoint) -> Double { ((x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)).squareRoot() }
}

/// Where everything sits, in units of one star spacing. It depends only on ids, order and counts, so the same
/// library always draws the same sky, and stars never move as days pass or as items are added: a constellation
/// keeps room to grow, and the sky only rearranges when a topic doubles.
struct SkyLayout: Sendable, Equatable {
    struct Star: Sendable, Equatable {
        var id: UUID
        var point: SkyPoint
        var constellation: Int
    }

    struct Constellation: Sendable, Equatable, Identifiable {
        /// The topic's id, or the course's for its field of items without a topic.
        var id: UUID
        var courseID: UUID
        /// Nil for a course's field, which has no lines.
        var topicID: UUID?
        var name: String
        var center: SkyPoint
        /// The room it keeps, stars and growth included.
        var radius: Double
        /// Its stars, as indices into `stars`, oldest first.
        var stars: Range<Int>
        var lines: [Line]
    }

    struct Line: Sendable, Equatable, Hashable {
        var a: Int
        var b: Int
    }

    /// The smallest circle around the constellations an exam covers, drawn as a faint nebula.
    struct Region: Sendable, Equatable, Identifiable {
        var id: UUID { examID }
        var examID: UUID
        var courseID: UUID
        var title: String
        var center: SkyPoint
        var radius: Double
        /// The constellations the exam covers, as indices into `constellations`. What lights with the region, and
        /// what Progress shows in its still. The circle can have another constellation's corner inside it that the
        /// exam doesn't cover, so this is the exam's scope, not a test of where things sit.
        var covers: [Int] = []
    }

    var stars: [Star] = []
    var constellations: [Constellation] = []
    var regions: [Region] = []
    /// Everything fits in 0…width × 0…height.
    var width: Double = 1
    var height: Double = 1

    static let empty = SkyLayout()
}

// MARK: - Light

/// How each star of a layout shines at a moment, in the layout's order.
struct SkyLight: Sendable, Equatable {
    /// Probability of recall now (0 for an item never studied).
    var recall: [Double] = []
    /// 0…1: dim as an item fades, bright while it is remembered.
    var brightness: [Double] = []
    /// Never studied: drawn as a hollow ring.
    var hollow: [Bool] = []
    /// 0…1: how restless the star is. FSRS counts whole days, so a card missed a minute ago still shows recall
    /// near 1; a fragile memory (low stability) shows as a bright star that will not keep still.
    var flicker: [Double] = []

    func isDim(_ i: Int) -> Bool { !hollow[i] && recall[i] < ReviewOutcome.fadingRecall }

    /// Lit stars that are bright, not dim, for one constellation.
    func brightCount(_ c: SkyLayout.Constellation) -> Int { c.stars.filter { !hollow[$0] && !isDim($0) }.count }
    func dimCount(_ c: SkyLayout.Constellation) -> Int { c.stars.filter { isDim($0) }.count }

    /// Mean recall over a constellation's studied stars (nil when none is studied yet).
    func meanRecall(_ c: SkyLayout.Constellation) -> Double? {
        let studied = c.stars.filter { !hollow[$0] }
        guard !studied.isEmpty else { return nil }
        return studied.map { recall[$0] }.reduce(0, +) / Double(studied.count)
    }
}

/// What a session did to the sky: the stars it relit, lit for the first time and saved, and how bright each was when
/// the session began, so the sky can play the change.
struct SkyRelight: Sendable, Equatable {
    /// Items whose last answer in the session was right: their stars shine now.
    var relit: Set<UUID> = []
    /// Relit items that had never been studied: they go from a hollow ring to a star.
    var lit: Set<UUID> = []
    /// Items saved: right while their recall had fallen below `ReviewOutcome.fadingRecall`.
    var saved: Set<UUID> = []
    /// Each relit item's brightness when the session began (0 for one lit for the first time).
    var from: [UUID: Double] = [:]

    static let none = SkyRelight()
    var isEmpty: Bool { relit.isEmpty }
}

// MARK: - Engine

enum SkyEngine {
    /// The golden angle, in radians.
    static let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
    /// How far a star may sit off its spiral point, in star spacings.
    static let jitter = 0.3
    /// Lines join at most this many stars of a constellation, the oldest.
    static let lineStars = 12
    /// Room between constellations of a course, and between courses.
    static let constellationGap = 1.2
    static let courseGap = 3.6
    /// Room around the whole sky.
    static let margin = 1.6

    // MARK: Layout

    /// - Parameter aspect: the height over the width the sky will be drawn at; courses are packed in rows to suit it.
    static func layout(items: [ItemSnapshot], topics: [TopicSnapshot], courses: [SkyCourse], exams: [ExamSnapshot],
                       aspect: Double) -> SkyLayout {
        let topicsByID = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // An item with no course has nowhere in the sky.
        let itemsByCourse = Dictionary(grouping: items.filter { $0.courseID != nil }, by: { $0.courseID! })
        let orderedCourses = courses
            .filter { itemsByCourse[$0.id] != nil }
            .sorted { ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString) }

        // Each course is laid out around its own origin, then packed.
        var blocks: [CourseBlock] = []
        for course in orderedCourses {
            blocks.append(courseBlock(course, items: itemsByCourse[course.id] ?? [], topics: topicsByID))
        }
        let offsets = pack(blocks.map(\.box), aspect: aspect)

        var layout = SkyLayout()
        for (block, offset) in zip(blocks, offsets) {
            for var c in block.constellations {
                let start = layout.stars.count
                let shift = SkyPoint(x: offset.x, y: offset.y)
                for local in c.localStars {
                    layout.stars.append(.init(id: local.id,
                                              point: SkyPoint(x: c.center.x + local.point.x + shift.x,
                                                              y: c.center.y + local.point.y + shift.y),
                                              constellation: layout.constellations.count))
                }
                c.center = SkyPoint(x: c.center.x + shift.x, y: c.center.y + shift.y)
                let range = start..<layout.stars.count
                let lines = c.topicID == nil ? [] : Self.lines(Array(layout.stars[range].prefix(lineStars)).map(\.point))
                layout.constellations.append(.init(id: c.id, courseID: c.courseID, topicID: c.topicID, name: c.name,
                                                   center: c.center, radius: c.radius, stars: range,
                                                   lines: lines.map { .init(a: $0.a + start, b: $0.b + start) }))
            }
        }
        layout.regions = regions(exams, layout: layout)
        return normalized(layout)
    }

    private struct LocalStar {
        var id: UUID
        var point: SkyPoint
    }

    private struct PlacedConstellation {
        var id: UUID
        var courseID: UUID
        var topicID: UUID?
        var name: String
        var center: SkyPoint
        var radius: Double
        var localStars: [LocalStar]
    }

    private struct CourseBlock {
        var constellations: [PlacedConstellation]
        /// Its bounds around its own origin.
        var box: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    }

    /// Topics in their order, then the field of items without a topic; each placed along golden-angle directions
    /// from the course's origin at the nearest distance that keeps clear of the ones before it.
    private static func courseBlock(_ course: SkyCourse, items: [ItemSnapshot], topics: [UUID: TopicSnapshot]) -> CourseBlock {
        var byTopic: [UUID: [ItemSnapshot]] = [:]
        var field: [ItemSnapshot] = []
        for item in items {
            if let t = item.topicID, let topic = topics[t], topic.courseID == course.id {
                byTopic[t, default: []].append(item)
            } else {
                field.append(item)
            }
        }
        let byAge: (ItemSnapshot, ItemSnapshot) -> Bool = { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var groups: [(id: UUID, topicID: UUID?, name: String, items: [ItemSnapshot])] = byTopic.keys
            .compactMap { topics[$0] }
            .sorted { ($0.sortOrder, $0.name, $0.id.uuidString) < ($1.sortOrder, $1.name, $1.id.uuidString) }
            .map { ($0.id, $0.id, $0.name, byTopic[$0.id]!.sorted(by: byAge)) }
        if !field.isEmpty { groups.append((course.id, nil, course.name, field.sorted(by: byAge))) }

        let turn = StableRandom.unit(course.id, day: 0, salt: 0x5c1) * 2 * .pi
        var placed: [PlacedConstellation] = []
        for (index, group) in groups.enumerated() {
            let radius = reservedRadius(group.items.count)
            var center = SkyPoint(x: 0, y: 0)
            if index > 0 {
                let angle = turn + Double(index) * goldenAngle
                var distance = 0.0
                repeat {
                    center = SkyPoint(x: cos(angle) * distance, y: sin(angle) * distance)
                    distance += 0.25
                } while placed.contains { $0.center.distance(to: center) < $0.radius + radius + constellationGap }
            }
            placed.append(PlacedConstellation(id: group.id, courseID: course.id, topicID: group.topicID, name: group.name,
                                              center: center, radius: radius,
                                              localStars: spiral(group.items.map(\.id), turn: group.id)))
        }
        let minX = placed.map { $0.center.x - $0.radius }.min() ?? 0
        let minY = placed.map { $0.center.y - $0.radius }.min() ?? 0
        let maxX = placed.map { $0.center.x + $0.radius }.max() ?? 0
        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? 0
        return CourseBlock(constellations: placed, box: (minX, minY, maxX, maxY))
    }

    /// A constellation keeps √(the next power of two of its size, at least 4) + 1 spacings of room, so it only
    /// grows, and moves its neighbours, when its topic doubles.
    static func reservedRadius(_ count: Int) -> Double {
        var room = 4
        while room < count { room *= 2 }
        return Double(room).squareRoot() + 1
    }

    /// Stars on a Vogel spiral: the k-th at radius √(k + ½), a golden angle further round each time, turned by an
    /// amount hashed from the constellation and nudged by up to `jitter` hashed from the star.
    static func spiralPoint(_ k: Int, id: UUID, turn: Double) -> SkyPoint {
        let r = (Double(k) + 0.5).squareRoot()
        let a = Double(k) * goldenAngle + turn
        let jx = (StableRandom.unit(id, day: 0, salt: 0xa11) - 0.5) * 2 * jitter
        let jy = (StableRandom.unit(id, day: 0, salt: 0xb22) - 0.5) * 2 * jitter
        return SkyPoint(x: r * cos(a) + jx, y: r * sin(a) + jy)
    }

    private static func spiral(_ ids: [UUID], turn id: UUID) -> [LocalStar] {
        let turn = StableRandom.unit(id, day: 0, salt: 0x7e1) * 2 * .pi
        return ids.enumerated().map { k, item in LocalStar(id: item, point: spiralPoint(k, id: item, turn: turn)) }
    }

    /// Shelf packing: courses in their order, left to right in rows, at the row width whose shape comes closest to
    /// `aspect`. Returns each block's offset.
    private static func pack(_ boxes: [(minX: Double, minY: Double, maxX: Double, maxY: Double)],
                             aspect: Double) -> [SkyPoint] {
        guard !boxes.isEmpty else { return [] }
        let widths = boxes.map { $0.maxX - $0.minX }
        let total = widths.reduce(0, +) + courseGap * Double(boxes.count - 1)
        let widest = widths.max() ?? 0
        var best: (score: Double, offsets: [SkyPoint])?
        let steps = 48
        for s in 0...steps {
            let limit = widest + (total - widest) * Double(s) / Double(steps)
            let (offsets, width, height) = shelves(boxes, limit: limit)
            let score = abs(log(max(height, 1e-6) / max(width, 1e-6)) - log(max(aspect, 0.05)))
            if best == nil || score < best!.score - 1e-9 { best = (score, offsets) }
        }
        return best!.offsets
    }

    private static func shelves(_ boxes: [(minX: Double, minY: Double, maxX: Double, maxY: Double)],
                                limit: Double) -> (offsets: [SkyPoint], width: Double, height: Double) {
        var rows: [[Int]] = [[]]
        var rowWidth = 0.0
        for (i, b) in boxes.enumerated() {
            let w = b.maxX - b.minX
            if !rows[rows.count - 1].isEmpty, rowWidth + courseGap + w > limit + 1e-9 {
                rows.append([])
                rowWidth = 0
            }
            rowWidth += (rows[rows.count - 1].isEmpty ? 0 : courseGap) + w
            rows[rows.count - 1].append(i)
        }
        let rowWidths = rows.map { row in row.map { boxes[$0].maxX - boxes[$0].minX }.reduce(0, +)
            + courseGap * Double(max(0, row.count - 1)) }
        let width = rowWidths.max() ?? 0
        var offsets = [SkyPoint](repeating: SkyPoint(x: 0, y: 0), count: boxes.count)
        var y = 0.0
        for (r, row) in rows.enumerated() {
            let height = row.map { boxes[$0].maxY - boxes[$0].minY }.max() ?? 0
            // Rows are centred, and each course sits in the middle of its row's height.
            var x = (width - rowWidths[r]) / 2
            for i in row {
                let b = boxes[i]
                offsets[i] = SkyPoint(x: x - b.minX, y: y + (height - (b.maxY - b.minY)) / 2 - b.minY)
                x += (b.maxX - b.minX) + courseGap
            }
            y += height + courseGap
        }
        return (offsets, width, max(0, y - courseGap))
    }

    /// A minimum spanning tree over the points (Prim's), plus, from six points on, the shortest edge that closes
    /// a loop, so bigger constellations read as shapes rather than chains.
    static func lines(_ points: [SkyPoint]) -> [SkyLayout.Line] {
        let n = points.count
        guard n > 1 else { return [] }
        var inTree = [Bool](repeating: false, count: n)
        var best = [Double](repeating: .infinity, count: n)
        var parent = [Int](repeating: -1, count: n)
        var edges: [SkyLayout.Line] = []
        best[0] = 0
        for _ in 0..<n {
            var u = -1
            for v in 0..<n where !inTree[v] && (u < 0 || best[v] < best[u]) { u = v }
            inTree[u] = true
            if parent[u] >= 0 { edges.append(.init(a: parent[u], b: u)) }
            for v in 0..<n where !inTree[v] {
                let d = points[u].distance(to: points[v])
                if d < best[v] { best[v] = d; parent[v] = u }
            }
        }
        if n >= 6 {
            let tree = Set(edges.map { [min($0.a, $0.b), max($0.a, $0.b)] })
            var closing: (Double, Int, Int)?
            for a in 0..<n {
                for b in (a + 1)..<n where !tree.contains([a, b]) {
                    let d = points[a].distance(to: points[b])
                    if closing == nil || d < closing!.0 { closing = (d, a, b) }
                }
            }
            if let closing { edges.append(.init(a: closing.1, b: closing.2)) }
        }
        return edges
    }

    /// Each exam's region: the smallest circle around the stars of the constellations it covers (the whole course when
    /// its scope is empty), with room to breathe. It wraps the stars, not the room a constellation keeps to grow, so
    /// it fits what is drawn.
    private static func regions(_ exams: [ExamSnapshot], layout: SkyLayout) -> [SkyLayout.Region] {
        exams.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }.compactMap { exam -> SkyLayout.Region? in
            guard let courseID = exam.courseID else { return nil }
            let covered = layout.constellations.indices.filter { i in
                let c = layout.constellations[i]
                return c.courseID == courseID && (exam.scope.isEmpty || c.topicID.map(exam.scope.contains) == true)
            }
            let points = covered.flatMap { i in layout.stars[layout.constellations[i].stars].map(\.point) }
            guard !points.isEmpty else { return nil }
            let circle = enclosingCircle(points, seed: StableRandom.seed(exam.id, day: 0))
            return .init(examID: exam.id, courseID: courseID, title: exam.title, center: circle.center,
                         radius: circle.radius + regionMargin, covers: covered)
        }
    }

    /// Room between a region's rim and the outermost star inside it, in star spacings.
    static let regionMargin = 1.3

    /// The smallest circle around the points (Welzl's algorithm, iterative, over a seeded shuffle so it runs in
    /// expected linear time and gives the same answer every time).
    static func enclosingCircle(_ input: [SkyPoint], seed: UInt64) -> (center: SkyPoint, radius: Double) {
        guard !input.isEmpty else { return (SkyPoint(x: 0, y: 0), 0) }
        var points = input
        var state = seed
        for i in stride(from: points.count - 1, to: 0, by: -1) {
            state = StableRandom.mix(state &+ 0x9e37_79b9_7f4a_7c15)
            points.swapAt(i, Int(state % UInt64(i + 1)))
        }
        let eps = 1e-9
        func inside(_ p: SkyPoint, _ c: (center: SkyPoint, radius: Double)) -> Bool {
            c.center.distance(to: p) <= c.radius + eps
        }
        func two(_ a: SkyPoint, _ b: SkyPoint) -> (center: SkyPoint, radius: Double) {
            let c = SkyPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            return (c, c.distance(to: a))
        }
        func three(_ a: SkyPoint, _ b: SkyPoint, _ c: SkyPoint) -> (center: SkyPoint, radius: Double) {
            let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
            guard abs(d) > 1e-12 else {
                // In a line: the two farthest apart.
                return [two(a, b), two(a, c), two(b, c)].max { $0.radius < $1.radius }!
            }
            let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
            let center = SkyPoint(x: (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                                  y: (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
            return (center, center.distance(to: a))
        }
        var circle = (center: points[0], radius: 0.0)
        for i in 1..<points.count where !inside(points[i], circle) {
            circle = (points[i], 0)
            for j in 0..<i where !inside(points[j], circle) {
                circle = two(points[i], points[j])
                for k in 0..<j where !inside(points[k], circle) {
                    circle = three(points[i], points[j], points[k])
                }
            }
        }
        return circle
    }

    /// Moves everything so the sky starts at `margin` from the top left, and measures it.
    private static func normalized(_ layout: SkyLayout) -> SkyLayout {
        guard !layout.constellations.isEmpty else { return .empty }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for c in layout.constellations {
            minX = min(minX, c.center.x - c.radius); maxX = max(maxX, c.center.x + c.radius)
            minY = min(minY, c.center.y - c.radius); maxY = max(maxY, c.center.y + c.radius)
        }
        for r in layout.regions {
            minX = min(minX, r.center.x - r.radius); maxX = max(maxX, r.center.x + r.radius)
            minY = min(minY, r.center.y - r.radius); maxY = max(maxY, r.center.y + r.radius)
        }
        let dx = margin - minX, dy = margin - minY
        func move(_ p: SkyPoint) -> SkyPoint { SkyPoint(x: p.x + dx, y: p.y + dy) }
        var out = layout
        out.stars = layout.stars.map { var s = $0; s.point = move(s.point); return s }
        out.constellations = layout.constellations.map { var c = $0; c.center = move(c.center); return c }
        out.regions = layout.regions.map { var r = $0; r.center = move(r.center); return r }
        out.width = maxX - minX + 2 * margin
        out.height = maxY - minY + 2 * margin
        return out
    }

    // MARK: Light

    /// Brightness rises with recall from a faint glow at 35% to full at 97%.
    static func brightness(recall: Double) -> Double {
        let t = min(1, max(0, (recall - 0.35) / (0.97 - 0.35)))
        return t * t * (3 - 2 * t)
    }

    /// Restlessness from stability: a memory that would fade within a day flickers fully, one that lasts ten days
    /// or more keeps still, on a log scale between.
    static func flicker(stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return min(1, max(0, log(10 / stability) / log(10)))
    }

    static func light(_ layout: SkyLayout, items: [ItemSnapshot], at date: Date, fsrs: FSRS = FSRS()) -> SkyLight {
        let memories = Dictionary(items.map { ($0.id, $0.memory) }, uniquingKeysWith: { a, _ in a })
        var light = SkyLight()
        light.recall.reserveCapacity(layout.stars.count)
        for star in layout.stars {
            let memory = memories[star.id] ?? .new
            let hollow = memory.state == .new
            let recall = hollow ? 0 : fsrs.retrievability(of: memory, at: date)
            light.recall.append(recall)
            light.hollow.append(hollow)
            light.brightness.append(hollow ? 0 : brightness(recall: recall))
            light.flicker.append(hollow ? 0 : flicker(stability: memory.stability))
        }
        return light
    }

    /// A star counts as relit only if it visibly changed: it began the session below this brightness (about 90%
    /// recall), or it was lit for the first time. A star already at full brightness that is answered right is kept
    /// bright, not relit.
    static let relitBelow = 0.9

    /// The stars a session relit (the last answer for the item was right), lit for the first time and saved. An item
    /// answered more than once counts once: its first answer says where it started, its last whether it shines.
    /// Saves are counted as they happened, so they match the "Just in time!" the person saw.
    static func relights(_ reviews: [SkyReview]) -> SkyRelight {
        var first: [UUID: SkyReview] = [:]
        var last: [UUID: Bool] = [:]
        var saved = Set<UUID>()
        for review in reviews {
            if first[review.itemID] == nil { first[review.itemID] = review }
            last[review.itemID] = review.wasCorrect
            if review.isSave { saved.insert(review.itemID) }
        }
        var out = SkyRelight(saved: saved)
        for (id, correct) in last where correct {
            guard let start = first[id] else { continue }
            let before = start.wasNew ? 0 : brightness(recall: start.recallBefore)
            guard start.wasNew || before <= relitBelow else { continue }
            out.relit.insert(id)
            if start.wasNew { out.lit.insert(id) }
            out.from[id] = before
        }
        return out
    }
}
