import SwiftUI

/// One course: its header (the next exam and its readiness ring, or "Add a date"), exams, the topics (readiness for the next exam,
/// coverage gaps, "Not on the Midterm"), sources, and the questions (filter by topic and format; tap to edit; swipe to suspend or
/// delete).
///
/// Harness: `CRAMLESS_ROUTE=course:<n>` opens the nth course (`course:3` is Spanish II, with no exam); `CRAMLESS_SCENARIO=past`
/// first moves the soonest exam three days back.
struct CourseView: View {
    let courseID: UUID

    @Environment(AppModel.self) private var app
    @State private var formatFilter: ItemKind?
    @State private var topicFilter: UUID?
    @State private var itemToDelete: UUID?
    @State private var confirmCourseDelete = false
    @State private var topicEditor: TopicEditor?
    @State private var topicName = ""
    @State private var topicToDelete: LibraryFormat.TopicLine?

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
        let courseTopics = app.courseTopics(course)
        let next = app.nextExam(of: course.id)
        let lines = LibraryFormat.topicLines(courseTopics: courseTopics, examTopics: next.map { app.topicReadiness(for: $0) },
                                             examTitle: next?.title, courseName: course.name)
        let topics = lines
        let topicNames = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.name) })
        let topicOrder = Dictionary(uniqueKeysWithValues: topics.enumerated().map { ($0.element.id, $0.offset) })
        let items = course.liveItems.filter { $0.status == .active || $0.status == .suspended }
            .sorted {
                let a = $0.topicID.flatMap { topicOrder[$0] } ?? Int.max, b = $1.topicID.flatMap { topicOrder[$0] } ?? Int.max
                return a != b ? a < b : $0.createdAt < $1.createdAt
            }
        let filtered = items.filter { (formatFilter == nil || $0.kind == formatFilter) && (topicFilter == nil || $0.topicID == topicFilter) }
        let model = LibraryCourseModel(course: course, app: app)
        let sources = course.liveSources.sorted { $0.createdAt > $1.createdAt }
        let questionCounts = Dictionary(grouping: items.compactMap { $0.sourceRef?.sourceID }, by: { $0 }).mapValues(\.count)
        let exams = course.liveExams
        // Live readiness for the exams still to come; one that has started (or passed) shows its grade instead.
        let readiness = Dictionary(uniqueKeysWithValues: exams.filter { $0.date > app.now }
            .map { ($0.id, app.readinessValue(of: ExamSnapshot($0))) })

        return ScrollViewReader { proxy in
            List {
                Section {
                    CourseHeader(model: model, canPractice: items.contains { $0.status == .active }) {
                        app.router.present(.session(SessionRequest(kind: .practice, courseID: course.id)))
                    } addMaterial: {
                        app.router.present(.capture(courseID: course.id))
                    } addDate: {
                        app.router.present(.newExam(courseID: course.id))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                }

                examsSection(exams, course: course, readiness: readiness)
                topicsSection(topics, course: course, exam: next, proxy: proxy)
                sourcesSection(sources, course: course, counts: questionCounts)
                questionsSection(items: items, filtered: filtered, topics: topics, topicNames: topicNames, course: course)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .scrollContentBackground(.hidden)
            .clScreenBackground()
            .environment(\.defaultMinListRowHeight, CLMetrics.minHitTarget)
            .harnessScroll(proxy)
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar(course) }
            #if DEBUG
            .task { app.applyHarnessScenarioOnce(examID: app.upcomingExams().first?.id) }
            #endif
            .animation(CLMotion.settle, value: filtered.map(\.id))
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
    }

    // MARK: Sections

    @ViewBuilder
    private func examsSection(_ exams: [Exam], course: Course, readiness: [UUID: Double]) -> some View {
        Section {
            ForEach(exams) { exam in
                NavigationLink(value: Route.exam(exam.id)) {
                    CourseExamRow(title: exam.title, date: exam.date, readiness: readiness[exam.id],
                                  result: exam.resultScore, now: app.now, calendar: app.calendar)
                }
                .listRowBackground(CLColor.surface)
                .id(exam.id == exams.first?.id ? AnyHashable("exams") : AnyHashable(exam.id))
            }
            Button {
                app.router.present(.newExam(courseID: course.id))
            } label: {
                Label("New exam", systemImage: "calendar.badge.plus")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
            }
            .listRowBackground(CLColor.surface)
        } header: {
            LibrarySectionTitle(title: "Exams")
        }
    }

    @ViewBuilder
    private func topicsSection(_ topics: [LibraryFormat.TopicLine], course: Course, exam: Exam?, proxy: ScrollViewProxy) -> some View {
        let gaps = topics.filter { $0.state == .gap }.count
        Section {
            ForEach(topics) { topic in
                Button {
                    CLHaptics.select()
                    withAnimation(CLMotion.snap) {
                        topicFilter = topicFilter == topic.id ? nil : topic.id
                        formatFilter = nil
                    }
                    if topic.questionCount > 0 {
                        withAnimation(CLMotion.calm) { proxy.scrollTo("questions", anchor: .top) }
                    }
                } label: {
                    LibraryTopicRow(name: topic.name, state: topic.state, questionCount: topic.questionCount,
                                    onAdd: topic.state == .gap ? { app.router.present(.capture(courseID: course.id)) } : nil)
                }
                .buttonStyle(.plain)
                .listRowBackground(topicFilter == topic.id ? CLColor.surface2 : CLColor.surface)
                .id(topic.id == topics.first?.id ? AnyHashable("topics") : AnyHashable(topic.id))
                .accessibilityHint(Text(topic.questionCount > 0 ? "Shows this topic's questions" : ""))
                .contextMenu {
                    if topic.questionCount > 0 {
                        Button("Practice this topic", systemImage: "play") {
                            app.router.present(.session(SessionRequest(kind: .practice, courseID: course.id, topicID: topic.id)))
                        }
                    }
                    Button("Rename", systemImage: "pencil") { topicName = topic.name; topicEditor = TopicEditor(topicID: topic.id) }
                    Button("Delete topic", systemImage: "trash", role: .destructive) { topicToDelete = topic }
                }
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
            LibrarySectionTitle(title: "Topics")
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
    }

    @ViewBuilder
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
                .id(source.id == sources.first?.id ? AnyHashable("sources") : AnyHashable(source.id))
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
            LibrarySectionTitle(title: "Sources")
        }
    }

    @ViewBuilder
    private func questionsSection(items: [StudyItem], filtered: [StudyItem], topics: [LibraryFormat.TopicLine],
                                  topicNames: [UUID: String], course: Course) -> some View {
        Section {
            QuestionFilters(items: items, topics: topics, format: $formatFilter, topic: $topicFilter)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
                .id("questions")
            if filtered.isEmpty {
                Text(items.isEmpty ? "No questions yet. Add material, or write your own." : "No questions match these filters.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .listRowBackground(CLColor.surface)
            }
            ForEach(filtered) { item in
                let suspended = item.status == .suspended
                Button {
                    app.router.present(.editItem(item.id))
                } label: {
                    LibraryItemRow(kind: item.kind, prompt: item.kind == .cloze ? (item.cloze.map { LibraryFormat.clozeDisplay($0.text) } ?? item.prompt) : item.prompt,
                                   detail: detail(for: item, topicNames: topicNames), tint: course.color, suspended: suspended)
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
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { itemToDelete = item.id }
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
        } header: {
            LibrarySectionTitle(title: "Questions")
        } footer: {
            Text("Swipe a question to suspend it or delete it. Questions you write are free and unlimited.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
        }
    }

    private func detail(for item: StudyItem, topicNames: [UUID: String]) -> String {
        var parts: [String] = []
        if let topic = item.topicID.flatMap({ topicNames[$0] }) { parts.append(topic) } else { parts.append(item.kind.displayName) }
        if let label = item.sourceRef?.label, !label.isEmpty { parts.append(label) }
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

// MARK: - Pieces

/// The course header: badge, next exam, counts and that exam's readiness ring (the course's one number), then Practice and Add
/// material. With no exam to come, "Add a date" and what it brings instead of a ring.
private struct CourseHeader: View {
    let model: LibraryCourseModel
    let canPractice: Bool
    var practice: () -> Void
    var addMaterial: () -> Void
    var addDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReflowStack(spacing: 14) {
                CLIconBadge(systemImage: model.symbol, tint: model.color, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.examLine).clFont(.headline).foregroundStyle(CLColor.ink)
                    Text(LibraryFormat.courseCounts(sources: model.sources, questions: model.questions))
                        .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let readiness = model.readiness {
                    ReadinessRing(value: readiness, size: 76, lineWidth: 9, caption: "ready", animatesFromZero: true)
                        .accessibilityLabel(Text(model.name))
                        .accessibilityValue(Text(model.readinessAccessibility))
                }
            }
            if model.readiness == nil {
                HStack(alignment: .center, spacing: 12) {
                    Text("Add an exam date and Capling shows how ready you are.")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LibraryAddDateButton(courseName: model.name, action: addDate)
                }
                .padding(14)
                .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
            }
            ReflowStack(spacing: 10) {
                Button(action: practice) {
                    FittingLabel(titles: ["Practice"], systemImage: "play.fill")
                }
                .buttonStyle(.cl(.primary, size: .medium))
                .disabled(!canPractice)
                Button(action: addMaterial) {
                    FittingLabel(titles: ["Add material", "Add"], systemImage: "plus")
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
        }
        .padding(.horizontal, 4)
    }
}

/// An exam in the course: its readiness ring, date and countdown (or its logged grade).
private struct CourseExamRow: View {
    let title: String
    let date: Date
    let readiness: Double?
    let result: Double?
    let now: Date
    let calendar: Calendar

    var body: some View {
        let days = calendar.dayDistance(from: now, to: date)
        HStack(spacing: 12) {
            if let readiness {
                ReadinessRing(value: readiness, size: 42, lineWidth: 5, showsLabel: false)
                    .accessibilityHidden(true)
            } else {
                CLIconBadge(systemImage: result == nil ? "pencil.and.list.clipboard" : "checkmark.seal", tint: result == nil ? .sun : .mint, size: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                Text(subtitle(days: days)).clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(days: Int) -> String {
        let day = CLFormat.day(date, calendar: calendar)
        if days >= 0, let readiness {
            return "\(day) · \(LibraryFormat.countdown(days: days)) · \(CLFormat.percent(readiness)) ready"
        }
        if let result { return "\(day) · you got \(CLFormat.percent(result))" }
        return "\(day) · log your grade"
    }
}

/// Filter chips over the questions: all, each format present, and a topic menu.
private struct QuestionFilters: View {
    let items: [StudyItem]
    let topics: [LibraryFormat.TopicLine]
    @Binding var format: ItemKind?
    @Binding var topic: UUID?

    var body: some View {
        let counts = Dictionary(grouping: items, by: \.kind).mapValues(\.count)
        let kinds = ItemKind.allCases.filter { (counts[$0] ?? 0) > 0 }
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
                chip("All \(items.count)", selected: format == nil) { format = nil }
                ForEach(kinds) { kind in
                    chip("\(kind.shortName) \(counts[kind] ?? 0)", selected: format == kind) { format = format == kind ? nil : kind }
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

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            CLHaptics.select()
            withAnimation(CLMotion.snap, action)
        } label: {
            CLChip(title: .verbatim(title), selected: selected)
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

