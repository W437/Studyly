import Foundation

/// Turns a generator's output into models. Every generator (cloud, on-device, rules, the sample, imports) goes
/// through here, so an item's source link, diagram boxes and topic are built one way.
enum ItemFactory {
    /// The source label for an item: "p. 87 · Anaphase" for a page, "Lecture 6 · 12:05" for a lecture.
    static func sourceLabel(source: Source, page: SourcePage?, anchors: [String], lineTexts: [String: String],
                            segments: [TranscriptSegment] = []) -> String {
        if source.kind == .lecture {
            let start = segments.first { anchors.contains($0.id) }?.start ?? 0
            return "\(shortTitle(source.title)) · \(timestamp(start))"
        }
        let pageLabel = page.map { "p. \($0.label)" } ?? source.title
        // A heading-like line among the anchors names the section ("Anaphase", "Why is mitosis important?").
        let heading = anchors.compactMap { lineTexts[$0] }.first { text in
            let words = text.split(separator: " ")
            return words.count <= 6 && !text.hasPrefix("•") && text.first?.isUppercase == true
        }
        if let heading { return "\(pageLabel) · \(heading.trimmingCharacters(in: CharacterSet(charactersIn: ".:")))" }
        return pageLabel
    }

    static func shortTitle(_ title: String) -> String {
        if let colon = title.firstIndex(of: ":") { return String(title[..<colon]) }
        return title
    }

    static func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Makes a StudyItem from a generated item. Diagram targets get their boxes from the page's own lines.
    static func makeItem(from generated: GeneratedItem, course: Course, topicID: UUID?, source: Source?,
                         page: SourcePage?, origin: ItemOrigin, status: ItemStatus, now: Date) -> StudyItem {
        let lines = page?.lines ?? []
        let byID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
        var ref: SourceRef?
        if let source {
            let segments = source.kind == .lecture ? source.segments : []
            let label = sourceLabel(source: source, page: page, anchors: generated.anchors,
                                    lineTexts: byID.mapValues(\.text), segments: segments)
            let times = segments.filter { generated.anchors.contains($0.id) }
            ref = SourceRef(sourceID: source.id, pageIndex: page?.pageIndex, anchorIDs: generated.anchors,
                            start: times.map(\.start).min(), end: times.map(\.end).max(), label: label)
        }
        var diagram: DiagramSpec?
        if generated.kind == .diagram, let source, let page, let labels = generated.diagramLabels {
            let targets = labels.compactMap { id -> DiagramTarget? in
                guard let line = byID[id], let box = line.box else { return nil }
                return DiagramTarget(anchorID: id, label: line.text, box: box)
            }
            if !targets.isEmpty { diagram = DiagramSpec(sourceID: source.id, pageIndex: page.pageIndex, targets: targets) }
        }
        // A diagram whose labels can't be boxed becomes a plain question rather than a broken one.
        let kind: ItemKind = (generated.kind == .diagram && diagram == nil) ? .recall : generated.kind
        var keyIdeas = generated.keyIdeas
        if kind == .recall && generated.kind == .diagram && keyIdeas.isEmpty {
            keyIdeas = generated.answer.split(separator: ",").enumerated().map { i, part in
                let t = part.trimmingCharacters(in: .whitespaces)
                return KeyIdea(id: "k\(i + 1)", label: t, terms: [t.lowercased()])
            }
        }
        return StudyItem(course: course, topicID: topicID, kind: kind, status: status, origin: origin,
                         prompt: generated.prompt, answer: generated.answer, explanation: generated.explanation,
                         keyIdeas: keyIdeas, choices: generated.choices, cloze: generated.cloze, diagram: diagram,
                         sourceRef: ref, difficultyHint: generated.difficulty, now: now)
    }

    /// Finds or creates the course's topic with this name (case-insensitive).
    static func topic(named name: String, in course: Course, summary: String = "", now: Date) -> Topic? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let existing = course.topics.first(where: { $0.deletedAt == nil && $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
            return existing
        }
        let topic = Topic(course: course, name: clean, summary: summary, sortOrder: course.topics.count, now: now)
        course.topics.append(topic)
        return topic
    }
}
