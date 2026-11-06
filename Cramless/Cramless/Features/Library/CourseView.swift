import SwiftUI

/// One course: its next exam's readiness ring (or "Add a date"), a chip for each exam, "Study Bio 101 · 15 min", and three tabs. Topics:
/// readiness for the next exam, gaps, and "Not on the Midterm" apart; a tap shows that topic's questions, Practice is its own button.
/// Sources. Questions: filter by what needs attention, what is suspended, format and topic; tap to edit, swipe to suspend or delete.
///
/// Harness: `CRAMLESS_ROUTE=course:<n>` opens the nth course (`course:3` is Spanish II, with no exam); `CRAMLESS_SCENARIO=past`
/// first moves the soonest exam three days back. `CRAMLESS_COURSE_TAB=topics|sources|questions` opens on a tab;
/// `CRAMLESS_COURSE_FILTER=attention|suspended|<kind>|topic:<n>` opens Questions with that filter; `CRAMLESS_SCROLL=tabs` brings the
/// tabs to the top (the header is tall at the largest text size).
struct CourseView: View {
    let courseID: UUID

    @Environment(AppModel.self) private var app
    @State private var tab = CourseTab.topics
    @State private var filter = CourseQuestions.Filter.all
    @State private var topicFilter: UUID?
    @State private var itemToDelete: UUID?
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
                                             examTitle: next?.title, courseName: course.name)
        let topicNames = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.name) })
        let topicOrder = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($0.element.id, $0.offset) })
        let items = course.liveItems.filter { $0.status == .active || $0.status == .suspended }
            .sorted {
                CourseQuestions.comesBefore(topicA: $0.topicID.flatMap { topicOrder[$0] } ?? Int.max, createdA: $0.createdAt, idA: $0.id,
                                            topicB: $1.topicID.flatMap { topicOrder[$0] } ?? Int.max, createdB: $1.createdAt, idB: $1.id)
            }
        let model = LibraryCourseModel(course: course, app: app)
        let sources = course.liveSources.sorted { $0.createdAt > $1.createdAt }
        let questionCounts = Dictionary(grouping: items.compactMap { $0.sourceRef?.sourceID }, by: { $0 }).mapValues(\.count)
        let chips = LibraryFormat.examChips(course.liveExams.map { exam in
            LibraryFormat.ChipExam(id: exam.id, title: exam.title, date: exam.date,
                                   readiness: exam.date > app.now ? app.readinessValue(of: ExamSnapshot(exam)) : nil, result: exam.resultScore)
        }, courseName: course.name, now: app.now, calendar: app.calendar)
        let session = study.value(revision: app.revision) { app.courseStudy(course) }

        return ScrollViewReader { proxy in List {
            Section {
                CourseHeader(model: model, chips: chips, study: session, openChip: openChip, start: { start(session) }, addMaterial: {
                    app.router.present(.capture(courseID: course.id))
                }, addDate: {
                    app.router.present(.newExam(courseID: course.id))
                })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            }
            Section {
                CourseTabs(selection: $tab, sources: sources.count, questions: items.count)
                    .id("tabs")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            switch tab {
            case .topics: topicsTab(lines, course: course, exam: next)
            case .sources: sourcesTab(sources, course: course, counts: questionCounts)
            case .questions: questionsTab(items: items, lines: lines, topicNames: topicNames, course: course)
            }
        }
        .harnessScroll(proxy) }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .clScreenBackground()
        .environment(\.defaultMinListRowHeight, CLMetrics.minHitTarget)
        .captureDebugCanvas()
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar(course) }
        #if DEBUG
        .task {
            app.applyHarnessScenarioOnce(examID: app.upcomingExams().first?.id)
            if let name = TestHarness.once("CRAMLESS_COURSE_TAB"), let shown = CourseTab(rawValue: name) { tab = shown }
            if let name = TestHarness.once("CRAMLESS_COURSE_FILTER") {
                tab = .questions
                if name.hasPrefix("topic:"), let index = Int(name.dropFirst(6)) {
                    let withQuestions = lines.filter { $0.questionCount > 0 }
                    if withQuestions.indices.contains(index) { topicFilter = withQuestions[index].id }
                } else if let chosen = CourseQuestions.filter(named: name) {
                    filter = chosen
                }
            }
        }
        #endif
        .confirmationDialog("Delete this question?", isPresented: Binding(
            get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete question", role: .destructive) {
                if let id = itemToDelete { withAnimation(CLMotion.settle) { app.deleteItems([id]) } }
                itemToDelete = nil
            }
        } message: {
            Text("It leaves your sessions and readiness for good.")
        }
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
                if let id = topicToDelete?.id {
                    if topicFilter == id { topicFilter = nil }
                    app.deleteTopic(id)
                }
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

    private func openChip(_ chip: LibraryFormat.ExamChip) {
        CLHaptics.tap()
        switch chip.state {
        case .upcoming, .graded: app.router.push(.exam(chip.id))
        case .logGrade: app.router.present(.logGrade(examID: chip.id))
        }
    }

    // MARK: Topics

    @ViewBuilder
    private func topicsTab(_ topics: [LibraryFormat.TopicLine], course: Course, exam: Exam?) -> some View {
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
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let exam, topics.contains(where: { if case .value = $0.state { true } else { false } }) {
                    Text(verbatim: LibraryFormat.topicsFootnote(examTitle: exam.title, courseName: course.name, date: exam.date,
                                                                calendar: app.calendar))
                }
                if gaps > 0 {
                    Text("\(gaps) topics have no material yet. Add some and they join your sessions.")
                }
            }
            .clFont(.footnote)
            .foregroundStyle(CLColor.ink2)
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

    private func topicRow(_ topic: LibraryFormat.TopicLine, course: Course) -> some View {
        ReflowStack(verticalAlignment: .center, spacing: 10) {
            if topic.questionCount > 0 {
                Button {
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) {
                        topicFilter = topic.id
                        filter = .all
                        tab = .questions
                    }
                } label: {
                    LibraryTopicRow(name: topic.name, state: topic.state, questionCount: topic.questionCount)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows this topic's questions"))
                Button {
                    CLHaptics.tap()
                    app.router.present(.session(SessionRequest(kind: .practice, courseID: course.id, topicID: topic.id)))
                } label: {
                    Text("Practice")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.tangerineInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: CLMetrics.minHitTarget)
                        .background(CLColor.tangerineSoft, in: Capsule())
                        .fixedSize()
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Practice \(topic.name)"))
            } else {
                LibraryTopicRow(name: topic.name, state: topic.state, questionCount: 0,
                                onAdd: { app.router.present(.capture(courseID: course.id)) })
            }
        }
        .listRowBackground(CLColor.surface)
        .contextMenu {
            if topic.questionCount > 0 {
                Button("Practice this topic", systemImage: "play") {
                    app.router.present(.session(SessionRequest(kind: .practice, courseID: course.id, topicID: topic.id)))
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

    @ViewBuilder
    private func sourcesTab(_ sources: [Source], course: Course, counts: [UUID: Int]) -> some View {
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
        }
    }

    // MARK: Questions

    @ViewBuilder
    private func questionsTab(items: [StudyItem], lines: [LibraryFormat.TopicLine], topicNames: [UUID: String], course: Course) -> some View {
        let rows = app.courseQuestionRows(items)
        let counts = CourseQuestions.counts(rows, topic: topicFilter)
        let shown = CourseQuestions.filtered(rows, filter: filter, topic: topicFilter)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        Section {
            QuestionFilters(counts: counts, topics: lines, filter: $filter, topic: $topicFilter)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
            if shown.isEmpty {
                Text(emptyLine(hasQuestions: !items.isEmpty))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .listRowBackground(CLColor.surface)
            }
            ForEach(shown) { row in
                if let item = byID[row.id] {
                    questionRow(item, row: row, topicNames: topicNames, course: course)
                }
            }
            Button {
                app.router.present(.newItem(courseID: course.id))
            } label: {
                Label("Write a question", systemImage: "square.and.pencil")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
            }
            .listRowBackground(CLColor.surface)
        } footer: {
            Text("Swipe a question to suspend it or delete it. Questions you write are free and unlimited.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
        }
    }

    private func emptyLine(hasQuestions: Bool) -> LocalizedStringResource {
        guard hasQuestions else { return "No questions yet. Add material, or write your own." }
        return filter == .attention ? "Nothing needs attention right now." : "No questions match these filters."
    }

    private func questionRow(_ item: StudyItem, row: CourseQuestions.Row, topicNames: [UUID: String], course: Course) -> some View {
        let suspended = item.status == .suspended
        return Button {
            app.router.present(.editItem(item.id))
        } label: {
            LibraryItemRow(kind: item.kind, prompt: item.kind == .cloze ? (item.cloze.map { LibraryFormat.clozeDisplay($0.text) } ?? item.prompt) : item.prompt,
                           detail: detail(for: item, row: row, topicNames: topicNames), tint: course.color, suspended: suspended)
        }
        .buttonStyle(.plain)
        .listRowBackground(CLColor.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                itemToDelete = item.id
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            Button {
                withAnimation(CLMotion.snap) { app.setSuspended([item.id], !suspended) }
            } label: {
                Label(suspended ? "Resume" : "Suspend", systemImage: suspended ? "play.fill" : "pause.fill")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { app.router.present(.editItem(item.id)) }
            Button(suspended ? "Resume" : "Suspend", systemImage: suspended ? "play" : "pause") {
                app.setSuspended([item.id], !suspended)
            }
            if let ref = item.sourceRef, let page = ref.pageIndex {
                Button("Show on the page", systemImage: "doc.text.magnifyingglass") {
                    app.router.push(.sourcePage(sourceID: ref.sourceID, pageIndex: page, highlight: ref.anchorIDs))
                }
            }
            Button("Looks wrong?", systemImage: "exclamationmark.bubble") {
                app.router.present(.looksWrong(itemID: item.id, given: ""))
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { itemToDelete = item.id }
        }
    }

    private func detail(for item: StudyItem, row: CourseQuestions.Row, topicNames: [UUID: String]) -> String {
        var parts: [String] = []
        if let topic = item.topicID.flatMap({ topicNames[$0] }) { parts.append(topic) } else { parts.append(item.kind.displayName) }
        // The reason takes the source's place here: a third part wraps on most phones.
        if item.reported {
            parts.append(String(localized: "waiting for Cap's check"))
        } else if filter == .attention {
            parts.append(row.inMixUp ? String(localized: "in a mix-up") : String(localized: "fading"))
        } else if let label = item.sourceRef?.label, !label.isEmpty {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private func toolbar(_ course: Course) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Edit course", systemImage: "pencil") { app.router.present(.editCourse(course.id)) }
                Button("New exam", systemImage: "calendar.badge.plus") { app.router.present(.newExam(courseID: course.id)) }
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

/// The course's session, kept for one revision of the store, so a filter or a tab redraws without building it again. Not observed: the
/// view reads it while it draws, and the revision is what moves it.
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

enum CourseTab: String, Hashable, CaseIterable {
    case topics, sources, questions
}

/// Topics, Sources 4, Questions 36: a segmented control, or three chips at the accessibility text sizes, where its labels wouldn't fit.
private struct CourseTabs: View {
    @Binding var selection: CourseTab
    let sources: Int
    let questions: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            CaptureChips {
                chip(.topics, "Topics")
                chip(.sources, "Sources \(sources)")
                chip(.questions, "Questions \(questions)")
            }
        } else {
            Picker("Show", selection: Binding(get: { selection }, set: { new in
                CLHaptics.select()
                withAnimation(CLMotion.settle) { selection = new }
            })) {
                Text("Topics").tag(CourseTab.topics)
                Text("Sources \(sources)").tag(CourseTab.sources)
                Text("Questions \(questions)").tag(CourseTab.questions)
            }
            .pickerStyle(.segmented)
        }
    }

    private func chip(_ tab: CourseTab, _ title: LocalizedStringResource) -> some View {
        Button {
            CLHaptics.select()
            withAnimation(CLMotion.settle) { selection = tab }
        } label: {
            CLChip(title: title, selected: selection == tab)
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The course's head: its badge, what's in it and the next exam's readiness ring (the course's one number), a chip for each exam, and the
/// session: "Study Bio 101 · 15 min" with a round + beside it. With no exam to come, "Add a date" and what it brings instead of a ring;
/// with nothing to study, "Add material".
private struct CourseHeader: View {
    let model: LibraryCourseModel
    let chips: [LibraryFormat.ExamChip]
    let study: CourseStudy?
    var openChip: (LibraryFormat.ExamChip) -> Void
    var start: () -> Void
    var addMaterial: () -> Void
    var addDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReflowStack(spacing: 14) {
                CLIconBadge(systemImage: model.symbol, tint: model.color, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    if model.readiness == nil {
                        Text(model.examLine).clFont(.headline).foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(LibraryFormat.courseCounts(sources: model.sources, questions: model.questions))
                        .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let readiness = model.readiness {
                    ReadinessRing(value: readiness, size: 76, lineWidth: 9, caption: "ready", animatesFromZero: true)
                        .accessibilityLabel(Text(model.name))
                        .accessibilityValue(Text(model.readinessAccessibility))
                }
            }
            if model.readiness == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add an exam date and Capling shows how ready you are.")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    LibraryAddDateButton(courseName: model.name, action: addDate)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
            }
            if !chips.isEmpty {
                CaptureChips {
                    ForEach(chips) { chip in
                        CourseExamChip(chip: chip) { openChip(chip) }
                    }
                    if model.readiness != nil {
                        LibraryAddDateButton(courseName: model.name, action: addDate)
                    }
                }
            }
            ReflowStack(spacing: 10) {
                if let study {
                    Button(action: start) {
                        FittingLabel(titles: [study.title], systemImage: "play.fill")
                    }
                    .buttonStyle(.cl(.primary))
                    Button(action: addMaterial) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CLColor.ink)
                            .frame(width: 52, height: 52)
                            .background(CLColor.surface3, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text("Add material"))
                } else {
                    Button(action: addMaterial) {
                        FittingLabel(titles: ["Add material"], systemImage: "plus")
                    }
                    .buttonStyle(.cl(.primary))
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// One exam of the course, as a chip: "Midterm · Nov 29 · 53% ready", "Quiz · log your grade", "Quiz · you got 91%".
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

/// Filter chips over the questions: a topic menu, all, what needs attention, what's suspended (only when any is), and each format present.
private struct QuestionFilters: View {
    let counts: CourseQuestions.Counts
    let topics: [LibraryFormat.TopicLine]
    @Binding var filter: CourseQuestions.Filter
    @Binding var topic: UUID?

    var body: some View {
        let kinds = ItemKind.allCases.filter { (counts.kinds[$0] ?? 0) > 0 }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All topics") { pick(topic: nil) }
                    ForEach(topics.filter { $0.questionCount > 0 }) { t in
                        Button { pick(topic: t.id) } label: {
                            if topic == t.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                } label: {
                    CLChip(title: topics.first { $0.id == topic }.map { .verbatim($0.name) } ?? "All topics", systemImage: "line.3.horizontal.decrease",
                           selected: topic != nil)
                        .frame(minHeight: CLMetrics.minHitTarget)
                }
                chip("All \(counts.all)", .all)
                chip("Needs attention \(counts.attention)", .attention)
                if counts.suspended > 0 || filter == .suspended {
                    chip("Suspended \(counts.suspended)", .suspended)
                }
                ForEach(kinds) { kind in
                    chip("\(kind.shortName) \(counts.kinds[kind] ?? 0)", .kind(kind))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private func pick(topic id: UUID?) {
        CLHaptics.select()
        withAnimation(CLMotion.snap) { topic = id }
    }

    private func chip(_ title: LocalizedStringResource, _ value: CourseQuestions.Filter) -> some View {
        Button {
            CLHaptics.select()
            withAnimation(CLMotion.snap) { filter = filter == value && value != .all ? .all : value }
        } label: {
            CLChip(title: title, selected: filter == value)
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
