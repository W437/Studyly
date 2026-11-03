import Foundation

/// Shapes engine values (`readinessHistory`, `plan(for:)`, day records) for the exam screens. Pure and clock-free:
/// no recall is computed here, only arranged.
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

    /// The sentence under the path: on track, or how far short the plan lands.
    static func pathSummary(_ path: Path, suggestedMinutes: Int?, calendar: Calendar) -> String {
        let target = CLFormat.percent(path.target)
        if let reached = path.targetReachedOn {
            if calendar.dayDistance(from: path.now, to: reached) <= 0 { return "You're at your \(target) target. The plan keeps you there." }
            return "On track for \(target) by \(LibraryFormat.shortDate(reached, calendar: calendar)) if you follow the plan."
        }
        let landing = "The plan gets you to \(CLFormat.percent(path.projectedAtExam)) by exam day."
        if let minutes = suggestedMinutes {
            return "\(landing) About \(minutes) minutes on the busy days would get you closer to \(target)."
        }
        return "\(landing) Adding material or a few minutes a day gets you closer to \(target)."
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

    /// "Capling projected 87%, you got 91%." and what that means for projections.
    static func gradeComparison(projected: Double, got: Double, calibratedNow: Bool) -> (headline: String, note: String) {
        let headline = "Capling projected \(CLFormat.percent(projected)), you got \(CLFormat.percent(got))."
        let note = calibratedNow
            ? "Projections are now calibrated to your grades."
            : "Projections will calibrate as you log more grades."
        return (headline, note)
    }
}
