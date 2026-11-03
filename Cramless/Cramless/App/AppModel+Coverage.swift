import Foundation
import SwiftData

// What the person's questions reach of their material (`Engine/Coverage.swift` does the counting; this reads the store).
//
// A source's sections are worked out from its pages and cached until the source changes (reading every page's lines out of the store
// is the expensive part, and Today, Progress and the exam screens all ask for the exam's readiness). The anchors of the active
// questions are read each time: they change with every question added or removed.
//
// A source whose questions are still drafts waiting for review isn't counted: its state is in flux, and "Add questions for the rest"
// would replace the drafts. A deck has no text and a failed read has no lines, so neither has sections.
//
// A lecture isn't counted either. Its notes are a summary of what was said, not a reading, and a lecture gets about ten questions
// whatever its length, so a share of its transcript would read as a gap nothing could close (the rest button is for readings).
//
// An exam on some topics only: a source doesn't record which topic a passage belongs to, only the questions made from it do. So such an
// exam counts the sources that have questions on its topics, and of each only the stretch from the first passage an on-topic question
// is anchored in to the last (`Coverage.span`), and "the rest" is taken from that stretch. That is as far as the data goes: a chapter
// of the reading the exam covers but no question has touched yet is not in the stretch.

/// The sections of each source, kept until the source changes.
final class CoverageCache {
    struct Key: Hashable {
        var updatedAt: Date
        var pages: Int
        var segmentBytes: Int
    }

    var sections: [UUID: (key: Key, sections: [Coverage.Section])] = [:]
}

extension AppModel {

    // MARK: Reading the store

    /// A source's own text as coverage reads it.
    func coverageReading(of source: Source) -> Coverage.Reading {
        if source.kind == .lecture {
            return Coverage.Reading(sourceID: source.id, title: source.title, segments: source.segments)
        }
        return Coverage.Reading(sourceID: source.id, title: source.title,
                                pages: source.sortedPages.map { Coverage.Page(index: $0.pageIndex, label: $0.label, lines: $0.lines) })
    }

    private func coverageSections(of source: Source) -> [Coverage.Section] {
        let key = CoverageCache.Key(updatedAt: source.updatedAt, pages: source.pages.count, segmentBytes: source.segmentsData?.count ?? 0)
        if let cached = coverageCache.sections[source.id], cached.key == key { return cached.sections }
        let sections = Coverage.sections(of: coverageReading(of: source))
        coverageCache.sections[source.id] = (key, sections)
        return sections
    }

    /// The anchors of a course's active questions, by the source they came from. With an exam, only those on its topics.
    private func coverageAnchors(in course: Course, within exam: ExamSnapshot? = nil) -> [UUID: Set<String>] {
        var anchors: [UUID: Set<String>] = [:]
        for item in course.activeItems {
            guard let ref = item.sourceRef else { continue }
            if let exam, !exam.covers(topic: item.topicID, course: course.id) { continue }
            anchors[ref.sourceID, default: []].formUnion(ref.anchorIDs)
        }
        return anchors
    }

    /// `spanning`: only the stretch of the reading the anchors are in (an exam on some topics).
    private func coverage(of source: Source, anchors: Set<String>, spanning: Bool = false) -> Coverage.SourceCoverage? {
        guard source.deletedAt == nil, source.kind != .lecture, source.status != .drafted, source.status != .failed else { return nil }
        var sections = coverageSections(of: source)
        if spanning { sections = Coverage.span(of: sections, around: anchors) }
        return Coverage.coverage(sourceID: source.id, title: source.title, sections: sections, anchors: anchors)
    }

    // MARK: Asking

    /// How much of one source its active questions reach. Nil when there is nothing to measure (a deck, a lecture, a page not read) or
    /// its questions are waiting for review.
    func coverage(of source: Source) -> Coverage.SourceCoverage? {
        guard let course = source.course else { return nil }
        return coverage(of: source, anchors: coverageAnchors(in: course)[source.id] ?? [])
    }

    /// How much of the material an exam draws on its questions reach: every reading of the course, or, for an exam on some topics, the
    /// stretch of each reading that has questions on them (see the note at the top). Nil when none of them has anything to measure.
    func coverage(for exam: Exam) -> Coverage.Summary? {
        guard let course = exam.course, course.deletedAt == nil else { return nil }
        let snapshot = ExamSnapshot(exam)
        let anchors = coverageAnchors(in: course, within: snapshot)
        let sources = course.liveSources.sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.title < $1.title }
        var counted: [Coverage.SourceCoverage] = []
        for source in sources {
            if snapshot.wholeCourse {
                if let part = coverage(of: source, anchors: anchors[source.id] ?? []) { counted.append(part) }
            } else if let found = anchors[source.id], !found.isEmpty,
                      let part = coverage(of: source, anchors: found, spanning: true) {
                counted.append(part)
            }
        }
        return Coverage.summary(counted)
    }

    /// The source "Add questions for the rest" works on for an exam: the one with the most still uncovered.
    func restTarget(in summary: Coverage.Summary) -> Coverage.SourceCoverage? {
        summary.sources
            .filter { $0.uncoveredWords > 0 }
            .sorted { $0.uncoveredWords != $1.uncoveredWords ? $0.uncoveredWords > $1.uncoveredWords : $0.title < $1.title }
            .first
    }

    // MARK: The rest

    /// What the next "Add questions for the rest" of `coverage`'s source works on, decided now: the passages no question reaches, on
    /// the pages the earlier runs for this source did not use, and no more pages than one scan takes (a free reading's 10, so a rest
    /// never costs more than one of the week's free scans). Nil when nothing is left.
    func restPlan(for coverage: Coverage.SourceCoverage) -> Coverage.Rest? {
        Coverage.rest(of: coverage, usedPages: restPagesUsed(coverage.sourceID), pageLimit: AIFreeLimits.pagesPerScan(ai.plan))
    }

    /// The request for the rest of one source, counting all of its questions (the Library's view). Nil when everything has one.
    func restRequest(for source: Source) -> CaptureRequest? {
        guard let coverage = coverage(of: source), let plan = restPlan(for: coverage) else { return nil }
        return .rest(plan, in: source.course?.id)
    }

    /// The request for the rest of an exam's material: the reading with the most left, and of it only what the exam draws on.
    func restRequest(for exam: Exam) -> CaptureRequest? {
        guard let summary = coverage(for: exam), let target = restTarget(in: summary), let plan = restPlan(for: target) else { return nil }
        return .rest(plan, in: exam.course?.id)
    }

    /// What `ai.generateSet` takes for a rest: the lines of the plan as pages of just those lines (their ids are the source's own,
    /// so the new questions anchor to the real lines), in reading order. Nil when none of them is there any more. A formulas read of
    /// the plan's pages since it was decided has added lines to them: those that follow the plan's lines are part of it
    /// (`Coverage.lineIDs`), so the formulas reach the new questions.
    func generationInput(for plan: Coverage.Rest, of source: Source) -> GenerationInput? {
        var pages: [PageText] = []
        let wanted = Coverage.lineIDs(of: plan, in: coverageReading(of: source))
        for page in source.sortedPages {
            let lines = page.lines.filter { wanted.contains($0.id) }
            guard !lines.isEmpty else { continue }
            pages.append(PageText(index: page.pageIndex, label: page.label, lines: lines,
                                  imageURL: page.imageFileName.map { FileStore.url(for: $0) }))
        }
        guard !pages.isEmpty else { return nil }
        return GenerationInput(course: source.course?.name ?? "", sourceTitle: source.title, level: settings.level?.rawValue,
                               pages: pages, formats: ItemKind.allCases,
                               maxItems: min(AIFreeLimits.maximumQuestions(ai.plan), max(6, plan.sections)),
                               courseLanguage: courseLanguage(of: source.course, excluding: source.id))
    }

    // MARK: Which pages a rest already used

    private func restKey(_ sourceID: UUID) -> String { "capling.rest.pages.\(sourceID.uuidString)" }

    /// The pages the runs of "Add questions for the rest" since the round last began used for a source. Kept on this iPhone, outside the
    /// store (nothing to migrate): it only steers which passages come next.
    func restPagesUsed(_ sourceID: UUID) -> Set<Int> {
        Set(defaults.array(forKey: restKey(sourceID)) as? [Int] ?? [])
    }

    /// A rest's drafts are made: the pages that were read for them are used, so the next tap moves on to different passages, and a plan
    /// that began the round again forgets the pages from before it. `readPages` is the pages of the parts of the reading that were
    /// read (`GenerationOutcome.pagesRead`): a part that failed, or that the free scans left unstarted, leaves its pages for the next
    /// tap, which would otherwise skip pages that never got a question. Nil: every page of the plan was read.
    func noteRestRun(_ plan: Coverage.Rest, readPages: Set<Int>? = nil) {
        var used = plan.startsOver ? [] : restPagesUsed(plan.sourceID)
        used.formUnion(readPages.map { $0.intersection(plan.pages) } ?? Set(plan.pages))
        defaults.set(used.sorted(), forKey: restKey(plan.sourceID))
    }
}
