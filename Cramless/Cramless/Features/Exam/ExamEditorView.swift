import SwiftUI

/// New exam or edit one: its name, course, date, what's on it (topics or the whole course), its format and notes,
/// the readiness target (70–95%), and Delete.
struct ExamEditorView: View {
    let courseID: UUID?
    let examID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExamDraft(date: .now)
    @State private var loaded = false
    @State private var confirmDelete = false

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
                    Toggle("The whole course", isOn: $draft.wholeCourse.animation(CLMotion.settle))
                        .clFont(.body)
                        .tint(CLColor.tangerine)
                    if !draft.wholeCourse {
                        if topics.isEmpty {
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
                    }
                } header: {
                    Text("What's on it")
                } footer: {
                    Text(draft.wholeCourse ? "Readiness covers every topic in the course." : "Readiness covers only the topics you tick.")
                }
                .listRowBackground(CLColor.surface)

                Section {
                    Toggle("Multiple choice", isOn: $draft.format.multipleChoice).tint(CLColor.tangerine)
                    Toggle("Short answer", isOn: $draft.format.shortAnswer).tint(CLColor.tangerine)
                    Toggle("Essay", isOn: $draft.format.essay).tint(CLColor.tangerine)
                    TextField("Notes, like open book or 90 minutes", text: $draft.format.notes, axis: .vertical)
                        .clFont(.body)
                        .lineLimit(1...4)
                } header: {
                    Text("Format")
                } footer: {
                    Text("The format shapes the projected grade: multiple choice leaves room for a good guess.")
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
        }
    }

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
