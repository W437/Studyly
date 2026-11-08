import SwiftUI

/// One course, on one page: the head (its badge, the next exam with its day, and that exam's readiness ring: the course's one number;
/// with no exam to come, "No exam yet"), its other exams with "Add exam", and "Study Bio 101 · 15 min". Then its topics (readiness for the
/// next exam, gaps, and "Not on the Midterm" apart; a tap practices that topic), its sources with "Add material", and a last row, "All 36
/// questions", that opens the questions list (`CourseQuestionsView`). The tab bar's + adds to this course (`AppModel.courseOnScreen`).
///
/// Harness: `CRAMLESS_ROUTE=course:<n>` opens the nth course (`course:3` is Spanish II, with no exam); `CRAMLESS_SCENARIO=past`
/// first moves the soonest exam three days back. `CRAMLESS_SCROLL=topics|sources|questions` scrolls to that part (the head is tall at the
/// largest text size). `CRAMLESS_COURSE_TAB=questions` and `CRAMLESS_COURSE_FILTER=…` open the questions list over it (see
/// `CourseQuestionsView`); `CRAMLESS_COURSE_TAB=sources` scrolls to the sources.
struct CourseView: View {
    let courseID: UUID

    @Environment(AppModel.self) private var app
    @State private var confirmCourseDelete = false
    @State private var topicEditor: TopicEditor?
    @State private var topicName = ""
    @State private var topicToDelete: LibraryFormat.TopicLine?
    /// The day's session for this course, read once per change of the store.
    @State private var study = CourseStudyCache()

    private struct TopicEditor: Identifiable {
        /// nil: a new topic.
        var topicID: UUID?
        var id: String { topicID?.uuidString ?? "new" }
    }

    var body: some View {
        let _ = app.revision
        if let course = app.course(courseID), course.deletedAt == nil {
            content(course)
        } else {
            ContentUnavailableView("This course is gone", systemImage: "books.vertical",
                                   description: Text("It was deleted on this or another device."))
                .clScreenBackground()
        }
    }

    // MARK: Content

    private func content(_ course: Course) -> some View {
        let next = app.nextExam(of: course.id)
        let lines = LibraryFormat.topicLines(courseTopics: app.courseTopics(course), examTopics: next.map { app.topicReadiness(for: $0) },
                                             examTitle: next?.title, courseName: course.name, drafts: app.draftSources(in: course), covered: app.coveredTopics(in: course))
        let questionCount = course.liveItems.filter { $0.status == .active || $0.status == .suspended }.count
        let model = LibraryCourseModel(course: course, app: app)
        let sources = course.liveSources.sorted { $0.createdAt > $1.createdAt }
        let questionCounts = Dictionary(grouping: course.liveItems.filter { $0.status == .active || $0.status == .suspended }
            .compactMap { $0.sourceRef?.sourceID }, by: { $0 }).mapValues(\.count)
        // The next exam is the head's; the others (and those waiting for a grade) are chips.
        let chips = LibraryFormat.examChips(course.liveExams.filter { $0.id != model.examID }.map { exam in
            LibraryFormat.ChipExam(id: exam.id, title: exam.title, date: exam.date, result: exam.resultScore)
        }, courseName: course.name, now: app.now, calendar: app.calendar)
        let session = study.value(revision: app.revision) { app.courseStudy(course) }

        return ScrollViewReader { proxy in List {
            Section {
                CourseHeader(model: model, chips: chips, study: session, openExam: {
                    guard let id = model.examID else { return }
                    CLHaptics.tap()
                    app.router.push(.exam(id))
                }, openChip: openChip, start: { start(session) }, addMaterial: {
                    app.router.present(.capture(courseID: course.id))
                }, addExam: {
                    app.router.present(.newExam(courseID: course.id, fromCourse: true))
                })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            }
            topicsSections(lines, course: course)
            sourcesSection(sources, course: course, counts: questionCounts)
            questionsSection(count: questionCount, course: course)
        }
        .harnessScroll(proxy)
        #if DEBUG
        .task {
            app.applyHarnessScenarioOnce(examID: app.upcomingExams().first?.id)
            let tab = TestHarness.once("CRAMLESS_COURSE_TAB")
            if tab == "sources" {
                try? await Task.sleep(for: .milliseconds(700))
                proxy.scrollTo("sources", anchor: .top)
            } else if tab == "questions" || TestHarness.value("CRAMLESS_COURSE_FILTER") != nil {
                app.router.push(.courseQuestions(courseID: course.id, topicID: nil))
            }
        }
        #endif
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .clScreenBackground()
        .environment(\.defaultMinListRowHeight, CLMetrics.minHitTarget)
        .captureDebugCanvas()
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar(course) }
        .alert("Delete \(course.name)?", isPresented: $confirmCourseDelete) {
            Button("Delete course", role: .destructive) {
                app.router.pop()
                app.deleteCourse(course.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its \(LibraryFormat.courseCounts(sources: model.sources, questions: model.questions)) and its exams go too.")
        }
        .alert(topicEditor?.topicID == nil ? "New topic" : "Rename topic", isPresented: Binding(
            get: { topicEditor != nil }, set: { if !$0 { topicEditor = nil } })) {
            TextField("Topic name", text: $topicName)
            Button("Cancel", role: .cancel) { topicEditor = nil }
            Button(topicEditor?.topicID == nil ? "Add" : "Rename") {
                if let id = topicEditor?.topicID { app.renameTopic(id, to: topicName) } else { app.addTopic(named: topicName, to: course.id) }
                topicEditor = nil
            }
        } message: {
            Text(topicEditor?.topicID == nil ? "A topic with no material yet shows as a gap to fill." : "")
        }
        .alert(topicToDelete.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(
            get: { topicToDelete != nil }, set: { if !$0 { topicToDelete = nil } })) {
            Button("Delete topic", role: .destructive) {
                if let id = topicToDelete?.id { app.deleteTopic(id) }
                topicToDelete = nil
            }
            Button("Cancel", role: .cancel) { topicToDelete = nil }
        } message: {
            if let topic = topicToDelete {
                Text(topic.questionCount > 0 ? "Its \(CLFormat.count(topic.questionCount, "question")) stay in \(course.name), without a topic." : "It has no questions.")
            }
        }
    }

    private func start(_ session: CourseStudy?) {
        guard let session else {
            app.router.present(.capture(courseID: courseID))
            return
        }
        CLHaptics.commit()
        // Built again for the moment it starts: its id is new, and the store may have moved on.
        var request = session.request
        request.id = UUID()
        app.router.present(.session(request))
    }

    private func practice(_ topic: LibraryFormat.TopicLine, course: Course) {
        CLHaptics.tap()
        app.router.present(.session(SessionRequest(kind: .practice, courseID: course.id, topicID: topic.id)))
    }

    private func openChip(_ chip: LibraryFormat.ExamChip) {
        CLHaptics.tap()
        switch chip.state {
        case .upcoming, .graded: app.router.push(.exam(chip.id))
        case .logGrade: app.router.present(.logGrade(examID: chip.id))
        }
    }

    // MARK: Topics

    @ViewBuilder
    private func topicsSections(_ topics: [LibraryFormat.TopicLine], course: Course) -> some View {
        let onExam = topics.filter { if case .notOnExam = $0.state { false } else { true } }
        let elsewhere = topics.filter { if case .notOnExam = $0.state { true } else { false } }
        let gaps = topics.filter { $0.state == .gap }.count
        Section {
            ForEach(onExam) { topic in
                topicRow(topic, course: course)
            }
            Button {
                topicName = ""
                topicEditor = TopicEditor(topicID: nil)
            } label: {
                Label("Add a topic", systemImage: "plus")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
            }
            .listRowBackground(CLColor.surface)
        } header: {
            LibrarySectionTitle(title: String(localized: "Topics"))
                .id("topics")
        } footer: {
            if gaps > 0 {
                Text("\(gaps) topics have no notes yet. Add some and they join your sessions.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
            }
        }
        if case .notOnExam(let examName)? = elsewhere.first?.state {
            Section {
                ForEach(elsewhere) { topic in
                    topicRow(topic, course: course)
                }
            } header: {
                LibrarySectionTitle(title: String(localized: "Not on the \(examName)"))
            }
        }
    }

    /// A topic with questions is one button: a tap practices it (the small grey play says so; Study is the page's one orange button). One
    /// without questions offers its own way forward ("Add material", "Review them").
    @ViewBuilder
    private func topicRow(_ topic: LibraryFormat.TopicLine, course: Course) -> some View {
        Group {
            if topic.questionCount > 0 {
                Button { practice(topic, course: course) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        LibraryTopicRow(name: topic.name, state: topic.state, questionCount: topic.questionCount)
                        CoursePlayGlyph()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Starts practice on this topic"))
            } else {
                LibraryTopicRow(name: topic.name, state: topic.state, questionCount: 0,
                                onAdd: { app.router.present(.capture(courseID: course.id)) },
                                onReview: { app.router.present(.reviewDraft(sourceID: $0)) })
            }
        }
        .listRowBackground(CLColor.surface)
        .contextMenu {
            if topic.questionCount > 0 {
                Button("Show its questions", systemImage: "list.bullet") {
                    app.router.push(.courseQuestions(courseID: course.id, topicID: topic.id))
                }
            }
            if topic.questionCount >= TeachPlanner.minIdeas {
                Button("Teach Cap", systemImage: "person.wave.2") {
                    app.router.present(.teach(topicID: topic.id))
                }
            }
            Button("Rename", systemImage: "pencil") { topicName = topic.name; topicEditor = TopicEditor(topicID: topic.id) }
            Button("Delete topic", systemImage: "trash", role: .destructive) { topicToDelete = topic }
        }
    }

    // MARK: Sources

    private func sourcesSection(_ sources: [Source], course: Course, counts: [UUID: Int]) -> some View {
        Section {
            ForEach(sources) { source in
                NavigationLink(value: source.kind.opensLectureNotes ? Route.lectureNotes(source.id) : Route.source(source.id)) {
                    LibrarySourceRow(kind: source.kind, title: source.title,
                                     meta: LibraryFormat.sourceMeta(kind: source.kind, pages: source.pages.count,
                                                                    duration: source.duration, questions: counts[source.id] ?? 0),
                                     tint: course.color, showsChevron: false)
                }
                .listRowBackground(CLColor.surface)
            }
            Button {
                app.router.present(.capture(courseID: course.id))
            } label: {
                Label("Add material", systemImage: "plus")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
            }
            .listRowBackground(CLColor.surface)
        } header: {
            LibrarySectionTitle(title: String(localized: "Sources"))
                .id("sources")
        }
    }

    // MARK: Questions

    /// The last row: every question, in a list of its own. With none yet, the way to write one.
    private func questionsSection(count: Int, course: Course) -> some View {
        Section {
            if count > 0 {
                NavigationLink(value: Route.courseQuestions(courseID: course.id, topicID: nil)) {
                    Label { Text("All \(count) questions") } icon: { Image(systemName: "list.bullet") }
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink)
                }
                .listRowBackground(CLColor.surface)
            } else {
                Button {
                    app.router.present(.newItem(courseID: course.id))
                } label: {
                    Label("Write a question", systemImage: "square.and.pencil")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                }
                .listRowBackground(CLColor.surface)
            }
        }
        .id("questions")
    }

    @ToolbarContentBuilder
    private func toolbar(_ course: Course) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Edit course", systemImage: "pencil") { app.router.present(.editCourse(course.id)) }
                Button("Add exam", systemImage: "calendar.badge.plus") { app.router.present(.newExam(courseID: course.id, fromCourse: true)) }
                Button("Add material", systemImage: "doc.viewfinder") { app.router.present(.capture(courseID: course.id)) }
                Button("Write a question", systemImage: "square.and.pencil") { app.router.present(.newItem(courseID: course.id)) }
                Divider()
                Button("Delete course", systemImage: "trash", role: .destructive) { confirmCourseDelete = true }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }
}

/// The course's session, kept for one revision of the store, so the page redraws without building it again. Not observed: the view reads
/// it while it draws, and the revision is what moves it.
@MainActor
final class CourseStudyCache {
    private var revision: Int?
    private var study: CourseStudy?

    func value(revision: Int, make: () -> CourseStudy?) -> CourseStudy? {
        if self.revision != revision {
            self.revision = revision
            study = make()
        }
        return study
    }
}

// MARK: - Pieces

/// A topic's quiet "practice it" mark: a small grey play, so the page keeps one orange button (Study).
private struct CoursePlayGlyph: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(CLColor.ink3)
            .frame(width: 28, height: 28)
            .background(CLColor.surface3, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The course's head: its badge, the next exam ("Midterm · Tue 1 Dec") and that exam's readiness ring, the course's one number; a tap
/// opens the exam. With no exam to come, "No exam yet". Under it the other exams as chips with "Add exam", and the session: "Study Bio 101
/// · 15 min", or "Add material" with nothing to study. The tab bar's + adds material to this course, so there is no second + here.
private struct CourseHeader: View {
    let model: LibraryCourseModel
    let chips: [LibraryFormat.ExamChip]
    let study: CourseStudy?
    var openExam: () -> Void
    var openChip: (LibraryFormat.ExamChip) -> Void
    var start: () -> Void
    var addMaterial: () -> Void
    var addExam: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let readiness = model.readiness, let line = model.headerLine {
                Button(action: openExam) {
                    ReflowStack(spacing: 14) {
                        CLIconBadge(systemImage: model.symbol, tint: model.color, size: 56)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(verbatim: line).clFont(.headline).foregroundStyle(CLColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CLColor.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ReadinessRing(value: readiness, size: 76, lineWidth: 9, caption: "ready", animatesFromZero: true)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: line))
                .accessibilityValue(Text(model.readinessAccessibility))
                .accessibilityHint(Text("Opens the exam"))
                .accessibilityAddTraits(.isButton)
            } else {
                ReflowStack(spacing: 14) {
                    CLIconBadge(systemImage: model.symbol, tint: model.color, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No exam yet").clFont(.headline).foregroundStyle(CLColor.ink)
                        Text("Add one to see how ready you are.")
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
            CaptureChips {
                ForEach(chips) { chip in
                    CourseExamChip(chip: chip) { openChip(chip) }
                }
                LibraryAddExamButton(courseName: model.name, action: addExam)
            }
            if let study {
                Button(action: start) {
                    FittingLabel(titles: [study.title], systemImage: "play.fill")
                }
                .buttonStyle(.cl(.primary))
            } else {
                Button(action: addMaterial) {
                    FittingLabel(titles: [String(localized: "Add material")], systemImage: "plus")
                }
                .buttonStyle(.cl(.primary))
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Another exam of the course, as a chip: "Final · Dec 14", "Quiz · log your grade", "Quiz · you got 91%".
private struct CourseExamChip: View {
    let chip: LibraryFormat.ExamChip
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(verbatim: chip.text).fixedSize(horizontal: false, vertical: true)
            }
            .clFont(.footnoteEmphasis)
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(minHeight: CLMetrics.minHitTarget)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private var symbol: String {
        switch chip.state {
        case .upcoming: "calendar"
        case .logGrade: "pencil.and.list.clipboard"
        case .graded: "checkmark.seal"
        }
    }

    private var ink: Color { chip.state == .logGrade ? CLColor.sunInk : CLColor.ink }
    private var fill: Color { chip.state == .logGrade ? CLColor.sunSoft : CLColor.surface }
}
