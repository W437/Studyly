import SwiftUI

// The plan screen's week: the next seven days' minutes.

/// One day of the week strip.
struct PlanWeekDay: Identifiable, Equatable {
    var id: Int
    var date: Date
    var minutes: Int
    var kind: PlanDay.Kind
    var isToday: Bool
}

/// The next seven days' minutes as columns: today in the accent, rest days empty, the night before and the exam marked.
struct PlanWeekStrip: View {
    let days: [PlanWeekDay]
    var risen: Bool

    private let barHeight: CGFloat = 64

    var body: some View {
        let most = max(1, days.map(\.minutes).max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 6) {
                    Text(label(day))
                        .clFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(day.kind == .rest ? CLColor.ink3 : CLColor.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: barHeight)
                        if day.kind == .exam {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(CLColor.tangerineInk)
                                .padding(.bottom, 4)
                        } else if day.minutes > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                                .fill(day.isToday ? CLColor.tangerine : CLColor.tangerine.opacity(0.42))
                                .frame(width: 22)
                                .frame(height: risen ? max(6, barHeight * Double(day.minutes) / Double(most)) : 4)
                                .animation(CLMotion.settle.delay(Double(index) * 0.05), value: risen)
                        }
                    }
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .clFont(.caption)
                        .fontWeight(day.isToday ? .bold : .semibold)
                        .foregroundStyle(day.isToday ? CLColor.tangerineInk : CLColor.ink3)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(spoken(day))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func label(_ day: PlanWeekDay) -> String {
        switch day.kind {
        case .exam: "Exam"
        case .rest: "rest"
        case .examEve: "\(day.minutes)m"
        case .study, .light: "\(day.minutes)m"
        }
    }

    private func spoken(_ day: PlanWeekDay) -> String {
        switch day.kind {
        case .exam: "Exam day"
        case .rest: "Rest"
        case .examEve: "Night before, \(SessionCopy.minutes(day.minutes)) on weak spots"
        case .study, .light: SessionCopy.minutes(day.minutes)
        }
    }
}
