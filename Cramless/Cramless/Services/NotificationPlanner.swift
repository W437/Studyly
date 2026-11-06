import Foundation

/// Plans the local notifications for the coming days from plain values. Pure (no clock, no notification center):
/// `NotificationScheduler` feeds it the app's state and applies the result; `NotificationPlannerTests` pins the rules.
///
/// - **Daily reminder** at the person's time (`settings.reminderMinutes`; nil means none): today when there's
///   something to study and it isn't done, and each of the next 6 days. Today's copy is specific ("15 minutes keeps
///   Bio 101 on track. 18 cards are due."); later days carry no counts (they'd be stale by then) and fall back to a
///   generic line when there's little to say. Seven days ahead at most, so someone who stops opening the app stops
///   hearing from it after a week.
/// - **Exam countdowns** for exams in the next 14 days: a week before at the reminder time (18:00 when reminders are
///   off), and the evening before at 20:00 ("Bio 101 tomorrow. 10 minutes of weak spots, then sleep."). Either one
///   replaces that day's reminder. Exams on the same day share one evening note. They're sent even with the daily
///   reminder off: they're about a date the person set, not about a habit.
/// - **Streak nudge** at 20:30 when the streak is 3 or more and the day isn't done yet: today if not studied (and
///   there's something to study), else tomorrow; only when the day's reminder came at least an hour earlier. Never
///   when reminders are off. Copy is calm ("15 minutes tonight and your 12-day streak is safe.").
/// - **Cap noticed** (`NoticePing`, from `NoticeEngine.pings`): one of Cap's cards, 2 to 6 days before its exam, at the reminder time
///   (18:00 when reminders are off), at most one a day. It replaces that day's reminder and streak nudge, so the evening has one
///   notification, and it never goes out on a day with an exam note.
/// - **The day a milestone is one session away** (a streak of 2, 6, 29, 99 or 364 that today's session would carry to
///   3, 7, 30, 100 or 365; tomorrow's, when today is done) says so in that day's reminder and nudge: "One session today
///   makes it 30 days."
/// - Every time is moved out of quiet hours: to 30 minutes before they start or to when they end, whichever keeps it
///   on the same day (and is closer).
/// - At most 2 a day and at least an hour apart, by priority: exam eve, exam week, Cap noticed, reminder, streak.
/// - Nothing in the past. Identifiers start with "capling."; requests starting "trial." belong to PurchaseStore
///   and are never removed (`staleIdentifiers`).
enum NotificationPlanner {
    struct ExamInfo: Equatable, Sendable {
        var id: UUID
        var title: String
        var courseName: String?
        var date: Date

        /// "Bio 101", or the exam's title when it has no course.
        var shortName: String {
            let name = courseName?.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? title : name
        }
    }

    struct Input: Equatable {
        var now: Date
        /// Minutes after midnight; nil means no daily reminder.
        var reminderMinutes: Int?
        var quietStart: Int
        var quietEnd: Int
        var goalMinutes: Int
        var today: TodaySummary
        var streak: StreakState
        /// Upcoming exams, any order.
        var exams: [ExamInfo]
        /// Cap's cards that may be sent, today's and tomorrow's.
        var notices: [NoticePing] = []
    }

    struct Planned: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable {
            case examEve, examWeek, notice, daily, streak

            var priority: Int {
                switch self {
                case .examEve: 0
                case .examWeek: 1
                case .notice: 2
                case .daily: 3
                case .streak: 4
                }
            }

            /// For the notification summary's ordering.
            var relevance: Double {
                switch self {
                case .examEve: 0.9
                case .examWeek: 0.7
                case .notice: 0.65
                case .daily: 0.6
                case .streak: 0.4
                }
            }
        }

        var id: String
        var kind: Kind
        var date: Date
        var body: String
        var url: URL
        var category: String
        var thread: String
    }

    static let prefix = "capling."
    static let studyCategory = "capling.study"
    static let examCategory = "capling.exam"
    static let noticeCategory = "capling.notice"
    static let reminderDays = 7
    static let examHorizonDays = 14
    static let maxPerDay = 2
    static let minimumGap: TimeInterval = 60 * 60
    static let examEveMinutes = 20 * 60
    static let streakMinutes = 20 * 60 + 30
    static let fallbackMinutes = 18 * 60
    static let streakThreshold = 3
    /// Nothing is scheduled closer to now than this.
    static let lead: TimeInterval = 60

    static func plan(_ input: Input, calendar: Calendar) -> [Planned] {
        var out: [Planned] = []
        let exams = input.exams.filter { $0.date > input.now }.sorted { $0.date < $1.date }
        let goal = max(1, input.goalMinutes)
        let studiedToday = input.today.studiedToday || input.streak.studiedToday
        let nothingToday = !input.today.sessionReady && input.today.reviews == 0 && input.today.newItems == 0

        func dayOffset(of date: Date) -> Int { days(from: input.now, to: date, calendar: calendar) }

        // The day one session reaches a milestone: today when it isn't done yet, tomorrow when it is.
        let milestone = milestoneNext(input.streak, studiedToday: studiedToday)

        func time(_ minutes: Int, onDay offset: Int) -> Date? {
            let start = calendar.startOfDay(for: input.now)
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let m = movedOutOfQuietHours(minutes, start: input.quietStart, end: input.quietEnd)
            guard let date = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day),
                  date > input.now.addingTimeInterval(lead) else { return nil }
            return date
        }

        // Exam eve: one note per evening, for the exams the next day.
        var eves: [Int: [ExamInfo]] = [:]
        for exam in exams {
            let offset = dayOffset(of: exam.date)
            guard offset >= 1, offset <= examHorizonDays else { continue }
            eves[offset - 1, default: []].append(exam)
        }
        for (offset, list) in eves {
            guard let date = time(examEveMinutes, onDay: offset) else { continue }
            var names: [String] = []
            for exam in list where !names.contains(exam.shortName) { names.append(exam.shortName) }
            let who = names.count == 1 ? names[0] : names.count == 2 ? "\(names[0]) and \(names[1])" : "\(list.count) exams"
            let url = list.count == 1 ? CramlessLink.session(kind: SessionKind.examEve.rawValue, exam: list[0].id)
                : CramlessLink.session(kind: SessionKind.examEve.rawValue)
            out.append(Planned(id: "\(prefix)eve.\(dayKey(date, calendar))", kind: .examEve, date: date,
                               body: "\(who) tomorrow. 10 minutes of weak spots, then sleep.", url: url,
                               category: studyCategory, thread: examCategory))
        }

        // A week before.
        for exam in exams {
            let offset = dayOffset(of: exam.date) - 7
            guard offset >= 0, offset + 7 <= examHorizonDays,
                  let date = time(input.reminderMinutes ?? fallbackMinutes, onDay: offset) else { continue }
            out.append(Planned(id: "\(prefix)week.\(exam.id.uuidString)", kind: .examWeek, date: date,
                               body: "\(exam.title) is a week away. Your plan: \(goal) minutes a day, weak spots first.",
                               url: CramlessLink.exam(exam.id), category: examCategory, thread: examCategory))
        }

        // Cap noticed: at the reminder time (18:00 with reminders off), at most one a day, in the week before the card's exam.
        var noticeDays = Set<Int>()
        for ping in input.notices where noticeDays.insert(ping.dayOffset).inserted {
            let left = dayOffset(of: ping.examDate) - ping.dayOffset
            guard NoticeEngine.pingWindow.contains(left),
                  let date = time(input.reminderMinutes ?? fallbackMinutes, onDay: ping.dayOffset) else { continue }
            out.append(Planned(id: "\(prefix)notice.\(dayKey(date, calendar))", kind: .notice, date: date, body: ping.body,
                               url: CramlessLink.today(notice: ping.linkID), category: noticeCategory, thread: noticeCategory))
        }

        // The daily reminder.
        if let reminder = input.reminderMinutes {
            let hasHistory = !nothingToday || !exams.isEmpty || input.streak.current > 0 || input.streak.best > 0
            for offset in 0..<reminderDays {
                guard let date = time(reminder, onDay: offset) else { continue }
                var body: String
                if offset == 0 {
                    guard !studiedToday, !nothingToday else { continue }
                    body = todayCopy(input, focus: focusExam(after: date, in: exams, calendar: calendar))
                } else {
                    guard hasHistory else { continue }
                    body = laterCopy(goal: goal, date: date, focus: focusExam(after: date, in: exams, calendar: calendar),
                                     calendar: calendar)
                }
                if let milestone, milestone.offset == offset { body = "One session today makes it \(milestone.days) days." }
                out.append(Planned(id: "\(prefix)daily.\(dayKey(date, calendar))", kind: .daily, date: date, body: body,
                                   url: CramlessLink.session, category: studyCategory, thread: studyCategory))
            }
        }

        // The streak nudge: tonight if today isn't done (and there's something to do), else tomorrow night.
        if input.reminderMinutes != nil, input.streak.current >= streakThreshold, studiedToday || !nothingToday,
           let date = time(streakMinutes, onDay: studiedToday ? 1 : 0) {
            let nudge = milestone.map { "\(goal) minutes tonight makes it \($0.days) days." }
                ?? "\(goal) minutes tonight and your \(input.streak.current)-day streak is safe."
            out.append(Planned(id: "\(prefix)streak.\(dayKey(date, calendar))", kind: .streak, date: date,
                               body: nudge,
                               url: CramlessLink.session, category: studyCategory, thread: studyCategory))
        }

        return capped(out, calendar: calendar)
    }

    /// The milestone one more session carries the streak to, and the day offset it falls on (0 today, 1 tomorrow). Today's
    /// session counts when the day isn't done; once it is, the next one is tomorrow's.
    static func milestoneNext(_ streak: StreakState, studiedToday: Bool) -> (offset: Int, days: Int)? {
        let reach = streak.current + 1
        guard streak.current > 0, StreakStage.milestones.contains(reach) else { return nil }
        return (studiedToday ? 1 : 0, reach)
    }

    /// Keeps at most `maxPerDay` a day, an hour apart, by priority. An exam note replaces the day's reminder, and
    /// the streak nudge only follows a reminder that came at least an hour earlier (else the reminder was enough).
    /// A "Cap noticed" never goes out beside an exam note, and replaces both the reminder and the nudge.
    static func capped(_ planned: [Planned], calendar: Calendar) -> [Planned] {
        let byDay = Dictionary(grouping: planned) { calendar.startOfDay(for: $0.date) }
        var kept: [Planned] = []
        for (_, list) in byDay {
            let hasExamNote = list.contains { $0.kind == .examEve || $0.kind == .examWeek }
            let hasNotice = !hasExamNote && list.contains { $0.kind == .notice }
            let reminder = hasExamNote ? nil : list.first { $0.kind == .daily }
            var accepted: [Planned] = []
            for item in list.sorted(by: { ($0.kind.priority, $0.date) < ($1.kind.priority, $1.date) }) {
                if item.kind == .notice, hasExamNote { continue }
                if hasNotice, item.kind == .daily || item.kind == .streak { continue }
                if item.kind == .daily, hasExamNote { continue }
                if item.kind == .streak, let reminder, reminder.date > item.date.addingTimeInterval(-minimumGap) {
                    continue
                }
                guard accepted.count < maxPerDay,
                      accepted.allSatisfy({ abs($0.date.timeIntervalSince(item.date)) >= minimumGap }) else { continue }
                accepted.append(item)
            }
            kept += accepted
        }
        return kept.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// The pending requests to remove: ours ("capling.") that aren't in the new plan. Never anything else, so
    /// PurchaseStore's "trial." requests survive every reschedule.
    static func staleIdentifiers(pending: [String], planned: [Planned]) -> [String] {
        let keep = Set(planned.map(\.id))
        return pending.filter { $0.hasPrefix(prefix) && !keep.contains($0) }
    }

    // MARK: Copy

    /// Today's reminder: specific when the summary says enough, generic when it doesn't.
    static func todayCopy(_ input: Input, focus: ExamInfo?) -> String {
        let t = input.today
        let minutes = t.plannedMinutes > 0 ? t.plannedMinutes : max(1, input.goalMinutes)
        if let focus {
            var text = "\(minutes) minutes keeps \(focus.shortName) on track."
            if t.reviews > 0 {
                text += " \(cards(t.reviews)) due."
            } else if t.newItems > 0 {
                text += " \(newQuestions(t.newItems)) ready."
            }
            return text
        }
        if t.reviews > 0 { return "\(cards(t.reviews)) due. Your \(minutes)-minute session is ready." }
        if t.newItems > 0 {
            return "Your \(minutes)-minute session has \(t.newItems) new \(t.newItems == 1 ? "question" : "questions")."
        }
        return "Your \(minutes)-minute session is ready when you are."
    }

    /// A later day's reminder: no counts, the exam when there's one coming.
    static func laterCopy(goal: Int, date: Date, focus: ExamInfo?, calendar: Calendar) -> String {
        if let focus {
            let d = days(from: date, to: focus.date, calendar: calendar)
            if d >= 2 { return "\(goal) minutes keeps \(focus.shortName) on track. \(focus.title) is in \(d) days." }
            return "\(goal) minutes keeps \(focus.shortName) on track."
        }
        return "Your \(goal)-minute session is ready when you are."
    }

    /// The exam a reminder at `date` is about: the next one after it, within a month.
    static func focusExam(after date: Date, in exams: [ExamInfo], calendar: Calendar) -> ExamInfo? {
        exams.first { $0.date > date && days(from: date, to: $0.date, calendar: calendar) <= 30 }
    }

    private static func cards(_ n: Int) -> String {
        n == 1 ? "1 card is" : "\(n) cards are"
    }

    private static func newQuestions(_ n: Int) -> String {
        n == 1 ? "1 new question is" : "\(n) new questions are"
    }

    // MARK: Time

    /// Minutes after midnight moved out of quiet hours [start, end) (which may wrap midnight): to 30 minutes before
    /// they start or to when they end, whichever stays on the same day and is closer.
    static func movedOutOfQuietHours(_ minutes: Int, start: Int, end: Int) -> Int {
        let m = ((minutes % 1440) + 1440) % 1440
        guard isQuiet(m, start: start, end: end) else { return m }
        let before = start - 30
        let after = end
        let back: Int? = before >= 0 && before <= m ? m - before : nil   // earlier, same day
        let forward: Int? = after > m && after < 1440 ? after - m : nil  // later, same day
        switch (back, forward) {
        case let (b?, f?): return b <= f ? before : after
        case (_?, nil): return before
        case (nil, _?): return after
        case (nil, nil): return after   // quiet nearly all day: the one quiet-free moment
        }
    }

    static func isQuiet(_ m: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end { return m >= start && m < end }
        return m >= start || m < end
    }

    static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        WidgetCalendar.days(from: a, to: b, calendar: calendar)
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
