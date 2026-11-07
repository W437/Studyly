import SwiftUI

/// The Progress tab, about a screen and a third: this week and the streak (a tap opens the month), the exams as rows (readiness is the one
/// percentage; no letter here), the topics with questions fading, each with Practice, mix-ups, and two tiles: badges and the memory sky.
/// Everything is read from the engine once per change of the store (`ProgressModel`).
///
/// Harness: `CRAMLESS_SCENARIO=missed|repair|bright|streak:<n>` puts the week in that state first, `CRAMLESS_SEED=0` is a person with nothing
/// yet (`AppModel.applyHarnessScenario`); `CRAMLESS_SCROLL=week|exams|fading|mixups|more`.
struct ProgressTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        let model = ProgressModel(app: app)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WeekCard(model: model)
                    .padding(.top, 8)
                    .id("week")
                ExamsSection(exams: model.exams).id("exams")
                FadingSection(model: model).id("fading")
                ConfusionsSection(confusions: model.confusions).id("mixups")
                MoreTiles(model: model)
                    .padding(.top, 26)
                    .id("more")
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
        .harnessScroll(proxy)
        }
        .clScreenBackground()
        .captureDebugCanvas()
        .navigationTitle("Progress")
        #if DEBUG
        .task { app.applyHarnessScenarioOnce(examID: nil) }
        #endif
    }
}

/// What the Progress tab shows, read once.
struct ProgressModel {
    struct ExamLine: Identifiable {
        var id: UUID
        var title: String
        var date: Date
        var days: Int
        var readiness: Double
        var delta: Double
        var history: [ReadinessPoint]
    }

    /// A topic with questions fading, as its constellation.
    struct FadingLine: Identifiable {
        var topic: ProgressPresentation.TopicLight
        var glyph: SkyGlyph?
        var id: UUID { topic.id }
    }

    struct ConfusionLine: Identifiable {
        var id: UUID
        var name: String
        var courseName: String
        var misses: Int
        /// How many questions it's about: one is a quick look, not a fix.
        var questions = 2
    }

    var calendar: Calendar
    var now: Date
    var exams: [ExamLine]
    var streak: StreakState
    var week: WeeklyStats
    var lastWeek: [Int]
    var sky: SkyScene
    var fading: [FadingLine]
    var confusions: [ConfusionLine]
    var badges: [BadgeStatus]
    var dailyMinutes: Int
    /// The run a repair today would join back up.
    var runBeforeRepair: Int

    /// A missed day can still be repaired: the run waits rather than reading as zero.
    var isOnHold: Bool { streak.current == 0 && streak.repairableDay != nil && runBeforeRepair > 0 }
    /// Anything studied yet.
    var hasStudied: Bool { sky.starCount > sky.hollowCount }

    @MainActor
    init(app: AppModel) {
        calendar = app.calendar
        now = app.now
        let sky = app.skyScene(aspect: 1)
        self.sky = sky
        exams = app.upcomingExams().filter { $0.course?.deletedAt == nil }.map { exam in
            let r = app.readiness(for: exam)
            return ExamLine(id: exam.id, title: exam.title, date: exam.date, days: r.daysLeft, readiness: r.value,
                            delta: r.deltaThisWeek, history: app.readinessHistory(for: exam, days: 14))
        }
        let streak = app.streak()
        let cells = app.heatmap(weeks: 12)
        let week = app.weeklyStats()
        self.streak = streak
        self.week = week
        lastWeek = ProgressPresentation.lastWeekMinutes(cells: cells, week: week, calendar: app.calendar)
        var courses: [UUID: Course] = [:]
        for course in app.courses { courses[course.id] = course }
        let daysToExam = ProgressPresentation.daysToNearestExam(regions: sky.layout.regions, examDates: sky.examDates, now: app.now,
                                                                calendar: app.calendar)
        let light = sky.light
        let topics = sky.layout.constellations.enumerated().compactMap { index, c -> ProgressPresentation.TopicLight? in
            guard let topicID = c.topicID, let course = courses[c.courseID] else { return nil }
            return ProgressPresentation.TopicLight(id: topicID, name: c.name, courseID: course.id, courseName: course.name,
                                                   color: course.color, index: index, dimCount: light.dimCount(c),
                                                   examDays: daysToExam[index])
        }
        fading = ProgressPresentation.fading(topics, count: 3).map { FadingLine(topic: $0, glyph: sky.glyph(of: $0.index)) }
        confusions = app.courses.flatMap { course in
            course.confusions.filter { $0.deletedAt == nil && $0.status == .open }
                .sorted { $0.lastSeenAt > $1.lastSeenAt }
                .map { ConfusionLine(id: $0.id, name: $0.name, courseName: course.name, misses: $0.missCount, questions: $0.itemIDs.count) }
        }
        badges = app.badgeStatuses()
        dailyMinutes = app.settings.dailyMinutes
        runBeforeRepair = streak.repairableDay.map { ProgressPresentation.runBefore($0, cells: cells, calendar: app.calendar) } ?? 0
    }
}

// MARK: - This week and the streak

/// "This week", the flame and the run, the minutes against last week and the week's chart. All of it one tap: the month. A repair offer
/// sits under it, outside that tap.
private struct WeekCard: View {
    let model: ProgressModel
    @Environment(AppModel.self) private var app

    var body: some View {
        let week = model.week
        let last = week.previousWeekMinutes
        VStack(alignment: .leading, spacing: 14) {
            Button {
                CLHaptics.tap()
                app.router.present(.streakMonth)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("This week").clFont(.title3).foregroundStyle(CLColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        HStack(spacing: 3) {
                            Text("The month").clFont(.subheadlineEmphasis)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(CLColor.skyInk)
                    }
                    if !app.settings.quietMode { streakLine }
                    ReflowStack(verticalAlignment: .firstTextBaseline, spacing: 10) {
                        Text(CLFormat.minutes(week.totalMinutes))
                            .clFont(.number(30))
                            .foregroundStyle(CLColor.ink)
                            .lineLimit(1)
                            .fixedSize()
                        if week.activeDays > 0 {
                            Text("\(week.activeDays) days studied")
                                .clFont(.subheadline)
                                .foregroundStyle(CLColor.ink2)
                        }
                    }
                    // Two empty weeks have nothing to compare.
                    if week.totalMinutes > 0 || last > 0 {
                        ReflowPill(text: .verbatim(ProgressPresentation.weekComparison(this: week.totalMinutes, last: last)),
                                   tone: week.totalMinutes > last ? .mint : .neutral,
                                   systemImage: week.totalMinutes > last ? "arrow.up.right" : nil)
                    }
                    WeekMinutesChart(week: week, lastWeek: model.lastWeek, calendar: model.calendar, plotHeight: 80)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the month"))
            if let day = model.streak.repairableDay, !app.settings.quietMode {
                Rectangle().fill(CLColor.hairline).frame(height: 1)
                RepairOffer(day: day, run: model.runBeforeRepair, dailyMinutes: model.dailyMinutes, calendar: model.calendar)
            }
        }
        .clCard()
    }

    @ViewBuilder
    private var streakLine: some View {
        let days = model.isOnHold ? model.runBeforeRepair : model.streak.current
        HStack(alignment: .center, spacing: 8) {
            StreakFlame(stage: StreakStage(days: days), size: 26, lit: !model.isOnHold)
            if days > 0 {
                Text("\(days)-day streak").clFont(.headline).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Start a streak today.").clFont(.headline).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isOnHold {
                ReflowPill(text: "On hold", tone: .sun, systemImage: "pause.fill")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "1 freeze saved · Thu, Oct 16 was covered by a freeze." and today's nudge.
struct StreakNotes: View {
    let streak: StreakState
    let calendar: Calendar
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(freezesLine).clFont(.subheadline).foregroundStyle(CLColor.ink2)
            } icon: {
                Image(systemName: "snowflake").foregroundStyle(CLColor.skyInk)
            }
            if !streak.studiedToday, streak.repairableDay == nil {
                Label {
                    Text(streak.current > 0 ? "Study today to make it \(streak.current + 1)." : "Study today to start a new streak.")
                        .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                } icon: {
                    Image(systemName: "sun.max").foregroundStyle(CLColor.tangerineInk)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var freezesLine: String {
        let held = streak.freezesAvailable == 0 ? "No freezes saved" : "\(CLFormat.count(streak.freezesAvailable, "freeze")) saved"
        if let frozen = streak.frozenDays.first, calendar.dayDistance(from: frozen, to: now) <= 14 {
            return "\(held) · \(CLFormat.day(frozen, calendar: calendar)) was covered by a freeze"
        }
        return held
    }
}

/// A missed day that a double session today would repair.
struct RepairOffer: View {
    let day: Date
    let run: Int
    let dailyMinutes: Int
    let calendar: Calendar
    @Environment(AppModel.self) private var app

    var body: some View {
        let weekday = day.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide))
        HStack(alignment: .top, spacing: 12) {
            CapFace(size: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text("Missed \(weekday)? You can repair it.").clFont(.headline).foregroundStyle(CLColor.ink)
                Text(run > 0
                     ? "Study \(CLFormat.minutes(dailyMinutes * 2)) today, twice your goal, and your \(run)-day streak carries on."
                     : "Study \(CLFormat.minutes(dailyMinutes * 2)) today, twice your goal, and \(weekday) counts again.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    app.router.present(.session(SessionRequest(kind: .daily, minutes: dailyMinutes * 2)))
                } label: {
                    Label("Start a \(CLFormat.minutes(dailyMinutes * 2)) session", systemImage: "play.fill")
                }
                .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Exams

private struct ExamsSection: View {
    let exams: [ProgressModel.ExamLine]
    @Environment(AppModel.self) private var app

    var body: some View {
        CLSectionHeader(title: "Exams")
        if exams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No exams coming up").clFont(.headline).foregroundStyle(CLColor.ink)
                Text("Add one and Capling plans backwards from its date, and shows how ready you are, day by day.")
                    .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add a date") { app.router.present(.newExam(courseID: nil)) }
                    .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
            }
            .clCard()
        } else {
            CLList {
                ForEach(exams) { exam in
                    NavigationLink(value: Route.exam(exam.id)) {
                        ExamRow(exam: exam)
                    }
                    .buttonStyle(LibraryRowButtonStyle())
                }
            }
        }
    }
}

/// One exam: its ring, its name, when and how the week went, and a sparkline of the last two weeks.
private struct ExamRow: View {
    let exam: ProgressModel.ExamLine

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            ReadinessRing(value: exam.readiness, size: typeSize.isAccessibilitySize ? 64 : 44, lineWidth: typeSize.isAccessibilitySize ? 7 : 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: exam.title)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: ProgressPresentation.examLine(days: exam.days, delta: exam.delta))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(exam.days <= 3 ? CLColor.roseInk : CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
                ReadinessSparkline(points: exam.history)
                    .frame(width: 64, height: 26)
                    .accessibilityHidden(true)
            }
            CLChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: exam.title))
        .accessibilityValue(Text(verbatim: "\(CLFormat.percent(exam.readiness)) ready, " + ProgressPresentation.examLine(days: exam.days, delta: exam.delta)))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Fading

/// Topics with questions under the sky's dim line, for the nearest exam first: its shape, its course and how many, and Practice.
private struct FadingSection: View {
    let model: ProgressModel
    @Environment(AppModel.self) private var app

    var body: some View {
        if model.hasStudied {
            CLSectionHeader(title: "Fading")
            if model.fading.isEmpty {
                Text("Nothing is fading right now.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clCard(padding: 16)
            } else {
                CLList {
                    ForEach(model.fading) { line in
                        Button { relight(line) } label: {
                            FadingRow(line: line)
                        }
                        .buttonStyle(LibraryRowButtonStyle())
                        .accessibilityHint(Text("Practises this topic"))
                    }
                }
            }
        }
    }

    private func relight(_ line: ProgressModel.FadingLine) {
        CLHaptics.tap()
        let index = line.topic.index
        if model.sky.layout.constellations.indices.contains(index) {
            app.router.present(.session(app.relightRequest(model.sky.layout.constellations[index], in: model.sky)))
        } else {
            app.router.present(.session(SessionRequest(kind: .practice, courseID: line.topic.courseID, topicID: line.topic.id)))
        }
    }
}

private struct FadingRow: View {
    let line: ProgressModel.FadingLine

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let topic = line.topic
        // At accessibility sizes Practice goes under the words: beside them, the name breaks mid-word.
        ReflowStack(verticalAlignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                if let glyph = line.glyph, !typeSize.isAccessibilitySize { SkyGlyphView(glyph: glyph, size: 46) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: topic.name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(topic.courseName) · \(ProgressPresentation.fadingLine(topic.dimCount))")
                        .clFont(.footnote).foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Practice")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.tangerineInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(CLColor.tangerineSoft, in: Capsule())
                .fixedSize()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mix-ups

private struct ConfusionsSection: View {
    let confusions: [ProgressModel.ConfusionLine]

    var body: some View {
        if !confusions.isEmpty {
            CLSectionHeader(title: "Mix-ups")
            CLList {
                ForEach(confusions) { confusion in
                    NavigationLink(value: Route.confusion(confusion.id)) {
                        HStack(spacing: 12) {
                            CapFace(size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(confusion.name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                                Text(confusion.questions == 1 ? "Missed \(CLFormat.count(confusion.misses, "time")) · \(confusion.courseName) · a quick look"
                                    : "Missed \(CLFormat.count(confusion.misses, "time")) · \(confusion.courseName) · a 2-minute fix")
                                    .clFont(.footnote).foregroundStyle(CLColor.ink2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            CLChevron()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LibraryRowButtonStyle())
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Badges and the sky

/// Two tiles side by side (stacked at the accessibility text sizes): the badges and the memory sky, each opening its own screen.
private struct MoreTiles: View {
    let model: ProgressModel
    @Environment(AppModel.self) private var app

    var body: some View {
        ReflowStack(verticalAlignment: .top, spacing: 12) {
            if !app.settings.quietMode { badges }
            NavigationLink(value: Route.sky) {
                tile(title: "Memory sky", line: .verbatim(ProgressPresentation.skyLine(stars: model.sky.starCount, dim: model.sky.dimCount))) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 40, height: 40)
                        .background(CLColor.night, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.pressable)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var badges: some View {
        NavigationLink(value: Route.badges) {
            tile(title: "Badges", line: BadgeCopy.count(earned: model.badges.filter(\.isEarned).count, of: model.badges.count)) {
                HStack(spacing: -6) {
                    ForEach(model.badges.featured(limit: 3)) { status in
                        BadgeMedal(badge: status.badge, earned: status.isEarned, size: 40)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(.pressable)
    }

    private func tile<Art: View>(title: LocalizedStringResource, line: LocalizedStringResource, @ViewBuilder art: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            art()
            Text(title).clFont(.headline).foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(line).clFont(.footnote).foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}
