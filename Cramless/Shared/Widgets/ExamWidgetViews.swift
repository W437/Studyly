import SwiftUI
import WidgetKit

/// The "Next exam" widget: how ready the person is for their next exam. Lock Screen circular (the ring) and
/// rectangular (title, readiness, days left, today's minutes); Home Screen small (ring, exam, days).
struct ExamWidgetView: View {
    var family: WidgetFamily
    /// Already rolled to `date`. Nil when the app hasn't written one (or there's no App Group).
    var snapshot: WidgetSnapshot?
    var date: Date
    var fullColor = true
    var calendar: Calendar = .current

    var body: some View {
        switch family {
        case .accessoryCircular:
            ExamCircularView(snapshot: snapshot, date: date, fullColor: fullColor, calendar: calendar)
        case .accessoryRectangular:
            ExamRectangularView(snapshot: snapshot, date: date, calendar: calendar)
        default:
            ExamSmallView(snapshot: snapshot, date: date, calendar: calendar)
        }
    }

    static let background = WidgetBackground.surface

    /// Where a tap goes: the exam, or Today when there's none.
    static func url(for snapshot: WidgetSnapshot?) -> URL {
        snapshot?.nextExam.map { CramlessLink.exam($0.id) } ?? CramlessLink.today
    }
}

// MARK: - Home Screen small

struct ExamSmallView: View {
    var snapshot: WidgetSnapshot?
    var date: Date
    var calendar: Calendar = .current

    var body: some View {
        if let snapshot, let exam = snapshot.nextExam {
            filled(exam, days: snapshot.daysLeft(to: exam, from: date, calendar: calendar))
        } else {
            WidgetEmptyState(
                title: snapshot == nil ? "Open Capling" : "No exam yet",
                detail: snapshot == nil ? "Your next exam and how ready you are show up here."
                    : "Add one and Capling tracks how ready you are.")
        }
    }

    private func filled(_ exam: WidgetSnapshot.Exam, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                WidgetReadinessRing(value: exam.readiness, size: 58, lineWidth: 7)
                Spacer(minLength: 0)
                DaysLeftBadge(days: days)
            }
            Spacer(minLength: 6)
            WidgetEyebrow(text: "Next exam", dot: exam.color)
                .padding(.bottom, 3)
            Text(exam.title)
                .font(WidgetFont.title)
                .foregroundStyle(CLColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            WidgetDelta(delta: exam.delta)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(WidgetCopy.examAccessibility(exam, daysLeft: days)))
    }
}

/// "23 / days" at the top right of the small widget; "Today" in tangerine on the day.
struct DaysLeftBadge: View {
    var days: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: -2) {
            if days < 1 {
                Text("Today")
                    .font(WidgetFont.number(19, .heavy))
                    .foregroundStyle(CLColor.tangerineInk)
            } else {
                Text("\(days)")
                    .font(WidgetFont.number(days > 99 ? 24 : 28))
                    .foregroundStyle(days <= 2 ? CLColor.tangerineInk : CLColor.ink)
                    .widgetAccentable()
                Text(days == 1 ? "day" : "days")
                    .font(WidgetFont.captionEmphasis)
                    .foregroundStyle(CLColor.ink2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Cap and two short lines, for widgets with nothing to show yet.
struct WidgetEmptyState: View {
    var title: String
    var detail: String
    var capSize: CGFloat = 38
    var titleColor: Color = CLColor.ink
    var detailColor: Color = CLColor.ink2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetCapFace(size: capSize)
            Spacer(minLength: 6)
            Text(title)
                .font(WidgetFont.title)
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Text(detail)
                .font(WidgetFont.caption)
                .foregroundStyle(detailColor)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lock Screen

/// The next exam's readiness as a ring with the percentage and days left inside. Lock Screen widgets render
/// vibrant (monochrome), so it draws in the primary style unless the context is full colour.
struct ExamCircularView: View {
    var snapshot: WidgetSnapshot?
    var date: Date
    var fullColor = false
    var calendar: Calendar = .current

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let snapshot, let exam = snapshot.nextExam {
                let days = snapshot.daysLeft(to: exam, from: date, calendar: calendar)
                WidgetRing(value: exam.readiness, lineWidth: 5,
                           tint: fullColor ? CLColor.readiness(exam.readiness) : .primary,
                           track: Color.primary.opacity(0.22))
                    .padding(2)
                VStack(spacing: -3) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(WidgetCopy.percent(exam.readiness))")
                            .font(WidgetFont.number(21))
                        Text("%")
                            .font(WidgetFont.number(10, .bold))
                    }
                    .widgetAccentable()
                    Text(WidgetCopy.daysShort(days))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(WidgetCopy.examAccessibility(exam, daysLeft: days)))
            } else {
                // No exam: today's goal as the ring.
                let s = snapshot
                let goal = max(1, s?.today.goalMinutes ?? 15)
                let done = s?.streak.studiedToday == true ? goal : (s?.today.doneMinutes ?? 0)
                WidgetRing(value: Double(done) / Double(goal), lineWidth: 5, tint: .primary,
                           track: Color.primary.opacity(0.22))
                    .padding(2)
                VStack(spacing: -3) {
                    Text("\(s?.today.sessionMinutes ?? 15)")
                        .font(WidgetFont.number(20))
                        .widgetAccentable()
                    Text("min")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("No exam yet. \(s?.today.sessionMinutes ?? 15) minutes today."))
            }
        }
    }
}

/// "(target) BIO 101 MIDTERM / 64% ready / 23 days · 15 min today".
struct ExamRectangularView: View {
    var snapshot: WidgetSnapshot?
    var date: Date
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot, let exam = snapshot.nextExam {
                let days = snapshot.daysLeft(to: exam, from: date, calendar: calendar)
                AccessoryEyebrow(text: exam.title, systemImage: "target")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(WidgetCopy.percent(exam.readiness))%")
                        .font(WidgetFont.number(26))
                        .widgetAccentable()
                    Text("ready")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text("\(WidgetCopy.days(days)) · \(WidgetCopy.todayProgress(snapshot))")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                AccessoryEyebrow(text: snapshot == nil ? "Capling" : "Next exam", systemImage: "target")
                Text(snapshot == nil ? "Get started" : "No exam yet")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .widgetAccentable()
                Text(snapshot.map { WidgetCopy.sentenceCase(WidgetCopy.todayProgress($0)) } ?? "Your next exam shows here")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The small uppercase line at the top of a Lock Screen widget.
struct AccessoryEyebrow: View {
    var text: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
    }
}
