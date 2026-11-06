import SwiftUI
import WidgetKit
import XCTest
@testable import Cramless

/// Draws every widget family, the Live Activities and the Siri snippet to PNGs in docs/shots/widgets/ (light and
/// dark) from sample snapshots, to be looked at. WidgetKit's own chrome (container backgrounds, margins, the
/// Dynamic Island, the Lock Screen's vibrancy) only exists inside the system, so these frames stand in for it:
/// the system's 16 pt margins and corner radius on a wallpaper, white-on-wallpaper for the Lock Screen, a black
/// pill for the island. Sizes are the 6.1-inch iPhone's (the tightest common one) plus the large phone's.
@MainActor
final class WidgetRenderTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 7, minute: 31))!
    private lazy var sample = WidgetSnapshot.sample(now: now, calendar: calendar)

    static let outputFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/shots/widgets", directoryHint: .isDirectory)

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: Self.outputFolder, withIntermediateDirectories: true)
    }

    // MARK: Scenarios

    private func day(_ offset: Int, hour: Int) -> Date {
        let d = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    /// The demo world: the Chem quiz in 2 days comes first.
    private var soon: WidgetSnapshot {
        var s = sample
        s.exams = [
            .init(id: UUID(), title: "Chem 110 Quiz", courseName: "Chem 110", color: .tangerine, date: day(2, hour: 10),
                  readiness: 0.41, delta: 0.09),
            .init(id: WidgetSnapshot.SampleID.bioMidterm, title: "Bio 101 Midterm", courseName: "Bio 101", color: .sky,
                  date: day(23, hour: 9), readiness: 0.64, delta: 0.05),
            .init(id: WidgetSnapshot.SampleID.psychExam, title: "AP Psych Exam", courseName: "AP Psychology",
                  color: .mint, date: day(196, hour: 8), readiness: 0.22, delta: 0),
        ]
        return s
    }

    private var done: WidgetSnapshot {
        var s = sample
        s.streak.studiedToday = true
        s.streak.current = 13
        s.today.doneMinutes = 16
        return s
    }

    private var caughtUp: WidgetSnapshot {
        var s = sample
        s.today = .init(goalMinutes: 15, doneMinutes: 0, plannedMinutes: 0, reviews: 0, newItems: 0, weakSpots: 0,
                        ready: false)
        return s
    }

    private var noExams: WidgetSnapshot {
        var s = sample
        s.exams = []
        s.streak.current = 0
        return s
    }

    private var longTitles: WidgetSnapshot {
        var s = sample
        s.exams[0].title = "Organic Chemistry II Cumulative Final"
        s.exams[0].courseName = "Organic Chemistry II"
        s.exams[0].date = day(196, hour: 9)
        s.exams[1].title = "Introduction to Macroeconomics Midterm"
        s.today.reviews = 128
        s.today.newItems = 40
        s.today.weakSpots = 12
        s.today.plannedMinutes = 120
        s.streak.current = 365
        return s
    }

    // MARK: Home Screen

    func testHomeScreenWidgets() throws {
        for scheme in [ColorScheme.light, .dark] {
            for (size, label) in [(Size.small158, ""), (Size.small170, "-large-phone")] {
                try render(home(ExamWidgetView(family: .systemSmall, snapshot: sample, date: now), size, .surface),
                           "exam-small\(label)", scheme)
            }
            try render(home(ExamWidgetView(family: .systemSmall, snapshot: soon, date: now), Size.small158, .surface),
                       "exam-small-soon", scheme)
            try render(home(ExamWidgetView(family: .systemSmall, snapshot: longTitles, date: now), Size.small158, .surface),
                       "exam-small-long", scheme)
            try render(home(ExamWidgetView(family: .systemSmall, snapshot: noExams, date: now), Size.small158, .surface),
                       "exam-small-no-exam", scheme)
            try render(home(ExamWidgetView(family: .systemSmall, snapshot: nil, date: now), Size.small158, .surface),
                       "exam-small-no-data", scheme)

            for (size, label) in [(Size.medium158, ""), (Size.medium170, "-large-phone")] {
                try render(home(TodayWidgetView(family: .systemMedium, snapshot: soon, date: now), size, .night),
                           "today-medium\(label)", scheme)
            }
            try render(home(TodayWidgetView(family: .systemMedium, snapshot: done, date: now), Size.medium158, .night),
                       "today-medium-done", scheme)
            try render(home(TodayWidgetView(family: .systemMedium, snapshot: caughtUp, date: now), Size.medium158, .night),
                       "today-medium-caught-up", scheme)
            try render(home(TodayWidgetView(family: .systemMedium, snapshot: noExams, date: now), Size.medium158, .night),
                       "today-medium-no-exam", scheme)
            try render(home(TodayWidgetView(family: .systemMedium, snapshot: longTitles, date: now), Size.medium158, .night),
                       "today-medium-long", scheme)
            try render(home(TodayWidgetView(family: .systemMedium, snapshot: nil, date: now), Size.medium158, .night),
                       "today-medium-no-data", scheme)

            for (size, label) in [(Size.large158, ""), (Size.large170, "-large-phone")] {
                try render(home(TodayWidgetView(family: .systemLarge, snapshot: soon, date: now), size, .surface),
                           "today-large\(label)", scheme)
            }
            try render(home(TodayWidgetView(family: .systemLarge, snapshot: done, date: now), Size.large158, .surface),
                       "today-large-done", scheme)
            try render(home(TodayWidgetView(family: .systemLarge, snapshot: noExams, date: now), Size.large158, .surface),
                       "today-large-no-exam", scheme)
        }
    }

    /// The person's biggest text size: each widget caps Dynamic Type at the size its layout holds.
    func testHomeScreenWidgetsAtLargestText() throws {
        try render(home(ExamWidgetView(family: .systemSmall, snapshot: sample, date: now), Size.small158, .surface)
                    .dynamicTypeSize(.accessibility3), "exam-small-ax3", .light)
        try render(home(TodayWidgetView(family: .systemMedium, snapshot: soon, date: now), Size.medium158, .night)
                    .dynamicTypeSize(.accessibility3), "today-medium-ax3", .light)
        try render(home(TodayWidgetView(family: .systemLarge, snapshot: soon, date: now), Size.large158, .surface)
                    .dynamicTypeSize(.accessibility3), "today-large-ax3", .light)
    }

    // MARK: Lock Screen

    func testLockScreenWidgets() throws {
        for (snapshot, label) in [(Optional(soon), ""), (Optional(done), "-done"), (Optional(noExams), "-no-exam"),
                                  (nil, "-no-data"), (Optional(longTitles), "-long")] {
            try render(LockScreenMock(snapshot: snapshot, date: now), "lock-screen\(label)", .dark)
        }
        for scheme in [ColorScheme.light, .dark] {
            try render(accessory(ExamCircularView(snapshot: soon, date: now), Size.circular), "exam-circular", scheme)
            try render(accessory(ExamRectangularView(snapshot: sample, date: now), Size.rectangular),
                       "exam-rectangular", scheme)
            try render(accessory(TodayGlanceView(snapshot: sample), Size.rectangular), "today-rectangular", scheme)
            try render(accessory(StreakCircularView(snapshot: sample), Size.circular), "streak-circular", scheme)
            try render(accessory(StreakInlineView(snapshot: sample).font(.system(size: 15, weight: .semibold)),
                                 Size.inline), "streak-inline", scheme)
        }
    }

    // MARK: Live Activities

    func testLiveActivities() throws {
        let started = Date().addingTimeInterval(-252)
        let attributes = StudySessionAttributes(title: "Today's session", total: 18, startedAt: started, plannedMinutes: 15)
        let exam = ExamWeekAttributes.sample(now: now, calendar: calendar)
        var tomorrow = ExamWeekAttributes.ContentState.sample
        tomorrow.daysLeft = 1
        tomorrow.readiness = 0.83
        tomorrow.delta = 0.12
        for scheme in [ColorScheme.light, .dark] {
            try render(activityBanner(SessionActivityView(attributes: attributes, state: .sample)), "session-lock", scheme)
            try render(activityBanner(SessionActivityView(attributes: attributes, state: .sample, isStale: true)),
                       "session-lock-paused", scheme)
            try render(activityBanner(SessionActivityView(attributes: attributes, state: .sampleFinished)),
                       "session-lock-done", scheme)
            let outLoud = StudySessionAttributes.sampleOutLoud(now: started)
            try render(activityBanner(SessionActivityView(attributes: outLoud, state: .sampleOutLoud)), "session-lock-outloud", scheme)
            var asking = StudySessionAttributes.ContentState.sampleOutLoud
            asking.voice = .asking
            try render(activityBanner(SessionActivityView(attributes: outLoud, state: asking)), "session-lock-outloud-asking", scheme)
            try render(activityBanner(OutLoudExpandedBottom(state: .sampleOutLoud)), "session-island-outloud", scheme)
            try render(activityBanner(ExamWeekActivityView(attributes: exam, state: .sample)), "exam-week-lock", scheme)
            try render(activityBanner(ExamWeekActivityView(attributes: exam, state: tomorrow)), "exam-week-lock-tomorrow", scheme)
            try render(activityBanner(ExamWeekActivityView(attributes: exam, state: .sample, isStale: true)),
                       "exam-week-lock-stale", scheme)

            let progress = StudySessionAttributes.ContentState.sample.progress(total: attributes.total)
            try render(IslandCompact(leading: SessionCompactRing(progress: progress),
                                     trailing: SessionCompactCount(attributes: attributes, state: .sample)),
                       "session-island-compact", scheme)
            try render(IslandMinimal(content: SessionCompactRing(progress: progress)), "session-island-minimal", scheme)
            try render(IslandExpanded(
                leading: WidgetCapFace(size: 40),
                trailing: SessionClock(attributes: attributes, state: .sample, isStale: false)
                    .font(WidgetFont.number(17, .semibold)).foregroundStyle(.white),
                center: SessionExpandedCenter(attributes: attributes, state: .sample),
                bottom: SessionExpandedBottom(attributes: attributes, state: .sample)), "session-island-expanded", scheme)

            try render(IslandCompact(leading: ExamWeekCompactRing(readiness: 0.64),
                                     trailing: ExamWeekCompactDays(state: .sample)), "exam-week-island-compact", scheme)
            try render(IslandMinimal(content: ExamWeekCompactRing(readiness: 0.64)), "exam-week-island-minimal", scheme)
            try render(IslandExpanded(
                leading: WidgetReadinessRing(value: 0.64, size: 44, lineWidth: 5, track: ActivityLook.track,
                                             labelColor: .white),
                trailing: Text("6 days").font(WidgetFont.number(17, .bold)).foregroundStyle(.white),
                center: Text(exam.title).font(.system(.subheadline, weight: .semibold)).foregroundStyle(.white),
                bottom: Text(ExamWeekCopy.today(state: .sample, courseName: exam.courseName))
                    .font(.system(.caption, weight: .medium)).foregroundStyle(ActivityLook.secondaryText)),
                       "exam-week-island-expanded", scheme)
        }
    }

    // MARK: Siri

    func testSiriSnippet() throws {
        for scheme in [ColorScheme.light, .dark] {
            try render(ReadinessSnippet(snapshot: soon, now: now, calendar: calendar)
                        .frame(width: 360)
                        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(16)
                        .background(CLColor.background), "siri-how-ready", scheme)
        }
    }

    // MARK: Frames

    enum Size {
        static let small158 = CGSize(width: 158, height: 158)
        static let small170 = CGSize(width: 170, height: 170)
        static let medium158 = CGSize(width: 338, height: 158)
        static let medium170 = CGSize(width: 364, height: 170)
        static let large158 = CGSize(width: 338, height: 354)
        static let large170 = CGSize(width: 364, height: 382)
        static let circular = CGSize(width: 72, height: 72)
        static let rectangular = CGSize(width: 160, height: 72)
        static let inline = CGSize(width: 240, height: 26)
    }

    private func home<V: View>(_ content: V, _ size: CGSize, _ background: WidgetBackground) -> some View {
        content
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(background.color)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(20)
            .background(HomeWallpaper())
    }

    private func accessory<V: View>(_ content: V, _ size: CGSize) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .environment(\.widgetRenderingMode, .vibrant)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .padding(16)
            .background(LockWallpaper())
    }

    private func activityBanner<V: View>(_ content: V) -> some View {
        content
            .frame(width: 361)
            .background(ActivityLook.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(16)
            .background(LockWallpaper())
    }

    private func render<V: View>(_ view: V, _ name: String, _ scheme: ColorScheme) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, name)
        let data = try XCTUnwrap(image.pngData(), name)
        let suffix = scheme == .dark ? "dark" : "light"
        try data.write(to: Self.outputFolder.appending(path: "\(name)-\(suffix).png"))
    }
}

// MARK: - Stand-ins for the system's chrome

private struct HomeWallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: scheme == .dark ? [Color(hex: 0x0B1220), Color(hex: 0x23304A)]
                       : [Color(hex: 0xBFE3FF), Color(hex: 0xFFE2C6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The prototype's Lock Screen wallpaper: sky blue into peach.
private struct LockWallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x3A78B8), Color(hex: 0x7CC8FF), Color(hex: 0xF5B38A)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// A Lock Screen with every accessory widget and a session Live Activity, like the prototype's screen.
private struct LockScreenMock: View {
    var snapshot: WidgetSnapshot?
    var date: Date

    var body: some View {
        VStack(spacing: 0) {
            Label {
                Text(WidgetCopy.inline(snapshot))
            } icon: {
                Image(systemName: (snapshot?.streak.current ?? 0) > 0 ? "flame" : "sun.max")
            }
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
            .frame(width: 300)
            .padding(.top, 70)
            Text("7:31")
                .font(.system(size: 96, weight: .semibold, design: .rounded))
            HStack(spacing: 12) {
                ExamCircularView(snapshot: snapshot, date: date).frame(width: 72, height: 72)
                StreakCircularView(snapshot: snapshot).frame(width: 72, height: 72)
                ExamRectangularView(snapshot: snapshot, date: date).frame(width: 160, height: 72)
            }
            .padding(.top, 8)
            HStack(spacing: 12) {
                TodayGlanceView(snapshot: snapshot).frame(width: 160, height: 72)
                ExamRectangularView(snapshot: snapshot, date: date).frame(width: 160, height: 72)
            }
            .padding(.top, 12)
            Spacer(minLength: 40)
            SessionActivityView(attributes: StudySessionAttributes(title: "Today's session", total: 18,
                                                                   startedAt: Date().addingTimeInterval(-252),
                                                                   plannedMinutes: 15),
                                state: .sample)
                .background(ActivityLook.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .foregroundStyle(.white)
        .environment(\.widgetRenderingMode, .vibrant)
        .environment(\.colorScheme, .dark)
        .frame(width: 393, height: 760)
        .background(LockWallpaper())
    }
}

private struct IslandCompact<L: View, T: View>: View {
    var leading: L
    var trailing: T

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: 44)
            Spacer(minLength: 126)
            trailing.frame(minWidth: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 37)
        .background(Color.black, in: Capsule())
        .padding(20)
        .background(LockWallpaper())
    }
}

private struct IslandMinimal<C: View>: View {
    var content: C

    var body: some View {
        content
            .frame(width: 37, height: 37)
            .background(Color.black, in: Circle())
            .padding(20)
            .background(LockWallpaper())
    }
}

private struct IslandExpanded<L: View, T: View, C: View, B: View>: View {
    var leading: L
    var trailing: T
    var center: C
    var bottom: B

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                leading
                Spacer(minLength: 8)
                center
                Spacer(minLength: 8)
                trailing
            }
            bottom
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: 371)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .padding(20)
        .background(LockWallpaper())
    }
}
