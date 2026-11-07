import Foundation

/// An exam's topics that nothing has been added for yet: they can't count toward readiness, however hard the student studies the rest. Pure.
/// A topic whose questions are written and waiting in review isn't a gap: it only needs a look.
struct ExamGap: Equatable, Sendable {
    struct Topic: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
    }

    var examID: UUID
    var examTitle: String
    var examDate: Date
    var daysLeft: Int
    /// No questions and no drafts.
    var topics: [Topic]
    /// Questions waiting for the student's review.
    var waiting: [Topic]
}

enum ExamGaps {
    /// Days before the exam Cap brings it up on Today. Inside two there's no time to add a chapter and study it (and an eve is quiet).
    static let noticeDays = 2...28

    /// The gaps of one exam. Nil with none, on the day and on the eve.
    /// - `within`: how far off the exam may be (`nil`: any distance, as the exam page shows them).
    /// - `covered`: empty topics whose words the student's questions or notes already speak of (`SyllabusMatcher`): not gaps, whatever they're filed under.
    static func find(exam: ExamSnapshot, topicReadiness: [TopicReadiness], draftTopicIDs: Set<UUID>, covered: Set<UUID> = [], daysLeft: Int,
                     within: ClosedRange<Int>? = noticeDays) -> ExamGap? {
        guard daysLeft >= noticeDays.lowerBound, within?.contains(daysLeft) ?? true else { return nil }
        let empty = topicReadiness.filter { $0.value == nil && $0.itemCount == 0 && !covered.contains($0.id) }
        let topics = empty.filter { !draftTopicIDs.contains($0.id) }.map { ExamGap.Topic(id: $0.id, name: $0.name) }
        let waiting = empty.filter { draftTopicIDs.contains($0.id) }.map { ExamGap.Topic(id: $0.id, name: $0.name) }
        guard !topics.isEmpty || !waiting.isEmpty else { return nil }
        return ExamGap(examID: exam.id, examTitle: exam.title, examDate: exam.date, daysLeft: daysLeft, topics: topics, waiting: waiting)
    }
}

/// The words of a gap, on Cap's card and the exam page.
enum ExamGapCopy {
    /// How many topics a line names before "and N more".
    static let namedTopics = 3

    /// "2 topics on your Bio 101 Midterm have no notes".
    static func title(count: Int, examTitle: String) -> String {
        String(localized: "\(count) topics on your \(examTitle) have no notes")
    }

    /// "Meiosis and Genetics. Want help filling them in?"
    static func detail(_ names: [String]) -> String {
        names.count == 1 ? String(localized: "\(list(names)). Want help filling it in?") : String(localized: "\(list(names)). Want help filling them in?")
    }

    /// "Questions for Meiosis are waiting for your review."
    static func waiting(_ names: [String]) -> String {
        String(localized: "Questions for \(list(names)) are waiting for your review.")
    }

    /// Up to three names joined with "and", then how many more.
    static func list(_ names: [String]) -> String {
        guard names.count > namedTopics else { return names.formatted(.list(type: .and)) }
        let shown = names.prefix(namedTopics).joined(separator: ", ")
        return String(localized: "\(shown) and \(names.count - namedTopics) more")
    }
}
