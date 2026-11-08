import SwiftUI

// The due forecast, drawn by hand because it is a handful of marks: one series in Sky with the counts on the caps. Columns are at
// most 24 pt wide with 4 pt rounded tops on a shared baseline. Brand fills sit under 3:1 on white, so values are written on the marks
// and every mark has a VoiceOver label and value. (Over the memory sky, in `SkyMemoryPanel`.)

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
