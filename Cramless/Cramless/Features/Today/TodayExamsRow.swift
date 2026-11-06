import SwiftUI

/// "Exams" on Today: each upcoming exam as a small tile (its readiness ring, its name, when it is, this week's change) in a row that
/// scrolls sideways, two tiles and the edge of the next on any phone, and "See all" to the Progress tab, the one list of exams. At the
/// large text sizes the tiles are rows.
/// Hidden on an exam's eve (one exam is all that matters tonight).
struct TodayExamsRow: View {
    let exams: [TodayExam]
    var onOpen: (UUID) -> Void
    var onSeeAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The row's width, edge to edge.
    @State private var rowWidth: CGFloat = 402

    private static let spacing: CGFloat = 12
    /// How much of the third tile shows, so the row says it scrolls.
    private static let peek: CGFloat = 28

    /// A tile's width on a row this wide: the gutter, two tiles and the edge of the next. No narrower than its words need.
    static func tileWidth(rowWidth: CGFloat) -> CGFloat {
        max(150, (rowWidth - CLSpace.gutter - 2 * spacing - peek) / 2)
    }

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
                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(exams) { exam in tile(exam, wide: false) }
                    }
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, CLSpace.gutter, for: .scrollContent)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
                .padding(.horizontal, -CLSpace.gutter)
                .padding(.vertical, -14)
            }
        }
    }

    private func tile(_ exam: TodayExam, wide: Bool) -> some View {
        TodayExamTile(exam: exam, wide: wide, width: Self.tileWidth(rowWidth: rowWidth)) { onOpen(exam.id) }
    }
}

/// One exam in Today's row: its readiness ring, its name, when it is (rose within three days), and this week's change.
struct TodayExamTile: View {
    let exam: TodayExam
    /// A full-width row (the large text sizes) rather than a tile.
    var wide = false
    /// The tile's width (not for a full-width row).
    var width: CGFloat = 165
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
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
                deltaPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clCard(padding: 14, radius: 22)
            .frame(width: wide ? nil : width)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(exam.title), \(exam.when)"))
        .accessibilityValue(Text(verbatim: "\(CLFormat.percent(exam.readiness)) \(String(localized: "ready")), \(deltaWords)"))
        .accessibilityAddTraits(.isButton)
    }

    /// "+15% this week" with an arrow up, "−3% this week" with an arrow down, "Steady this week": words and a shape, not colour alone.
    private var deltaPill: some View {
        let points = Int((exam.delta * 100).rounded())
        return Group {
            if points > 0 {
                ReflowPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: .mint, systemImage: "arrow.up.right")
            } else if points < 0 {
                ReflowPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: .neutral, systemImage: "arrow.down.right")
            } else {
                ReflowPill(text: "Steady this week", tone: .neutral, systemImage: "minus")
            }
        }
    }

    private var deltaWords: String {
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
