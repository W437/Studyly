import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Settings ▸ Your data: every card as CSV (for a spreadsheet, Anki or Quizlet) and everything as JSON. The formats
/// are pure functions of plain records (`DataExport.csv`, `DataExport.json`), tested in `SettingsExportTests`; the
/// records are read from the store on the main actor. Nothing leaves the iPhone except where the person sends it.
enum DataExport {

    // MARK: Cards as CSV

    /// One card as a CSV row.
    struct CardRow: Codable, Equatable, Sendable {
        var course: String
        var topic: String
        var kind: String
        var question: String
        var answer: String
        /// Multiple choice: every option, in order.
        var options: [String]
        var explanation: String
        var source: String
        var status: String
        var due: Date?
        var reviews: Int
        var lapses: Int
    }

    static let csvHeader = ["Course", "Topic", "Type", "Question", "Answer", "Options", "Explanation", "Source", "Status",
                            "Due", "Reviews", "Lapses"]

    /// RFC 4180 CSV with a header row and CRLF line ends. Due dates are days in the person's time zone.
    static func csv(_ rows: [CardRow], timeZone: TimeZone = .current) -> String {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        day.timeZone = timeZone
        var lines = [csvHeader.map(field).joined(separator: ",")]
        for row in rows {
            let cells = [row.course, row.topic, row.kind, row.question, row.answer, row.options.joined(separator: " | "),
                         row.explanation, row.source, row.status, row.due.map { day.string(from: $0) } ?? "",
                         String(row.reviews), String(row.lapses)]
            lines.append(cells.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// One CSV field: quoted when it holds a comma, quote or line break (quotes doubled). A field a spreadsheet would
    /// run as a formula (starting with =, + or @) gets a leading apostrophe.
    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+@".contains(first) { text = "'" + text }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            || text.hasPrefix(" ") || text.hasSuffix(" ") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A card's row: a fill-in reads as its sentence with blanks, a multiple choice as its right option.
    static func row(prompt: String, answer: String, kind: ItemKind, choices: [Choice], cloze: ClozeSpec?, explanation: String,
                    course: String, topic: String, source: String, status: ItemStatus, due: Date?, reviews: Int, lapses: Int) -> CardRow {
        var question = prompt
        var answerText = answer
        switch kind {
        case .cloze:
            if let cloze {
                question = cloze.text.replacingOccurrences(of: #"\{\{[^}]*\}\}"#, with: "____", options: .regularExpression)
                answerText = cloze.answers.joined(separator: "; ")
            }
        case .mcq:
            if let right = choices.first(where: \.correct) { answerText = right.text }
        default:
            break
        }
        return CardRow(course: course, topic: topic, kind: kind.displayName, question: question, answer: answerText,
                       options: kind == .mcq ? choices.map(\.text) : [], explanation: explanation, source: source,
                       status: status.rawValue, due: due, reviews: reviews, lapses: lapses)
    }

    // MARK: Everything as JSON

    struct Archive: Codable, Equatable, Sendable {
        var format = "capling-export"
        var version = 1
        var exportedAt: Date
        var app: String
        var profile: ProfileRecord
        var courses: [CourseRecord]
        var reviews: [ReviewRecord]
        var sessions: [SessionRecord]
        var days: [DayEntry]
        var chats: [ChatRecord]
    }

    struct ProfileRecord: Codable, Equatable, Sendable {
        var firstName: String
        var goal: String?
        var level: String?
        var dailyMinutes: Int
        var reminderMinutes: Int?
        var quietHoursStart: Int
        var quietHoursEnd: Int
        var targetRetention: Double
        var easyDays: [Int]
        var tutorMode: String
        var cloudAI: Bool
        var sendPhotos: Bool
        var theme: String
        var dyslexicFont: Bool
        var readAloud: Bool
        var haptics: Bool
        var sounds: Bool
        var capMoves: Bool
        /// Optional so an archive made before it existed still reads.
        var capTalks: Bool?
    }

    struct CourseRecord: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var color: String
        var createdAt: Date
        var topics: [TopicRecord]
        var sources: [SourceRecord]
        var items: [ItemRecord]
        var exams: [ExamRecord]
        var confusions: [ConfusionRecord]
    }

    struct TopicRecord: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var summary: String
    }

    struct SourceRecord: Codable, Equatable, Sendable {
        var id: UUID
        var kind: String
        var title: String
        var createdAt: Date
        var pages: [PageRecord]
        var transcript: [TranscriptSegment]
        var lectureNotes: LectureNotes?
    }

    struct PageRecord: Codable, Equatable, Sendable {
        var index: Int
        var label: String
        var text: String
    }

    struct ItemRecord: Codable, Equatable, Sendable {
        var id: UUID
        var topicID: UUID?
        var kind: String
        var status: String
        var origin: String
        var prompt: String
        var answer: String
        var explanation: String
        var keyIdeas: [KeyIdea]
        var choices: [Choice]
        var cloze: ClozeSpec?
        var source: SourceRef?
        var memory: MemoryState
        var createdAt: Date
    }

    struct ExamRecord: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var date: Date
        var format: ExamFormat
        var targetReadiness: Double
        var resultScore: Double?
    }

    struct ConfusionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var explanation: String
        var status: String
        var itemIDs: [UUID]
    }

    struct ReviewRecord: Codable, Equatable, Sendable {
        var itemID: UUID
        var reviewedAt: Date
        var rating: Int
        var score: Double?
        var answer: String?
        var gradedBy: String
        var seconds: Double
    }

    struct SessionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var kind: String
        var startedAt: Date
        var endedAt: Date?
        var minutes: Double
        var questions: Int
        var correct: Int
    }

    struct DayEntry: Codable, Equatable, Sendable {
        var day: String
        var minutes: Double
        var reviewed: Int
        var frozen: Bool
    }

    struct ChatRecord: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var courseID: UUID?
        var createdAt: Date
        var messages: [MessageRecord]
    }

    struct MessageRecord: Codable, Equatable, Sendable {
        var role: String
        var text: String
        var citations: [Citation]
        var answeredBy: String?
        var createdAt: Date
    }

    static func json(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Archive.self, from: data)
    }

    // MARK: From the store

    /// Every live card, course by course, as CSV rows.
    @MainActor
    static func cardRows(app: AppModel) -> [CardRow] {
        app.courses.flatMap { course -> [CardRow] in
            let topics = Dictionary(uniqueKeysWithValues: course.topics.map { ($0.id, $0.name) })
            return course.liveItems
                .filter { $0.status == .active || $0.status == .suspended }
                .sorted { $0.createdAt < $1.createdAt }
                .map { item in
                    row(prompt: item.prompt, answer: item.answer, kind: item.kind, choices: item.choices, cloze: item.cloze,
                        explanation: item.explanation, course: course.name, topic: item.topicID.flatMap { topics[$0] } ?? "",
                        source: item.sourceRef?.label ?? "", status: item.status, due: item.due, reviews: item.reps,
                        lapses: item.lapses)
                }
        }
    }

    /// Everything the person has made or done in Capling (live, not in the trash), and their settings.
    @MainActor
    static func archive(app: AppModel) -> Archive {
        let s = app.settings
        let profile = ProfileRecord(firstName: s.firstName, goal: s.goal?.rawValue, level: s.level?.rawValue,
                                    dailyMinutes: s.dailyMinutes, reminderMinutes: s.reminderMinutes,
                                    quietHoursStart: s.quietHoursStart, quietHoursEnd: s.quietHoursEnd,
                                    targetRetention: s.targetRetention, easyDays: s.easyDays, tutorMode: s.tutorMode.rawValue,
                                    cloudAI: app.hasCloudConsent, sendPhotos: s.sendPhotos, theme: s.theme.rawValue,
                                    dyslexicFont: s.dyslexicFont, readAloud: s.readAloud, haptics: s.haptics,
                                    sounds: s.sounds, capMoves: s.capMoves, capTalks: s.capTalks)
        let courses = app.courses.map { course in
            CourseRecord(
                id: course.id, name: course.name, color: course.colorRaw, createdAt: course.createdAt,
                topics: course.liveTopics.map { TopicRecord(id: $0.id, name: $0.name, summary: $0.summary) },
                sources: course.liveSources.sorted { $0.createdAt < $1.createdAt }.map { source in
                    SourceRecord(id: source.id, kind: source.kindRaw, title: source.title, createdAt: source.createdAt,
                                 pages: source.sortedPages.map { PageRecord(index: $0.pageIndex, label: $0.label, text: $0.text) },
                                 transcript: source.kind == .lecture ? source.segments : [],
                                 lectureNotes: source.kind == .lecture ? source.notes : nil)
                },
                items: course.liveItems.sorted { $0.createdAt < $1.createdAt }.map { item in
                    ItemRecord(id: item.id, topicID: item.topicID, kind: item.kindRaw, status: item.statusRaw,
                               origin: item.originRaw, prompt: item.prompt, answer: item.answer, explanation: item.explanation,
                               keyIdeas: item.keyIdeas, choices: item.choices, cloze: item.cloze, source: item.sourceRef,
                               memory: item.memory, createdAt: item.createdAt)
                },
                exams: course.liveExams.map {
                    ExamRecord(id: $0.id, title: $0.title, date: $0.date, format: $0.format,
                               targetReadiness: $0.targetReadiness, resultScore: $0.resultScore)
                },
                confusions: course.confusions.filter { $0.deletedAt == nil }.map {
                    ConfusionRecord(id: $0.id, name: $0.name, explanation: $0.explanation, status: $0.statusRaw, itemIDs: $0.itemIDs)
                })
        }
        let liveItemIDs = Set(courses.flatMap { $0.items.map(\.id) })
        let reviews = app.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)]))
            .filter { liveItemIDs.contains($0.itemID) }
            .map { ReviewRecord(itemID: $0.itemID, reviewedAt: $0.reviewedAt, rating: $0.ratingRaw,
                                score: $0.score >= 0 ? $0.score : nil, answer: $0.answer, gradedBy: $0.gradedBy,
                                seconds: Double($0.durationMs) / 1000) }
        let sessions = app.fetch(FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\.startedAt)])).map {
            SessionRecord(id: $0.id, kind: $0.kindRaw, startedAt: $0.startedAt, endedAt: $0.endedAt,
                          minutes: ($0.activeSeconds / 60 * 10).rounded() / 10, questions: $0.itemCount, correct: $0.correctCount)
        }
        let days = app.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.day)])).map {
            DayEntry(day: $0.dayKey, minutes: ($0.studySeconds / 60 * 10).rounded() / 10, reviewed: $0.itemsReviewed, frozen: $0.frozen)
        }
        let chats = app.chatThreads().reversed().map { thread in
            ChatRecord(id: thread.id, title: thread.title, courseID: thread.courseID, createdAt: thread.createdAt,
                       messages: thread.sortedMessages.map {
                           MessageRecord(role: $0.roleRaw, text: $0.text, citations: $0.citations, answeredBy: $0.origin,
                                         createdAt: $0.createdAt)
                       })
        }
        return Archive(exportedAt: app.now, app: "Capling \(AboutInfo.version)", profile: profile, courses: courses,
                       reviews: reviews, sessions: sessions, days: days, chats: Array(chats))
    }

    /// "Capling cards 2026-10-22.csv".
    static func fileName(_ base: String, ext: String, date: Date) -> String {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        day.timeZone = .current
        return "\(base) \(day.string(from: date)).\(ext)"
    }
}

/// A finished export, handed to the share sheet as a file with a dated name.
struct ExportFile: Transferable, Sendable {
    var data: Data
    var fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            SentTransferredFile(try file.write())
        }
        .exportingCondition { $0.fileName.hasSuffix(".csv") }
        FileRepresentation(exportedContentType: .json) { file in
            SentTransferredFile(try file.write())
        }
        .exportingCondition { $0.fileName.hasSuffix(".json") }
    }

    /// Written to a fresh temporary folder, so two exports on one day never collide.
    func write() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// The app's version for About and the export: "1.0 (1)".
enum AboutInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
