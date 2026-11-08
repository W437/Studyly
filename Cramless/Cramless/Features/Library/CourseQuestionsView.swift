import SwiftUI

/// A course's questions, from the course page's last row ("All 36 questions") or a topic's "Show its questions": filter by topic, what needs
/// attention, what is suspended and format; tap to edit, swipe to suspend or delete; "Write a question" at the end.
///
/// Harness (with `CRAMLESS_ROUTE=course[:<n>]`): `CRAMLESS_COURSE_TAB=questions` opens it over the course page;
/// `CRAMLESS_COURSE_FILTER=attention|suspended|<kind>|topic:<n>` opens it with that filter (`topic:<n>`: the nth topic with questions).
struct CourseQuestionsView: View {
    let courseID: UUID
    var topicID: UUID?

    @Environment(AppModel.self) private var app
    @State private var filter = CourseQuestions.Filter.all
    @State private var topicFilter: UUID?
    @State private var itemToDelete: UUID?
    @State private var loaded = false

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
        let rows = app.courseQuestionRows(items)
        let counts = CourseQuestions.counts(rows, topic: topicFilter)
        let shown = CourseQuestions.filtered(rows, filter: filter, topic: topicFilter)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        return List {
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
                Text("Swipe a question to suspend it or delete it.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .clScreenBackground()
        .environment(\.defaultMinListRowHeight, CLMetrics.minHitTarget)
        .captureDebugCanvas()
        .navigationTitle("Questions")
        .navigationSubtitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            topicFilter = topicID
            #if DEBUG
            if let name = TestHarness.once("CRAMLESS_COURSE_FILTER") {
                if name.hasPrefix("topic:"), let index = Int(name.dropFirst(6)) {
                    let withQuestions = lines.filter { $0.questionCount > 0 }
                    if withQuestions.indices.contains(index) { topicFilter = withQuestions[index].id }
                } else if let chosen = CourseQuestions.filter(named: name) {
                    filter = chosen
                }
            }
            #endif
        }
        .confirmationDialog("Delete this question?", isPresented: Binding(
            get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete question", role: .destructive) {
                if let id = itemToDelete { withAnimation(CLMotion.settle) { app.deleteItems([id]) } }
                itemToDelete = nil
            }
        } message: {
            Text("It leaves your sessions and readiness for good.")
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
            parts.append(row.inMixUp ? String(localized: "often confused") : String(localized: "to review"))
        } else if let label = item.sourceRef?.label, !label.isEmpty {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }
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
                    chip("\(kind.displayName) \(counts.kinds[kind] ?? 0)", .kind(kind))
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
