import SwiftUI

/// One exam, in the order a student reads it: how ready they are now (the ring with the goal's dot and the plan's faint arc), one
/// sentence on where the plan takes them and what that takes, today's session ("Study · 15 min"), the topics weakest first with a
/// practice round each, the plan as stops with "What if I skip Saturday?", the materials, how it's gone so far (folded), and Exam
/// Pass for a free plan. After the exam: readiness on the day and the grade. Every number comes from the engine, read once per
/// change of the store; the letter grade shows only once logged grades calibrate it.
///
/// Harness: `CRAMLESS_ROUTE=exam[:n]` (0 the Chem quiz on Sunday, 1 the Bio midterm, 2 AP Psych, with
/// `CRAMLESS_NOW=2026-11-06T14:00:00-05:00`); `CRAMLESS_SCENARIO=eve|past|graded|missed|thin|calibrated|ontrack|crowded|empty` puts
/// the exam (or yesterday) in that state first (`AppModel.applyHarnessScenario`); `CRAMLESS_EXAM_SKIP=1` opens with the what-if on;
/// `CRAMLESS_SCROLL=topics|plan|materials|path` scrolls to a section. `CRAMLESS_SCENARIO=mocked` adds a mock taken three days ago (the
/// card's "Last mock" line); `fewItems` leaves five questions in scope (the card asks for more); `gap` leaves a topic of the exam with drafts waiting too, beside the
/// topics with nothing yet (the gap card, `FillGapSheet`).
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
    var topics: [ExamPresentation.TopicRow]
    var today: ExamPresentation.TodayWork
    var study: ExamPresentation.StudyAction?
    /// On the eve, tonight's session's own minutes (0: nothing to review): the button and the plan's "Tonight" say this number.
    var tonightMinutes: Int?
    /// On the eve, tonight's session is finished.
    var eveDone = false
    var skip: ExamPresentation.SkipOption?
    var result: Double?
    var readinessAtExam: Double?
    /// Exams with readiness on the day and a logged grade, this one included: two calibrate the letter.
    var calibratingExams: Int
    /// How much of the material its questions reach (for an exam still to come).
    var coverage: ExamPresentation.CoverageNote?
    /// There is a reading with something left to write questions for ("Add questions for the rest").
    var offersRest = false
    var materials: [Material]
    var offersExamPass: Bool
    /// The mock exam's card; nil on the eve, the day and after.
    var mock: ExamPresentation.MockCard?
    /// Topics with no notes, while there is time to fill them (nil once put off for the day).
    var gap: ExamGap?
    /// The drafts waiting for the gap's `waiting` topics.
    var gapDrafts: UUID?
    /// The seconds the other exams' plans give each day: with this one's, what the plan's stops name.
    var otherExams: [Int: Double]
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
        let read = app.readinessAndPlan(for: exam)
        readiness = read.readiness
        plan = read.plan
        otherExams = app.otherExamsSeconds(besides: read.plan)
        let history = app.readinessHistory(for: exam, days: 14)
        path = ExamPresentation.path(history: history, plan: plan, examDate: exam.date, now: app.now, calendar: app.calendar)
        topics = ExamPresentation.topicsWeakestFirst(readiness.topics, target: readiness.target, drafts: app.draftSources(in: course))
        // Today's session as Today starts it, built once: the "Study" button and the plan's first stop read it.
        let (summary, session) = app.todayPlan()
        let strip = ExamPresentation.weekStrip(plan: plan, yesterday: app.dayRecordSnapshot(for: app.calendar.adding(days: -1, to: app.now)),
                                               examCreatedAt: exam.createdAt, now: app.now, calendar: app.calendar)
        today = ExamPresentation.todayWork(entries: session.entries, sessionMinutes: summary.sessionReady ? summary.plannedMinutes : 0,
                                           exam: ExamSnapshot(exam), topicNames: app.topicNames(), studiedToday: summary.studiedToday,
                                           missedYesterday: strip.first.map { $0.kind == .missed || $0.kind == .frozen } == true)
        if case .eve = phase {
            tonightMinutes = app.builtEveMinutes(examID: exam.id)
            eveDone = app.eveSessionDone(summary)
        } else if app.calendar.dayDistance(from: app.now, to: exam.date) == 2 {
            // Its evening is tomorrow: the plan's stop says what Today's strip says.
            tonightMinutes = app.builtEveMinutes(examID: exam.id)
        }
        study = ExamPresentation.studyAction(phase: phase, today: today, weakest: topics.first { $0.isWeakest }, courseName: course.name,
                                             eveMinutes: tonightMinutes ?? SessionBuilder.examEveMinutes, eveDone: eveDone)
        skip = ExamPresentation.skipOption(plan: plan, phase: phase, calendar: app.calendar)
        result = exam.resultScore
        readinessAtExam = exam.readinessAtExam
        calibratingExams = app.calibratingExamCount
        if case .past = phase {
            coverage = nil
            offersRest = false
        } else {
            // Adding questions is for the weeks before: on the eve and on the day, the note only says how much they reach.
            var canAdd = false
            if case .ahead = phase { canAdd = true }
            let summary = app.coverage(for: exam)
            let target = summary.flatMap { app.restTarget(in: $0) }
            let empty = canAdd ? topics.filter(\.isEmpty).count : 0
            coverage = summary.map { ExamPresentation.coverageNote($0, canAddMore: canAdd && target != nil, emptyTopics: empty) }
            offersRest = canAdd && target != nil
        }
        let items = course.liveItems
        let counts = Dictionary(grouping: items.compactMap { $0.sourceRef?.sourceID }, by: { $0 }).mapValues(\.count)
        materials = course.liveSources.sorted { $0.createdAt > $1.createdAt }.map { source in
            Material(id: source.id, kind: source.kind, title: source.title,
                     meta: LibraryFormat.sourceMeta(kind: source.kind, pages: source.pages.count, duration: source.duration,
                                                    questions: counts[source.id] ?? 0))
        }
        offersExamPass = ExamPresentation.offersExamPass(plan: app.purchases.plan, examDate: exam.date,
                                                         examDates: app.upcomingExams().map(\.date), now: app.now,
                                                         calendar: app.calendar)
        let offer = app.mockOffer(for: exam)
        let last = offer == .hidden ? nil : app.lastMock(for: exam.id)
        // Only a card that asks for more questions needs to know whether a reading has more to give.
        var canWrite = false
        if case .tooFew = offer { canWrite = app.restRequest(for: exam) != nil }
        mock = ExamPresentation.mockCard(offer: offer, format: exam.format, lastScore: last?.score, lastDate: last?.date, canWrite: canWrite, calendar: app.calendar)
        if case .ahead = phase, !app.gapIsPutOff(exam.id), let found = app.examGap(for: exam, topics: readiness.topics) {
            gap = found
            gapDrafts = found.waiting.isEmpty ? nil : app.draftSource(forTopics: found.waiting.map(\.id), in: course.id)
        }
    }

    var isPast: Bool { if case .past = phase { true } else { false } }
}

private struct ExamDetailContent: View {
    let model: ExamDetailModel
    @Environment(AppModel.self) private var app
    @State private var confirmDelete = false
    @State private var showsAllTopics = false
    @State private var showsHistory = false
    /// The what-if: the day skipped and the plan without it (a preview; nothing is stored).
    @State private var skipping = false
    @State private var skipPlan: (revision: Int, plan: StudyPlan)?

    /// Topics shown before "See all".
    private let topicsShown = 4

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if let projection {
                    projectionCard(projection).padding(.top, 20)
                }
                actions.padding(.top, 16)
                if model.isPast, model.result != nil {
                    resultCard.padding(.top, 16)
                }
                if let mock = model.mock {
                    mockCard(mock).padding(.top, 16)
                }
                topicsSection.id("topics")
                // The ring is how well the questions are remembered; this is how much of the material they reach, and what no material reaches yet.
                if let gap = model.gap {
                    gapCard(gap).padding(.top, 12)
                } else if let note = model.coverage {
                    CoverageNoteCard(sentence: note.sentence, detail: note.mainGap, isThin: note.isThin,
                                     offersMore: note.offersMore && model.offersRest, centered: false, onAdd: addForTheRest)
                        .padding(.top, 12)
                }
                planSection.id("plan")
                materials.id("materials")
                if !model.isPast { historyFold.padding(.top, 16).id("path") }
                if model.offersExamPass {
                    examPassCard.padding(.top, 16)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
            .animation(CLMotion.settle, value: skipping)
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
                    if !model.isPast {
                        Button(SyllabusCopy.setFromSyllabus, systemImage: "camera") { app.router.present(.syllabus(examID: model.id)) }
                    }
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
        #if DEBUG
        .task {
            // Harness: `CRAMLESS_EXAM_SKIP=1` opens with "What if I skip …?" on; `CRAMLESS_GAP` opens "Fill the gap" (`FillGapSheet`).
            if TestHarness.once("CRAMLESS_EXAM_SKIP") == "1", model.skip != nil { toggleSkip() }
            if TestHarness.once("CRAMLESS_GAP") != nil { app.router.present(.fillGap(examID: model.id, topicID: nil)) }
        }
        #endif
    }

    private var isPastOrToday: Bool {
        switch model.phase {
        case .past, .today: true
        default: false
        }
    }

    // MARK: The what-if

    /// The plan without the skipped day, built when asked and kept for this revision of the store.
    private var shownSkipPlan: StudyPlan? {
        guard skipping, let skipPlan, skipPlan.revision == app.revision else { return nil }
        return skipPlan.plan
    }

    private func toggleSkip() {
        guard let skip = model.skip, let exam = app.exam(model.id) else { return }
        if !skipping, skipPlan?.revision != app.revision {
            skipPlan = (app.revision, app.plan(for: exam, skipping: [skip.offset]))
        }
        withAnimation(CLMotion.settle) { skipping.toggle() }
    }

    private var skipCost: ExamPresentation.SkipCost? {
        guard let skip = model.skip, let plan = shownSkipPlan else { return nil }
        return ExamPresentation.skipCost(skip, planned: model.plan.projectedReadiness, skipped: plan.projectedReadiness,
                                         examDate: model.date, now: model.now, calendar: model.calendar)
    }

    // MARK: Hero

    private var hero: some View {
        let target = model.readiness.target
        let ahead = !model.isPast
        return ReflowStack(horizontalAlignment: .center, verticalAlignment: .center, spacing: 18) {
            ReadinessRing(value: shownReadiness, size: 150, lineWidth: 15, caption: model.isPast ? "on the day" : "ready",
                          animatesFromZero: true, goal: ahead ? target : nil,
                          projected: ahead && model.readiness.itemsInScope > 0 ? (shownSkipPlan ?? model.plan).projectedReadiness : nil)
                .accessibilityLabel(Text(model.isPast ? "Readiness on the day" : "Readiness"))
            VStack(alignment: .leading, spacing: 6) {
                DotLine(parts: whenParts)
                    .clFont(.title3)
                    .foregroundStyle(CLColor.ink)
                DotLine(parts: sublineParts)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                if ahead {
                    ReflowPill(text: "\(CLFormat.delta(model.readiness.deltaThisWeek)) this week",
                               tone: model.readiness.deltaThisWeek > 0.004 ? .mint : .neutral,
                               systemImage: model.readiness.deltaThisWeek > 0.004 ? "arrow.up.right" : nil)
                        .padding(.top, 2)
                    HStack(spacing: 6) {
                        Circle().fill(CLColor.mint).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(CLColor.surface, lineWidth: 2))
                            .accessibilityHidden(true)
                        Text("Goal \(CLFormat.percent(target))")
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink2)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    /// The same flow as importing a source, for the parts of the exam's material no question reaches. The part is decided now.
    private func addForTheRest() {
        guard let exam = app.exam(model.id), let request = app.restRequest(for: exam) else { return }
        app.router.present(.captureFlow(request))
    }

    private var shownReadiness: Double {
        if model.isPast, let atExam = model.readinessAtExam { return atExam }
        return model.readiness.value
    }

    /// "Sun, Nov 8", "10:00 AM".
    private var whenParts: [String] {
        let style = LibraryFormat.dateStyle(model.calendar)
        return [model.date.formatted(style.weekday(.abbreviated).month(.abbreviated).day()), model.date.formatted(style.hour().minute())]
    }

    /// "2 days to go", then the exam's format.
    private var sublineParts: [String] {
        let when: String
        switch model.phase {
        case .ahead(let days): when = LibraryFormat.countdown(days: days)
        case .eve: when = "Tomorrow"
        case .today: when = "Today"
        case .past(let days): when = days == 0 ? "Earlier today" : LibraryFormat.countdown(days: -days)
        }
        return [when] + model.formatLine.components(separatedBy: " · ").filter { !$0.isEmpty }
    }

    // MARK: The projection

    private var projection: ExamPresentation.Projection? {
        ExamPresentation.projection(phase: model.phase, plan: shownSkipPlan ?? model.plan, questionCount: model.readiness.itemsInScope,
                                    weakestTopic: model.topics.first { $0.isWeakest }?.name,
                                    grade: model.readiness.projectedGrade, examDate: model.date, now: model.now,
                                    calendar: model.calendar, skipping: shownSkipPlan == nil ? nil : model.skip, eveDone: model.eveDone,
                                    newQuestions: model.readiness.newQuestions, newQuestionsInPlan: model.readiness.newQuestionsInPlan)
    }

    private func projectionCard(_ p: ExamPresentation.Projection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: p.sentence)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if let nudge = p.nudge {
                Text(verbatim: nudge)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let new = p.newQuestions {
                Label {
                    Text(verbatim: new).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "text.badge.plus").foregroundStyle(CLColor.skyInk)
                }
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
            }
            if let letter = p.letter {
                Label {
                    Text(verbatim: letter)
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(CLColor.mintInk)
                }
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
            if p.addsMaterial {
                Button {
                    app.router.present(.capture(courseID: model.courseID))
                } label: {
                    FittingLabel(titles: ["Add material", "Add"], systemImage: "plus")
                }
                .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                .padding(.top, 4)
            }
            let small = [p.basedOn, p.footnote].compactMap { $0 }
            if !small.isEmpty {
                Text(verbatim: small.joined(separator: " "))
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if let study = model.study {
            VStack(spacing: 8) {
                Button {
                    start(study)
                } label: {
                    FittingLabel(titles: [study.title] + [study.shortTitle].compactMap { $0 },
                                 systemImage: study.kind == .examEve ? "moon.stars.fill" : "play.fill")
                }
                .buttonStyle(.cl(.primary))
                if let subline = study.subline {
                    Text(verbatim: subline)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            switch model.phase {
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
                        Text(verbatim: ExamPresentation.logGradeInvite(onTheDay: model.readinessAtExam))
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func start(_ study: ExamPresentation.StudyAction) {
        switch study.kind {
        case .daily:
            app.router.present(.session(SessionRequest(kind: .daily)))
        case .examEve:
            app.router.present(.session(SessionRequest(kind: .examEve, examID: model.id)))
        case .practice(let topicID, let minutes):
            app.router.present(.session(SessionRequest(kind: .practice, courseID: model.courseID, examID: model.id, minutes: minutes,
                                                       topicID: topicID)))
        }
    }

    // MARK: The mock exam

    private func mockCard(_ card: ExamPresentation.MockCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: "timer", tint: .sky, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(MockCopy.title)
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                switch card.kind {
                case .offer(let line, let mix):
                    Text(verbatim: line)
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: mix)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                case .tooFew(let line, _):
                    Text(verbatim: line)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let last = card.last {
                    Text(verbatim: last)
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                switch card.kind {
                case .offer:
                    Button {
                        CLHaptics.commit()
                        app.router.present(.mockExam(examID: model.id))
                    } label: {
                        Text("Take it")
                    }
                    .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                    .padding(.top, 6)
                case .tooFew(_, let canWrite):
                    CLFlow(spacing: 8, lineSpacing: 8) {
                        if canWrite {
                            Button("Write more questions", action: addForTheRest)
                                .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                        }
                        Button("Add material") { app.router.present(.capture(courseID: model.courseID)) }
                            .buttonStyle(.cl(canWrite ? .soft : .dark, size: .medium, fullWidth: false))
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: The gap

    /// A topic of this exam with no notes can't count toward readiness: the card says which, offers help, and says how much of what has been added its questions reach:
    /// one statement, so a share of the notes never reads as all of the exam.
    private func gapCard(_ gap: ExamGap) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: "text.badge.plus", tint: .tangerine, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                if !gap.topics.isEmpty {
                    Text(verbatim: ExamGapCopy.title(count: gap.topics.count, examTitle: gap.examTitle))
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: ExamGapCopy.detail(gap.topics.map(\.name)))
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    CaptureChips {
                        Button("Fill the gap") {
                            CLHaptics.commit()
                            app.router.present(.fillGap(examID: model.id, topicID: nil))
                        }
                        .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                        Button("Later") {
                            CLHaptics.tap()
                            app.snoozeNotice(NoticeEngine.gapID(model.id))
                        }
                        .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
                    }
                    .padding(.top, 6)
                }
                if !gap.waiting.isEmpty {
                    Text(verbatim: ExamGapCopy.waiting(gap.waiting.map(\.name)))
                        .clFont(gap.topics.isEmpty ? .subheadlineEmphasis : .subheadline)
                        .foregroundStyle(gap.topics.isEmpty ? CLColor.ink : CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, gap.topics.isEmpty ? 0 : 6)
                    if let source = model.gapDrafts {
                        Button("Review them") {
                            CLHaptics.tap()
                            app.router.present(.reviewDraft(sourceID: source))
                        }
                        .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
                        .padding(.top, 4)
                    }
                }
                if let note = model.coverage {
                    Text(verbatim: note.covered)
                        .clFont(.subheadline)
                        .foregroundStyle(note.isThin ? CLColor.sunInk : CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    if let detail = note.mainGap {
                        Text(verbatim: detail)
                            .clFont(.footnote)
                            .foregroundStyle(note.isThin ? CLColor.sunInk : CLColor.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if note.offersMore, model.offersRest {
                        Button {
                            CLHaptics.tap()
                            addForTheRest()
                        } label: {
                            Text("Add questions for the rest")
                        }
                        .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: After the exam

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CLEyebrow(text: "How it went")
            if let result = model.result {
                let lines = ExamPresentation.gradeComparison(onTheDay: model.readinessAtExam, got: result,
                                                             calibratingExams: model.calibratingExams)
                Text(verbatim: lines.headline).clFont(.headline).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                GradeBars(onTheDay: model.readinessAtExam, got: result)
                Text(verbatim: lines.note).clFont(.footnote).foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Change your grade") { app.router.present(.logGrade(examID: model.id)) }
                    .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                    .frame(minHeight: CLMetrics.minHitTarget)
            }
        }
        .clCard()
    }

    // MARK: Topics

    @ViewBuilder
    private var topicsSection: some View {
        if !model.isPast, !model.topics.isEmpty {
            let shown = showsAllTopics ? model.topics : Array(model.topics.prefix(topicsShown))
            CLSectionHeader(title: "Topics", actionTitle: model.topics.count > topicsShown && !showsAllTopics ? "See all \(model.topics.count)" : nil) {
                withAnimation(CLMotion.settle) { showsAllTopics = true }
            }
            CLList {
                ForEach(shown) { topic in
                    ExamTopicRow(topic: topic) {
                        app.router.present(.session(SessionRequest(kind: .practice, courseID: model.courseID, examID: model.id,
                                                                   minutes: topic.practiceMinutes, topicID: topic.id)))
                    } onAdd: {
                        app.router.present(.fillGap(examID: model.id, topicID: topic.id))
                    } onReview: { source in
                        app.router.present(.reviewDraft(sourceID: source))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: The plan

    @ViewBuilder
    private var planSection: some View {
        let stops = ExamPresentation.stops(plan: shownSkipPlan ?? model.plan, phase: model.phase, examTitle: model.title,
                                           examDate: model.date, today: model.today,
                                           skipped: shownSkipPlan == nil ? nil : model.skip?.offset,
                                           tonightMinutes: model.tonightMinutes, eveDone: model.eveDone, otherExams: model.otherExams,
                                           now: model.now, calendar: model.calendar)
        if !stops.isEmpty, model.readiness.itemsInScope > 0 {
            CLSectionHeader(title: "The plan", actionTitle: "Adjust") { app.router.push(.settingsPage(.study)) }
            ExamPlanPath(stops: stops, skip: model.skip, skipping: shownSkipPlan != nil, cost: skipCost) { toggleSkip() }
        }
    }

    // MARK: How it's gone

    private var historyFold: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                CLHaptics.select()
                withAnimation(CLMotion.settle) { showsHistory.toggle() }
            } label: {
                HStack {
                    Text("How it's gone").clFont(.headline).foregroundStyle(CLColor.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CLColor.ink3)
                        .rotationEffect(.degrees(showsHistory ? 180 : 0))
                }
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(showsHistory ? "Shown" : "Hidden"))
            if showsHistory {
                ExamPathChart(path: model.path, calendar: model.calendar)
                ExamPathKey()
            }
        }
        .clCard()
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

/// Readiness on the day beside the grade the person got, as two meters.
struct GradeBars: View {
    let onTheDay: Double?
    let got: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onTheDay { row("Ready on the day", onTheDay, color: CLColor.ink4) }
            row("You got", got, color: CLColor.readiness(got))
        }
    }

    private func row(_ title: LocalizedStringResource, _ value: Double, color: Color) -> some View {
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

/// A topic on the exam page: its readiness for the exam with a meter, "Your weakest topic" on the first under the goal, and a
/// practice round ("Practice · 3 min"), "On track" at the goal, for a gap "No notes yet" with Add material, or with questions written and
/// not yet added, "Waiting for review" with Review them: what the card about it says. At the largest text sizes the name takes the line and the rest goes under it.
private struct ExamTopicRow: View {
    let topic: ExamPresentation.TopicRow
    var onPractice: () -> Void
    var onAdd: () -> Void
    var onReview: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if topic.isWeakest {
                Text("Your weakest topic")
                    .clFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(CLColor.tangerineInk)
            }
            ReflowStack(verticalAlignment: .firstTextBaseline, spacing: 10) {
                Text(topic.name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value = topic.value {
                    Text(topic.questionCount > 0 && value < 0.005 ? "New" : CLFormat.percent(value))
                        .clFont(.number(15, .bold))
                        .foregroundStyle(topic.questionCount > 0 && value < 0.005 ? CLColor.ink3 : CLColor.ink)
                } else if topic.reviewSource != nil {
                    ReflowPill(text: "Waiting for review", tone: .sky)
                } else {
                    ReflowPill(text: "No notes yet", tone: .rose)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(topic.name))
            .accessibilityValue(Text(accessibilityValue))
            if let value = topic.value {
                CLBar(value: value).accessibilityHidden(true)
            }
            if let minutes = topic.practiceMinutes {
                Button {
                    CLHaptics.tap()
                    onPractice()
                } label: {
                    Label("Practice · \(minutes) min", systemImage: "play.fill")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.tangerineInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: CLMetrics.minHitTarget)
                        .background(CLColor.tangerineSoft, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Practice \(topic.name), \(minutes) minutes"))
            } else if topic.isOnTrack {
                CLPill(text: "On track", tone: .mint, systemImage: "checkmark")
            } else if let source = topic.reviewSource {
                Button {
                    CLHaptics.tap()
                    onReview(source)
                } label: {
                    Label("Review them", systemImage: "checklist")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                        .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Review the questions for \(topic.name)"))
            } else if topic.value == nil {
                Button(action: onAdd) {
                    Label("Add material", systemImage: "plus")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                        .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accessibilityValue: String {
        guard let value = topic.value else {
            return topic.reviewSource != nil ? String(localized: "Waiting for review") : String(localized: "No notes yet")
        }
        if topic.questionCount > 0 && value < 0.005 { return String(localized: "Not studied yet") }
        let ready = String(localized: "\(Int((value * 100).rounded())) percent ready")
        return topic.isWeakest ? String(localized: "Your weakest topic.") + " " + ready : ready
    }
}
