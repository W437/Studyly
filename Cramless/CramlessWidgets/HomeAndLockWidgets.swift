import SwiftUI
import WidgetKit

/// "Next exam": readiness for the next exam. Home Screen small; Lock Screen circular and rectangular.
struct ExamWidget: Widget {
    static let kind = "capling.exam"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            ExamWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next exam")
        .description("How ready you are for your next exam, and the days left.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct ExamWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: SnapshotEntry

    var body: some View {
        ExamWidgetView(family: family, snapshot: entry.snapshot, date: entry.date,
                       fullColor: renderingMode == .fullColor)
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { ExamWidgetView.background.color }
            }
            .widgetURL(ExamWidgetView.url(for: entry.snapshot))
    }
}

/// "Today's session": Home Screen medium and large; the Lock Screen glance ("18 due").
struct TodayWidget: Widget {
    static let kind = "capling.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's session")
        .description("Today's minutes, what's due, and your next exams. Start in one tap.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        TodayWidgetView(family: family, snapshot: entry.snapshot, date: entry.date)
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { TodayWidgetView.background(for: family).color }
            }
            .widgetURL(TodayWidgetView.url)
    }
}

/// "Streak": the inline line beside the Lock Screen clock, and a circular flame.
struct StreakWidget: Widget {
    static let kind = "capling.streak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            StreakWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Your streak and today's minutes, beside the clock.")
        .supportedFamilies([.accessoryInline, .accessoryCircular])
    }
}

private struct StreakWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        StreakWidgetView(family: family, snapshot: entry.snapshot)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(StreakWidgetView.url)
    }
}
