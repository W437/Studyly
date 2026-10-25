import Foundation

// The synced tables as rows: each model's fields in snake_case (the columns of
// supabase/migrations/20261022000000_cramless_schema.sql). Rows never carry `user_id` (the server fills it from the
// token) or `synced_at` (the server stamps it). Codable blobs travel as embedded JSON. Every row a table sends has
// the same keys, and a nil field is an explicit null, because PostgREST updates exactly the keys it receives.

/// Finds the local models a pulled row points at.
struct SyncResolver {
    var course: (UUID?) -> Course?
    var source: (UUID?) -> Source?
}

enum SyncRecords {
    // MARK: courses

    static func row(_ c: Course) -> SyncRow {
        ["id": .uuid(c.id), "name": .string(c.name), "color": .string(c.colorRaw), "symbol": .string(c.symbol),
         "sort_order": .integer(c.sortOrder), "created_at": .date(c.createdAt), "updated_at": .date(c.updatedAt),
         "deleted_at": .date(c.deletedAt)]
    }

    static func makeCourse(_ row: SyncRow) -> Course? {
        guard let id = row.uuid("id") else { return nil }
        let course = Course(id: id, name: row.string("name") ?? "")
        fill(course, from: row)
        return course
    }

    static func fill(_ c: Course, from row: SyncRow) {
        if let v = row.string("name") { c.name = v }
        if let v = row.string("color") { c.colorRaw = v }
        if let v = row.string("symbol") { c.symbol = v }
        if let v = row.int("sort_order") { c.sortOrder = v }
        if let v = row.date("created_at") { c.createdAt = v }
        c.deletedAt = row.date("deleted_at")
    }

    // MARK: topics

    static func row(_ t: Topic) -> SyncRow {
        ["id": .uuid(t.id), "course_id": .uuid(t.course?.id), "name": .string(t.name), "summary": .string(t.summary),
         "sort_order": .integer(t.sortOrder), "created_at": .date(t.createdAt), "updated_at": .date(t.updatedAt),
         "deleted_at": .date(t.deletedAt)]
    }

    static func makeTopic(_ row: SyncRow, _ resolve: SyncResolver) -> Topic? {
        guard let id = row.uuid("id") else { return nil }
        let topic = Topic(id: id, course: nil, name: row.string("name") ?? "")
        fill(topic, from: row, resolve)
        return topic
    }

    static func fill(_ t: Topic, from row: SyncRow, _ resolve: SyncResolver) {
        t.course = resolve.course(row.uuid("course_id"))
        if let v = row.string("name") { t.name = v }
        if let v = row.string("summary") { t.summary = v }
        if let v = row.int("sort_order") { t.sortOrder = v }
        if let v = row.date("created_at") { t.createdAt = v }
        t.deletedAt = row.date("deleted_at")
    }

    // MARK: sources and their pages

    static func row(_ s: Source) -> SyncRow {
        ["id": .uuid(s.id), "course_id": .uuid(s.course?.id), "kind": .string(s.kindRaw), "status": .string(s.statusRaw),
         "title": .string(s.title), "file_name": .text(s.fileName), "duration": .number(s.duration),
         "segments": .blob(s.segmentsData), "flags": .blob(s.flagsData), "notes": .blob(s.notesData),
         "created_at": .date(s.createdAt), "updated_at": .date(s.updatedAt), "deleted_at": .date(s.deletedAt)]
    }

    static func makeSource(_ row: SyncRow, _ resolve: SyncResolver) -> Source? {
        guard let id = row.uuid("id") else { return nil }
        let source = Source(id: id, course: nil, kind: SourceKind(rawValue: row.string("kind") ?? "") ?? .text,
                            title: row.string("title") ?? "")
        fill(source, from: row, resolve)
        return source
    }

    static func fill(_ s: Source, from row: SyncRow, _ resolve: SyncResolver) {
        s.course = resolve.course(row.uuid("course_id"))
        if let v = row.string("kind") { s.kindRaw = v }
        if let v = row.string("status") { s.statusRaw = v }
        if let v = row.string("title") { s.title = v }
        s.fileName = row.string("file_name")
        if let v = row.double("duration") { s.duration = v }
        s.segmentsData = row.blob("segments")
        s.flagsData = row.blob("flags")
        s.notesData = row.blob("notes")
        if let v = row.date("created_at") { s.createdAt = v }
        s.deletedAt = row.date("deleted_at")
    }

    /// A page goes up with its source and carries the source's `updatedAt` (pages have no stamps of their own).
    /// `image_path` is never sent here: only the device that uploads the image sets it.
    static func row(_ p: SourcePage, source: Source) -> SyncRow {
        ["id": .uuid(p.id), "source_id": .uuid(source.id), "page_index": .integer(p.pageIndex), "label": .string(p.label),
         "text": .string(p.text), "lines": .blob(p.linesData), "read": .blob(p.readData),
         "width": .number(p.width), "height": .number(p.height),
         "updated_at": .date(source.updatedAt), "deleted_at": .null]
    }

    static func makePage(_ row: SyncRow, source: Source) -> SourcePage? {
        guard let id = row.uuid("id") else { return nil }
        let page = SourcePage(id: id, source: source, pageIndex: row.int("page_index") ?? 0, label: row.string("label") ?? "",
                              text: row.string("text") ?? "", lines: [])
        fill(page, from: row)
        return page
    }

    static func fill(_ p: SourcePage, from row: SyncRow) {
        if let v = row.int("page_index") { p.pageIndex = v }
        if let v = row.string("label") { p.label = v }
        if let v = row.string("text") { p.text = v }
        p.linesData = row.blob("lines")
        p.readData = row.blob("read")
        if let v = row.double("width") { p.width = v }
        if let v = row.double("height") { p.height = v }
    }

    // MARK: items

    static func row(_ i: StudyItem) -> SyncRow {
        ["id": .uuid(i.id), "course_id": .uuid(i.course?.id), "topic_id": .uuid(i.topicID), "kind": .string(i.kindRaw),
         "status": .string(i.statusRaw), "origin": .string(i.originRaw), "prompt": .string(i.prompt),
         "answer": .string(i.answer), "explanation": .string(i.explanation), "key_ideas": .blob(i.keyIdeasData),
         "choices": .blob(i.choicesData), "cloze": .blob(i.clozeData), "diagram": .blob(i.diagramData),
         "source_ref": .blob(i.sourceRefData), "checked_at": .date(i.checkedAt),
         "difficulty_hint": .number(i.difficultyHint), "reported": .bool(i.reported), "state": .integer(i.stateRaw),
         "stability": .number(i.stability), "difficulty": .number(i.difficulty), "due": .date(i.due),
         "last_review": .date(i.lastReview), "reps": .integer(i.reps), "lapses": .integer(i.lapses),
         "step": .integer(i.step), "created_at": .date(i.createdAt), "updated_at": .date(i.updatedAt),
         "deleted_at": .date(i.deletedAt)]
    }

    static func makeItem(_ row: SyncRow, _ resolve: SyncResolver) -> StudyItem? {
        guard let id = row.uuid("id") else { return nil }
        let item = StudyItem(id: id, course: nil, kind: ItemKind(rawValue: row.string("kind") ?? "") ?? .flashcard,
                             origin: ItemOrigin(rawValue: row.string("origin") ?? "") ?? .person,
                             prompt: row.string("prompt") ?? "", answer: row.string("answer") ?? "")
        fill(item, from: row, resolve)
        return item
    }

    static func fill(_ i: StudyItem, from row: SyncRow, _ resolve: SyncResolver) {
        i.course = resolve.course(row.uuid("course_id"))
        i.topicID = row.uuid("topic_id")
        if let v = row.string("kind") { i.kindRaw = v }
        if let v = row.string("status") { i.statusRaw = v }
        if let v = row.string("origin") { i.originRaw = v }
        if let v = row.string("prompt") { i.prompt = v }
        if let v = row.string("answer") { i.answer = v }
        if let v = row.string("explanation") { i.explanation = v }
        i.keyIdeasData = row.blob("key_ideas")
        i.choicesData = row.blob("choices")
        i.clozeData = row.blob("cloze")
        i.diagramData = row.blob("diagram")
        i.sourceRefData = row.blob("source_ref")
        i.checkedAt = row.date("checked_at")
        if let v = row.double("difficulty_hint") { i.difficultyHint = v }
        if let v = row.bool("reported") { i.reported = v }
        if let v = row.int("state") { i.stateRaw = v }
        if let v = row.double("stability") { i.stability = v }
        if let v = row.double("difficulty") { i.difficulty = v }
        i.due = row.date("due")
        i.lastReview = row.date("last_review")
        if let v = row.int("reps") { i.reps = v }
        if let v = row.int("lapses") { i.lapses = v }
        if let v = row.int("step") { i.step = v }
        if let v = row.date("created_at") { i.createdAt = v }
        i.deletedAt = row.date("deleted_at")
    }

    // MARK: review logs (insert-only)

    static func row(_ r: ReviewLog) -> SyncRow {
        ["id": .uuid(r.id), "item_id": .uuid(r.itemID), "course_id": .uuid(r.courseID), "session_id": .uuid(r.sessionID),
         "reviewed_at": .date(r.reviewedAt), "rating": .integer(r.ratingRaw), "score": .number(r.score),
         "answer": .text(r.answer), "graded_by": .string(r.gradedBy), "duration_ms": .integer(r.durationMs),
         "state_before": .integer(r.stateBeforeRaw), "stability_before": .number(r.stabilityBefore),
         "difficulty_before": .number(r.difficultyBefore), "elapsed_days": .number(r.elapsedDays),
         "scheduled_days": .number(r.scheduledDays), "stability_after": .number(r.stabilityAfter),
         "difficulty_after": .number(r.difficultyAfter)]
    }

    static func makeReviewLog(_ row: SyncRow) -> ReviewLog? {
        guard let id = row.uuid("id"), let itemID = row.uuid("item_id"), let reviewedAt = row.date("reviewed_at") else {
            return nil
        }
        let before = MemoryState(state: CardState(rawValue: row.int("state_before") ?? 0) ?? .new,
                                 stability: row.double("stability_before") ?? 0,
                                 difficulty: row.double("difficulty_before") ?? 0)
        let after = MemoryState(stability: row.double("stability_after") ?? 0,
                                difficulty: row.double("difficulty_after") ?? 0)
        let log = ReviewLog(id: id, itemID: itemID, courseID: row.uuid("course_id"), sessionID: row.uuid("session_id"),
                            reviewedAt: reviewedAt, rating: Rating(rawValue: row.int("rating") ?? 3) ?? .good,
                            score: row.double("score") ?? -1, answer: row.string("answer"),
                            gradedBy: row.string("graded_by") ?? "person", durationMs: row.int("duration_ms") ?? 0,
                            before: before, after: after, elapsedDays: row.double("elapsed_days") ?? 0,
                            scheduledDays: row.double("scheduled_days") ?? 0)
        if let rating = row.int("rating") { log.ratingRaw = rating }
        if let state = row.int("state_before") { log.stateBeforeRaw = state }
        return log
    }

    // MARK: exams

    static func row(_ e: Exam) -> SyncRow {
        ["id": .uuid(e.id), "course_id": .uuid(e.course?.id), "title": .string(e.title), "date": .date(e.date),
         "scope": .blob(e.scopeData), "format": .blob(e.formatData), "target_readiness": .number(e.targetReadiness),
         "result_score": .number(e.resultScore), "result_logged_at": .date(e.resultLoggedAt),
         "readiness_at_exam": .number(e.readinessAtExam), "created_at": .date(e.createdAt),
         "updated_at": .date(e.updatedAt), "deleted_at": .date(e.deletedAt)]
    }

    static func makeExam(_ row: SyncRow, _ resolve: SyncResolver) -> Exam? {
        guard let id = row.uuid("id") else { return nil }
        let exam = Exam(id: id, course: nil, title: row.string("title") ?? "", date: row.date("date") ?? Date())
        fill(exam, from: row, resolve)
        return exam
    }

    static func fill(_ e: Exam, from row: SyncRow, _ resolve: SyncResolver) {
        e.course = resolve.course(row.uuid("course_id"))
        if let v = row.string("title") { e.title = v }
        if let v = row.date("date") { e.date = v }
        e.scopeData = row.blob("scope")
        e.formatData = row.blob("format")
        if let v = row.double("target_readiness") { e.targetReadiness = v }
        e.resultScore = row.double("result_score")
        e.resultLoggedAt = row.date("result_logged_at")
        e.readinessAtExam = row.double("readiness_at_exam")
        if let v = row.date("created_at") { e.createdAt = v }
        e.deletedAt = row.date("deleted_at")
    }

    // MARK: study sessions

    /// A session has no `updatedAt` on the device: its stamp is when it ended, or when it started while running.
    static func stamp(_ s: StudySession) -> Date { s.endedAt ?? s.startedAt }

    static func row(_ s: StudySession) -> SyncRow {
        ["id": .uuid(s.id), "kind": .string(s.kindRaw), "started_at": .date(s.startedAt), "ended_at": .date(s.endedAt),
         "planned_seconds": .number(s.plannedSeconds), "active_seconds": .number(s.activeSeconds),
         "item_count": .integer(s.itemCount), "correct_count": .integer(s.correctCount), "course_id": .uuid(s.courseID),
         "exam_id": .uuid(s.examID), "confusion_id": .uuid(s.confusionID),
         "readiness_before": .number(s.readinessBefore), "readiness_after": .number(s.readinessAfter),
         "updated_at": .date(stamp(s))]
    }

    static func makeSession(_ row: SyncRow) -> StudySession? {
        guard let id = row.uuid("id"), let started = row.date("started_at") else { return nil }
        let session = StudySession(id: id, kind: SessionKind(rawValue: row.string("kind") ?? "") ?? .daily,
                                   startedAt: started, plannedSeconds: row.double("planned_seconds") ?? 0)
        fill(session, from: row)
        return session
    }

    static func fill(_ s: StudySession, from row: SyncRow) {
        if let v = row.string("kind") { s.kindRaw = v }
        if let v = row.date("started_at") { s.startedAt = v }
        s.endedAt = row.date("ended_at")
        if let v = row.double("planned_seconds") { s.plannedSeconds = v }
        if let v = row.double("active_seconds") { s.activeSeconds = v }
        if let v = row.int("item_count") { s.itemCount = v }
        if let v = row.int("correct_count") { s.correctCount = v }
        s.courseID = row.uuid("course_id")
        s.examID = row.uuid("exam_id")
        s.confusionID = row.uuid("confusion_id")
        s.readinessBefore = row.double("readiness_before")
        s.readinessAfter = row.double("readiness_after")
    }

    // MARK: day records

    static func row(_ d: DayRecord, now: Date) -> SyncRow {
        ["day_key": .string(d.dayKey), "day": .date(d.day), "study_seconds": .number(d.studySeconds),
         "items_reviewed": .integer(d.itemsReviewed), "sessions": .integer(d.sessions), "frozen": .bool(d.frozen),
         "repaired": .bool(d.repaired), "updated_at": .date(now)]
    }

    static func makeDay(_ row: SyncRow) -> DayRecord? {
        guard let key = row.string("day_key"), let day = row.date("day") else { return nil }
        return DayRecord(dayKey: key, day: day, studySeconds: row.double("study_seconds") ?? 0,
                         itemsReviewed: row.int("items_reviewed") ?? 0, sessions: row.int("sessions") ?? 0,
                         frozen: row.bool("frozen") ?? false, repaired: row.bool("repaired") ?? false)
    }

    /// Two devices studied the same day: keep the larger of each count and either flag. Returns true when the
    /// local record changed.
    @discardableResult
    static func merge(_ d: DayRecord, with row: SyncRow) -> Bool {
        let seconds = max(d.studySeconds, row.double("study_seconds") ?? 0)
        let reviewed = max(d.itemsReviewed, row.int("items_reviewed") ?? 0)
        let sessions = max(d.sessions, row.int("sessions") ?? 0)
        let frozen = d.frozen || (row.bool("frozen") ?? false)
        let repaired = d.repaired || (row.bool("repaired") ?? false)
        let changed = seconds != d.studySeconds || reviewed != d.itemsReviewed || sessions != d.sessions
            || frozen != d.frozen || repaired != d.repaired
        d.studySeconds = seconds
        d.itemsReviewed = reviewed
        d.sessions = sessions
        d.frozen = frozen
        d.repaired = repaired
        return changed
    }

    /// True when the server row holds less than the merged local record (so the record goes up again).
    static func serverIsBehind(_ d: DayRecord, _ row: SyncRow) -> Bool {
        (row.double("study_seconds") ?? 0) < d.studySeconds || (row.int("items_reviewed") ?? 0) < d.itemsReviewed
            || (row.int("sessions") ?? 0) < d.sessions || (row.bool("frozen") ?? false) != d.frozen
            || (row.bool("repaired") ?? false) != d.repaired
    }

    // MARK: confusions

    static func row(_ c: Confusion) -> SyncRow {
        ["id": .uuid(c.id), "course_id": .uuid(c.course?.id), "name": .string(c.name), "explanation": .string(c.explanation),
         "item_ids": .blob(c.itemIDsData), "fix": .blob(c.fixData), "status": .string(c.statusRaw),
         "miss_count": .integer(c.missCount), "created_at": .date(c.createdAt), "updated_at": .date(c.updatedAt),
         "last_seen_at": .date(c.lastSeenAt), "deleted_at": .date(c.deletedAt)]
    }

    static func makeConfusion(_ row: SyncRow, _ resolve: SyncResolver) -> Confusion? {
        guard let id = row.uuid("id") else { return nil }
        let confusion = Confusion(id: id, course: nil, name: row.string("name") ?? "",
                                  explanation: row.string("explanation") ?? "", itemIDs: [],
                                  missCount: row.int("miss_count") ?? 0)
        fill(confusion, from: row, resolve)
        return confusion
    }

    static func fill(_ c: Confusion, from row: SyncRow, _ resolve: SyncResolver) {
        c.course = resolve.course(row.uuid("course_id"))
        if let v = row.string("name") { c.name = v }
        if let v = row.string("explanation") { c.explanation = v }
        c.itemIDsData = row.blob("item_ids")
        c.fixData = row.blob("fix")
        if let v = row.string("status") { c.statusRaw = v }
        if let v = row.int("miss_count") { c.missCount = v }
        if let v = row.date("created_at") { c.createdAt = v }
        if let v = row.date("last_seen_at") { c.lastSeenAt = v }
        c.deletedAt = row.date("deleted_at")
    }
}
