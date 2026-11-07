import Foundation
import SwiftData

// Lectures and the exams they mention: the dates heard in class, and the questions that came from the moments a lecturer stressed. A date is found by the rules, kept in a file beside
// the lecture, and only ever becomes an exam on a tap. One AI check runs on that tap, when it's allowed; whatever it says, the student decides.
extension AppModel {
    /// A heard date as its card shows it.
    struct ExamHeard: Equatable {
        var sourceID: UUID
        var courseID: UUID?
        var courseName: String
        var mention: ExamMention
        var date: Date
        var match: ExamHeardMatch
    }

    /// What the check on a tap came back with.
    struct ExamHeardCheck: Equatable {
        /// The model thinks this isn't an exam (nil: nobody asked, or nobody answered).
        var doubted = false
        var title: String?
        var date: Date?
    }

    /// How recent a lecture has to be for Cap to bring its date up on Today.
    static let heardNoticeDays = 14

    // MARK: Reading

    /// The dates heard in this lecture: kept in memory and in a file beside it while the transcript is the same (its size says so, with no need to read it), or found now.
    func examMentions(of source: Source) -> [ExamMention] {
        guard source.kind == .lecture, source.deletedAt == nil else { return [] }
        let bytes = source.segmentsData?.count ?? 0
        guard bytes > 0 else { return [] }
        if let kept = lectureCache.mentions[source.id], kept.bytes == bytes { return kept.mentions }
        let path = FileStore.url(for: ExamMentionFile.path(source.id))
        if let data = try? Data(contentsOf: path), let file = try? JSONDecoder.cramless.decode(ExamMentionFile.self, from: data), file.segmentBytes == bytes {
            lectureCache.mentions[source.id] = (bytes, file.mentions)
            return file.mentions
        }
        let found = ExamDateFinder.find(in: source.segments, recordedAt: source.createdAt, calendar: calendar)
        if let data = try? JSONEncoder.cramless.encode(ExamMentionFile(segmentBytes: bytes, mentions: found)) {
            _ = try? FileStore.write(data, folder: PageImageStore.sourceFolder(source.id), name: ExamMentionFile.fileName)
        }
        lectureCache.mentions[source.id] = (bytes, found)
        return found
    }

    /// The first date heard in this lecture that the student hasn't dealt with.
    func examHeard(in source: Source) -> ExamHeard? {
        let handled = settings.heardDatesHandled
        guard let mention = examMentions(of: source).first(where: { !handled.contains(Self.handledKey(source.id, $0.id)) }),
              let date = TextDates.date(day: mention.day, time: mention.clock, calendar: calendar), date > now else { return nil }
        let exams = source.course?.liveExams.map(ExamSnapshot.init) ?? []
        return ExamHeard(sourceID: source.id, courseID: source.course?.id, courseName: source.course?.name ?? "", mention: mention, date: date,
                         match: ExamHeardMatch.classify(mention, exams: exams, now: now, calendar: calendar))
    }

    /// The dates of recent lectures not dealt with, for Cap's card. One already in the plan isn't news.
    func noticeHeardDates() -> [NoticeHeardDate] {
        let lecture = SourceKind.lecture.rawValue
        let since = calendar.adding(days: -Self.heardNoticeDays, to: now)
        let recent = fetch(FetchDescriptor<Source>(predicate: #Predicate { $0.deletedAt == nil && $0.kindRaw == lecture && $0.createdAt >= since },
                                                   sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        return recent.compactMap { source -> NoticeHeardDate? in
            guard let heard = examHeard(in: source), case .new = heard.match else { return nil }
            return NoticeHeardDate(sourceID: source.id, lectureTitle: source.title, mentionID: heard.mention.id, quote: heard.mention.quote,
                                   date: heard.date, title: heard.mention.word)
        }
    }

    private static func handledKey(_ sourceID: UUID, _ mentionID: String) -> String { "\(sourceID.uuidString):\(mentionID)" }

    // MARK: Deciding

    /// "That's wrong", or a date already in the plan: this one isn't brought up again.
    func dismissExamHeard(_ heard: ExamHeard) {
        settings.heardDatesHandled.insert(Self.handledKey(heard.sourceID, heard.mention.id))
        save()
    }

    /// "That's wrong" on Cap's card: the same, from Today.
    func decline(_ decline: CapNotice.Decline) {
        switch decline {
        case .heardDate(let sourceID, let mentionID):
            settings.heardDatesHandled.insert(Self.handledKey(sourceID, mentionID))
            save()
        }
    }

    /// The one AI look at the words, after the student's tap. It may correct the name and choose among the days read; it may also doubt the whole thing, and then the student decides.
    func checkExamHeard(_ heard: ExamHeard) async -> ExamHeardCheck {
        guard let source = source(heard.sourceID) else { return ExamHeardCheck() }
        let topics = source.course?.liveTopics.map(\.name) ?? []
        let verdict = await Self.withinLessonWait(fallback: nil as ExamMentionVerdict?) {
            await self.ai.checkExamMention(heard.mention, course: heard.courseName, title: source.title, recordedAt: source.createdAt, topics: topics)
        }
        guard let verdict else { return ExamHeardCheck() }
        guard verdict.isExam else { return ExamHeardCheck(doubted: true) }
        var date: Date?
        if let checked = try? AssistantDrafts.examDate(day: verdict.date, time: verdict.time, calendar: calendar, now: now) { date = checked.date }
        return ExamHeardCheck(title: verdict.title?.clTrimmed.clNonEmpty, date: date)
    }

    /// The exam, on the whole course (the words said are on the card; a week-by-week scope waits for a later version). Undo is `deleteExam`, and `restoreExamHeard` brings the card back.
    @discardableResult
    func addExam(from heard: ExamHeard, check: ExamHeardCheck = ExamHeardCheck()) -> Exam? {
        guard let courseID = heard.courseID else { return nil }
        var draft = ExamDraft.new(courseID: courseID, now: now, calendar: calendar)
        let word = check.title ?? heard.mention.word
        draft.title = word.lowercased().contains(heard.courseName.lowercased()) ? word : "\(heard.courseName) \(word)"
        draft.date = check.date ?? heard.date
        draft.wholeCourse = true
        settings.heardDatesHandled.insert(Self.handledKey(heard.sourceID, heard.mention.id))
        return createExam(draft)
    }

    /// Undo of "Add the exam": the exam goes and the card is back.
    func undoExamHeard(_ heard: ExamHeard, examID: UUID) {
        settings.heardDatesHandled.remove(Self.handledKey(heard.sourceID, heard.mention.id))
        deleteExam(examID)
    }

    /// "Use Nov 20": the exam moves to the day the lecturer said.
    func useHeardDate(_ heard: ExamHeard) {
        guard case .moved(let examID, _, _) = heard.match, let exam = exam(examID) else { return }
        var draft = ExamDraft(exam: exam)
        if heard.mention.clock != nil {
            draft.date = heard.date
        } else {
            let keep = calendar.dateComponents([.hour, .minute], from: exam.date)
            draft.date = calendar.date(bySettingHour: keep.hour ?? 9, minute: keep.minute ?? 0, second: 0, of: heard.date) ?? heard.date
        }
        settings.heardDatesHandled.insert(Self.handledKey(heard.sourceID, heard.mention.id))
        updateExam(examID, with: draft)
    }

    // MARK: Flagged questions

    /// The questions from the moments a lecturer said would be on the exam: anchored to the flagged segment or the next one, or starting within a minute of it. Sessions take them first among
    /// ties. Worked out again only when a lecture changes or the number of questions does.
    func examFlaggedItemIDs() -> Set<UUID> {
        if let cached = lectureCache.flagged, cached.revision == revision { return cached.ids }
        let lecture = SourceKind.lecture.rawValue
        let lectures = fetch(FetchDescriptor<Source>(predicate: #Predicate { $0.deletedAt == nil && $0.kindRaw == lecture && $0.flagsData != nil }))
        guard !lectures.isEmpty else {
            lectureCache.flagged = (revision, "", [])
            return []
        }
        let active = ItemStatus.active.rawValue
        let count = (try? context.fetchCount(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == active }))) ?? 0
        let stamp = lectures.map { "\($0.id)\($0.updatedAt.timeIntervalSinceReferenceDate)" }.sorted().joined() + "|\(count)"
        if let cached = lectureCache.flagged, cached.stamp == stamp {
            lectureCache.flagged = (revision, stamp, cached.ids)
            return cached.ids
        }
        var ids = Set<UUID>()
        for source in lectures {
            let flags = source.flags
            guard !flags.isEmpty else { continue }
            let anchored = ExamFlagAnchors(flags: flags, segments: source.segments)
            for item in items(fromSource: source.id) where anchored.covers(item.sourceRef) { ids.insert(item.id) }
        }
        lectureCache.flagged = (revision, stamp, ids)
        return ids
    }
}

/// Which questions a lecture's flags point at. Pure.
struct ExamFlagAnchors: Sendable {
    /// A question starting this close after a flag is about what was flagged.
    static let window: Double = 60

    var segmentIDs = Set<String>()
    var times: [Double] = []

    init(flags: [ExamFlag], segments: [TranscriptSegment]) {
        let sorted = segments.sorted { $0.start < $1.start }
        times = flags.map(\.time)
        for flag in flags {
            guard let at = sorted.lastIndex(where: { $0.start <= flag.time }) ?? sorted.indices.first else { continue }
            segmentIDs.insert(sorted[at].id)
            if at + 1 < sorted.count { segmentIDs.insert(sorted[at + 1].id) }
        }
    }

    func covers(_ ref: SourceRef?) -> Bool {
        guard let ref else { return false }
        if ref.anchorIDs.contains(where: segmentIDs.contains) { return true }
        guard let start = ref.start else { return false }
        return times.contains { (0...Self.window).contains(start - $0) }
    }
}

/// The dates heard in one lecture, in a file beside it (not synced: another device finds them again).
struct ExamMentionFile: Codable, Sendable {
    static let fileName = "exam-mentions.json"
    static func path(_ sourceID: UUID) -> String { "\(PageImageStore.sourceFolder(sourceID))/\(fileName)" }

    /// The transcript it was read from, by size: a transcript made again is read again.
    var segmentBytes: Int
    var mentions: [ExamMention]
}

/// What the lecture code keeps between reads.
final class LectureCache {
    var flagged: (revision: Int, stamp: String, ids: Set<UUID>)?
    var mentions: [UUID: (bytes: Int, mentions: [ExamMention])] = [:]
}

#if DEBUG
// `CRAMLESS_EXAM_HEARD=new|known|moved|added` (with `CRAMLESS_ROUTE=lectureNotes`): Lecture 6 says a date. `new`: a second quiz, two weeks off; `known`: the midterm, on the day it's set for;
// `moved`: the midterm, three days sooner; `added`: as `new`, with "Add the exam" pressed.
extension AppModel {
    func applyExamHeardHarness() {
        guard config.isHarness, let state = TestHarness.value("CRAMLESS_EXAM_HEARD") else { return }
        debugHearExamDate(state)
    }

    func debugHearExamDate(_ state: String) {
        guard let bio = courses.first(where: { $0.name == "Bio 101" }), let lecture = bio.liveSources.first(where: { $0.kind == .lecture }) else { return }
        let midterm = upcomingExams().first { $0.title == "Bio 101 Midterm" }
        let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone).month(.wide).day()
        let line: String
        switch state {
        case "known":
            line = "So the midterm is on \((midterm?.date ?? now).formatted(style)), and it covers weeks one to seven."
        case "moved":
            line = "So the midterm is on \(calendar.adding(days: -3, to: midterm?.date ?? now).formatted(style)), and it covers weeks one to seven."
        default:
            line = "The second quiz is on \(calendar.adding(days: 14, to: now).formatted(style)), and it covers everything since the first one."
        }
        lecture.segments += [TranscriptSegment(id: "s7", start: 1042, end: 1060, text: line)]
        lectureCache.mentions[lecture.id] = nil
        try? FileManager.default.removeItem(at: FileStore.url(for: ExamMentionFile.path(lecture.id)))
        touch(lecture)
        save()
    }
}
#endif
