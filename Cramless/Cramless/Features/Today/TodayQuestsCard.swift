import SwiftUI

/// Today's quests under the day's button: the three things today could be, each with how far it is, and the week's meter
/// ("5 of 12 this week") that lights a new sky at 12. Quiet by design: nothing here is owed, and a quest not finished
/// is just a row without a check.
struct TodayQuestsCard: View {
    let quests: QuestsToday

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(spacing: 12) {
                ForEach(quests.rows) { row in
                    QuestRowView(row: row)
                }
            }
            Rectangle().fill(CLColor.hairline).frame(height: 1)
            meter
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    /// "Today's quests" and the week's count beside it (below it at the big text sizes).
    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text("Today's quests")
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(QuestCopy.week(quests.week, of: quests.weekGoal))
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
        }
    }

    /// Twelve small pips, one for each quest the week wants, and what they light.
    private var meter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<quests.weekGoal, id: \.self) { index in
                    Capsule()
                        .fill(index < quests.week ? CLColor.tangerine : CLColor.surface3)
                        .frame(height: 6)
                }
            }
            .animation(CLMotion.pop, value: quests.week)
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(quests.weekLit ? CLColor.sunInk : CLColor.ink3)
                    .accessibilityHidden(true)
                Text(QuestCopy.skyLine(quests))
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(quests.week) of \(quests.weekGoal) quests this week"))
        .accessibilityValue(Text(QuestCopy.skyLine(quests)))
    }
}

/// One quest: its icon, its words, and either a check or how far it is.
struct QuestRowView: View {
    let row: QuestRow

    var body: some View {
        HStack(spacing: 12) {
            CLIconBadge(systemImage: row.kind.symbol, tint: row.kind.tint, size: 32)
                .opacity(row.isDone ? 0.6 : 1)
            Text(row.title)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(row.isDone ? CLColor.ink2 : CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.title))
        .accessibilityValue(row.isDone ? Text("Done") : row.progressText.map { Text($0) } ?? Text("Not done yet"))
    }

    @ViewBuilder private var trailing: some View {
        if row.isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CLColor.mint)
                .transition(.scale.combined(with: .opacity))
        } else if let text = row.progressText {
            Text(text)
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
                .monospacedDigit()
        } else {
            Circle()
                .strokeBorder(CLColor.ink4, lineWidth: 1.5)
                .frame(width: 20, height: 20)
        }
    }
}
