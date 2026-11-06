import Foundation

/// Shapes engine values (`readinessHistory`, `plan(for:)`, today's session, day records) for the exam screens: the projection
/// sentence, the plan as stops, the what-if, the topics weakest first, the letter's gate and the grade after the exam. Pure and
/// clock-free: no recall is computed here, only arranged.
enum ExamPresentation {
    // MARK: Path to the target

    struct Path: Equatable, Sendable {
        /// Readiness at the end of each past day, then now: drawn solid.
        var history: [ReadinessPoint]
        /// Now, then each morning up to the exam if the plan is followed: drawn dashed. Cut at `end`.
        var projection: [ReadinessPoint]
        var target: Double
        var now: Date
        var current: Double
        var start: Date
        /// The chart's last day: the exam, or `maxDays` from now for far-off exams.
        var end: Date
        var examDate: Date
        /// The plan runs past `end`.
        var isCut: Bool
        /// Readiness on exam morning if the plan is followed.
        var projectedAtExam: Double
        var targetReachedOn: Date?

        /// The point a reader's finger is nearest to.
        func nearest(to date: Date) -> ReadinessPoint? {
            (history + projection.dropFirst()).min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
    }

    /// The last two weeks (solid) joined at now to the plan's curve (dashed). `readinessHistory` stamps each day's
    /// end-of-day value with the day's start, so past days are drawn at their end and today's point gives way to now.
    /// A plan longer than `maxDays` is cut there so the history stays readable; `projectedAtExam` is still the exam's.
    static func path(history: [ReadinessPoint], plan: StudyPlan, examDate: Date, now: Date, calendar: Calendar,
                     maxDays: Int = 56) -> Path {
        let current = plan.curve.first?.value ?? history.last?.value ?? 0
        let startOfToday = calendar.startOfDay(for: now)
        var past = history.filter { $0.date < startOfToday }
            .map { ReadinessPoint(date: calendar.adding(days: 1, to: $0.date), value: $0.value, isProjection: false) }
            .filter { $0.date <= now }
        past.append(ReadinessPoint(date: now, value: current, isProjection: false))
        let limit = calendar.adding(days: maxDays, to: now)
        let cut = examDate > limit
        let end = cut ? limit : max(examDate, now)
        var ahead = [ReadinessPoint(date: now, value: current, isProjection: true)]
        ahead += plan.curve.dropFirst().filter { $0.date > now && $0.date <= end }
            .map { ReadinessPoint(date: $0.date, value: $0.value, isProjection: true) }
        return Path(history: past, projection: ahead, target: plan.target, now: now, current: current,
                    start: past.first?.date ?? now, end: end, examDate: examDate, isCut: cut,
                    projectedAtExam: plan.projectedReadiness, targetReachedOn: plan.targetReachedOn)
    }

    // MARK: The week strip

    struct StripDay: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            /// A past day not studied.
            case missed
            /// A past day not studied but covered by a streak freeze.
            case frozen
            case study, light, rest, eve, exam
        }

        var date: Date
        var kind: Kind
        /// This exam's minutes that day (plan days only).
        var minutes: Int
        var isToday: Bool
        /// Picks up the work of the missed day before it.
        var absorbsMissedDay = false

        var id: Date { date }
    }

    /// Up to `count` days: yesterday first when it was missed while the exam was already set (the plan has moved its
    /// reviews into the days ahead, so today is marked as absorbing it), then the plan's days from today on.
    static func weekStrip(plan: StudyPlan, yesterday: DaySnapshot?, examCreatedAt: Date, now: Date,
                          calendar: Calendar, count: Int = 7) -> [StripDay] {
        var days: [StripDay] = []
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.adding(days: -1, to: todayStart)
        let studied = (yesterday?.sessions ?? 0) > 0 || yesterday?.repaired == true
        let examWasSet = examCreatedAt < todayStart
        let examStillAhead = plan.days.contains { $0.kind != .exam } || plan.daysLeft > 0
        if !studied, examWasSet, examStillAhead {
            days.append(StripDay(date: yesterdayStart, kind: yesterday?.frozen == true ? .frozen : .missed, minutes: 0,
                                 isToday: false))
        }
        for day in plan.days {
            guard days.count < count else { break }
            let kind: StripDay.Kind
            switch day.kind {
            case .study: kind = .study
            case .light: kind = .light
            case .rest: kind = .rest
            case .examEve: kind = .eve
            case .exam: kind = .exam
            }
            days.append(StripDay(date: day.date, kind: kind, minutes: day.minutes, isToday: day.isToday,
                                 absorbsMissedDay: day.isToday && days.first.map { $0.kind == .missed || $0.kind == .frozen } == true))
        }
        return days
    }

    // MARK: Exam state

    enum Phase: Equatable, Sendable {
        /// More than a day to go.
        case ahead(days: Int)
        /// The exam is tomorrow: tonight is exam eve.
        case eve
        /// The exam is today.
        case today
        /// The date has passed.
        case past(days: Int)
    }

    static func phase(examDate: Date, now: Date, calendar: Calendar) -> Phase {
        let days = calendar.dayDistance(from: now, to: examDate)
        switch days {
        case ...(-1): return .past(days: -days)
        case 0: return examDate < now ? .past(days: 0) : .today
        case 1: return .eve
        default: return .ahead(days: days)
        }
    }

    /// Free users within three weeks of an upcoming exam see the Exam Pass offer.
    static func offersExamPass(plan: Plan, phase: Phase) -> Bool {
        guard plan == .free else { return false }
        switch phase {
        case .ahead(let days): return days <= 21
        case .eve, .today: return true
        case .past: return false
        }
    }

    // MARK: What the questions cover

    /// Below this share the coverage note turns amber.
    static let thinCoverage = 0.5
    /// From this share on there is little enough left that the note stops offering more questions.
    static let wellCovered = 0.9

    /// The exam screen's line about how much of the material the questions reach, under the ring.
    struct CoverageNote: Equatable, Sendable {
        /// "Your questions cover 17% of your material."
        var sentence: String
        /// The source that holds most of what is left, with its own share: "Palsgraf: 18%".
        var mainGap: String?
        /// Below half: an amber tone, never an alarm.
        var isThin: Bool
        /// Enough is left to offer "Add questions for the rest".
        var offersMore: Bool
    }

    /// `canAddMore`: a source with something left to cover can be written questions for.
    static func coverageNote(_ summary: Coverage.Summary, canAddMore: Bool) -> CoverageNote {
        // Judged on the number the person reads, so "50%" is never amber.
        let shown = Double(Int((summary.share * 100).rounded())) / 100
        return CoverageNote(sentence: "Your questions cover \(CLFormat.percent(summary.share)) of your material.",
                            mainGap: summary.mainGap.map { "\($0.title): \(CLFormat.percent($0.share))" },
                            isThin: shown < thinCoverage,
                            offersMore: canAddMore && shown < wellCovered)
    }

    // MARK: After the exam

    /// "You got 81%, at 74% ready on the day." and what logging it does. `calibratingExams`: the exams with both readiness on the day
    /// and a logged grade, this one included (`AppModel.calibratingExamCount`); two make a projection.
    static func gradeComparison(onTheDay: Double?, got: Double, calibratingExams: Int) -> (headline: String, note: String) {
        let headline = onTheDay.map { String(localized: "You got \(CLFormat.percent(got)), at \(CLFormat.percent($0)) ready on the day.") }
            ?? String(localized: "You got \(CLFormat.percent(got)).")
        let note: String
        switch calibratingExams {
        case 2...: note = String(localized: "Capling now projects your grades from your readiness.")
        case 1: note = String(localized: "Log one more grade and Capling can project yours.")
        default: note = String(localized: "Log your grades after exams and Capling can project yours.")
        }
        return (headline, note)
    }

    /// Under a past exam with no grade yet: "You were 74% ready on the day. Log your grade and Capling learns how your readiness turns
    /// into grades."
    static func logGradeInvite(onTheDay: Double?) -> String {
        let learns = String(localized: "Log your grade and Capling learns how your readiness turns into grades.")
        guard let onTheDay else { return learns }
        return String(localized: "You were \(CLFormat.percent(onTheDay)) ready on the day.") + " " + learns
    }

    // MARK: The letter grade

    /// The letter grade shows only once logged grades calibrate it: two or more other exams with readiness on the day and a grade.
    static func showsLetter(_ grade: ProjectedGrade) -> Bool { grade.isCalibrated }

    /// The grade to show, or nil before it is calibrated.
    static func shownGrade(_ grade: ProjectedGrade) -> ProjectedGrade? { showsLetter(grade) ? grade : nil }

    /// Progress's line: "Projected B+ from your grades".
    static func calibratedGradeLine(_ grade: ProjectedGrade) -> String {
        String(localized: "Projected \(grade.letter) from your grades")
    }

    /// The exam page's line: "From your past grades, that's about a B+."
    static func calibratedProjectionLine(_ grade: ProjectedGrade) -> String {
        let vowel = grade.letter.hasPrefix("A") || grade.letter.hasPrefix("F")
        return vowel ? String(localized: "From your past grades, that's about an \(grade.letter).")
            : String(localized: "From your past grades, that's about a \(grade.letter).")
    }

    // MARK: Days in words

    /// "today", "Saturday" within the week, "Nov 29" after.
    static func dayName(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        if days == 0 { return String(localized: "today") }
        if (1...6).contains(days) { return date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide)) }
        return LibraryFormat.shortDate(date, calendar: calendar)
    }

    /// The exam's day in a sentence: "by Sunday", "by Nov 29".
    static func examDayName(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        if (1...6).contains(days) { return date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide)) }
        return LibraryFormat.shortDate(date, calendar: calendar)
    }

    /// "Limiting reagents and Moles": at most two topic names, joined with "and" (a session interleaves them; never "then").
    static func topicList(_ names: [String], limit: Int = 2) -> String {
        ListFormatter.localizedString(byJoining: Array(names.prefix(limit)))
    }

    // MARK: The projection

    /// Under this many questions in scope, the card says how few the projection rests on.
    static let fewQuestions = 15

    /// The projection card: one sentence that says where the plan takes readiness and what that takes, with what else gets closer
    /// to the goal, the letter once calibrated and how few questions it rests on.
    struct Projection: Equatable, Sendable {
        var sentence: String
        /// "Practice Limiting reagents as well to get closer to 80%." / "About 25 minutes a day gets you closer to 80%."
        var nudge: String?
        /// "From your past grades, that's about a B+." (calibrated only).
        var letter: String?
        /// "Based on 7 questions so far."
        var basedOn: String?
        /// "A projection from your recall so far, not a promise." Nil when there is nothing to project.
        var footnote: String?
        /// Nothing to study yet: the card offers "Add material".
        var addsMaterial = false
        /// The projection reaches the goal.
        var reachesGoal = false
    }

    /// The projection for an exam still to come. `plan` is the exam's shared plan, or its what-if plan with `skipping` (the day
    /// skipped). `weakestTopic`: the weakest topic under the goal with questions. Nil on exam day and after.
    static func projection(phase: Phase, plan: StudyPlan, questionCount: Int, weakestTopic: String?, grade: ProjectedGrade?,
                           examDate: Date, now: Date, calendar: Calendar, skipping: SkipOption? = nil) -> Projection? {
        switch phase {
        case .today, .past: return nil
        case .ahead, .eve: break
        }
        guard questionCount > 0 else {
            return Projection(sentence: String(localized: "Nothing to study for this exam yet. Add material and Capling plans the way there."),
                              addsMaterial: true)
        }
        let projected = CLFormat.percent(plan.projectedReadiness)
        let goal = CLFormat.percent(plan.target)
        let reaches = Int((plan.projectedReadiness * 100).rounded()) >= Int((plan.target * 100).rounded())
        let when = examDayName(examDate, now: now, calendar: calendar)
        var result = Projection(sentence: "", footnote: String(localized: "A projection from your recall so far, not a promise."),
                                reachesGoal: reaches)
        if questionCount < fewQuestions { result.basedOn = String(localized: "Based on \(questionCount) questions so far.") }
        if let grade, showsLetter(grade), skipping == nil { result.letter = calibratedProjectionLine(grade) }
        let past = reaches ? " " + (Int((plan.projectedReadiness * 100).rounded()) == Int((plan.target * 100).rounded())
            ? String(localized: "That's your \(goal) goal.") : String(localized: "That's past your \(goal) goal.")) : ""
        let practice = weakestTopic.map { String(localized: "Practice \($0) as well to get closer to \(goal).") }

        if let skipping {
            result.sentence = String(localized: "Skip \(skipping.name), and you'll be about \(projected) ready by \(when).")
            return result
        }
        if case .eve = phase {
            let morning = calendar.component(.hour, from: examDate) < 12
            result.sentence = morning
                ? String(localized: "Tonight's weak spots take you to about \(projected) by tomorrow morning.")
                : String(localized: "Tonight's weak spots take you to about \(projected) by tomorrow.")
            return result
        }
        let daysLeft = calendar.dayDistance(from: now, to: examDate)
        if daysLeft <= nearDays {
            let names = plan.days.filter { $0.kind != .exam && $0.seconds > 0 && !$0.isSkipped }.map { day -> String in
                if day.offset == 0 { return String(localized: "today") }
                let weekday = day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide))
                return day.kind == .examEve ? String(localized: "\(weekday) evening") : weekday
            }
            result.sentence = names.isEmpty
                ? String(localized: "You'll be about \(projected) ready by \(when).") + past
                : String(localized: "Study \(ListFormatter.localizedString(byJoining: names)), and you'll be about \(projected) ready by \(when).") + past
            if !reaches { result.nudge = practice }
            return result
        }
        let perDay = String(localized: "\(plan.dailyMinutes) minutes a day")
        if !reaches, let suggested = plan.suggestedMinutes, suggested > plan.dailyMinutes {
            result.sentence = String(localized: "At \(perDay) you'll be about \(projected) ready by \(when).")
            result.nudge = String(localized: "About \(String(localized: "\(suggested) minutes a day")) gets you closer to \(goal).")
        } else {
            result.sentence = String(localized: "Keep up your \(perDay), and you'll be about \(projected) ready by \(when).") + past
            if !reaches { result.nudge = practice }
        }
        return result
    }

    /// An exam this many days away or nearer is planned day by day; further, as "about N min a day".
    static let nearDays = 3

    // MARK: Today's work

    /// What today's session (the day's session, as Today starts it) does for this exam.
    struct TodayWork: Equatable, Sendable {
        /// The session's minutes as built now; 0 when there is nothing to study.
        var sessionMinutes: Int
        /// This exam's seconds in it: the questions it covers.
        var examSeconds: Double
        /// This exam's topics in it, the most time first.
        var topics: [String]
        var studiedToday: Bool
        /// Yesterday wasn't studied while the exam was set: today picks up its reviews.
        var missedYesterday: Bool

        /// "About 4" of the session's minutes.
        var examMinutes: Int { examSeconds > 0 ? max(1, Int((examSeconds / 60).rounded())) : 0 }
    }

    /// Today's share for `exam`: the session's questions it covers (by topic and course, so an exam shares the questions a sooner
    /// exam also covers), their seconds and their topics.
    static func todayWork(entries: [SessionEntry], sessionMinutes: Int, exam: ExamSnapshot, topicNames: [UUID: String],
                          studiedToday: Bool, missedYesterday: Bool) -> TodayWork {
        var seconds = 0.0
        var byTopic: [UUID: Double] = [:]
        var order: [UUID] = []
        for entry in entries where exam.covers(topic: entry.topicID, course: entry.courseID) {
            seconds += entry.estimatedSeconds
            guard let t = entry.topicID else { continue }
            if byTopic[t] == nil { order.append(t) }
            byTopic[t, default: 0] += entry.estimatedSeconds
        }
        let topics = order.enumerated().sorted { a, b in
            byTopic[a.element]! != byTopic[b.element]! ? byTopic[a.element]! > byTopic[b.element]! : a.offset < b.offset
        }.compactMap { topicNames[$0.element] }
        return TodayWork(sessionMinutes: sessionMinutes, examSeconds: seconds, topics: topics, studiedToday: studiedToday,
                         missedYesterday: missedYesterday)
    }

    /// The page's main button: the day's session ("Study · 15 min"), tonight's on the eve, or a practice round once today is done.
    struct StudyAction: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case daily
            case examEve
            /// A practice round on one topic (nil: the course).
            case practice(topicID: UUID?, minutes: Int?)
        }

        var kind: Kind
        var title: String
        var subline: String?
    }

    static func studyAction(phase: Phase, today: TodayWork, weakest: TopicRow?, courseName: String,
                            eveMinutes: Int = Int(PlanBuilder.examEveSeconds / 60)) -> StudyAction? {
        switch phase {
        case .today, .past: return nil
        case .eve:
            return StudyAction(kind: .examEve, title: String(localized: "Tonight · \(eveMinutes) min"),
                               subline: String(localized: "About \(eveMinutes) minutes on what you're shakiest on. Then stop: sleep does the rest."))
        case .ahead: break
        }
        if today.sessionMinutes > 0 {
            let subline: String
            if today.examSeconds <= 0 {
                subline = String(localized: "Today's session is for your other exams.")
            } else if today.examMinutes >= today.sessionMinutes {
                subline = String(localized: "The whole session is for this exam.")
            } else {
                subline = String(localized: "About \(today.examMinutes) of the \(today.sessionMinutes) minutes are for this exam.")
            }
            return StudyAction(kind: .daily, title: String(localized: "Study · \(today.sessionMinutes) min"), subline: subline)
        }
        let done = today.studiedToday ? String(localized: "Today's session is done. This one is extra.") : nil
        if let weakest, let minutes = weakest.practiceMinutes {
            return StudyAction(kind: .practice(topicID: weakest.id, minutes: minutes),
                               title: String(localized: SkyCopy.practice(weakest.name, minutes: minutes)), subline: done)
        }
        return StudyAction(kind: .practice(topicID: nil, minutes: nil), title: String(localized: "Practice \(courseName)"), subline: done)
    }

    // MARK: Topics

    /// A topic on the exam page, weakest first.
    struct TopicRow: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        /// Readiness for this exam; nil for a topic with no material yet (a gap).
        var value: Double?
        var questionCount: Int
        /// "Practice · N min": topics with questions under the goal.
        var practiceMinutes: Int?
        /// The first topic under the goal with questions: "Your weakest topic".
        var isWeakest = false
        /// At or above the goal.
        var isOnTrack = false
    }

    /// The exam's topics: gaps first (nothing there can count yet), then the lowest readiness first; ties keep the course's order.
    static func topicsWeakestFirst(_ topics: [TopicReadiness], target: Double) -> [TopicRow] {
        let ordered = topics.enumerated().sorted { a, b in
            switch (a.element.value, b.element.value) {
            case (nil, nil): return a.offset < b.offset
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return abs(x - y) > 1e-9 ? x < y : a.offset < b.offset
            }
        }.map(\.element)
        var flagged = false
        return ordered.map { t in
            var row = TopicRow(id: t.id, name: t.name, value: t.value, questionCount: t.itemCount)
            if let v = t.value, t.itemCount > 0 {
                if v >= target - 1e-9 {
                    row.isOnTrack = true
                } else {
                    row.practiceMinutes = t.practiceMinutes
                    if !flagged { row.isWeakest = true; flagged = true }
                }
            }
            return row
        }
    }

    // MARK: The plan as stops

    /// One stop on the way to the exam: today, a later study day, a stretch of days, the eve, the exam.
    struct Stop: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable { case today, day, span, eve, exam }

        var id: String
        var kind: Kind
        var title: String
        var detail: String?
        /// "Includes yesterday's reviews."
        var note: String?
        /// A day off in the what-if.
        var isSkipped = false
    }

    /// The plan as stops. Within `nearDays`: today, each later study day, the eve, the exam. Further: today, "Then about N min a day
    /// until <date>", the eve, the exam. A skipped day (the what-if) shows as its own stop.
    static func stops(plan: StudyPlan, phase: Phase, examTitle: String, examDate: Date, today: TodayWork, skipped: Int?,
                      now: Date, calendar: Calendar) -> [Stop] {
        switch phase {
        case .today, .past: return []
        case .ahead, .eve: break
        }
        func weekday(_ d: Date) -> String { d.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide)) }
        func minutes(_ seconds: Double) -> Int { max(1, Int((seconds / 60).rounded())) }
        let eveLine = String(localized: "Weak spots only, then sleep")
        var stops: [Stop] = []

        if case .eve = phase {
            let eve = plan.days.first { $0.kind == .examEve }
            stops.append(Stop(id: "eve", kind: .eve,
                              title: String(localized: "Tonight · about \(minutes(eve?.seconds ?? PlanBuilder.examEveSeconds)) min"),
                              detail: eveLine))
        } else {
            let todayStop: Stop
            if today.sessionMinutes > 0 {
                let detail: String
                if today.examSeconds <= 0 {
                    detail = String(localized: "Today's session is for your other exams.")
                } else if today.topics.isEmpty {
                    detail = String(localized: "About \(today.examMinutes) min for this exam")
                } else {
                    detail = String(localized: "About \(today.examMinutes) min for this exam: \(topicList(today.topics))")
                }
                todayStop = Stop(id: "today", kind: .today, title: String(localized: "Today · \(today.sessionMinutes) min"), detail: detail)
            } else if today.studiedToday {
                todayStop = Stop(id: "today", kind: .today, title: String(localized: "Today · done"),
                                 detail: String(localized: "Today's session is in."))
            } else {
                todayStop = Stop(id: "today", kind: .today, title: String(localized: "Today · nothing due"))
            }
            var first = todayStop
            if today.missedYesterday { first.note = String(localized: "Includes yesterday's reviews.") }
            stops.append(first)

            let later = plan.days.filter { $0.offset >= 1 && $0.kind != .exam }
            func dayStop(_ day: PlanDay) -> Stop {
                let name = day.kind == .examEve ? String(localized: "\(weekday(day.date)) evening") : weekday(day.date)
                if day.isSkipped || day.offset == skipped {
                    return Stop(id: "d\(day.offset)", kind: day.kind == .examEve ? .eve : .day,
                                title: String(localized: "\(name) · skipped"),
                                detail: String(localized: "Nothing that day in this what-if."), isSkipped: true)
                }
                if day.kind == .examEve {
                    return Stop(id: "d\(day.offset)", kind: .eve, title: String(localized: "\(name) · about \(minutes(day.seconds)) min"),
                                detail: eveLine)
                }
                return Stop(id: "d\(day.offset)", kind: .day, title: String(localized: "\(name) · about \(minutes(day.seconds)) min"))
            }
            if calendar.dayDistance(from: now, to: examDate) <= nearDays {
                for day in later where day.seconds > 0 || day.isSkipped || day.offset == skipped {
                    stops.append(dayStop(day))
                }
            } else {
                let middle = later.filter { $0.kind != .examEve }
                if let off = middle.first(where: { $0.isSkipped || $0.offset == skipped }) { stops.append(dayStop(off)) }
                let span = middle.filter { !($0.isSkipped || $0.offset == skipped) }
                let total = span.reduce(0) { $0 + $1.seconds }
                if let last = span.last, total > 0 {
                    let perDay = minutes(total / Double(span.count))
                    stops.append(Stop(id: "span", kind: .span,
                                      title: String(localized: "Then about \(perDay) min a day until \(LibraryFormat.shortDate(last.date, calendar: calendar))")))
                }
                if let eve = later.first(where: { $0.kind == .examEve }) { stops.append(dayStop(eve)) }
            }
        }
        let time = examDate.formatted(Date.FormatStyle(locale: calendar.locale ?? .autoupdatingCurrent, calendar: calendar,
                                                       timeZone: calendar.timeZone).hour().minute())
        let day = calendar.dayDistance(from: now, to: examDate) == 1 ? String(localized: "Tomorrow") : examDayName(examDate, now: now, calendar: calendar)
        stops.append(Stop(id: "exam", kind: .exam, title: String(localized: "\(day) · \(time)"), detail: examTitle))
        return stops
    }

    // MARK: What if I skip a day?

    /// The day the what-if offers to skip: the next day after today the plan has work for this exam (the eve included).
    struct SkipOption: Equatable, Sendable {
        /// Days from today (`PlanDay.offset`).
        var offset: Int
        /// "Saturday".
        var name: String

        var question: String { String(localized: "What if I skip \(name)?") }
        var keep: String { String(localized: "Keep \(name)") }
    }

    static func skipOption(plan: StudyPlan, phase: Phase, calendar: Calendar) -> SkipOption? {
        guard case .ahead = phase,
              let day = plan.days.first(where: { $0.offset >= 1 && $0.kind != .exam && $0.seconds > 0 }) else { return nil }
        return SkipOption(offset: day.offset, name: day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide)))
    }

    /// What skipping costs, in points of readiness on exam day: "Skipping Saturday costs about 8 points" / "About 69% ready by Sunday
    /// instead of 77%." Under 2 points it says so: a review put off a day can land nearer the exam.
    struct SkipCost: Equatable, Sendable {
        var points: Int
        var title: String
        var detail: String
    }

    static func skipCost(_ option: SkipOption, planned: Double, skipped: Double, examDate: Date, now: Date,
                         calendar: Calendar) -> SkipCost {
        let points = max(0, Int(((planned - skipped) * 100).rounded()))
        if points < 2 {
            return SkipCost(points: points, title: String(localized: "Skipping \(option.name) costs almost nothing"),
                            detail: String(localized: "The days around it pick up its reviews."))
        }
        let when = examDayName(examDate, now: now, calendar: calendar)
        return SkipCost(points: points,
                        title: String(localized: "Skipping \(option.name) costs about \(String(localized: "\(points) points"))"),
                        detail: String(localized: "About \(CLFormat.percent(skipped)) ready by \(when) instead of \(CLFormat.percent(planned))."))
    }
}
