import SwiftUI
import WidgetKit

// The Live Activities' views: the Lock Screen banner and the Dynamic Island regions for a study session and for
// exam week. The extension assembles them (CramlessWidgets/LiveActivityWidgets.swift); the render tests draw them
// on a stand-in island and Lock Screen. Both sit on the night tint, so they read in light and dark.

enum ActivityLook {
    /// The Lock Screen banner's background.
    static let background = CLColor.night.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.72)
    static let track = Color.white.opacity(0.18)
}

// MARK: - Study session

/// Lock Screen: "Today's session · 4:12 / Question 10 of 18 · 7 correct / (progress bar) / Phases of mitosis".
struct SessionActivityView: View {
    var attributes: StudySessionAttributes
    var state: StudySessionAttributes.ContentState
    var isStale = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WidgetCapFace(size: 46)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.finished ? "Session done" : attributes.title)
                        .font(.system(.headline))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    SessionClock(attributes: attributes, state: state, isStale: isStale)
                        .font(WidgetFont.number(15, .semibold))
                        .foregroundStyle(ActivityLook.secondaryText)
                }
                Text(SessionActivityCopy.detail(attributes: attributes, state: state, isStale: isStale))
                    .font(.system(.subheadline))
                    .foregroundStyle(ActivityLook.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                WidgetBar(value: state.progress(total: attributes.total),
                          tint: state.finished ? CLColor.mint : CLColor.tangerine,
                          track: ActivityLook.track, height: 6)
                    .padding(.top, 2)
                if let topic = state.topic, !state.finished {
                    Text(topic)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(ActivityLook.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SessionActivityCopy.accessibility(attributes: attributes, state: state)))
    }
}

/// Elapsed time, live: the system ticks it without updates. "Paused" when stale, nothing once finished.
struct SessionClock: View {
    var attributes: StudySessionAttributes
    var state: StudySessionAttributes.ContentState
    var isStale: Bool

    var body: some View {
        if state.finished {
            EmptyView()
        } else if isStale {
            Text("Paused")
        } else {
            Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

enum SessionActivityCopy {
    /// "Question 10 of 18 · 7 correct", "Paused at question 10 of 18", "18 answered · 15 correct".
    static func detail(attributes: StudySessionAttributes, state: StudySessionAttributes.ContentState,
                       isStale: Bool) -> String {
        let total = max(1, attributes.total)
        if state.finished {
            return "\(state.answered) answered · \(state.correct) correct"
        }
        let current = min(state.answered + 1, total)
        return "Question \(current) of \(total) · \(state.correct) correct"
    }

    static func accessibility(attributes: StudySessionAttributes, state: StudySessionAttributes.ContentState) -> String {
        if state.finished {
            return "Session done. \(state.answered) answered, \(state.correct) correct."
        }
        var text = "\(attributes.title). \(state.answered) of \(attributes.total) answered, \(state.correct) correct."
        if let topic = state.topic { text += " Now: \(topic)." }
        return text
    }
}

/// Compact leading: progress as a small tangerine ring.
struct SessionCompactRing: View {
    var progress: Double
    var finished = false

    var body: some View {
        WidgetRing(value: progress, lineWidth: 3.5, tint: finished ? CLColor.mint : CLColor.tangerine,
                   track: ActivityLook.track)
            .frame(width: 22, height: 22)
    }
}

/// Compact trailing: "9/18".
struct SessionCompactCount: View {
    var attributes: StudySessionAttributes
    var state: StudySessionAttributes.ContentState

    var body: some View {
        Text(state.finished ? "Done" : "\(state.answered)/\(attributes.total)")
            .font(WidgetFont.number(15, .bold))
            .foregroundStyle(state.finished ? CLColor.mint : CLColor.tangerine)
            .lineLimit(1)
    }
}

/// The expanded island's bottom: the bar and "Phases of mitosis · 7 correct".
struct SessionExpandedBottom: View {
    var attributes: StudySessionAttributes
    var state: StudySessionAttributes.ContentState
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetBar(value: state.progress(total: attributes.total),
                      tint: state.finished ? CLColor.mint : CLColor.tangerine, track: ActivityLook.track, height: 6)
            HStack {
                Text(state.finished ? "Session done" : (state.topic ?? attributes.title))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(state.correct) correct")
                    .monospacedDigit()
            }
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(ActivityLook.secondaryText)
        }
        .padding(.horizontal, 4)
    }
}

/// The expanded island's centre: title and question number.
struct SessionExpandedCenter: View {
    var attributes: StudySessionAttributes
    var state: StudySessionAttributes.ContentState
    var isStale = false

    var body: some View {
        VStack(spacing: 1) {
            Text(state.finished ? "Session done" : attributes.title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
            Text(state.finished ? "\(state.answered) answered"
                 : "Question \(min(state.answered + 1, max(1, attributes.total))) of \(attributes.total)")
                .font(.system(.caption))
                .foregroundStyle(ActivityLook.secondaryText)
        }
        .lineLimit(1)
    }
}

// MARK: - Exam week

/// Lock Screen: the readiness ring, the exam, days left, and what today asks for.
struct ExamWeekActivityView: View {
    var attributes: ExamWeekAttributes
    var state: ExamWeekAttributes.ContentState
    var isStale = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            WidgetReadinessRing(value: state.readiness, size: 56, lineWidth: 6.5, track: ActivityLook.track,
                                labelColor: .white)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(attributes.color.fill).frame(width: 8, height: 8)
                        Text(attributes.title)
                            .font(.system(.headline))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    Text(ExamWeekCopy.days(state: state, examDate: attributes.examDate, isStale: isStale))
                        .font(WidgetFont.number(16, .bold))
                        .foregroundStyle(state.daysLeft <= 1 ? CLColor.tangerine : .white)
                        .lineLimit(1)
                }
                if let delta = WidgetCopy.delta(state.delta), !isStale {
                    Text(delta)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(state.delta > 0 ? CLColor.mint : ActivityLook.secondaryText)
                }
                Text(ExamWeekCopy.today(state: state, courseName: attributes.courseName))
                    .font(.system(.subheadline))
                    .foregroundStyle(ActivityLook.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ExamWeekCopy.accessibility(attributes: attributes, state: state)))
    }
}

enum ExamWeekCopy {
    /// "6 days", "Tomorrow", "Today"; the date once the count may be out of date.
    static func days(state: ExamWeekAttributes.ContentState, examDate: Date, isStale: Bool) -> String {
        if isStale { return examDate.formatted(.dateTime.weekday(.abbreviated).day()) }
        return WidgetCopy.days(state.daysLeft)
    }

    /// What today asks for, calmly.
    static func today(state: ExamWeekAttributes.ContentState, courseName: String) -> String {
        switch state.daysLeft {
        case ..<1: return "Today. You've prepared for this."
        case 1: return "Weak spots tonight, then sleep."
        default:
            return state.studiedToday ? "Today's session is done."
                : "\(state.todayMinutes) minutes today keeps you on track."
        }
    }

    static func accessibility(attributes: ExamWeekAttributes, state: ExamWeekAttributes.ContentState) -> String {
        let when = state.daysLeft < 1 ? "today" : state.daysLeft == 1 ? "tomorrow" : "in \(state.daysLeft) days"
        return "\(attributes.title) \(when). \(WidgetCopy.percent(state.readiness)) percent ready."
    }
}

/// Compact leading and minimal: the readiness ring, coloured.
struct ExamWeekCompactRing: View {
    var readiness: Double

    var body: some View {
        WidgetRing(value: readiness, lineWidth: 3.5, tint: CLColor.readiness(readiness), track: ActivityLook.track)
            .frame(width: 22, height: 22)
    }
}

/// Compact trailing: "6d" (or "Today").
struct ExamWeekCompactDays: View {
    var state: ExamWeekAttributes.ContentState

    var body: some View {
        Text(WidgetCopy.daysShort(state.daysLeft))
            .font(WidgetFont.number(15, .bold))
            .foregroundStyle(CLColor.readiness(state.readiness))
            .lineLimit(1)
    }
}
