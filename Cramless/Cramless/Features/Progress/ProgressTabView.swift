import SwiftUI

/// The Progress tab: readiness per upcoming exam with its last two weeks (the only percentage here; a projected letter only once
/// logged grades calibrate it), the streak with twelve weeks of studying, this week against last, what's due, the topics with
/// questions fading and the brightest, and open mix-ups. Everything is read from the engine once per change of the store
/// (`ProgressModel`).
///
/// Harness: `CRAMLESS_SCENARIO=missed|repair` puts yesterday in that state first, `calibrated` logs two past Chem grades
/// (`AppModel.applyHarnessScenario`); `CRAMLESS_SCROLL=streak|week|memory|topics`.
struct ProgressTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        let model = ProgressModel(app: app)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ExamsSection(exams: model.exams, calendar: model.calendar).padding(.top, 8)
                StreakSection(model: model).id("streak")
                BadgesSection(badges: model.badges).id("badges")
                WeekSection(model: model).id("week")
                MemorySection(due: model.due, calendar: model.calendar)
                    .id("memory")
                ConstellationsSection(sky: model.sky, brightest: model.brightest, fading: model.fading).id("topics")
                ConfusionsSection(confusions: model.confusions)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
        .harnessScroll(proxy)
        }
        .clScreenBackground()
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
        /// The projected grade, only once logged grades calibrate it (`ProjectedGrade.isCalibrated`); nil before.
        var grade: ProjectedGrade?
        var history: [ReadinessPoint]
        /// The exam's region of the sky, cut out for its card (nil when nothing in its scope has been studied).
        var region: SkyScene?
    }

    /// A topic as a constellation: its counts from the sky and its glyph.
    struct ConstellationLine: Identifiable {
        var topic: ProgressPresentation.TopicLight
        var glyph: SkyGlyph?
        var id: UUID { topic.id }
    }

    struct ConfusionLine: Identifiable {
        var id: UUID
        var name: String
        var courseName: String
        var misses: Int
    }

    var calendar: Calendar
    var now: Date
    var exams: [ExamLine]
    var streak: StreakState
    var cells: [HeatmapCell]
    var week: WeeklyStats
    var lastWeek: [Int]
    var due: [DueForecastDay]
    var sky: SkyScene
    var brightest: [ConstellationLine]
    var fading: [ConstellationLine]
    var confusions: [ConfusionLine]
    var badges: [BadgeStatus]
    var dailyMinutes: Int
    /// The run a repair today would join back up.
    var runBeforeRepair: Int

    @MainActor
    init(app: AppModel) {
        calendar = app.calendar
        now = app.now
        // Laid out as a square: an exam's region is the same wherever the sky is drawn.
        let sky = app.skyScene(aspect: 1)
        self.sky = sky
        exams = app.upcomingExams().filter { $0.course?.deletedAt == nil }.map { exam in
            let r = app.readiness(for: exam)
            return ExamLine(id: exam.id, title: exam.title, date: exam.date, days: r.daysLeft, readiness: r.value,
                            delta: r.deltaThisWeek, grade: ExamPresentation.shownGrade(r.projectedGrade),
                            history: app.readinessHistory(for: exam, days: 14), region: sky.region(of: exam.id))
        }
        let streak = app.streak()
        let cells = app.heatmap(weeks: 12)
        let week = app.weeklyStats()
        self.streak = streak
        self.cells = cells
        self.week = week
        lastWeek = ProgressPresentation.lastWeekMinutes(cells: cells, week: week, calendar: app.calendar)
        due = app.dueForecast(days: 7)
        // Each topic's readiness for its course's next exam (only topics on that exam have one): what orders the fading list.
        var readiness: [UUID: Double] = [:]
        var courses: [UUID: Course] = [:]
        for course in app.courses {
            courses[course.id] = course
            guard let exam = app.nextExam(of: course.id) else { continue }
            for topic in app.topicReadiness(for: exam) { if let v = topic.value { readiness[topic.id] = v } }
        }
        let light = sky.light
        let topics = sky.layout.constellations.enumerated().compactMap { index, c -> ProgressPresentation.TopicLight? in
            guard let topicID = c.topicID, let course = courses[c.courseID] else { return nil }
            let lit = c.stars.filter { !light.hollow[$0] }.count
            return ProgressPresentation.TopicLight(id: topicID, name: c.name, courseID: course.id, courseName: course.name,
                                                   color: course.color, index: index, dimCount: light.dimCount(c),
                                                   brightCount: light.brightCount(c), litCount: lit,
                                                   meanRecall: light.meanRecall(c), readiness: readiness[topicID])
        }
        func line(_ topic: ProgressPresentation.TopicLight) -> ConstellationLine {
            ConstellationLine(topic: topic, glyph: sky.glyph(of: topic.index))
        }
        let fadingTopics = ProgressPresentation.fading(topics, count: 3)
        fading = fadingTopics.map(line)
        brightest = ProgressPresentation.brightest(topics, excluding: Set(fadingTopics.map(\.id)), count: 3).map(line)
        confusions = app.courses.flatMap { course in
            course.confusions.filter { $0.deletedAt == nil && $0.status == .open }
                .sorted { $0.lastSeenAt > $1.lastSeenAt }
                .map { ConfusionLine(id: $0.id, name: $0.name, courseName: course.name, misses: $0.missCount) }
        }
        badges = app.badgeStatuses()
        dailyMinutes = app.settings.dailyMinutes
        runBeforeRepair = streak.repairableDay.map { ProgressPresentation.runBefore($0, cells: cells, calendar: app.calendar) } ?? 0
    }
}

// MARK: - Sections

private struct ExamsSection: View {
    let exams: [ProgressModel.ExamLine]
    let calendar: Calendar
    @Environment(AppModel.self) private var app

    var body: some View {
        CLSectionHeader(title: "Exams")
        if exams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No exams coming up").clFont(.headline).foregroundStyle(CLColor.ink)
                Text("Add one and Capling plans backwards from its date, and shows how ready you are, day by day.")
                    .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("New exam") { app.router.present(.newExam(courseID: nil)) }
                    .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
            }
            .clCard()
        } else {
            VStack(spacing: 12) {
                ForEach(exams) { exam in
                    NavigationLink(value: Route.exam(exam.id)) {
                        ExamReadinessCard(exam: exam, calendar: calendar)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }
}

/// One exam: readiness now with its change this week and a sparkline of the last two weeks. A projected letter only once logged
/// grades calibrate it ("Projected B+ from your grades").
private struct ExamReadinessCard: View {
    let exam: ProgressModel.ExamLine
    let calendar: Calendar

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exam.title).clFont(.headline).foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(LibraryFormat.shortDate(exam.date, calendar: calendar)) · \(exam.days == 1 ? "tomorrow" : exam.days == 0 ? "today" : "\(exam.days) days")")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(exam.days <= 3 ? CLColor.roseInk : CLColor.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Its stars, lit or fading: the readiness number below, as a picture. Left out at the big text sizes.
                if let region = exam.region, !typeSize.isAccessibilitySize {
                    SkyRegionStill(scene: region, cornerRadius: 15).frame(width: 50, height: 50)
                }
                CLChevron()
            }
            ReflowStack(verticalAlignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int((exam.readiness * 100).rounded()))")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(CLColor.ink)
                        Text("%").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(CLColor.ink2)
                        Text("ready").clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink2).padding(.leading, 6)
                    }
                    ReflowPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: exam.delta > 0.004 ? .mint : .neutral,
                               systemImage: exam.delta > 0.004 ? "arrow.up.right" : nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ReadinessSparkline(points: exam.history)
                    .frame(width: 110, height: 44)
            }
            if let grade = exam.grade {
                Rectangle().fill(CLColor.hairline).frame(height: 1)
                Text(ExamPresentation.calibratedGradeLine(grade))
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(exam.title))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        var text = "\(CLFormat.percent(exam.readiness)) ready, \(CLFormat.delta(exam.delta)) this week. \(LibraryFormat.countdown(days: exam.days))."
        if let grade = exam.grade { text += " \(ExamPresentation.calibratedGradeLine(grade))." }
        return text
    }
}

/// A row of badges: the latest earned, then the ones that are close. "See all" opens every badge; a tap opens one.
private struct BadgesSection: View {
    let badges: [BadgeStatus]
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let earned = badges.filter(\.isEarned).count
        CLSectionHeader(title: "Badges", actionTitle: "See all") { app.router.push(.badges) }
        let shown = badges.featured(limit: typeSize.isAccessibilitySize ? 2 : 4)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(shown) { status in
                    Button {
                        CLHaptics.tap()
                        app.router.present(.badge(status.badge))
                    } label: {
                        BadgeCell(status: status, calendar: app.calendar, medalSize: 64, showsDetail: false)
                    }
                    .buttonStyle(.pressable)
                }
            }
            Text(BadgeCopy.count(earned: earned, of: badges.count))
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
        }
        .clCard()
    }
}

private struct StreakSection: View {
    let model: ProgressModel
    @Environment(AppModel.self) private var app

    /// A missed day can still be repaired: the run waits rather than reading as zero.
    private var onHold: Bool { model.streak.current == 0 && model.streak.repairableDay != nil && model.runBeforeRepair > 0 }

    var body: some View {
        let streak = model.streak
        CLSectionHeader(title: "Streak", actionTitle: "Calendar") { app.router.push(.streak) }
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: Route.streak) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StreakFlame(stage: StreakStage(days: onHold ? model.runBeforeRepair : streak.current), size: 30, lit: !onHold)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                        Text(CLFormat.count(onHold ? model.runBeforeRepair : streak.current, "day"))
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(CLColor.ink)
                        if onHold {
                            ReflowPill(text: "On hold", tone: .sun, systemImage: "pause.fill")
                        }
                        Spacer(minLength: 8)
                        Text("Best \(streak.best)")
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink3)
                    }
                    .accessibilityElement(children: .combine)
                    StreakNotes(streak: streak, calendar: model.calendar, now: model.now)
                    StudyHeatmap(cells: model.cells, calendar: model.calendar)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let day = streak.repairableDay {
                Rectangle().fill(CLColor.hairline).frame(height: 1)
                RepairOffer(day: day, run: model.runBeforeRepair, dailyMinutes: model.dailyMinutes, calendar: model.calendar)
            }
        }
        .clCard()
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

private struct WeekSection: View {
    let model: ProgressModel

    var body: some View {
        let week = model.week
        let last = model.week.previousWeekMinutes
        CLSectionHeader(title: "This week")
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ReflowStack(verticalAlignment: .firstTextBaseline, spacing: 10) {
                    Text(CLFormat.minutes(week.totalMinutes))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(CLColor.ink)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(CLFormat.count(week.activeDays, "day")) studied")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                }
                ReflowPill(text: .verbatim(ProgressPresentation.weekComparison(this: week.totalMinutes, last: last)),
                           tone: week.totalMinutes > last ? .mint : .neutral,
                           systemImage: week.totalMinutes > last ? "arrow.up.right" : nil)
            }
            .accessibilityElement(children: .combine)
            WeekMinutesChart(week: week, lastWeek: model.lastWeek, calendar: model.calendar)
        }
        .clCard()
    }
}

/// What's due over the next week. (How much you remember is no longer a percentage here: each exam's readiness is the only one.)
private struct MemorySection: View {
    let due: [DueForecastDay]
    let calendar: Calendar

    var body: some View {
        CLSectionHeader(title: "Memory")
        VStack(alignment: .leading, spacing: 6) {
            CLEyebrow(text: "Reviews due, next 7 days")
                .padding(.bottom, 6)
            DueForecastChart(days: due, calendar: calendar)
            Text("Questions come back right before you'd forget them.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .clCard()
    }
}

/// "Topics" as constellations: the ones with questions fading first, each with Practice (weakest for its course's next exam
/// first), then the brightest. Counts only, in the sky's own words.
private struct ConstellationsSection: View {
    let sky: SkyScene
    let brightest: [ProgressModel.ConstellationLine]
    let fading: [ProgressModel.ConstellationLine]
    @Environment(AppModel.self) private var app

    var body: some View {
        if !brightest.isEmpty || !fading.isEmpty {
            CLSectionHeader(title: "Constellations", actionTitle: sky.isEmpty ? nil : "See the sky",
                            action: sky.isEmpty ? nil : { app.router.push(.sky) })
            VStack(alignment: .leading, spacing: 8) {
                if !fading.isEmpty {
                    CLEyebrow(text: "Fading").padding(.leading, 4)
                    CLList {
                        ForEach(fading) { line in
                            Button { relight(line) } label: {
                                ConstellationRow(line: line, sky: sky, trailing: .practice)
                            }
                            .buttonStyle(LibraryRowButtonStyle())
                            .accessibilityHint(Text("Practises this topic"))
                        }
                    }
                }
                if !brightest.isEmpty {
                    CLEyebrow(text: "Brightest").padding(.leading, 4).padding(.top, fading.isEmpty ? 0 : 12)
                    CLList {
                        ForEach(brightest) { line in
                            NavigationLink(value: Route.course(line.topic.courseID)) {
                                ConstellationRow(line: line, sky: sky, trailing: .chevron)
                            }
                            .buttonStyle(LibraryRowButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func relight(_ line: ProgressModel.ConstellationLine) {
        let index = line.topic.index
        if sky.layout.constellations.indices.contains(index) {
            app.router.present(.session(app.relightRequest(sky.layout.constellations[index], in: sky)))
        } else {
            app.router.present(.session(SessionRequest(kind: .practice, courseID: line.topic.courseID, topicID: line.topic.id)))
        }
    }
}

private struct ConstellationRow: View {
    enum Trailing { case chevron, practice }

    let line: ProgressModel.ConstellationLine
    let sky: SkyScene
    let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let topic = line.topic
        HStack(spacing: 12) {
            if let glyph = line.glyph, !typeSize.isAccessibilitySize { SkyGlyphView(glyph: glyph, size: 46) }
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Circle().fill(topic.color.fill).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(topic.courseName).clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                Text(verbatim: detail).clFont(.footnote).foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch trailing {
            case .chevron:
                CLChevron()
            case .practice:
                Text("Practice")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.tangerineInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(CLColor.tangerineSoft, in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Fading: "2 questions fading"; brightest: the sky's own line, "8 of 14 bright · 2 dim".
    private var detail: String {
        switch trailing {
        case .practice: ProgressPresentation.fadingLine(line.topic.dimCount)
        case .chevron: SkyCopy.detail(line.topic.index, in: sky)
        }
    }
}

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
                                Text("Missed \(CLFormat.count(confusion.misses, "time")) · \(confusion.courseName) · a 2-minute fix")
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
