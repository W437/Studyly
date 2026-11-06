import SwiftUI

/// "Your plan" on Today: the week as seven small marks (`TodayPlanStrip`: two days back, today, four ahead, each exam's eve and day),
/// "Calendar" to the streak page's month, and once a first session is done, today's quests folded into one line that opens them in
/// a sheet. Nothing here is ever red: a missed day is a hollow circle.
///
/// - Large text: the five days ahead as rows, in words.
/// - VoiceOver: the week is one element read day by day; the quests line is a button.
struct TodayPlanCard: View {
    let days: [TodayPlanDay]
    let quests: QuestsToday
    var onCalendar: () -> Void
    var onQuests: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your plan")
                    .clFont(.title3)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("Calendar", action: onCalendar)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: CLMetrics.minHitTarget)
                    .accessibilityHint("Opens your streak and the month")
            }
            .padding(.bottom, -10)
            Group {
                if typeSize.isAccessibilitySize { rows } else { strip }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("This week"))
            .accessibilityValue(Text(verbatim: TodayCopy.stripSpoken(days, calendar: app.calendar)))
            if !quests.isEmpty {
                Rectangle().fill(CLColor.hairline).frame(height: 1)
                questsLine
            }
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: The week

    private var strip: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(verbatim: day.isToday ? String(localized: "Today")
                         : day.date.formatted(Date.FormatStyle(calendar: app.calendar, timeZone: app.calendar.timeZone).weekday(.abbreviated)))
                        .font(.system(size: 11, weight: day.isToday ? .bold : .semibold))
                        .foregroundStyle(day.isToday ? CLColor.tangerineInk : CLColor.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    TodayDayMark(day: day, size: 32)
                    Text(verbatim: TodayCopy.stripCaption(day))
                        .font(.system(size: 11, weight: day.isToday ? .bold : .medium, design: .rounded))
                        .foregroundStyle(day.isToday ? CLColor.ink : CLColor.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minHeight: 13)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Today and the four days ahead as rows: the mark and the day in words.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(days.filter { $0.offset >= 0 }) { day in
                HStack(alignment: .center, spacing: 12) {
                    TodayDayMark(day: day, size: 30)
                    Text(verbatim: TodayCopy.stripDay(day, calendar: app.calendar))
                        .clFont(day.isToday ? .subheadlineEmphasis : .subheadline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Quests

    /// "0 of 3 quests today · 5 of 12 this week", with each quest's icon: opens the quests.
    private var questsLine: some View {
        Button(action: onQuests) {
            HStack(spacing: 10) {
                HStack(spacing: -6) {
                    ForEach(quests.rows) { row in
                        Image(systemName: row.isDone ? "checkmark" : row.kind.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(row.isDone ? CLColor.onFill : row.kind.tint.ink)
                            .frame(width: 26, height: 26)
                            .background(row.isDone ? CLColor.mint : row.kind.tint.soft, in: Circle())
                            .overlay(Circle().strokeBorder(CLColor.surface, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Text(verbatim: TodayCopy.questsLine(done: quests.done, of: quests.rows.count, week: quests.week, weekGoal: quests.weekGoal))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CLChevron()
            }
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Today's quests"))
        .accessibilityValue(Text(verbatim: TodayCopy.questsLine(done: quests.done, of: quests.rows.count, week: quests.week,
                                                               weekGoal: quests.weekGoal)))
    }
}

/// One day's mark in "Your plan": a check (studied), a snowflake (a freeze), a hollow circle (nothing, never red), today ringed,
/// a moon on an exam's eve and a mortarboard on its day.
struct TodayDayMark: View {
    let day: TodayPlanDay
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            switch day.mark {
            case .studied, .done:
                Circle().fill(CLColor.tangerine)
                symbol("checkmark", CLColor.onFill)
            case .frozen:
                Circle().fill(CLColor.sky)
                symbol("snowflake", CLColor.onFill)
            case .missed:
                Circle().strokeBorder(CLColor.ink4, lineWidth: 1.5)
            case .minutes:
                Circle().fill(CLColor.surface3)
                if day.isToday { Circle().strokeBorder(CLColor.tangerine, lineWidth: 2.5) }
            case .eve:
                Circle().fill(CLColor.sunSoft)
                if day.isToday { Circle().strokeBorder(CLColor.tangerine, lineWidth: 2.5) }
                symbol("moon.stars.fill", CLColor.sunInk)
            case .exam(let count):
                Circle().fill(CLColor.tangerineSoft)
                symbol("graduationcap.fill", CLColor.tangerineInk)
                if count > 1 {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(CLColor.onFill)
                        .frame(width: 16, height: 16)
                        .background(CLColor.tangerine, in: Circle())
                        .offset(x: size * 0.36, y: -size * 0.36)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(color)
    }
}
