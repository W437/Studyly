import Foundation

/// "Your plan" on Today: seven days, two back, today and four ahead, across every exam (`TodayPlanStrip.make`, pure). The past
/// days say whether you studied (a check, a repair counts), a freeze covered the day (a snowflake) or not (a hollow circle: never
/// red, nothing is owed); today says its planned minutes, or a check once the goal is met; each exam's eve is a moon with its 10
/// minutes, the exam day a mortarboard ("2" when two exams share it); other days the minutes planned: the daily goal (half on an
/// easy day), more when an exam's share of the shared plan (`AppModel.examPlans()`) needs more.
struct TodayPlanDay: Equatable, Sendable, Identifiable {
    enum Mark: Equatable, Sendable {
        /// A past day you studied (or repaired).
        case studied
        /// A past day a freeze covered.
        case frozen
        /// A past day with nothing: a hollow circle.
        case missed
        /// Today's goal is met.
        case done
        /// Minutes planned (today or ahead).
        case minutes(Int)
        /// The night before an exam: its short session.
        case eve(minutes: Int)
        /// An exam day: how many exams.
        case exam(count: Int)
    }

    /// Days from today (-2 ... 4).
    var offset: Int
    /// The start of the day.
    var date: Date
    var mark: Mark
    /// The exams that make the day an eve or an exam day, for VoiceOver.
    var examTitles: [String] = []
    var isEasy = false

    var id: Int { offset }
    var isToday: Bool { offset == 0 }
}

enum TodayPlanStrip {
    /// Days shown before and after today.
    static let back = 2
    static let ahead = 4

    /// One exam as the strip needs it: its title and its share of the plan, day by day (`StudyPlan.days`, from today to the exam).
    struct ExamPlan: Equatable, Sendable {
        var title: String
        var days: [PlanDay]
    }

    /// The week. `today` is now; `past` are the day records (any range; only the two days back are read); `todayMinutes` is the
    /// session planned now and `todayDone` that the day's goal is met; `goal` the daily minutes; `easyDays` the weekdays (1 Sunday
    /// ... 7 Saturday) that are easy.
    static func make(today: Date, plans: [ExamPlan], past: [DaySnapshot], todayMinutes: Int, todayDone: Bool, goal: Int,
                     easyDays: [Int], calendar: Calendar) -> [TodayPlanDay] {
        let todayNumber = calendar.dayNumber(for: today)
        let records = Dictionary(past.map { (calendar.dayNumber(for: $0.day), $0) }, uniquingKeysWith: { a, b in a.studied ? a : b })
        // What each exam's plan says about each day ahead.
        var eves: [Int: [String]] = [:]
        var examDays: [Int: [String]] = [:]
        var busiest: [Int: Int] = [:]
        for plan in plans {
            for day in plan.days {
                let offset = day.dayNumber - todayNumber
                guard offset >= 0, offset <= ahead else { continue }
                switch day.kind {
                case .exam: examDays[offset, default: []].append(plan.title)
                case .examEve: eves[offset, default: []].append(plan.title)
                case .study, .light, .rest:
                    if !day.isSkipped { busiest[offset] = max(busiest[offset] ?? 0, day.sessionMinutes) }
                }
            }
        }

        func easy(_ number: Int) -> Bool { !easyDays.isEmpty && easyDays.contains(Calendar.weekday(dayNumber: number)) }
        func dayGoal(_ number: Int) -> Int {
            easy(number) ? Int((Double(goal) * StudyScheduler.easyDayCapacity).rounded()) : goal
        }

        var week: [TodayPlanDay] = []
        for offset in -back...ahead {
            let number = todayNumber + offset
            let date = calendar.startOfDay(dayNumber: number)
            var day = TodayPlanDay(offset: offset, date: date, mark: .missed, isEasy: easy(number))
            if offset < 0 {
                let record = records[number]
                if let record, record.studied {
                    day.mark = .studied
                } else if record?.frozen == true {
                    day.mark = .frozen
                } else {
                    day.mark = .missed
                }
            } else if let titles = examDays[offset] {
                day.mark = .exam(count: titles.count)
                day.examTitles = titles
            } else if let titles = eves[offset] {
                day.mark = offset == 0 && todayDone ? .done : .eve(minutes: SessionBuilder.examEveMinutes)
                day.examTitles = titles
            } else if offset == 0 {
                day.mark = todayDone ? .done : .minutes(todayMinutes)
            } else {
                day.mark = .minutes(max(dayGoal(number), busiest[offset] ?? 0))
            }
            week.append(day)
        }
        return week
    }
}
