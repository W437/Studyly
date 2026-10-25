import SwiftUI

/// One exam: how ready you are now, the projected grade, the path to the target, the topics in scope with their
/// gaps, the week's plan, the materials, and what to do next (today's session, the exam-eve review, logging the
/// grade). Every number comes from the engine, read once per change of the store.
///
/// Harness: `CRAMLESS_SCENARIO=eve|past|graded|missed` puts the exam (or yesterday) in that state first
/// (`AppModel.applyHarnessScenario`).
struct ExamDetailView: View {
    let examID: UUID

    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        Group {
            if let exam = app.exam(examID), exam.deletedAt == nil, let course = exam.course, course.deletedAt == nil {
                ExamDetailContent(model: ExamDetailModel(exam: exam, course: course, app: app))
            } else {
                ContentUnavailableView("This exam is gone", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("It was deleted on this or another device."))
                    .clScreenBackground()
            }
        }
        #if DEBUG
        .task { app.applyHarnessScenarioOnce(examID: examID) }
        #endif
    }
}

/// Everything the exam screen shows, read from the engine once.
struct ExamDetailModel {
    var id: UUID
    var title: String
    var courseID: UUID
    var courseName: String
    var color: CourseColor
    var date: Date
    var formatLine: String
    var phase: ExamPresentation.Phase
    var readiness: ExamReadiness
    var plan: StudyPlan
    var path: ExamPresentation.Path
    var strip: [ExamPresentation.StripDay]
    var gapNames: [String]
    var topicCount: Int
    var result: Double?
    var readinessAtExam: Double?
    var projectedAtExam: ProjectedGrade
    var materials: [Material]
    var sessionMinutes: Int
    var sessionReady: Bool
    var offersExamPass: Bool
    var dailyMinutes: Int
    var now: Date
    var calendar: Calendar

    struct Material: Identifiable {
        var id: UUID
        var kind: SourceKind
        var title: String
        var meta: String
    }

    @MainActor
    init(exam: Exam, course: Course, app: AppModel) {
        id = exam.id
        title = exam.title
        courseID = course.id
        courseName = course.name
        color = course.color
        date = exam.date
        formatLine = LibraryFormat.formatLine(exam.format)
        now = app.now
        calendar = app.calendar
        phase = ExamPresentation.phase(examDate: exam.date, now: app.now, calendar: app.calendar)
        readiness = app.readiness(for: exam)
        plan = app.plan(for: exam)
        let history = app.readinessHistory(for: exam, days: 14)
        path = ExamPresentation.path(history: history, plan: plan, examDate: exam.date, now: app.now, calendar: app.calendar)
        strip = ExamPresentation.weekStrip(plan: plan, yesterday: app.dayRecordSnapshot(for: app.calendar.adding(days: -1, to: app.now)),
                                           examCreatedAt: exam.createdAt, now: app.now, calendar: app.calendar)
        gapNames = readiness.topics.filter { $0.value == nil }.map(\.name)
        topicCount = readiness.topics.count
        result = exam.resultScore
        readinessAtExam = exam.readinessAtExam
        projectedAtExam = app.projectedGrade(for: exam)
        let items = course.liveItems
        let counts = Dictionary(grouping: items.compactMap { $0.sourceRef?.sourceID }, by: { $0 }).mapValues(\.count)
        materials = course.liveSources.sorted { $0.createdAt > $1.createdAt }.map { source in
            Material(id: source.id, kind: source.kind, title: source.title,
                     meta: LibraryFormat.sourceMeta(kind: source.kind, pages: source.pages.count, duration: source.duration,
                                                    questions: counts[source.id] ?? 0))
        }
        let today = app.todaySummary()
        sessionMinutes = today.plannedMinutes
        sessionReady = today.sessionReady
        offersExamPass = ExamPresentation.offersExamPass(plan: app.purchases.plan, phase: phase)
        dailyMinutes = app.settings.dailyMinutes
    }
}

private struct ExamDetailContent: View {
    let model: ExamDetailModel
    @Environment(AppModel.self) private var app
    @State private var confirmDelete = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                actions
                    .padding(.top, 20)
                if case .past = model.phase {
                    if model.result != nil { resultCard.padding(.top, 16) }
                } else {
                    gradeCard.padding(.top, 16)
                    pathCard.padding(.top, 16).id("path")
                }
                if !model.gapNames.isEmpty {
                    gapCard.padding(.top, 16)
                }
                topics.id("topics")
                if case .past = model.phase {} else { planSection.id("plan") }
                if model.offersExamPass {
                    examPassCard.padding(.top, 16)
                }
                materials.id("materials")
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
        .harnessScroll(proxy)
        }
        .clScreenBackground()
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit exam", systemImage: "pencil") { app.router.present(.editExam(model.id)) }
                    if isPastOrToday {
                        Button(model.result == nil ? "Log your grade" : "Change your grade", systemImage: "checkmark.seal") {
                            app.router.present(.logGrade(examID: model.id))
                        }
                    }
                    NavigationLink(value: Route.course(model.courseID)) { Label("Open \(model.courseName)", systemImage: "books.vertical") }
                    Divider()
                    Button("Delete exam", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .alert("Delete \(model.title)?", isPresented: $confirmDelete) {
            Button("Delete exam", role: .destructive) {
                app.router.pop()
                app.deleteExam(model.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its plan goes. Your questions and progress stay in \(model.courseName).")
        }
    }

    private var isPastOrToday: Bool {
        switch model.phase {
        case .past, .today: true
        default: false
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ReadinessRing(value: shownReadiness, size: 176, lineWidth: 16, caption: ringCaption, animatesFromZero: true)
                .accessibilityLabel(Text(ringCaption == "ready" ? "Readiness" : ringCaption.capitalized))
                .padding(.top, 8)
            if case .past = model.phase {} else {
                ReflowPill(text: "\(CLFormat.delta(model.readiness.deltaThisWeek)) this week",
                           tone: model.readiness.deltaThisWeek > 0.004 ? .mint : .neutral,
                           systemImage: model.readiness.deltaThisWeek > 0.004 ? "arrow.up.right" : nil)
            }
            Text(model.date.formatted(LibraryFormat.dateStyle(model.calendar).weekday(.abbreviated).month(.abbreviated).day()))
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .padding(.top, 4)
            Text(subline)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var shownReadiness: Double {
        if case .past = model.phase, let atExam = model.readinessAtExam { return atExam }
        return model.readiness.value
    }

    private var ringCaption: String {
        if case .past = model.phase { return "on the day" }
        return "ready"
    }

    private var subline: String {
        let when: String
        switch model.phase {
        case .ahead(let days): when = LibraryFormat.countdown(days: days)
        case .eve: when = "Tomorrow at \(model.date.formatted(date: .omitted, time: .shortened))"
        case .today: when = "Today at \(model.date.formatted(date: .omitted, time: .shortened))"
        case .past(let days): when = days == 0 ? "Earlier today" : LibraryFormat.countdown(days: -days)
        }
        return "\(when) · \(model.formatLine)"
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch model.phase {
        case .ahead:
            VStack(spacing: 10) {
                startTodayButton(primary: true)
            }
        case .eve:
            VStack(spacing: 10) {
                Button {
                    app.router.present(.session(SessionRequest(kind: .examEve, examID: model.id)))
                } label: {
                    FittingLabel(titles: ["Tonight: weak spots, then sleep", "Tonight's review"],
                                 systemImage: "moon.stars.fill")
                }
                .buttonStyle(.cl(.primary))
                Text("About 10 minutes on what you're shakiest on. Then stop: sleep does the rest.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        case .today:
            HStack(alignment: .center, spacing: 12) {
                CapView(pose: .celebrate, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("It's exam day.").clFont(.headline).foregroundStyle(CLColor.ink)
                    Text("You've done the work. Have a glance at your weak spots, then go.")
                        .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clCard(padding: 16)
        case .past:
            if model.result == nil {
                VStack(spacing: 8) {
                    Button {
                        app.router.present(.logGrade(examID: model.id))
                    } label: {
                        FittingLabel(titles: ["Log your grade", "Log grade"], systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(.cl(.primary))
                    Text("Capling projected \(CLFormat.percent(model.projectedAtExam.percent)) (\(model.projectedAtExam.letter)). Your grade shows how close that was, and makes the next projection fit you better.")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func startTodayButton(primary: Bool) -> some View {
        Button {
            if model.sessionReady {
                app.router.present(.session(SessionRequest(kind: .daily)))
            } else {
                app.router.present(.session(SessionRequest(kind: .practice, courseID: model.courseID)))
            }
        } label: {
            FittingLabel(titles: model.sessionReady
                         ? ["Start today's session · \(CLFormat.minutes(model.sessionMinutes))", "Start today's session", "Start"]
                         : ["Practice \(model.courseName)", "Practice"],
                         systemImage: "play.fill")
        }
        .buttonStyle(.cl(primary ? .primary : .soft))
    }

    // MARK: Cards

    private var gradeCard: some View {
        let grade = model.readiness.projectedGrade
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                CLEyebrow(text: "Projected grade")
                Spacer()
                ReflowPill(text: grade.isCalibrated ? "Calibrated" : "Projection", tone: grade.isCalibrated ? .mint : .neutral,
                           systemImage: grade.isCalibrated ? "checkmark" : nil)
            }
            ReflowStack(verticalAlignment: .firstTextBaseline, spacing: 12) {
                Text(grade.letter)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(CLColor.ink)
                    .accessibilityLabel(Text("Projected grade \(grade.letter)"))
                Text("\(CLFormat.percent(grade.percent)) on exam day if you follow the plan")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(grade.isCalibrated ? "A projection calibrated to your past grades, not a promise."
                 : "A projection from your recall history, not a promise. It calibrates as you log grades.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CLEyebrow(text: "Path to \(CLFormat.percent(model.path.target))")
                Spacer()
                if let reached = model.path.targetReachedOn {
                    ReflowPill(text: "by \(LibraryFormat.shortDate(reached, calendar: model.calendar))", tone: .mint, systemImage: "flag.fill")
                }
            }
            ExamPathChart(path: model.path, calendar: model.calendar)
            ExamPathKey()
            Text(ExamPresentation.pathSummary(model.path, suggestedMinutes: model.plan.suggestedMinutes, calendar: model.calendar))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .clCard()
    }

    private var gapCard: some View {
        let covered = model.topicCount - model.gapNames.count
        return HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: "info", tint: .sun, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(covered) of \(CLFormat.count(model.topicCount, "topic")) have material")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                Text("You haven't added anything for \(ListFormatter.localizedString(byJoining: model.gapNames)) yet, so it can't count toward readiness.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    app.router.present(.capture(courseID: model.courseID))
                } label: {
                    FittingLabel(titles: ["Add material", "Add"], systemImage: "plus")
                }
                .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard(flat: true)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CLEyebrow(text: model.result == nil ? "Your grade" : "How it went")
            if let result = model.result {
                let lines = ExamPresentation.gradeComparison(projected: model.projectedAtExam.percent, got: result,
                                                             calibratedNow: model.projectedAtExam.isCalibrated)
                Text(lines.headline).clFont(.headline).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                GradeBars(projected: model.projectedAtExam.percent, got: result)
                Text(lines.note).clFont(.footnote).foregroundStyle(CLColor.ink2)
                Button("Change your grade") { app.router.present(.logGrade(examID: model.id)) }
                    .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                    .frame(minHeight: CLMetrics.minHitTarget)
            } else {
                Text("Capling projected \(CLFormat.percent(model.projectedAtExam.percent)) (\(model.projectedAtExam.letter)). Log your grade to see how close it was.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clCard()
    }

    @ViewBuilder
    private var topics: some View {
        if !model.readiness.topics.isEmpty {
            CLSectionHeader(title: "Topics", actionTitle: "Practice") {
                app.router.present(.session(SessionRequest(kind: .practice, courseID: model.courseID)))
            }
            CLList {
                ForEach(model.readiness.topics) { topic in
                    LibraryTopicRow(name: topic.name, value: topic.value, itemCount: topic.itemCount,
                                    onAdd: topic.value == nil ? { app.router.present(.capture(courseID: model.courseID)) } : nil)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if !model.strip.isEmpty {
            CLSectionHeader(title: "This week's plan", actionTitle: "Adjust") { app.router.push(.settingsPage(.study)) }
            VStack(alignment: .leading, spacing: 14) {
                ExamWeekStrip(days: model.strip, calendar: model.calendar)
                Text(planCaption)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let eve = model.plan.examEve, model.phase != .eve {
                    Label("Exam eve, \(CLFormat.day(eve, calendar: model.calendar)): weak spots only, then sleep.", systemImage: "moon.stars")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                }
            }
            .clCard()
        }
    }

    private var planCaption: String {
        let missed = model.strip.first.map { $0.kind == .missed || $0.kind == .frozen } == true
        let base = "Minutes for this exam, inside your \(model.dailyMinutes)-minute daily session."
        return missed ? "Yesterday's reviews moved into the next few days, so nothing piles up. " + base : base
    }

    private var examPassCard: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: "ticket", tint: .tangerine, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Exam Pass for \(model.title)").clFont(.headline).foregroundStyle(CLColor.ink)
                Text("Everything in Pro for 30 days with one payment. No subscription to cancel.")
                    .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See Exam Pass") { app.router.present(.examPass(examID: model.id)) }
                    .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
    }

    @ViewBuilder
    private var materials: some View {
        CLSectionHeader(title: "Materials", actionTitle: "Add") { app.router.present(.capture(courseID: model.courseID)) }
        if model.materials.isEmpty {
            Text("Nothing added for \(model.courseName) yet.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clCard(padding: 16)
        } else {
            CLList {
                ForEach(model.materials) { material in
                    NavigationLink(value: material.kind.opensLectureNotes ? Route.lectureNotes(material.id) : Route.source(material.id)) {
                        LibrarySourceRow(kind: material.kind, title: material.title, meta: material.meta, tint: model.color)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(LibraryRowButtonStyle())
                }
            }
        }
    }
}

/// The projected grade beside the logged one, as two meters.
struct GradeBars: View {
    let projected: Double
    let got: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Projected", projected, color: CLColor.ink4)
            row("You got", got, color: CLColor.readiness(got))
        }
    }

    private func row(_ title: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink2)
                Spacer()
                Text(CLFormat.percent(value)).clFont(.number(15, .bold)).foregroundStyle(CLColor.ink)
            }
            CLBar(value: value, color: color, height: 10).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
