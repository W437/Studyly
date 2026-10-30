import SwiftUI

/// The streak in full: this month's calendar of studied, frozen and repaired days (earlier months a swipe of the
/// arrows away), the repair offer when there is one, and how freezes and repairs work, in plain words.
struct StreakView: View {
    @Environment(AppModel.self) private var app
    @State private var monthOffset = 0

    var body: some View {
        let _ = app.revision
        let streak = app.streak()
        let cells = app.heatmap(weeks: 20)
        let calendar = app.calendar
        let byDay = Dictionary(cells.map { (calendar.dayNumber(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let earliest = cells.first { $0.level > 0 || $0.frozen || $0.repaired }?.date ?? app.now
        let monthsBack = max(0, monthsBetween(earliest, app.now, calendar: calendar))
        let month = calendar.date(byAdding: .month, value: monthOffset, to: app.now) ?? app.now
        let dailyMinutes = app.settings.dailyMinutes
        let run = streak.repairableDay.map { ProgressPresentation.runBefore($0, cells: cells, calendar: calendar) } ?? 0

        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(streak, run: run)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(month.formatted(LibraryFormat.dateStyle(calendar).month(.wide).year()))
                            .clFont(.headline)
                            .foregroundStyle(CLColor.ink)
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
                        .disabled(monthOffset >= 0)
                        .opacity(monthOffset >= 0 ? 0.35 : 1)
                    }
                    MonthCalendar(month: month, byDay: byDay, today: calendar.dayNumber(for: app.now), calendar: calendar)
                        .id(monthOffset)
                        .transition(.opacity)
                    CalendarLegend()
                }
                .clCard()
                .padding(.top, 20)

                if let day = streak.repairableDay {
                    RepairOffer(day: day, run: run, dailyMinutes: dailyMinutes, calendar: calendar)
                        .clCard()
                        .padding(.top, 16)
                }

                CLSectionHeader(title: "Milestones")
                    .id("milestones")
                MilestonesCard(current: streak.current, best: streak.best)

                CLSectionHeader(title: "How freezes work")
                    .id("freezes")
                Explainer(icon: "snowflake", tint: .sky, lines: [
                    "Every 7 days in a row you study earns a freeze. You can hold \(StreakEngine.maxFreezes).",
                    "Miss a single day and a freeze covers it the next morning, so your streak carries on.",
                    "A freeze never covers two days in a row.",
                ])

                CLSectionHeader(title: "How repairs work")
                Explainer(icon: "bandage", tint: .tangerine, lines: [
                    "Missed a day with no freeze left? You have \(StreakEngine.repairWindow) days to fix it.",
                    "Study \(CLFormat.minutes(dailyMinutes * 2)) in one day, twice your daily goal, and the missed day counts again.",
                    "One missed day never undoes a good run. That's the point.",
                ])
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
        .harnessScroll(proxy)
        }
        .clScreenBackground()
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
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

    private func monthsBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        let ca = calendar.dateComponents([.year, .month], from: a)
        let cb = calendar.dateComponents([.year, .month], from: b)
        return ((cb.year ?? 0) - (ca.year ?? 0)) * 12 + ((cb.month ?? 0) - (ca.month ?? 0))
    }
}

/// The milestones, each with the flame it brings: a check on the ones the best streak has reached, and how far the streak
/// is along to the next. A milestone reached stays reached, whatever the streak does after.
private struct MilestonesCard: View {
    let current: Int
    let best: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let next = StreakStage.nextMilestone(after: best)
        VStack(spacing: 14) {
            ForEach(StreakStage.milestones, id: \.self) { days in
                row(days, reached: best >= days, isNext: days == next)
            }
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    private func along(_ days: Int) -> some View {
        Text("\(min(current, days)) of \(days)")
            .clFont(.footnoteEmphasis)
            .foregroundStyle(CLColor.tangerineInk)
            .monospacedDigit()
    }

    private func row(_ days: Int, reached: Bool, isNext: Bool) -> some View {
        let stage = StreakStage(days: days)
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                StreakFlame(stage: stage, size: 34, lit: reached)
                    .opacity(reached || isNext ? 1 : 0.7)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(days) days")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(reached || isNext ? CLColor.ink : CLColor.ink3)
                    Text(stage.title)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                    // At the big text sizes the count has no room beside the name: it goes under it.
                    if isNext, typeSize.isAccessibilitySize { along(days) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if reached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CLColor.mint)
                } else if isNext, !typeSize.isAccessibilitySize {
                    along(days)
                }
            }
            if isNext {
                CLBar(value: Double(min(current, days)) / Double(days), color: CLColor.tangerine, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(days) days, \(String(localized: stage.title))"))
        .accessibilityValue(reached ? Text("Reached") : isNext ? Text("\(min(current, days)) of \(days)") : Text("Not yet"))
    }
}

/// A month: studied days filled, frozen days in Sky with a snowflake, repaired days marked, today ringed.
private struct MonthCalendar: View {
    let month: Date
    let byDay: [Int: HeatmapCell]
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
                            DayCell(date: date, cell: byDay[calendar.dayNumber(for: date)],
                                    isToday: calendar.dayNumber(for: date) == today,
                                    isFuture: calendar.dayNumber(for: date) > today, calendar: calendar)
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
    let calendar: Calendar

    var body: some View {
        let studied = (cell?.level ?? 0) > 0
        let frozen = cell?.frozen == true && !studied
        let repaired = cell?.repaired == true
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            shape.fill(studied ? CLColor.tangerine : frozen ? CLColor.sky : Color.clear)
            if isToday { shape.strokeBorder(CLColor.ink, lineWidth: 2) }
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 15, weight: studied || isToday ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(studied || frozen ? CLColor.onFill : isFuture ? CLColor.ink4 : CLColor.ink2)
                if frozen {
                    Image(systemName: "snowflake").font(.system(size: 8, weight: .bold)).foregroundStyle(CLColor.onFill)
                } else if repaired {
                    Image(systemName: "bandage.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(CLColor.onFill)
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
        if isFuture { return "" }
        var parts: [String] = []
        if isToday { parts.append("Today") }
        if studied { parts.append("Studied \(CLFormat.count(cell?.minutes ?? 0, "minute"))") }
        if frozen { parts.append("Covered by a freeze") }
        if repaired { parts.append("Repaired") }
        if parts.isEmpty || (parts == ["Today"]) { parts.append("Not studied") }
        return parts.joined(separator: ", ")
    }
}

private struct CalendarLegend: View {
    var body: some View {
        ReflowStack(spacing: 14) {
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

/// A few plain sentences beside an icon.
private struct Explainer: View {
    let icon: String
    let tint: CourseColor
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
    }
}
