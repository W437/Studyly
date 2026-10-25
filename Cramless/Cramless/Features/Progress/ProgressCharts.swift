import SwiftUI

// The Progress charts, drawn by hand because each is a handful of marks:
// - the heatmap draws each day as a star: one hue (tangerine), and the star grows and brightens with the minutes
//   against the goal (a dot, then a sparkle), with a scale legend; a frozen day is a different state, so it takes Sky
//   and says so in the legend;
// - this week's columns carry the accent and last week's sit beside them in the quiet ink (emphasis, one axis);
// - the due forecast is one series in Sky with the counts on the caps.
// Columns are at most 24 pt wide with 4 pt rounded tops on a shared baseline, 2 pt apart when they touch. Brand
// fills sit under 3:1 on white, so values are written on the marks and every mark has a VoiceOver label and value.

/// Twelve weeks of studying: a column per week, a row per weekday, oldest on the left. Cells stay square at any
/// width.
struct StudyHeatmap: View {
    let cells: [HeatmapCell]
    let calendar: Calendar
    var spacing: CGFloat = 4

    @State private var width: CGFloat = 330
    private let labelWidth: CGFloat = 16

    var body: some View {
        let weeks = ProgressPresentation.weeks(cells)
        let months = ProgressPresentation.monthLabels(weeks, calendar: calendar)
        let symbols = ProgressPresentation.weekdaySymbols(calendar: calendar)
        let columns = CGFloat(max(1, weeks.count))
        let cell = max(8, (width - labelWidth - spacing * columns) / columns)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    ForEach(months, id: \.column) { month in
                        Text(month.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CLColor.ink3)
                            .fixedSize()
                            .offset(x: labelWidth + spacing + CGFloat(month.column) * (cell + spacing))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)
                .accessibilityHidden(true)
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(row % 2 == 1 ? symbols[row] : "")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CLColor.ink3)
                                .frame(width: labelWidth, height: cell)
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(week) { day in
                                HeatCell(cell: day, calendar: calendar)
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            HeatmapLegend()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Last 12 weeks of studying"))
    }
}

private struct HeatCell: View {
    let cell: HeatmapCell
    let calendar: Calendar

    var body: some View {
        let style = ProgressPresentation.style(cell)
        let words = ProgressPresentation.accessibility(cell, calendar: calendar)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                mark(style, side: side)
                if cell.isToday {
                    Circle().strokeBorder(CLColor.ink, lineWidth: 1.5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(words.label))
        .accessibilityValue(Text(words.value))
    }

    @ViewBuilder
    private func mark(_ style: ProgressPresentation.CellStyle, side: CGFloat) -> some View {
        if let star = ProgressPresentation.starMark(style) {
            let size = side * star.size
            if star.glow {
                Circle().fill(CLColor.tangerine.opacity(0.20)).frame(width: side * 1.25, height: side * 1.25)
            }
            switch star.shape {
            case .dot:
                Circle().fill(fill(style, opacity: star.opacity)).frame(width: size, height: size)
            case .sparkle:
                SparkleShape().fill(fill(style, opacity: star.opacity)).frame(width: size, height: size)
            }
            if case .frozen = style {
                Image(systemName: "snowflake")
                    .font(.system(size: max(7, side * 0.4), weight: .bold))
                    .foregroundStyle(CLColor.onFill.opacity(0.75))
            }
        } else {
            Circle().strokeBorder(CLColor.surface3, lineWidth: 1).frame(width: side * 0.26, height: side * 0.26)
        }
    }

    private func fill(_ style: ProgressPresentation.CellStyle, opacity: Double) -> Color {
        switch style {
        case .empty, .future: CLColor.surface3
        case .frozen: CLColor.sky
        case .level: CLColor.tangerine.opacity(opacity)
        }
    }
}

/// "Less · • ✦ More · ❄ Frozen": the scale as the stars themselves.
struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 11, weight: .semibold)).foregroundStyle(CLColor.ink3)
            swatch(.empty)
            ForEach(1...4, id: \.self) { swatch(.level($0)) }
            Text("More").font(.system(size: 11, weight: .semibold)).foregroundStyle(CLColor.ink3)
            Spacer(minLength: 8)
            swatch(.frozen)
            Text("Frozen").font(.system(size: 11, weight: .semibold)).foregroundStyle(CLColor.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bigger, brighter stars mean more minutes. Blue stars are days a freeze covered."))
    }

    private func swatch(_ style: ProgressPresentation.CellStyle) -> some View {
        let star = ProgressPresentation.starMark(style) ?? .init(shape: .dot, size: 0.3, opacity: 1, glow: false)
        let side: CGFloat = 13
        let color: Color = switch style {
        case .empty, .future: CLColor.surface3
        case .frozen: CLColor.sky
        case .level: CLColor.tangerine.opacity(star.opacity)
        }
        return ZStack {
            switch star.shape {
            case .dot: Circle().fill(color).frame(width: side * star.size, height: side * star.size)
            case .sparkle: SparkleShape().fill(color).frame(width: side * star.size, height: side * star.size)
            }
        }
        .frame(width: side, height: side)
    }
}

/// This week's minutes per day beside last week's, on one baseline.
struct WeekMinutesChart: View {
    let week: WeeklyStats
    let lastWeek: [Int]
    let calendar: Calendar
    var plotHeight: CGFloat = 110

    var body: some View {
        let peak = max(1, (week.days.map(\.minutes) + lastWeek).max() ?? 1, week.goalMinutes / 7)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                    let last = lastWeek.indices.contains(index) ? lastWeek[index] : 0
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 2) {
                            column(value: last, peak: peak, color: Self.lastWeekColor)
                            column(value: day.isFuture ? 0 : day.minutes, peak: peak, color: CLColor.tangerine)
                                .overlay(alignment: .top) {
                                    if !day.isFuture, day.minutes > 0 {
                                        Text("\(day.minutes)")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(CLColor.ink2)
                                            .fixedSize()
                                            .offset(y: -16)
                                    }
                                }
                        }
                        .frame(height: plotHeight, alignment: .bottom)
                        .padding(.top, 16)
                        .overlay(alignment: .bottom) { Rectangle().fill(CLColor.hairline).frame(height: 1) }
                        Text(day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.narrow)))
                            .font(.system(size: 11, weight: day.isToday ? .heavy : .semibold))
                            .foregroundStyle(day.isToday ? CLColor.ink : CLColor.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide)) + (day.isToday ? ", today" : "")))
                    .accessibilityValue(Text(day.isFuture ? "Still to come. Last week \(CLFormat.count(last, "minute"))"
                                             : "\(CLFormat.count(day.minutes, "minute")). Last week \(CLFormat.count(last, "minute"))"))
                }
            }
            ReflowStack(spacing: 14) {
                legend(CLColor.tangerine, "This week")
                legend(Self.lastWeekColor, "Last week")
            }
            .accessibilityHidden(true)
        }
    }

    /// Last week, the context: the quiet ink, half strength.
    static let lastWeekColor = CLColor.ink4.opacity(0.45)

    private func column(value: Int, peak: Int, color: Color) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 4,
                               style: .continuous)
            .fill(color)
            .frame(maxWidth: 12)
            .frame(height: value > 0 ? max(3, plotHeight * CGFloat(value) / CGFloat(peak)) : 0)
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(title).clFont(.caption).foregroundStyle(CLColor.ink2)
        }
    }
}

/// Reviews due on each of the next seven days.
struct DueForecastChart: View {
    let days: [DueForecastDay]
    let calendar: Calendar
    var plotHeight: CGFloat = 96

    var body: some View {
        let peak = max(1, days.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text("\(day.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(day.count > 0 ? CLColor.ink2 : CLColor.ink4)
                        .fixedSize()
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                           topTrailingRadius: 4, style: .continuous)
                        .fill(day.count > 0 ? CLColor.sky : CLColor.surface3)
                        .frame(maxWidth: 24)
                        .frame(height: day.count > 0 ? max(4, plotHeight * CGFloat(day.count) / CGFloat(peak)) : 3)
                        .frame(height: plotHeight, alignment: .bottom)
                    Text(day.isToday ? "Today" : day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.abbreviated)))
                        .font(.system(size: 11, weight: day.isToday ? .heavy : .semibold))
                        .foregroundStyle(day.isToday ? CLColor.ink : CLColor.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day.isToday ? "Today" : day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide))))
                .accessibilityValue(Text(CLFormat.count(day.count, "review")))
            }
        }
    }
}
