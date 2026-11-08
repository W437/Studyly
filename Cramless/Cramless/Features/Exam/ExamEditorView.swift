import SwiftUI

/// Add an exam, or edit one. A new exam asks for what it was opened for first: when, then its name, then what's on it (the whole course,
/// or the topics ticked, and "Snap the syllabus"); its format and readiness target wait behind one row, "Format and target". Opened from a
/// course, it doesn't ask for the course. Editing shows everything (format and target in place, the course, Delete). "Snap the syllabus"
/// reads a photo or a PDF (`SyllabusFlowView`), and its page of what it found is the one check: its button adds or saves the exam.
///
/// Harness: `CRAMLESS_ROUTE=syllabus[:new|edit]` opens it on the flow (`edit`, the default: the Bio midterm). `CRAMLESS_SYLLABUS=pick|reading|proposal|offline|applied|error:<kind>`
/// holds a state, from a sample syllabus (`SyllabusSample`): `proposal`, what Cloud AI reads (the mock relay's reply); `offline`, what this iPhone's
/// rules read; `applied`, the editor filled from it (what's left when the found page can't save on its own: a new exam with no course named);
/// `error:unreadable|nothing|nodate|notopics`. `CRAMLESS_EXAM_FORMAT=1` opens "Format and target" on a new exam.
struct ExamEditorView: View {
    let courseID: UUID?
    let examID: UUID?
    /// Opens straight on the syllabus flow.
    var opensSyllabus = false
    /// Opened from `courseID`'s own page or card: the course isn't asked (from Today or Progress it is, with `courseID` as the guess).
    var courseIsFixed = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExamDraft(date: .now)
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var showsSyllabus = false
    @State private var path: [EditorPage] = []
    /// The flow's opening state (DEBUG).
    @State private var syllabusHold: String?

    private enum EditorPage: Hashable { case formatAndTarget }

    /// A new exam opened from its course: the course is known, so it isn't asked.
    private var courseIsGiven: Bool { examID == nil && courseIsFixed && app.course(courseID) != nil }

    var body: some View {
        let courses = app.courses
        let exam = app.exam(examID)
        let course = app.course(draft.courseID)
        let topics = course?.liveTopics ?? []
        NavigationStack(path: $path) {
            Form {
                Section {
                    DatePicker("Date", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                        .clFont(.body)
                        .tint(CLColor.tangerine)
                } header: {
                    Text("When")
                } footer: {
                    Text(whenFooter)
                }
                .listRowBackground(CLColor.surface)

                Section("Name") {
                    TextField(draft.resolvedTitle(courseName: course?.name ?? draft.newCourseName.clTrimmed), text: $draft.title)
                        .clFont(.body)
                        .textInputAutocapitalization(.words)
                }
                .listRowBackground(CLColor.surface)

                if !courseIsGiven {
                    Section("Course") {
                        if courses.isEmpty {
                            // No course yet: name it here, and it is made with the exam.
                            TextField("Course name, like Bio 101", text: $draft.newCourseName)
                                .clFont(.body)
                                .textInputAutocapitalization(.words)
                        } else {
                            Picker("Course", selection: Binding(get: { draft.courseID }, set: { id in
                                draft.courseID = id
                                draft.scope = []
                                draft.newTopics = []
                                draft.wholeCourse = true
                            })) {
                                ForEach(courses) { course in
                                    Text(course.name).tag(Optional(course.id))
                                }
                            }
                        }
                    }
                    .listRowBackground(CLColor.surface)
                }

                Section {
                    Toggle("The whole course", isOn: $draft.wholeCourse.animation(CLMotion.settle))
                        .clFont(.body)
                        .tint(CLColor.tangerine)
                    if !draft.wholeCourse {
                        if topics.isEmpty, draft.newTopics.isEmpty {
                            Text("This course has no topics yet.").clFont(.subheadline).foregroundStyle(CLColor.ink2)
                        }
                        ForEach(topics) { topic in
                            Button {
                                CLHaptics.select()
                                if draft.scope.contains(topic.id) { draft.scope.remove(topic.id) } else { draft.scope.insert(topic.id) }
                            } label: {
                                HStack {
                                    Text(topic.name).clFont(.body).foregroundStyle(CLColor.ink)
                                    Spacer()
                                    Image(systemName: draft.scope.contains(topic.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(draft.scope.contains(topic.id) ? CLColor.tangerineInk : CLColor.ink4)
                                }
                                .frame(minHeight: CLMetrics.minHitTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(draft.scope.contains(topic.id) ? [.isSelected] : [])
                        }
                        ForEach(draft.newTopics, id: \.self) { name in
                            Button {
                                CLHaptics.select()
                                draft.newTopics.removeAll { $0 == name }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(verbatim: name).clFont(.body).foregroundStyle(CLColor.ink)
                                    CLPill(text: SyllabusCopy.noNotes, tone: .tangerine)
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(CLColor.tangerineInk)
                                }
                                .frame(minHeight: CLMetrics.minHitTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isSelected)
                            .accessibilityHint(Text("Takes it off this exam"))
                        }
                    }
                    syllabusRow
                } header: {
                    Text("What's on it")
                } footer: {
                    Text(whatsOnItFooter)
                }
                .listRowBackground(CLColor.surface)

                if exam == nil {
                    Section {
                        NavigationLink(value: EditorPage.formatAndTarget) {
                            Text("Format and target").clFont(.body)
                        }
                    }
                    .listRowBackground(CLColor.surface)
                } else {
                    ExamFormatSections(draft: $draft)
                }

                if let exam {
                    Section {
                        Button("Delete exam", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    } footer: {
                        Text("Its plan goes. The questions and progress in \(exam.course?.name ?? "the course") stay.")
                    }
                    .listRowBackground(CLColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .clScreenBackground()
            .navigationTitle(examID == nil ? "Add exam" : "Edit exam")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EditorPage.self) { _ in
                Form { ExamFormatSections(draft: $draft) }
                    .scrollContentBackground(.hidden)
                    .clScreenBackground()
                    .navigationTitle("Format and target")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(examID == nil ? "Add" : "Save", action: save)
                        .disabled(draft.problem != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let problem = draft.problem, loaded {
                    Label(problem, systemImage: "info.circle")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .alert("Delete \(exam?.title ?? "exam")?", isPresented: $confirmDelete) {
                Button("Delete exam", role: .destructive) {
                    if let examID {
                        dismiss()
                        if case .exam(examID)? = app.router.paths[app.router.tab]?.last { app.router.pop() }
                        app.deleteExam(examID)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationBackground(CLColor.background)
        .onAppear {
            guard !loaded else { return }
            if let exam {
                draft = ExamDraft(exam: exam)
            } else {
                draft = .new(courseID: courseID ?? courses.first?.id, now: app.now, calendar: app.calendar)
            }
            loaded = true
            if opensSyllabus { showsSyllabus = true }
            #if DEBUG
            if let hold = TestHarness.once("CRAMLESS_SYLLABUS") {
                if hold == "applied" {
                    applySample()
                } else {
                    syllabusHold = hold
                    showsSyllabus = true
                }
            }
            if TestHarness.once("CRAMLESS_EXAM_FORMAT") == "1", exam == nil { path = [.formatAndTarget] }
            #endif
        }
        // A cover of its own: the router's would close this sheet, and the draft with it.
        .fullScreenCover(isPresented: $showsSyllabus) {
            SyllabusFlowView(base: draft, courseName: course?.name ?? draft.newCourseName.clTrimmed, topics: topics.map { ($0.id, $0.name) },
                             hold: syllabusHold, actionTitle: { syllabusActionTitle($0, courseName: course?.name ?? draft.newCourseName.clTrimmed) }) { proposal in
                proposal.apply(to: &draft, courseName: course?.name ?? draft.newCourseName.clTrimmed, calendar: app.calendar)
                // The found page was the check: it saves, unless something only the form can give is missing (a new course's name).
                if draft.problem == nil {
                    save()
                } else {
                    showsSyllabus = false
                }
            } onClose: {
                showsSyllabus = false
            }
            .environment(app)
        }
    }

    /// The found page's button: "Add Midterm" for a new exam, "Save changes" for one being edited. When the draft can't be saved from there
    /// (a new course still to name), it fills the form instead.
    private func syllabusActionTitle(_ proposal: SyllabusProposal, courseName: String) -> String {
        var after = draft
        proposal.apply(to: &after, courseName: courseName, calendar: app.calendar)
        guard after.problem == nil else { return String(localized: SyllabusCopy.looksRight) }
        guard examID == nil else { return String(localized: "Save changes") }
        let name = LibraryFormat.shortExamTitle(after.resolvedTitle(courseName: courseName), courseName: courseName)
        return String(localized: "Add \(name)")
    }

    /// "Snap the syllabus": one row that fills all of this in from a photo, until a syllabus has.
    @ViewBuilder
    private var syllabusRow: some View {
        if !draft.fromSyllabus {
            Button {
                CLHaptics.tap()
                showsSyllabus = true
            } label: {
                Label { Text(SyllabusCopy.snap) } icon: { Image(systemName: "camera") }
                    .clFont(.bodyEmphasis)
                    .foregroundStyle(CLColor.tangerineInk)
                    .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Cap reads the date, the topics and the format from a photo or a PDF"))
        }
    }

    private var whatsOnItFooter: LocalizedStringResource {
        if draft.fromSyllabus { return SyllabusCopy.filledNote }
        return draft.wholeCourse ? "Readiness covers every topic in the course." : "Readiness covers only the topics you tick."
    }

    #if DEBUG
    /// `CRAMLESS_SYLLABUS=applied`: the sample syllabus, filled into the draft as the found page does.
    private func applySample() {
        let course = app.course(draft.courseID)
        let names = (course?.liveTopics ?? []).map { ($0.id, $0.name) }
        let exams = (try? RelayFixtures.load(SyllabusResponse.self, "syllabus").exams) ?? []
        let ids = SyllabusProposal.requestIDs(for: names)
        let matched = exams.map { exam -> SyllabusExam in
            var e = exam
            e.topics = exam.topics.map { topic in
                var t = topic
                t.topicId = ids.first { $0.value.name.lowercased() == topic.name.lowercased() }?.key
                return t
            }
            return e
        }
        if let proposal = SyllabusProposal.make(exams: matched, examTitle: draft.title, topicIDs: ids, base: draft, pageText: SyllabusSample.text,
                                                origin: .cloud, now: app.now, calendar: app.calendar) {
            proposal.apply(to: &draft, courseName: course?.name ?? "", calendar: app.calendar)
        }
    }
    #endif

    private var whenFooter: String {
        let days = app.calendar.dayDistance(from: app.now, to: draft.date)
        switch days {
        case ..<0: return "That date has passed. You can still log your grade for it."
        case 0: return "Today. The plan keeps it to a light look at weak spots."
        default: return "\(LibraryFormat.countdown(days: days)). The plan spreads new material over the days until three days before."
        }
    }

    private func save() {
        guard draft.problem == nil else { return }
        showsSyllabus = false
        if let examID {
            app.updateExam(examID, with: draft)
            CLHaptics.land()
            dismiss()
        } else if let exam = app.createExam(draft) {
            CLHaptics.land()
            dismiss()
            app.router.toast("\(exam.title) is in your plan")
        }
    }
}

/// An exam's format and readiness target: in place when editing, behind "Format and target" on a new exam.
private struct ExamFormatSections: View {
    @Binding var draft: ExamDraft

    var body: some View {
        Section {
            Toggle("Multiple choice", isOn: $draft.format.multipleChoice).tint(CLColor.tangerine)
            Toggle("Short answer", isOn: $draft.format.shortAnswer).tint(CLColor.tangerine)
            Toggle("Essay", isOn: $draft.format.essay).tint(CLColor.tangerine)
            LabeledContent("Questions on it") {
                TextField("Not sure", value: $draft.format.questionCount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Minutes") {
                TextField("Not sure", value: $draft.format.minutes, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            TextField("Notes, like open book", text: $draft.format.notes, axis: .vertical)
                .clFont(.body)
                .lineLimit(1...4)
        } header: {
            Text("Format")
        } footer: {
            Text("Mock exams follow it.")
        }
        .clFont(.body)
        .listRowBackground(CLColor.surface)

        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Readiness target").clFont(.body).foregroundStyle(CLColor.ink)
                    Spacer()
                    Text(CLFormat.percent(draft.clampedTarget))
                        .clFont(.number(20))
                        .foregroundStyle(CLColor.ink)
                        .contentTransition(.numericText())
                        .animation(CLMotion.snap, value: draft.clampedTarget)
                }
                Slider(value: $draft.target, in: ExamDraft.targetRange, step: ExamDraft.targetStep) {
                    Text("Readiness target")
                } minimumValueLabel: {
                    Text("70%").clFont(.caption).foregroundStyle(CLColor.ink3)
                } maximumValueLabel: {
                    Text("95%").clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                .tint(CLColor.tangerine)
                .accessibilityValue(Text(CLFormat.percent(draft.clampedTarget)))
                .onChange(of: draft.clampedTarget) { _, _ in CLHaptics.select() }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Target")
        } footer: {
            Text("Your plan aims for this readiness by exam day. 90% suits most exams.")
        }
        .listRowBackground(CLColor.surface)
    }
}
