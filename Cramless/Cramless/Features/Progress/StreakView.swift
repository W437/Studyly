import SwiftUI

/// The streak: its header, this month's calendar of studied, frozen and repaired days, with each upcoming exam's day and the night
/// before marked (earlier months and the next one a tap of the arrows away), the repair offer when there is one, and one fold, "How freezes
/// work". Every streak link opens it (Progress's row, Today's flame). In Quiet mode it is only the calendar.
///
/// Harness: `CRAMLESS_ROUTE=streak`; `CRAMLESS_SCROLL=freezes` opens the fold and scrolls to it.
struct StreakView: View {
    @Environment(AppModel.self) private var app
    @State private var showsFreezes = false

    var body: some View {
        let _ = app.revision
        let streak = app.streak()
        let cells = app.heatmap(weeks: 20)
        let calendar = app.calendar
        let dailyMinutes = app.settings.dailyMinutes
        let run = streak.repairableDay.map { ProgressPresentation.runBefore($0, cells: cells, calendar: calendar) } ?? 0

        let quiet = app.settings.quietMode
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !quiet {
                    header(streak, run: run)
                        .padding(.top, 8)
                }

                StreakMonthCard(cells: cells)
                    .padding(.top, 20)

                if !quiet {
                    if let day = streak.repairableDay {
                        RepairOffer(day: day, run: run, dailyMinutes: dailyMinutes, calendar: calendar)
                            .clCard()
                            .padding(.top, 16)
                    }

                    FreezesFold(isOpen: $showsFreezes, dailyMinutes: dailyMinutes)
                        .padding(.top, 16)
                        .id("freezes")
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
        .harnessScroll(proxy)
        }
        .clScreenBackground()
        .navigationTitle(quiet ? "Calendar" : "Streak")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .task { if TestHarness.value("CRAMLESS_SCROLL") == "freezes" { showsFreezes = true } }
        #endif
    }

    private func header(_ streak: StreakState, run: Int) -> some View {
        let onHold = streak.current == 0 && streak.repairableDay != nil && run > 0
        let days = onHold ? run : streak.current
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // On hold (a missed day that a repair can still join back up) the flame is only an outline.
                StreakFlame(stage: StreakStage(days: days), size: 44, lit: !onHold)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
                Text(days == 1 ? "1-day streak" : "\(days)-day streak")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ReflowStack(spacing: 8) {
                if onHold {
                    ReflowPill(text: "On hold", tone: .sun, systemImage: "pause.fill")
                }
                ReflowPill(text: "Best \(streak.best)", tone: .neutral, systemImage: "trophy.fill")
                ReflowPill(text: streak.freezesAvailable == 1 ? "1 freeze saved" : "\(streak.freezesAvailable) freezes saved",
                           tone: .sky, systemImage: "snowflake")
                if streak.studiedToday {
                    ReflowPill(text: "Done today", tone: .mint, systemImage: "checkmark")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

}

/// The month's card on the streak page: the calendar with its arrows and its legend.
struct StreakMonthCard: View {
    /// The days that can be shown, with what was studied on each.
    let cells: [HeatmapCell]

    @Environment(AppModel.self) private var app
    @State private var monthOffset = 0

    /// How far ahead the calendar goes: the next month, where the exams and their eves are marked.
    static let monthsAhead = 1

    var body: some View {
        let calendar = app.calendar
        let byDay = Dictionary(cells.map { (calendar.dayNumber(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let earliest = cells.first { $0.level > 0 || $0.frozen || $0.repaired }?.date ?? app.now
        let monthsBack = max(0, monthsBetween(earliest, app.now, calendar: calendar))
        let month = calendar.date(byAdding: .month, value: monthOffset, to: app.now) ?? app.now
        let marks = ExamMarks(app.upcomingExams().filter { $0.course?.deletedAt == nil && $0.date > app.now }
            .map { (title: $0.title, date: $0.date) }, calendar: calendar)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(month.formatted(LibraryFormat.dateStyle(calendar).month(.wide).year()))
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.opacity)
                Spacer()
                CLIconButton(systemImage: "chevron.left", label: "Previous month") {
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) { monthOffset -= 1 }
                }
                .disabled(-monthOffset >= monthsBack)
                .opacity(-monthOffset >= monthsBack ? 0.35 : 1)
                CLIconButton(systemImage: "chevron.right", label: "Next month") {
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) { monthOffset += 1 }
                }
                .disabled(monthOffset >= Self.monthsAhead)
                .opacity(monthOffset >= Self.monthsAhead ? 0.35 : 1)
            }
            MonthCalendar(month: month, byDay: byDay, marks: marks, today: calendar.dayNumber(for: app.now), calendar: calendar)
                .id(monthOffset)
                .transition(.opacity)
            CalendarLegend(showsExams: !marks.isEmpty)
        }
        .clCard()
    }

    private func monthsBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        let ca = calendar.dateComponents([.year, .month], from: a)
        let cb = calendar.dateComponents([.year, .month], from: b)
        return ((cb.year ?? 0) - (ca.year ?? 0)) * 12 + ((cb.month ?? 0) - (ca.month ?? 0))
    }
}

/// The upcoming exams by day: each exam's day and its eve (the night before), by day number.
struct ExamMarks: Equatable {
    var exams: [Int: [String]] = [:]
    var eves: [Int: [String]] = [:]

    init(_ list: [(title: String, date: Date)], calendar: Calendar) {
        for exam in list {
            let day = calendar.dayNumber(for: exam.date)
            exams[day, default: []].append(exam.title)
            eves[day - 1, default: []].append(exam.title)
        }
    }

    var isEmpty: Bool { exams.isEmpty }
}

/// A month: studied days filled, frozen days in Sky with a snowflake, repaired days marked, today ringed, exam days with a
/// mortarboard and the night before each with a moon.
private struct MonthCalendar: View {
    let month: Date
    let byDay: [Int: HeatmapCell]
    let marks: ExamMarks
    let today: Int
    let calendar: Calendar

    var body: some View {
        let grid = ProgressPresentation.monthGrid(for: month, calendar: calendar)
        let symbols = ProgressPresentation.weekdaySymbols(calendar: calendar)
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CLColor.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            let number = calendar.dayNumber(for: date)
                            DayCell(date: date, cell: byDay[number], isToday: number == today, isFuture: number > today,
                                    exams: marks.exams[number] ?? [], eves: number >= today ? marks.eves[number] ?? [] : [],
                                    calendar: calendar)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let cell: HeatmapCell?
    let isToday: Bool
    let isFuture: Bool
    /// The exams on this day, and the exams the day is the eve of.
    var exams: [String] = []
    var eves: [String] = []
    let calendar: Calendar

    var body: some View {
        let studied = (cell?.level ?? 0) > 0
        let frozen = cell?.frozen == true && !studied
        let repaired = cell?.repaired == true
        let exam = !exams.isEmpty && !studied
        let eve = !eves.isEmpty && !studied && !exam
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            shape.fill(studied ? CLColor.tangerine : frozen ? CLColor.sky : exam ? CLColor.tangerineSoft : eve ? CLColor.sunSoft : Color.clear)
            if isToday { shape.strokeBorder(CLColor.ink, lineWidth: 2) }
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 15, weight: studied || isToday || exam ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(studied || frozen ? CLColor.onFill : exam ? CLColor.tangerineInk : eve ? CLColor.sunInk
                                     : isFuture ? CLColor.ink4 : CLColor.ink2)
                if frozen {
                    Image(systemName: "snowflake").font(.system(size: 8, weight: .bold)).foregroundStyle(CLColor.onFill)
                } else if repaired {
                    Image(systemName: "bandage.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(CLColor.onFill)
                } else if exam {
                    Image(systemName: "graduationcap.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(CLColor.tangerineInk)
                } else if eve {
                    Image(systemName: "moon.stars.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(CLColor.sunInk)
                }
            }
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide).month(.wide).day())))
        .accessibilityValue(Text(value(studied: studied, frozen: frozen, repaired: repaired)))
    }

    private func value(studied: Bool, frozen: Bool, repaired: Bool) -> String {
        var marks: [String] = []
        if !exams.isEmpty { marks.append(String(localized: "Exam: \(exams.formatted(.list(type: .and)))")) }
        if !eves.isEmpty { marks.append(String(localized: "The night before \(eves.formatted(.list(type: .and)))")) }
        if isFuture { return marks.joined(separator: ", ") }
        var parts: [String] = []
        if isToday { parts.append("Today") }
        if studied { parts.append("Studied \(CLFormat.count(cell?.minutes ?? 0, "minute"))") }
        if frozen { parts.append("Covered by a freeze") }
        if repaired { parts.append("Repaired") }
        if parts.isEmpty || (parts == ["Today"]) { parts.append("Not studied") }
        return (parts + marks).joined(separator: ", ")
    }
}

private struct CalendarLegend: View {
    var showsExams = false

    var body: some View {
        // Wraps onto a second line rather than squeezing a word (six keys don't fit one line on a phone).
        CLFlow(spacing: 14, lineSpacing: 8) {
            key(CLColor.tangerine, "Studied")
            key(CLColor.sky, "Frozen")
            HStack(spacing: 5) {
                Image(systemName: "bandage.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(CLColor.tangerineInk)
                Text("Repaired").clFont(.caption).foregroundStyle(CLColor.ink2)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(CLColor.ink, lineWidth: 1.5).frame(width: 12, height: 12)
                Text("Today").clFont(.caption).foregroundStyle(CLColor.ink2)
            }
            if showsExams {
                HStack(spacing: 5) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(CLColor.tangerineInk)
                    Text("Exam").clFont(.caption).foregroundStyle(CLColor.ink2)
                }
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(CLColor.sunInk)
                    Text("Night before").clFont(.caption).foregroundStyle(CLColor.ink2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 12, height: 12)
            Text(title).clFont(.caption).foregroundStyle(CLColor.ink2)
        }
    }
}

/// "How freezes work", folded: how a freeze is earned and what it covers, and the repair for a day no freeze covered.
private struct FreezesFold: View {
    @Binding var isOpen: Bool
    let dailyMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                CLHaptics.select()
                withAnimation(CLMotion.settle) { isOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    CLIconBadge(systemImage: "snowflake", tint: .sky, size: 36)
                    Text("How freezes work").clFont(.headline).foregroundStyle(CLColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CLColor.ink3)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(isOpen ? "Shown" : "Hidden"))
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        Text(verbatim: line)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity)
            }
        }
        .clCard()
    }

    private var lines: [String] {
        [String(localized: "Every 7 days in a row earns a freeze. You can hold \(StreakEngine.maxFreezes)."),
         String(localized: "Miss a day and a freeze covers it, so your streak carries on. It never covers two days in a row."),
         String(localized: "No freeze left? Within \(StreakEngine.repairWindow) days, study \(CLFormat.minutes(dailyMinutes * 2)) in one day, twice your daily goal, and the missed day counts again.")]
    }
}
