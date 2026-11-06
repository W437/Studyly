import SwiftUI

/// New exam or edit one: its name, course, date, what's on it (topics or the whole course), its format and notes,
/// the readiness target (70–95%), and Delete. "Snap the syllabus" reads a photo or a PDF and fills all of that in (`SyllabusFlowView`), for
/// the person to check before Add or Save.
///
/// Harness: `CRAMLESS_ROUTE=syllabus[:new|edit]` opens it on the flow (`edit`, the default: the Bio midterm). `CRAMLESS_SYLLABUS=pick|reading|proposal|offline|applied|error:<kind>`
/// holds a state, from a sample syllabus (`SyllabusSample`): `proposal`, what Cloud AI reads (the mock relay's reply); `offline`, what this iPhone's
/// rules read; `applied`, the editor once "Looks right" has filled it; `error:unreadable|nothing|nodate|notopics`.
struct ExamEditorView: View {
    let courseID: UUID?
    let examID: UUID?
    /// Opens straight on the syllabus flow.
    var opensSyllabus = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExamDraft(date: .now)
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var showsSyllabus = false
    /// The flow's opening state (DEBUG).
    @State private var syllabusHold: String?

    var body: some View {
        let courses = app.courses
        let exam = app.exam(examID)
        let course = app.course(draft.courseID)
        let topics = course?.liveTopics ?? []
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(course.map { "\($0.name) Midterm" } ?? (draft.newCourseName.clTrimmed.isEmpty ? "Midterm" : "\(draft.newCourseName.clTrimmed) Midterm"), text: $draft.title)
                        .clFont(.body)
                        .textInputAutocapitalization(.words)
                }
                .listRowBackground(CLColor.surface)

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

                Section {
                    syllabusRow
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
                } header: {
                    Text("What's on it")
                } footer: {
                    Text(whatsOnItFooter)
                }
                .listRowBackground(CLColor.surface)

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
                    Text("Mock exams follow the format. It shapes the projected grade too: multiple choice leaves room for a good guess.")
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
            .navigationTitle(examID == nil ? "New exam" : "Edit exam")
            .navigationBarTitleDisplayMode(.inline)
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
            #endif
        }
        // A cover of its own: the router's would close this sheet, and the draft with it.
        .fullScreenCover(isPresented: $showsSyllabus) {
            SyllabusFlowView(base: draft, courseName: course?.name ?? draft.newCourseName.clTrimmed, topics: topics.map { ($0.id, $0.name) },
                             hold: syllabusHold) { proposal in
                proposal.apply(to: &draft, courseName: course?.name ?? draft.newCourseName.clTrimmed, calendar: app.calendar)
                showsSyllabus = false
            } onClose: {
                showsSyllabus = false
            }
            .environment(app)
        }
    }

    /// "What does it cover?": the way to fill this in from a photo, until a syllabus has.
    @ViewBuilder
    private var syllabusRow: some View {
        if !draft.fromSyllabus {
            VStack(alignment: .leading, spacing: 6) {
                Text(SyllabusCopy.question).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text(SyllabusCopy.pitch)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                CaptureChips {
                    Button {
                        CLHaptics.tap()
                        showsSyllabus = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera").accessibilityHidden(true)
                            Text(SyllabusCopy.snap)
                        }
                    }
                    .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                    if draft.wholeCourse {
                        Button(SyllabusCopy.pickTopics) {
                            CLHaptics.select()
                            withAnimation(CLMotion.settle) { draft.wholeCourse = false }
                        }
                        .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
                    }
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 4)
        }
    }

    private var whatsOnItFooter: LocalizedStringResource {
        if draft.fromSyllabus { return SyllabusCopy.filledNote }
        return draft.wholeCourse ? "Readiness covers every topic in the course." : "Readiness covers only the topics you tick."
    }

    #if DEBUG
    /// `CRAMLESS_SYLLABUS=applied`: the sample syllabus, as "Looks right" leaves the draft.
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
