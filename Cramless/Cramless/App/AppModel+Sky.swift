import Foundation
import SwiftData

/// What the memory sky draws, read once: where every star sits, how it shines now, and the names and colours around
/// it. Built by `AppModel.skyScene(aspect:at:)`; the views never touch the store.
struct SkyScene: Sendable, Equatable {
    var layout: SkyLayout
    var light: SkyLight
    var courseColors: [UUID: CourseColor]
    var courseNames: [UUID: String]
    /// Each exam region's date, for its label.
    var examDates: [UUID: Date]
    /// Seconds it takes to answer each constellation's dim stars (in `layout.constellations` order).
    var dimSeconds: [Double]
    var date: Date

    var isEmpty: Bool { layout.stars.isEmpty }

    /// No stars at all.
    static let empty = SkyScene(layout: .empty, light: SkyLight(), courseColors: [:], courseNames: [:], examDates: [:],
                                dimSeconds: [], date: .distantPast)
    var starCount: Int { layout.stars.count }
    var dimCount: Int { layout.stars.indices.filter { light.isDim($0) }.count }
    var hollowCount: Int { light.hollow.filter { $0 }.count }
    var brightCount: Int { starCount - dimCount - hollowCount }

    func color(of constellation: SkyLayout.Constellation) -> CourseColor { courseColors[constellation.courseID] ?? .sky }
    func courseName(of constellation: SkyLayout.Constellation) -> String { courseNames[constellation.courseID] ?? "" }

    /// The minutes "Practice …" asks for: what its dim stars take to answer, at least two and at most fifteen. With
    /// none dim, a short practice round.
    func minutesToRelight(_ index: Int) -> Int {
        guard layout.constellations.indices.contains(index) else { return 3 }
        let seconds = dimSeconds[index]
        return seconds <= 0 ? 3 : min(15, max(2, Int((seconds / 60).rounded(.up))))
    }
}

/// The last few layouts, kept until the library's shape changes. A few, not one: the card on Progress and the full
/// screen sky are laid out for different shapes, and going between them shouldn't lay out again each time.
final class SkyCache: @unchecked Sendable {
    private var order: [Int] = []
    private var layouts: [Int: SkyLayout] = [:]
    private let capacity = 4

    func layout(for key: Int, make: () -> SkyLayout) -> SkyLayout {
        if let layout = layouts[key] { return layout }
        let made = make()
        layouts[key] = made
        order.append(key)
        if order.count > capacity { layouts[order.removeFirst()] = nil }
        return made
    }
}

extension AppModel {
    /// The sky as it is at `date` (default: now), laid out for a screen `aspect` tall (height over width). The layout
    /// is cached; only the light is worked out again.
    func skyScene(aspect: Double, at date: Date? = nil) -> SkyScene {
        let date = date ?? now
        let items = itemSnapshots()
        let liveCourses = courses
        let topics = fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil }))
            .map { TopicSnapshot(id: $0.id, courseID: $0.course?.id, name: $0.name, sortOrder: $0.sortOrder) }
        let skyCourses = liveCourses.map {
            SkyCourse(id: $0.id, name: $0.name, color: $0.color, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
        }
        let exams = examSnapshots(upcomingOnly: true)

        // The key covers everything the layout reads, and nothing it doesn't (not the memories, not the colours).
        var hasher = Hasher()
        hasher.combine((aspect * 20).rounded())
        for item in items { hasher.combine(item.id); hasher.combine(item.courseID); hasher.combine(item.topicID); hasher.combine(item.createdAt) }
        for topic in topics { hasher.combine(topic.id); hasher.combine(topic.courseID); hasher.combine(topic.name); hasher.combine(topic.sortOrder) }
        for course in skyCourses { hasher.combine(course.id); hasher.combine(course.sortOrder); hasher.combine(course.createdAt) }
        for exam in exams { hasher.combine(exam.id); hasher.combine(exam.courseID); hasher.combine(exam.scope.sorted { $0.uuidString < $1.uuidString }) }
        let layout = skyCache.layout(for: hasher.finalize()) {
            SkyEngine.layout(items: items, topics: topics, courses: skyCourses, exams: exams, aspect: aspect)
        }

        let light = SkyEngine.light(layout, items: items, at: date, fsrs: fsrs)
        let kinds = Dictionary(items.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let dimSeconds = layout.constellations.map { c in
            c.stars.filter { light.isDim($0) }.reduce(0.0) { $0 + (kinds[layout.stars[$1].id]?.typicalSeconds ?? 20) }
        }
        return SkyScene(layout: layout, light: light,
                        courseColors: Dictionary(uniqueKeysWithValues: liveCourses.map { ($0.id, $0.color) }),
                        courseNames: Dictionary(uniqueKeysWithValues: liveCourses.map { ($0.id, $0.name) }),
                        examDates: Dictionary(exams.map { ($0.id, $0.date) }, uniquingKeysWith: { a, _ in a }),
                        dimSeconds: dimSeconds, date: date)
    }

    /// A practice session that relights one constellation: its dim stars first, for as long as they take.
    func relightRequest(_ constellation: SkyLayout.Constellation, in scene: SkyScene) -> SessionRequest {
        let index = scene.layout.constellations.firstIndex { $0.id == constellation.id } ?? 0
        return SessionRequest(kind: .practice, courseID: constellation.courseID, examID: nil, confusionID: nil,
                              minutes: scene.minutesToRelight(index), topicID: constellation.topicID)
    }

    /// Keeps what a finished session did to the sky until the sky is shown. Sessions that end before it is shown add up.
    func noteSkyRelight(_ relight: SkyRelight) {
        guard !relight.relit.isEmpty || !relight.saved.isEmpty else { return }
        var merged = pendingSkyRelight
        merged.relit.formUnion(relight.relit)
        merged.lit.formUnion(relight.lit)
        merged.saved.formUnion(relight.saved)
        // The earliest brightness wins: it is where the star was before any of the sessions.
        merged.from.merge(relight.from) { earlier, _ in earlier }
        pendingSkyRelight = merged
    }

    /// The pending relight, handed over once.
    func takeSkyRelight() -> SkyRelight {
        defer { pendingSkyRelight = .none }
        return pendingSkyRelight
    }
}

#if DEBUG
extension AppModel {
    /// Adds `count` studied items to the demo world, spread over its topics, with memories from just reviewed to
    /// long forgotten and a few never studied. Deterministic, so a film repeats (`CRAMLESS_SKY=fill:<n>`).
    func debugFillSky(_ count: Int) {
        let topics = fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil }))
            .sorted { ($0.course?.sortOrder ?? 0, $0.sortOrder, $0.name) < ($1.course?.sortOrder ?? 0, $1.sortOrder, $1.name) }
        guard !topics.isEmpty else { return }
        let fsrs = self.fsrs
        let kinds: [ItemKind] = [.flashcard, .mcq, .cloze, .recall, .flashcard]
        for i in 0..<count {
            let topic = topics[i % topics.count]
            guard let course = topic.course else { continue }
            let id = StableRandom.uuid("sky-fill-\(i)")
            guard item(id) == nil else { continue }
            let item = StudyItem(id: id, course: course, topicID: topic.id, kind: kinds[i % kinds.count], status: .active,
                                 origin: .person, prompt: "Filler question \(i)?", answer: "Answer",
                                 now: now.addingTimeInterval(Double(i - count) * 60))
            let roll = StableRandom.unit(id, day: 0, salt: 0x51)
            if roll >= 0.12 {
                // Recall now, drawn so a sky has mostly bright stars, a good share dim, and some in between.
                let pick = StableRandom.unit(id, day: 0, salt: 0x52)
                let recall = roll < 0.58 ? 0.8 + pick * 0.19 : roll < 0.88 ? 0.35 + pick * 0.34 : 0.7 + pick * 0.1
                let days = 2 + StableRandom.unit(id, day: 0, salt: 0x53) * 12
                let whole = days.rounded()
                let stability = max(0.05, fsrs.factor * whole / (pow(recall, 1 / fsrs.decay) - 1))
                item.memory = MemoryState(state: .review, stability: stability, difficulty: 5,
                                          due: calendar.date(byAdding: .day, value: 1, to: now),
                                          lastReview: calendar.date(byAdding: .day, value: -Int(whole), to: now)?.addingTimeInterval(-60),
                                          reps: 3)
            }
            // The item's own `course` sets the inverse; appending to the course's array too would be quadratic.
            context.insert(item)
        }
        save()
    }
}
#endif
