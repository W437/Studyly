import SwiftUI

/// "Exams" on Today: each upcoming exam as a small tile (its readiness ring, its name, when it is, this week's change) in a row that
/// scrolls sideways, and "See all" to the Progress tab, the one list of exams. At the large text sizes the tiles are rows.
/// Hidden on an exam's eve (one exam is all that matters tonight).
struct TodayExamsRow: View {
    let exams: [TodayExam]
    var onOpen: (UUID) -> Void
    var onSeeAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Exams", actionTitle: "See all", action: onSeeAll)
                .padding(.top, -16)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(exams) { exam in tile(exam, wide: true) }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(exams) { exam in tile(exam, wide: false) }
                    }
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, CLSpace.gutter, for: .scrollContent)
                .padding(.horizontal, -CLSpace.gutter)
                .padding(.vertical, -14)
            }
        }
    }

    private func tile(_ exam: TodayExam, wide: Bool) -> some View {
        Button { onOpen(exam.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ReadinessRing(value: exam.readiness, size: 46, lineWidth: 6)
                Text(verbatim: exam.title)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(wide ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: exam.when)
                    .clFont(.footnote)
                    .foregroundStyle(exam.daysLeft <= 3 ? CLColor.roseInk : CLColor.ink2)
                    .fontWeight(exam.daysLeft <= 3 ? .semibold : .regular)
                    .lineLimit(wide ? nil : 1)
                    .minimumScaleFactor(0.85)
                deltaPill(exam)
            }
            .frame(width: wide ? nil : 150, alignment: .leading)
            .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
            .clCard(padding: 14, radius: 22)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(exam.title), \(exam.when)"))
        .accessibilityValue(Text(verbatim: "\(CLFormat.percent(exam.readiness)) \(String(localized: "ready")), \(deltaWords(exam))"))
        .accessibilityAddTraits(.isButton)
    }

    /// "+15% this week" with an arrow up, "−3% this week" with an arrow down, "Steady this week": words and a shape, not colour alone.
    private func deltaPill(_ exam: TodayExam) -> some View {
        let points = Int((exam.delta * 100).rounded())
        return Group {
            if points > 0 {
                CLPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: .mint, systemImage: "arrow.up.right")
            } else if points < 0 {
                CLPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: .neutral, systemImage: "arrow.down.right")
            } else {
                CLPill(text: "Steady this week", tone: .neutral, systemImage: "minus")
            }
        }
    }

    private func deltaWords(_ exam: TodayExam) -> String {
        let points = Int((exam.delta * 100).rounded())
        return points == 0 ? String(localized: "steady this week")
            : points > 0 ? String(localized: "up \(points) points this week") : String(localized: "down \(-points) points this week")
    }
}

/// In the exams' place when there is material and no exam yet: "When is your next exam?" and "Add an exam".
struct TodayAddExamCard: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CLIconBadge(systemImage: "calendar.badge.plus", tint: .tangerine, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TodayCopy.addExamTitle)
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(TodayCopy.addExamDetail)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Add an exam", action: onAdd)
                .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }
}
