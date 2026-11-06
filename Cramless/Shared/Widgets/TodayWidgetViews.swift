import SwiftUI
import WidgetKit

/// The "Today's session" widget: Home Screen medium (the session, a Start button, the next two exams) and large
/// (the session card, weak spots, three exams, the streak), and the Lock Screen glance ("18 due").
struct TodayWidgetView: View {
    var family: WidgetFamily
    /// Already rolled to `date`; nil when the app hasn't written one.
    var snapshot: WidgetSnapshot?
    var date: Date
    var calendar: Calendar = .current

    var body: some View {
        let snapshot = snapshot?.forTodayWidget
        switch family {
        case .accessoryRectangular:
            TodayGlanceView(snapshot: snapshot)
        case .systemLarge:
            TodayLargeView(snapshot: snapshot, date: date, calendar: calendar)
        default:
            TodayMediumView(snapshot: snapshot, date: date, calendar: calendar)
        }
    }

    static func background(for family: WidgetFamily) -> WidgetBackground {
        family == .systemLarge ? .surface : .night
    }

    static let url = CramlessLink.today
}

// MARK: - Medium

/// The night card from Today: minutes, counts and Start on the left, the next two exams on the right.
struct TodayMediumView: View {
    var snapshot: WidgetSnapshot?
    var date: Date
    var calendar: Calendar = .current

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TodaySessionPanel(snapshot: snapshot, style: .medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let snapshot, !snapshot.exams.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                NextExamsColumn(snapshot: snapshot, date: date, calendar: calendar)
                    .frame(width: 124, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Image("Cap-study")
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 10)
                    .accessibilityHidden(true)
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// Today's session on the night card: eyebrow, minutes, what's in it, and the one action.
struct TodaySessionPanel: View {
    enum Style { case medium, large }

    var snapshot: WidgetSnapshot?
    var style: Style
    /// Room kept clear on the right of the text lines (the large widget's Cap sits there).
    var textInset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                WidgetEyebrow(text: "Today's session", color: CLColor.ink2)
                Spacer(minLength: 4)
                if style == .large, let s = snapshot, s.streak.current > 0, !s.streak.studiedToday {
                    WidgetStreakPill(count: s.streak.current, studiedToday: false, onNight: true)
                }
            }
            Spacer(minLength: style == .large ? 2 : 4)
            content
        }
        .foregroundStyle(CLColor.ink)
    }

    @ViewBuilder
    private var content: some View {
        if let s = snapshot {
            if s.streak.studiedToday {
                done(s)
            } else if s.today.ready || s.today.hasCounts {
                ready(s)
            } else {
                caughtUp(s)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Capling")
                    .font(WidgetFont.number(style == .large ? 24 : 22, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Your session for today shows up here.")
                    .font(WidgetFont.caption)
                    .foregroundStyle(CLColor.ink2)
                    .lineLimit(2)
                    .padding(.trailing, textInset)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        }
    }

    private func ready(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(s.today.sessionMinutes)")
                    .font(WidgetFont.number(style == .large ? 38 : 34))
                    .widgetAccentable()
                Text("min")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CLColor.ink2)
            }
            Text(WidgetCopy.sessionCounts(s.today) ?? "Your session is ready.")
                .font(WidgetFont.caption)
                .foregroundStyle(CLColor.ink2)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
                .padding(.trailing, textInset)
            if style == .large, s.today.hasCounts, let weak = WidgetCopy.weakSpotsLine(s.today) {
                // Both names when they fit, else the first and how many more.
                ViewThatFits(in: .horizontal) {
                    Text(weak).lineLimit(1)
                    if let short = WidgetCopy.weakSpotsLine(s.today, maxNames: 1) { Text(short).lineLimit(1) }
                }
                .font(WidgetFont.captionEmphasis)
                .foregroundStyle(CLColor.ink)
                .padding(.top, 3)
                .padding(.trailing, textInset)
            }
            Spacer(minLength: 6)
            Link(destination: CramlessLink.session) {
                WidgetPrimaryLabel(title: "Start", systemImage: "play.fill")
            }
            .accessibilityLabel(Text("Start today's session, \(s.today.sessionMinutes) minutes"))
        }
    }

    private func done(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: style == .large ? 26 : 22, weight: .bold))
                    .foregroundStyle(CLColor.mint)
                    .widgetAccentable()
                Text("Done")
                    .font(WidgetFont.number(style == .large ? 36 : 30))
            }
            Text(doneLine(s))
                .font(WidgetFont.caption)
                .foregroundStyle(CLColor.ink2)
                .lineLimit(2)
                .padding(.top, 2)
                .padding(.trailing, textInset)
            Spacer(minLength: 6)
            if s.streak.current > 0 {
                HStack(spacing: 5) {
                    StreakFlame(stage: StreakStage(days: s.streak.current), size: 20)
                    Text("\(s.streak.current)-day streak")
                }
                .font(WidgetFont.captionEmphasis)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(Color.white.opacity(0.1), in: Capsule())
            }
        }
    }

    private func doneLine(_ s: WidgetSnapshot) -> String {
        let minutes = s.today.doneMinutes
        return minutes > 0 ? "\(minutes)\u{00A0}min today. See\u{00A0}you\u{00A0}tomorrow." : "See you tomorrow."
    }

    private func caughtUp(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("All caught up")
                .font(WidgetFont.number(style == .large ? 26 : 22, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Nothing is due right now. Add pages to study more.")
                .font(WidgetFont.caption)
                .foregroundStyle(CLColor.ink2)
                .lineLimit(2)
                .padding(.top, 2)
                .padding(.trailing, textInset)
            Spacer(minLength: 6)
            Link(destination: CramlessLink.scan) {
                WidgetPrimaryLabel(title: "Scan", systemImage: "doc.viewfinder")
            }
            .accessibilityLabel(Text("Scan pages"))
        }
    }
}

/// The next two exams beside the session: dot, title, days and readiness with a thin bar.
struct NextExamsColumn: View {
    var snapshot: WidgetSnapshot
    var date: Date
    var calendar: Calendar = .current

    var body: some View {
        let exams = Array(snapshot.exams.prefix(2))
        VStack(alignment: .leading, spacing: 9) {
            WidgetEyebrow(text: exams.count > 1 ? "Next exams" : "Next exam", color: CLColor.ink2)
            ForEach(exams) { exam in
                let days = snapshot.daysLeft(to: exam, from: date, calendar: calendar)
                Link(destination: CramlessLink.exam(exam.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(exam.color.fill).frame(width: 7, height: 7)
                            Text(exam.title)
                                .font(WidgetFont.captionEmphasis)
                                .foregroundStyle(CLColor.ink)
                                .lineLimit(1)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(WidgetCopy.days(days))
                                .font(WidgetFont.caption)
                                .foregroundStyle(days <= 2 ? CLColor.tangerineInk : CLColor.ink2)
                            Spacer(minLength: 2)
                            Text("\(WidgetCopy.percent(exam.readiness))%")
                                .font(WidgetFont.number(13, .bold))
                                .foregroundStyle(CLColor.readiness(exam.readiness))
                        }
                        WidgetBar(value: exam.readiness, tint: CLColor.readiness(exam.readiness),
                                  track: Color.white.opacity(0.12), height: 4)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(WidgetCopy.examAccessibility(exam, daysLeft: days)))
                }
            }
        }
    }
}

// MARK: - Large

/// The session card on top (with Cap), then as many of the next three exams as fit. One glance, one action.
struct TodayLargeView: View {
    var snapshot: WidgetSnapshot?
    var date: Date
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TodaySessionPanel(snapshot: snapshot, style: .large, textInset: 74)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 164)
                .background(alignment: .bottomTrailing) {
                    Image("Cap-study")
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .offset(x: 4, y: 8)
                        .accessibilityHidden(true)
                }
                .background(CLColor.night)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .environment(\.colorScheme, .dark)
            if let s = snapshot, !s.exams.isEmpty {
                ViewThatFits(in: .vertical) {
                    examList(s, limit: 3)
                    examList(s, limit: 2)
                    examList(s, limit: 1)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CLColor.skyInk)
                            .frame(width: 38, height: 38)
                            .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(snapshot == nil ? "Open Capling to set up" : "No exam yet")
                                .font(WidgetFont.bodyEmphasis)
                                .foregroundStyle(CLColor.ink)
                            Text("Add one and Capling tracks how ready you are, day by day.")
                                .font(WidgetFont.caption)
                                .foregroundStyle(CLColor.ink2)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if snapshot != nil {
                        Link(destination: CramlessLink.newExam) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Add an exam")
                                    .font(.system(.subheadline, weight: .semibold))
                            }
                            .foregroundStyle(CLColor.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(CLColor.surface3, in: Capsule())
                        }
                        .padding(.leading, 48)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func examList(_ s: WidgetSnapshot, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetEyebrow(text: s.exams.count > 1 ? "Upcoming exams" : "Next exam")
            VStack(spacing: 5) {
                ForEach(s.exams.prefix(limit)) { exam in
                    ExamListRow(exam: exam, days: s.daysLeft(to: exam, from: date, calendar: calendar))
                }
            }
        }
    }
}

/// One exam in the large widget: ring, title and change, days left.
struct ExamListRow: View {
    var exam: WidgetSnapshot.Exam
    var days: Int

    var body: some View {
        Link(destination: CramlessLink.exam(exam.id)) {
            HStack(spacing: 10) {
                WidgetReadinessRing(value: exam.readiness, size: 36, lineWidth: 4.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(exam.title)
                        .font(WidgetFont.bodyEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .lineLimit(1)
                    if WidgetCopy.delta(exam.delta) != nil {
                        WidgetDelta(delta: exam.delta, font: WidgetFont.caption)
                    } else {
                        Text(exam.courseName)
                            .font(WidgetFont.caption)
                            .foregroundStyle(CLColor.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(WidgetCopy.days(days))
                    .font(WidgetFont.number(15, .bold))
                    .foregroundStyle(days <= 2 ? CLColor.tangerineInk : CLColor.ink)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(WidgetCopy.examAccessibility(exam, daysLeft: days)))
        }
    }
}

// MARK: - Lock Screen

/// The Lock Screen glance from the plan: "(flame) CAPLING / 18 due / 15 min keeps your streak".
struct TodayGlanceView: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        let glance = WidgetCopy.todayGlance(snapshot)
        VStack(alignment: .leading, spacing: 0) {
            AccessoryEyebrow(text: "Capling", systemImage: (snapshot?.streak.current ?? 0) > 1 ? "flame" : "sun.max")
            Text(glance.headline)
                .font(WidgetFont.number(26))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Text(glance.detail)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
