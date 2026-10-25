import SwiftUI

/// One of the four questions. Single-choice answers move on by themselves after a beat; the date waits for
/// Continue; where notes live is multi-select. After the minutes question comes the reminder moment.
///
/// DEBUG hook: `CRAMLESS_ONB_REMINDER=1` opens the reminder sheet on the minutes question.
struct QuizStepView: View {
    let question: QuizQuestion

    @Environment(OnboardingCoordinator.self) private var onboarding
    @Environment(AppModel.self) private var app

    @State private var advanceTask: Task<Void, Never>?
    @State private var showsReminder = false
    @State private var examDate = Date()
    @State private var dateChosen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(question.title)
                    .clFont(.brandTitle(30))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(question.subtitle)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                answers
                    .padding(.top, 24)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(CLColor.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            Button(continueTitle) {
                CLHaptics.tap()
                advanceTask?.cancel()
                onboarding.advance()
            }
            .buttonStyle(.cl(.primary))
            .disabled(!canContinue)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                OnboardingProgressBar(value: onboarding.machine.setupProgress ?? 0)
            }
        }
        .sheet(isPresented: $showsReminder, onDismiss: reminderDismissed) {
            ReminderSheet(minutes: app.settings.dailyMinutes)
        }
        .onAppear(perform: prepare)
        .onDisappear { advanceTask?.cancel() }
    }

    // MARK: Answers

    @ViewBuilder private var answers: some View {
        switch question {
        case .goal:
            VStack(spacing: 12) {
                ForEach(QuizContent.goals) { choice in
                    QuizOptionRow(symbol: choice.symbol, title: choice.title, detail: choice.detail,
                                  selected: app.settings.goal == choice.value) {
                        app.settings.goal = choice.value
                        answered()
                    }
                }
            }
        case .examDate:
            examDateAnswers
        case .minutes:
            VStack(spacing: 12) {
                ForEach(QuizContent.minutes) { choice in
                    QuizOptionRow(symbol: choice.symbol, title: choice.title, detail: choice.detail,
                                  selected: onboarding.answered.contains(.minutes) && app.settings.dailyMinutes == choice.value) {
                        app.settings.dailyMinutes = choice.value
                        onboarding.answered.insert(.minutes)
                        if onboarding.reminderAsked { scheduleAdvance() } else { showsReminder = true }
                    }
                }
            }
        case .notes:
            VStack(spacing: 12) {
                ForEach(QuizContent.notes) { choice in
                    QuizOptionRow(symbol: choice.symbol, title: choice.title, detail: choice.detail,
                                  selected: app.settings.notesLocations.contains(choice.value), multiSelect: true) {
                        app.settings.toggleNotesLocation(choice.value)
                    }
                }
            }
        }
    }

    private var examDateAnswers: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !dateChosen {
                    Text("Tap the day of your exam")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink3)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
                DatePicker("Exam date", selection: dateBinding, in: dateRange, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(CLColor.tangerine)
                if dateChosen {
                    Label(QuizContent.examSummary(examDate, now: app.now, calendar: app.calendar), systemImage: "calendar")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.tangerineInk)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
            }
            .padding(10)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(dateChosen ? CLColor.tangerine : .clear, lineWidth: 2))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
            .animation(CLMotion.snap, value: dateChosen)

            QuizOptionRow(symbol: "calendar.badge.minus", title: "No exam yet",
                          detail: "We'll keep a steady weekly rhythm",
                          selected: onboarding.noExamYet) {
                app.settings.nextExamDate = nil
                onboarding.noExamYet = true
                dateChosen = false
                answered()
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let today = app.calendar.startOfDay(for: app.now)
        return today...(app.calendar.date(byAdding: .year, value: 1, to: today) ?? today)
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { examDate }, set: { date in
            CLHaptics.select()
            examDate = date
            dateChosen = true
            onboarding.noExamYet = false
            onboarding.answered.insert(.examDate)
            // The time of day isn't asked; morning is the likeliest.
            app.settings.nextExamDate = app.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        })
    }

    // MARK: Flow

    private var canContinue: Bool {
        switch question {
        case .goal: app.settings.goal != nil
        case .examDate: dateChosen || onboarding.noExamYet
        case .minutes: onboarding.answered.contains(.minutes)
        case .notes: true
        }
    }

    private var continueTitle: String {
        question == .notes && app.settings.notesLocations.isEmpty ? "Skip for now" : "Continue"
    }

    private func prepare() {
        if question == .examDate {
            if let saved = app.settings.nextExamDate, saved >= app.calendar.startOfDay(for: app.now) {
                examDate = saved
                dateChosen = true
            } else {
                // Open on today: a suggested date drawn as selected would look like an answer nobody gave.
                examDate = app.calendar.startOfDay(for: app.now)
            }
        }
        #if DEBUG
        if question == .minutes, TestHarness.once("CRAMLESS_ONB_REMINDER") == "1" {
            onboarding.answered.insert(.minutes)
            showsReminder = true
        }
        #endif
    }

    /// A pick on a single-choice question: a short beat to see the check land, then on.
    private func answered() {
        onboarding.answered.insert(question)
        scheduleAdvance()
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        let step = OnboardingStep.quiz(question.rawValue)
        advanceTask = Task {
            try? await nap(380)
            guard !Task.isCancelled, onboarding.step == step else { return }
            onboarding.advance()
        }
    }

    private func reminderDismissed() {
        onboarding.reminderAsked = true
        scheduleAdvance()
    }
}

/// A tappable answer card: an icon on a soft tile, the answer, and a check that fills when picked.
struct QuizOptionRow: View {
    let symbol: String
    let title: String
    var detail: String?
    let selected: Bool
    var multiSelect = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            CLHaptics.select()
            action()
        } label: {
            // Centred normally; at accessibility sizes a row is several lines tall, so the icon and the check
            // stay with the first line.
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CLColor.skyInk)
                    .frame(width: 40, height: 40)
                    .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .clFont(.bodyEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                check
            }
            .padding(16)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? CLColor.tangerine : .clear, lineWidth: 2))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressable)
        .animation(CLMotion.snap, value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(multiSelect ? "Pick as many as apply" : "")
    }

    private var check: some View {
        ZStack {
            Circle().strokeBorder(CLColor.surface3, lineWidth: 2).opacity(selected ? 0 : 1)
            Circle().fill(CLColor.tangerine).opacity(selected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(CLColor.onFill)
                .scaleEffect(selected ? 1 : 0.4)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: 26, height: 26)
        .animation(CLMotion.pop, value: selected)
        .accessibilityHidden(true)
    }
}

/// The thin bar across the top of the setup steps.
struct OnboardingProgressBar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(CLColor.surface3)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(CLColor.tangerine).frame(width: geo.size.width * max(0, min(1, value)))
                }
            }
            .frame(width: 190, height: 6)
            .clipShape(Capsule())
            .animation(CLMotion.calm, value: value)
            .accessibilityElement()
            .accessibilityLabel("Setup progress")
            .accessibilityValue(Text("\(Int((value * 100).rounded())) percent"))
    }
}

/// The reminder moment, right after the minutes question: when the reminder comes, and why.
struct ReminderSheet: View {
    let minutes: Int

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var asking = false
    /// The sheet sizes itself to its content (and scrolls past the screen at the largest text sizes).
    @State private var contentHeight: CGFloat = 430

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .padding(.top, 8)
                Text("A nudge at the right time")
                    .clFont(.brandTitle(26))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 22)
                Text(QuizContent.reminderBody(minutes: minutes, time: timeText))
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                HStack {
                    Text("Remind me at").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                    Spacer()
                    DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(CLColor.tangerine)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: CLMetrics.rowMinHeight)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
                .padding(.top, 18)
                VStack(spacing: 4) {
                    Button(action: enable) {
                        ZStack {
                            Text("Turn on reminders").opacity(asking ? 0 : 1)
                            if asking { ProgressView().tint(CLColor.onFill) }
                        }
                    }
                    .buttonStyle(.cl(.primary))
                    .disabled(asking)
                    Button("Not now") {
                        app.settings.reminderMinutes = nil
                        dismiss()
                    }
                    .buttonStyle(.cl(.ghost, size: .small))
                    .disabled(asking)
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight + 24)])
        .presentationDragIndicator(.visible)
        // Solid, so the question's buttons don't bleed through the glass behind the copy.
        .presentationBackground(CLColor.background)
        .onAppear {
            let minutes = app.settings.reminderMinutes ?? 19 * 60
            time = app.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: app.now) ?? app.now
        }
    }

    private var timeText: String { time.formatted(.dateTime.hour().minute()) }

    /// A miniature of the reminder itself, so the person sees what they're agreeing to.
    private var preview: some View {
        HStack(spacing: 11) {
            CapFace(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Capling").clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    Spacer(minLength: 4)
                    Text(timeText).clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                Text("\(minutes) minutes tonight and you're done.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.1), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Example reminder: \(minutes) minutes tonight and you're done."))
    }

    private func enable() {
        let parts = app.calendar.dateComponents([.hour, .minute], from: time)
        app.settings.reminderMinutes = (parts.hour ?? 19) * 60 + (parts.minute ?? 0)
        asking = true
        Task {
            _ = await app.notifications.requestAuthorization()
            asking = false
            dismiss()
        }
    }
}
