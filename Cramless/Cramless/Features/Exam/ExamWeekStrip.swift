import SwiftUI

/// The exam's week as a strip of days: this exam's minutes each day, today filled, rest days quiet, the eve and the
/// exam marked. A missed yesterday leads the strip struck through, with an arrow into today, which picks up its
/// reviews. At accessibility text sizes the days become rows.
struct ExamWeekStrip: View {
    let days: [ExamPresentation.StripDay]
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.abbreviated).day()))
                            .clFont(.bodyEmphasis)
                            .foregroundStyle(day.isToday ? CLColor.tangerineInk : CLColor.ink)
                        Text(Self.describe(day)).clFont(.body).foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                ForEach(days) { day in
                    DayColumn(day: day, calendar: calendar)
                        .overlay(alignment: .trailing) {
                            if day.kind == .missed || day.kind == .frozen, days.first?.id == day.id, days.count > 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(CLColor.tangerineInk)
                                    .frame(width: 16, height: 16)
                                    .background(CLColor.surface, in: Circle())
                                    .overlay(Circle().strokeBorder(CLColor.tangerineSoft, lineWidth: 1))
                                    .offset(x: 11)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                    .padding(.bottom, 9)
                                    .accessibilityHidden(true)
                            }
                        }
                        .zIndex(day.kind == .missed || day.kind == .frozen ? 1 : 0)
                }
            }
        }
    }

    /// A day in words, for VoiceOver and the large-text rows.
    static func describe(_ day: ExamPresentation.StripDay) -> String {
        let today = day.isToday ? "Today. " : ""
        switch day.kind {
        case .missed: return "Missed. Its reviews moved into the next days."
        case .frozen: return "Missed, covered by a streak freeze. Its reviews moved into the next days."
        case .study, .light:
            let base = "\(today)\(CLFormat.minutes(day.minutes)) for this exam"
            return day.absorbsMissedDay ? base + ", including yesterday's reviews" : base
        case .rest: return "\(today)Nothing due for this exam"
        case .eve: return "\(today)Exam eve: weak spots, then sleep"
        case .exam: return "Exam day"
        }
    }

    private struct DayColumn: View {
        let day: ExamPresentation.StripDay
        let calendar: Calendar

        var body: some View {
            VStack(spacing: 6) {
                Text(day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.abbreviated)))
                    .clFont(.caption).fontWeight(.semibold)
                    .foregroundStyle(day.isToday ? CLColor.tangerineInk : CLColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(day.date.formatted(LibraryFormat.dateStyle(calendar).day()))
                    .clFont(.number(15, .bold))
                    .foregroundStyle(day.kind == .missed || day.kind == .frozen ? CLColor.ink3 : CLColor.ink)
                pill
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(day.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide).month(.wide).day())))
            .accessibilityValue(Text(ExamWeekStrip.describe(day)))
        }

        @ViewBuilder
        private var pill: some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            Group {
                switch day.kind {
                case .study, .light:
                    Text("\(day.minutes)m")
                        .clFont(.number(12, .bold))
                        .foregroundStyle(day.isToday ? CLColor.onFill : CLColor.tangerineInk)
                case .rest:
                    Text("rest").clFont(.caption).fontWeight(.semibold).foregroundStyle(CLColor.ink3)
                case .eve:
                    HStack(spacing: 2) {
                        Image(systemName: "moon.stars.fill").font(.system(size: 11, weight: .semibold))
                        if day.minutes > 0 { Text("\(day.minutes)m").clFont(.number(12, .bold)) }
                    }
                    .foregroundStyle(day.isToday ? CLColor.onFill : CLColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                case .exam:
                    Image(systemName: "graduationcap.fill").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CLColor.onFill)
                case .missed:
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(CLColor.ink3)
                case .frozen:
                    Image(systemName: "snowflake").font(.system(size: 13, weight: .bold)).foregroundStyle(CLColor.skyInk)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(fill, in: shape)
            .overlay {
                if day.absorbsMissedDay {
                    shape.strokeBorder(CLColor.tangerineInk, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .padding(-3)
                }
            }
        }

        private var fill: Color {
            switch day.kind {
            case .study, .light: day.isToday ? CLColor.tangerine : CLColor.tangerineSoft
            case .rest: .clear
            case .eve: day.isToday ? CLColor.tangerine : CLColor.surface3
            case .exam: CLColor.sun
            case .missed: CLColor.surface2
            case .frozen: CLColor.skySoft
            }
        }
    }
}
