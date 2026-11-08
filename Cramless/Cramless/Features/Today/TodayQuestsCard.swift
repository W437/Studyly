import SwiftUI

/// Today's quests up close, in the quests sheet: the three things today could be, each with how far it is, and the week's meter
/// ("5 of 12 quests this week", "12 this week unlocks a new sky: Dusk"). Quiet by design: nothing here is owed, and a quest not
/// finished is just a row without a check.
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

/// Today's one quests row under the day card: each quest's mark and "0 of 3 quests ›", which opens them in a sheet. For a Squad member,
/// one line under it says who in the Squad has studied today and opens the Squad. Nothing here is ever red, and nothing is owed.
///
/// VoiceOver: "Today's quests, 0 of 3 quests" (a button), then "Your Squad" with its line.
struct TodayQuestsRow: View {
    let quests: QuestsToday
    /// Who in the Squad has studied today: only for a Squad member, never the night before an exam or in Quiet mode.
    var squad: SquadToday?
    var onQuests: () -> Void
    var onSquad: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !quests.isEmpty { questsLine }
            if !quests.isEmpty, squad != nil {
                Rectangle().fill(CLColor.hairline).frame(height: 1).padding(.vertical, 4)
            }
            if let squad { squadLine(squad) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .clCard(padding: 0)
        .accessibilityElement(children: .contain)
    }

    /// Each quest's mark (a check once done), "0 of 3 quests" and a chevron.
    private var questsLine: some View {
        Button(action: onQuests) {
            HStack(spacing: 12) {
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
                Text(verbatim: TodayCopy.quests(done: quests.done, of: quests.rows.count))
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CLChevron()
            }
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Today's quests"))
        .accessibilityValue(Text(verbatim: TodayCopy.quests(done: quests.done, of: quests.rows.count)))
        .accessibilityHint(Text("Opens today's quests and the week's"))
    }

    /// "Priya studied today", with each friend's face: opens the Squad.
    private func squadLine(_ squad: SquadToday) -> some View {
        Button(action: onSquad) {
            HStack(spacing: 12) {
                HStack(spacing: -4) {
                    // The first on top: each face's mark sits over the next one's edge.
                    ForEach(Array(squad.friends.prefix(3).enumerated()), id: \.element.id) { index, friend in
                        SquadFace(name: friend.name, studied: friend.studied == true, size: 26, ring: true)
                            .zIndex(Double(-index))
                    }
                }
                .accessibilityHidden(true)
                Text(verbatim: squad.line)
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
        .accessibilityLabel(Text("Your Squad"))
        .accessibilityValue(Text(verbatim: squad.line))
    }
}
