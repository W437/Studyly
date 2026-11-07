import Foundation
import SwiftData

// Teach Cap, from the store's side: what a topic's plan is made of, the follow-up's one review, and the missing idea as a new question.
// What the person said isn't kept anywhere: the words live in the session while it's open, and the review the follow-up records has no answer in it.
extension AppModel {
    /// What Cap hopes to hear about a topic; nil with too little to ask.
    func teachPlan(topicID: UUID) -> TeachPlan? {
        guard let topic = fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.id == topicID })).first, topic.deletedAt == nil,
              let course = topic.course, course.deletedAt == nil else { return nil }
        let items = course.items.filter { $0.deletedAt == nil && $0.status == .active && $0.topicID == topicID && $0.kind != .diagram }
        return TeachPlanner.plan(topicID: topicID, topicName: topic.name, courseID: course.id, items: items.map(teachItem))
    }

    private func teachItem(_ item: StudyItem) -> TeachItem {
        let memory = item.memory
        let studied = memory.state != .new && memory.lastReview != nil && memory.stability > 0
        let answer: String
        switch item.kind {
        case .mcq: answer = item.choices.first(where: \.correct)?.text ?? item.answer
        case .cloze: answer = item.cloze?.answers.first ?? item.answer
        default: answer = item.answer
        }
        let reason = item.kind == .mcq ? item.choices.first(where: \.correct)?.why?.clNonEmpty : nil
        return TeachItem(id: item.id, kind: item.kind, prompt: item.prompt, answer: answer, ideas: item.kind.isOwnWords ? item.keyIdeas : [],
                         recall: studied ? fsrs.retrievability(of: memory, at: now) : nil, cloze: item.kind == .cloze ? item.cloze : nil,
                         explanation: reason ?? item.explanation)
    }

    /// The question behind a missed idea, to ask as the follow-up.
    func teachFollowUp(for idea: TeachIdea) -> TeachFollowUp? {
        guard let item = item(idea.itemID), item.deletedAt == nil else { return nil }
        let value = teachItem(item)
        return TeachFollowUp(itemID: item.id, prompt: TeachPlanner.followUpPrompt(of: value), answer: value.answer, idea: idea,
                             subject: TeachPlanner.followUpSubject(value, level: settings.level?.rawValue),
                             canAdd: TeachPlanner.addedQuestion(for: idea, from: value) != nil)
    }

    /// The follow-up's answer: one review, like any other, with no words in it.
    @discardableResult
    func recordTeachFollowUp(_ followUp: TeachFollowUp, rating: Rating, score: Double, gradedBy: String, durationMs: Int) -> ReviewOutcome? {
        recordReview(itemID: followUp.itemID, rating: rating, score: score, answer: nil, gradedBy: gradedBy, durationMs: durationMs)
    }

    /// "Add the missing idea as a question": a question in the person's own words, on the same topic, linked to the same page or lecture moment as the
    /// question the idea comes from. The person asked for it, so it goes straight into the course. Nil when it would only repeat itself (`TeachPlanner.addedQuestion`).
    @discardableResult
    func addMissingIdea(_ idea: TeachIdea, topicID: UUID) -> StudyItem? {
        guard let parent = item(idea.itemID), parent.deletedAt == nil, let course = parent.course, course.deletedAt == nil,
              let added = TeachPlanner.addedQuestion(for: idea, from: teachItem(parent)) else { return nil }
        var page: SourcePage?
        var source: Source?
        if let ref = parent.sourceRef, let found = self.source(ref.sourceID), found.deletedAt == nil {
            source = found
            page = ref.pageIndex.flatMap { index in found.pages.first { $0.pageIndex == index } }
        }
        let generated = GeneratedItem(id: "teach", kind: .recall, topic: "", prompt: added.prompt, answer: added.answer,
                                      explanation: parent.explanation, keyIdeas: [added.idea], anchors: parent.sourceRef?.anchorIDs ?? [])
        let made = ItemFactory.makeItem(from: generated, course: course, topicID: topicID, source: source, page: page, origin: .rules, status: .active, now: now)
        context.insert(made)
        course.items.append(made)
        touch(made)
        save()
        return made
    }

    /// The topics Cap may offer today, from the store (`TeachPlanner.offers`).
    func teachOffers(items: [ItemSnapshot], exams: [ExamSnapshot]) -> [NoticeTeachBack] {
        var mastery: [TopicReadiness] = []
        var courseOf: [UUID: UUID] = [:]
        for course in courses {
            let topics = topicMastery(course: course)
            mastery += topics
            for topic in topics { courseOf[topic.id] = course.id }
        }
        // Every exam, not only those to come: one just sat keeps its topics quiet for a few days.
        return TeachPlanner.offers(mastery: mastery, courseOf: courseOf, items: items, exams: examSnapshots(), taught: noticeLedger.taught, now: now, calendar: calendar)
    }
}

/// The follow-up: one question, from the first missed idea.
struct TeachFollowUp: Equatable, Sendable {
    var itemID: UUID
    var prompt: String
    var answer: String
    var idea: TeachIdea
    var subject: GradeSubject
    /// The missed idea can become a question of its own.
    var canAdd = true
}
