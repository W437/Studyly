import SwiftUI

/// Write a question, or edit one, in one layout: the question first, its format as one row, then its answer in the form the format needs
/// (key ideas with the other ways to say each folded under them, choices with the right one marked, a fill-in's sentence with the
/// blanks in [brackets], as in the review's editor), the explanation, course and topic; an existing question adds suspend, its source
/// and delete. The source chip opens the page it came from. No AI involved.
struct ItemEditorView: View {
    let itemID: UUID?
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ItemDraft.blank()
    @State private var chosenCourseID: UUID?
    @State private var newCourseName = ""
    @State private var pendingTopicName: String?
    @State private var topicNameInput = ""
    @State private var askingTopic = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var path: [Route] = []
    /// Key ideas whose other ways of saying them are open.
    @State private var openIdeas: Set<String> = []

    var body: some View {
        let item = app.item(itemID)
        let courses = app.courses
        let course = item?.course ?? app.course(chosenCourseID)
        let topics = course?.liveTopics ?? []
        let isDiagram = item?.kind == .diagram
        let gone = itemID != nil && (item == nil || item?.deletedAt != nil)

        NavigationStack(path: $path) {
            Form {
                if gone {
                    Text("This question was deleted.").clFont(.body).foregroundStyle(CLColor.ink2)
                } else {
                    questionSection
                    formatSection(isDiagram: isDiagram)
                    switch draft.kind {
                    case .flashcard: answerSection(title: "Back", placeholder: "Definition or answer")
                    case .recall, .apply:
                        answerSection(title: "Model answer", placeholder: "What a full answer says")
                        ideasSection
                    case .mcq: choicesSection
                    case .cloze: clozeSection
                    case .diagram: diagramSection(item)
                    }
                    explanationSection
                    if itemID == nil && courseID == nil { courseSection(courses) }
                    topicSection(topics, course: course)
                    if item != nil { suspendSection }
                    if let ref = item?.sourceRef { sourceSection(ref) }
                    if item != nil { deleteSection }
                }
            }
            .scrollContentBackground(.hidden)
            .clScreenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(itemID == nil ? "Write a question" : "Edit question")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in RouteDestination(route: route) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(itemID == nil ? "Add" : "Save") { save(course: course) }
                        .disabled(gone || blocker(course: course) != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !gone, let blocker = blocker(course: course), hasStarted {
                    Label(blocker, systemImage: "info.circle")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .animation(CLMotion.settle, value: draft.kind)
            .alert("New topic", isPresented: $askingTopic) {
                TextField("Topic name", text: $topicNameInput)
                Button("Cancel", role: .cancel) {}
                Button("Use it") {
                    let clean = topicNameInput.clTrimmed
                    guard !clean.isEmpty else { return }
                    if let existing = topics.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
                        draft.topicID = existing.id
                        pendingTopicName = nil
                    } else {
                        draft.topicID = nil
                        pendingTopicName = clean
                    }
                }
            } message: {
                Text("It's added to the course when you save.")
            }
            .confirmationDialog("Delete this question?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete question", role: .destructive) {
                    if let itemID { app.deleteItems([itemID]) }
                    dismiss()
                }
            } message: {
                Text("It leaves your sessions and readiness for good.")
            }
        }
        .presentationDetents([.large])
        .presentationBackground(CLColor.background)
        .interactiveDismissDisabled(hasChanges(item))
        .onAppear { load(item, courses: courses) }
    }

    // MARK: Sections

    /// The format, as one row (a diagram's is fixed: its labels come from a page).
    private func formatSection(isDiagram: Bool) -> some View {
        Section {
            if isDiagram {
                LabeledContent("Format") {
                    Text(ItemKind.diagram.displayName).foregroundStyle(CLColor.ink2)
                }
                .clFont(.body)
            } else {
                Picker("Format", selection: Binding(get: { draft.kind }, set: { kind in
                    CLHaptics.select()
                    draft.kind = kind
                    draft.prepareRows()
                })) {
                    ForEach(ItemDraft.writableKinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .clFont(.body)
                .tint(CLColor.tangerineInk)
            }
        } footer: {
            Text(draft.kind.editorHint)
        }
        .listRowBackground(CLColor.surface)
    }

    private var questionSection: some View {
        Section(draft.kind == .flashcard ? "Front" : draft.kind == .apply ? "Situation" : draft.kind == .cloze ? "Instruction" : "Question") {
            TextField(promptPlaceholder, text: $draft.prompt, axis: .vertical)
                .clFont(.body)
                .lineLimit(1...8)
        }
        .listRowBackground(CLColor.surface)
    }

    private var promptPlaceholder: String {
        switch draft.kind {
        case .flashcard: "Term or question"
        case .recall: "In your own words: why do cells divide?"
        case .apply: "A drug stops spindle fibres forming. Which phase can't happen, and why?"
        case .mcq: "Which phase comes right before cytokinesis?"
        case .cloze: ItemDraft.defaultClozePrompt
        case .diagram: "Name the labelled parts"
        }
    }

    private func answerSection(title: String, placeholder: String) -> some View {
        Section(title) {
            TextField(placeholder, text: $draft.answer, axis: .vertical)
                .clFont(.body)
                .lineLimit(1...8)
        }
        .listRowBackground(CLColor.surface)
    }

    private var ideasSection: some View {
        Section {
            ForEach($draft.ideas) { $idea in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CLColor.sunInk)
                            .accessibilityHidden(true)
                        TextField("Key idea", text: $idea.label, axis: .vertical)
                            .clFont(.bodyEmphasis)
                            .lineLimit(1...4)
                        if draft.ideas.count > 1 {
                            RemoveButton(label: "Remove key idea") { remove(idea: idea.id) }
                        }
                    }
                    otherWays(of: $idea)
                        .padding(.leading, 21)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                guard draft.ideas.count - offsets.count >= 1 else { return }
                draft.ideas.remove(atOffsets: offsets)
            }
            Button {
                withAnimation(CLMotion.settle) { draft.addIdea() }
            } label: {
                Label("Add a key idea", systemImage: "plus.circle.fill")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
            }
        } header: {
            Text("Key ideas")
        } footer: {
            Text("A good answer hits each key idea. Other ways to say it count too.")
        }
        .listRowBackground(CLColor.surface)
    }

    /// A key idea's accepted phrasings, folded: "Other ways to say it (6)" opens the list to edit.
    private func otherWays(of idea: Binding<ItemDraft.Idea>) -> some View {
        let id = idea.wrappedValue.id
        let count = ItemDraft.split(idea.wrappedValue.phrasings).count
        return DisclosureGroup(isExpanded: Binding(get: { openIdeas.contains(id) }, set: { open in
            withAnimation(CLMotion.settle) { if open { openIdeas.insert(id) } else { openIdeas.remove(id) } }
        })) {
            TextField("Other ways to say it, separated by commas", text: idea.phrasings, axis: .vertical)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .lineLimit(1...6)
                .padding(.top, 4)
        } label: {
            Text(count > 0 ? "Other ways to say it (\(count))" : "Other ways to say it")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink2)
        }
        .tint(CLColor.ink3)
    }

    private var choicesSection: some View {
        Section {
            ForEach($draft.options) { $option in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button {
                            CLHaptics.select()
                            withAnimation(CLMotion.pop) { draft.markCorrect(option.id) }
                        } label: {
                            Image(systemName: option.correct ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(option.correct ? CLColor.mintInk : CLColor.ink4)
                                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(option.correct ? "Right answer" : "Mark as the right answer"))
                        TextField("Choice", text: $option.text, axis: .vertical)
                            .clFont(option.correct ? .bodyEmphasis : .body)
                            .lineLimit(1...4)
                        if draft.options.count > 2 {
                            RemoveButton(label: "Remove choice") { remove(option: option.id) }
                        }
                    }
                    TextField(option.correct ? "Why it's right (optional)" : "Why it's wrong (optional)", text: $option.why, axis: .vertical)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .lineLimit(1...4)
                        .padding(.leading, 50)
                }
            }
            .onDelete { offsets in
                guard draft.options.count - offsets.count >= 2 else { return }
                draft.options.remove(atOffsets: offsets)
            }
            if draft.options.count < 6 {
                Button {
                    withAnimation(CLMotion.settle) { draft.addOption() }
                } label: {
                    Label("Add a choice", systemImage: "plus.circle.fill")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                }
            }
        } header: {
            Text("Choices")
        } footer: {
            Text("Tap a circle to mark the one right answer.")
        }
        .listRowBackground(CLColor.surface)
    }

    private var clozeSection: some View {
        let blanks = draft.blanks
        return Section {
            TextField("During [telophase], the chromatids reach opposite poles.", text: $draft.clozeText, axis: .vertical)
                .clFont(.body)
                .lineLimit(2...8)
                .autocorrectionDisabled()
            if !blanks.isEmpty {
                let preview = LibraryFormat.clozeDisplay(ItemDraft.braced(draft.clozeText.clTrimmed))
                Text(preview)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .accessibilityLabel(Text("Preview: \(preview)"))
                ForEach(Array(blanks.enumerated()), id: \.offset) { index, blank in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(blank.isEmpty ? "Empty blank" : blank)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(blank.isEmpty ? CLColor.roseInk : CLColor.ink)
                        TextField("Other ways to say it, separated by commas", text: alternateBinding(index))
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                            .autocorrectionDisabled()
                    }
                }
            }
        } header: {
            Text("Sentence")
        } footer: {
            Text("Put [brackets] around each word to hide, like: During [telophase], the nuclear envelopes re-form.")
        }
        .listRowBackground(CLColor.surface)
    }

    private func diagramSection(_ item: StudyItem?) -> some View {
        Section {
            ForEach(item?.diagram?.targets ?? []) { target in
                Label(target.label, systemImage: "tag")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink)
            }
        } header: {
            Text("Labels")
        } footer: {
            Text("The labels come from the page, so they stay as they were read.")
        }
        .listRowBackground(CLColor.surface)
    }

    private var explanationSection: some View {
        Section {
            TextField("Why it's right, in a sentence or two", text: $draft.explanation, axis: .vertical)
                .clFont(.body)
                .lineLimit(1...6)
        } header: {
            Text("Explanation")
        } footer: {
            Text("Optional. Shown after you answer.")
        }
        .listRowBackground(CLColor.surface)
    }

    private func courseSection(_ courses: [Course]) -> some View {
        Section("Course") {
            if courses.isEmpty {
                TextField("New course name, like Bio 101", text: $newCourseName)
                    .clFont(.body)
                    .textInputAutocapitalization(.words)
            } else {
                Picker("Course", selection: Binding(get: { chosenCourseID }, set: { id in
                    chosenCourseID = id
                    draft.topicID = nil
                    pendingTopicName = nil
                })) {
                    ForEach(courses) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
            }
        }
        .listRowBackground(CLColor.surface)
    }

    private func topicSection(_ topics: [Topic], course: Course?) -> some View {
        Section {
            Picker("Topic", selection: Binding(get: { pendingTopicName == nil ? draft.topicID : nil }, set: { id in
                draft.topicID = id
                pendingTopicName = nil
            })) {
                if let pendingTopicName {
                    Text("\(pendingTopicName) (new)").tag(UUID?.none)
                } else {
                    Text("None").tag(UUID?.none)
                }
                ForEach(topics) { topic in
                    Text(topic.name).tag(Optional(topic.id))
                }
            }
            Button {
                topicNameInput = ""
                askingTopic = true
            } label: {
                Label("New topic", systemImage: "plus.circle.fill")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
            }
            .disabled(course == nil && newCourseName.clTrimmed.isEmpty)
        } header: {
            Text("Topic")
        } footer: {
            Text("Topics show where you're strong and where you're not, per exam.")
        }
        .listRowBackground(CLColor.surface)
    }

    private var suspendSection: some View {
        Section {
            Toggle("Suspended", isOn: $draft.suspended)
                .clFont(.body)
                .tint(CLColor.tangerine)
        } footer: {
            Text("A suspended question stays out of sessions and readiness until you turn this off. Its memory is kept.")
        }
        .listRowBackground(CLColor.surface)
    }

    private func sourceSection(_ ref: SourceRef) -> some View {
        let source = app.source(ref.sourceID)
        let isLecture = source?.kind == .lecture
        return Section {
            if let source, source.deletedAt == nil, !app.opens(ref) {
                // A card from an imported deck: where it came from, and nothing to open.
                Text(verbatim: source.title).clFont(.subheadline).foregroundStyle(CLColor.ink2)
            } else if let source, source.deletedAt == nil {
                NavigationLink(value: isLecture ? Route.lectureNotes(ref.sourceID)
                               : Route.sourcePage(sourceID: ref.sourceID, pageIndex: ref.pageIndex ?? 0, highlight: ref.anchorIDs)) {
                    HStack(spacing: 10) {
                        CLSourceChip(label: ref.label, systemImage: isLecture ? "mic" : "book.pages")
                        Text(source.title).clFont(.footnote).foregroundStyle(CLColor.ink2).lineLimit(1)
                    }
                }
                .accessibilityHint(Text(isLecture ? "Opens the lecture notes" : "Opens the page with these lines marked"))
            } else {
                Text("Its source was deleted.").clFont(.subheadline).foregroundStyle(CLColor.ink2)
            }
        } header: {
            Text("From")
        }
        .listRowBackground(CLColor.surface)
    }

    private var deleteSection: some View {
        Section {
            Button("Delete question", role: .destructive) { confirmDelete = true }
                .frame(maxWidth: .infinity)
        }
        .listRowBackground(CLColor.surface)
    }

    // MARK: Logic

    private var hasStarted: Bool {
        itemID != nil || !draft.prompt.clTrimmed.isEmpty || !draft.answer.clTrimmed.isEmpty || !draft.clozeText.clTrimmed.isEmpty
            || draft.options.contains { !$0.text.clTrimmed.isEmpty } || draft.ideas.contains { !$0.label.clTrimmed.isEmpty }
    }

    /// What stops saving: the draft's own problem, or no course to put it in.
    private func blocker(course: Course?) -> String? {
        if let problem = draft.problem { return problem }
        if itemID == nil, course == nil, newCourseName.clTrimmed.isEmpty { return "Pick the course it belongs to." }
        return nil
    }

    private func hasChanges(_ item: StudyItem?) -> Bool {
        guard let item, item.modelContext != nil else { return hasStarted }
        return ItemDraft(item: item) != draft || pendingTopicName != nil
    }

    private func load(_ item: StudyItem?, courses: [Course]) {
        guard !loaded else { return }
        loaded = true
        if let item, item.modelContext != nil {
            draft = ItemDraft(item: item)
            chosenCourseID = item.course?.id
        } else {
            chosenCourseID = courseID ?? courses.first?.id
            draft = .blank(kind: .flashcard)
        }
    }

    private func remove(idea id: String) {
        withAnimation(CLMotion.settle) { draft.ideas.removeAll { $0.id == id } }
    }

    private func remove(option id: UUID) {
        withAnimation(CLMotion.settle) {
            let wasCorrect = draft.options.first { $0.id == id }?.correct == true
            draft.options.removeAll { $0.id == id }
            if wasCorrect, let first = draft.options.first { draft.markCorrect(first.id) }
        }
    }

    private func alternateBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft.clozeAlternates.indices.contains(index) ? draft.clozeAlternates[index] : "" },
                set: { value in
                    while draft.clozeAlternates.count <= index { draft.clozeAlternates.append("") }
                    draft.clozeAlternates[index] = value
                })
    }

    private func save(course: Course?) {
        guard blocker(course: course) == nil else { return }
        var target = course
        if target == nil, itemID == nil {
            target = app.createCourse(name: newCourseName, color: .sky, symbol: "book.closed")
        }
        guard let target else { return }
        var final = draft
        if let name = pendingTopicName, let topic = app.addTopic(named: name, to: target.id) {
            final.topicID = topic.id
        }
        if let itemID {
            app.updateItem(itemID, from: final)
            CLHaptics.land()
            dismiss()
        } else if app.createItem(in: target.id, from: final) != nil {
            CLHaptics.land()
            dismiss()
            app.router.toast("Added to \(target.name)")
        }
    }
}

/// A small minus button for removing a row, 44 pt to tap.
private struct RemoveButton: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CLColor.ink4)
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
