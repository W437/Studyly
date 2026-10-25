import ActivityKit
import SwiftUI
import WidgetKit

/// The study-session Live Activity: Lock Screen banner and Dynamic Island. Tapping it returns to the session
/// (`capling://session` doesn't start a second one while one is open).
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudySessionAttributes.self) { context in
            SessionActivityView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(ActivityLook.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(CramlessLink.session)
        } dynamicIsland: { context in
            let progress = context.state.progress(total: context.attributes.total)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetCapFace(size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionClock(attributes: context.attributes, state: context.state, isStale: context.isStale)
                        .font(WidgetFont.number(17, .semibold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    SessionExpandedCenter(attributes: context.attributes, state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionExpandedBottom(attributes: context.attributes, state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                SessionCompactRing(progress: progress, finished: context.state.finished)
            } compactTrailing: {
                SessionCompactCount(attributes: context.attributes, state: context.state)
            } minimal: {
                SessionCompactRing(progress: progress, finished: context.state.finished)
            }
            .widgetURL(CramlessLink.session)
            .keylineTint(CLColor.tangerine)
        }
    }
}

/// The exam-week Live Activity: readiness and days left for the next exam in its last week.
struct ExamWeekLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExamWeekAttributes.self) { context in
            ExamWeekActivityView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(ActivityLook.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(CramlessLink.exam(context.attributes.examID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetReadinessRing(value: context.state.readiness, size: 44, lineWidth: 5,
                                        track: ActivityLook.track, labelColor: .white)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ExamWeekCopy.days(state: context.state, examDate: context.attributes.examDate,
                                           isStale: context.isStale))
                        .font(WidgetFont.number(17, .bold))
                        .foregroundStyle(context.state.daysLeft <= 1 ? CLColor.tangerine : .white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ExamWeekCopy.today(state: context.state, courseName: context.attributes.courseName))
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(ActivityLook.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                ExamWeekCompactRing(readiness: context.state.readiness)
            } compactTrailing: {
                ExamWeekCompactDays(state: context.state)
            } minimal: {
                ExamWeekCompactRing(readiness: context.state.readiness)
            }
            .widgetURL(CramlessLink.exam(context.attributes.examID))
            .keylineTint(CLColor.readiness(context.state.readiness))
        }
    }
}
