import SwiftUI

/// The month, from Progress's week card: the streak in a line, the calendar, today's notes, and the way to the rest of the streak page.
/// A fitted sheet.
struct StreakMonthSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let streak = app.streak()
        let cells = app.heatmap(weeks: 20)
        let run = streak.repairableDay.map { ProgressPresentation.runBefore($0, cells: cells, calendar: app.calendar) } ?? 0
        let onHold = streak.current == 0 && streak.repairableDay != nil && run > 0
        let days = onHold ? run : streak.current
        TodayFittedSheet {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 8) {
                    StreakFlame(stage: StreakStage(days: days), size: 30, lit: !onHold)
                    Text(verbatim: ProgressPresentation.monthHeadline(days: days, best: streak.best, freezes: streak.freezesAvailable))
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 24)
                StreakMonthCard(cells: cells)
                StreakNotes(streak: streak, calendar: app.calendar, now: app.now)
                Button {
                    CLHaptics.tap()
                    dismiss()
                    app.router.push(.streak)
                } label: {
                    HStack(spacing: 4) {
                        Text("Milestones and how freezes work")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    }
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 16)
        }
    }
}
