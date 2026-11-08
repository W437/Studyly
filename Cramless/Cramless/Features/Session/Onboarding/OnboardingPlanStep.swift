import SwiftUI

/// Onboarding's plan, one screen: the readiness ring after the first two answers, "Bio 101 exam · 23 days", one line from the
/// plan engine ("15 minutes a day gets you to 90% by Nov 28."), the week, then the two choices that shape it: the minutes a day (a
/// plain picker) and the daily reminder (on at 7:00 PM, its time editable). With no exam (none given, or the sample page) Cap stands
/// where the ring would be and there is no percentage. "Continue" asks iOS for notifications when the reminder is on, then calls
/// `onDone` (the paywall is next).
///
/// Harness: `CRAMLESS_STEP=plan` (with `CRAMLESS_SEED=0`; `CRAMLESS_STEP_NODATE=1` for no exam), or `CRAMLESS_ROUTE=onboarding:4`.
/// `CRAMLESS_STEP_SCROLL=bottom` scrolls to the two rows once the screen has settled.
///
///     OnboardingPlanStep(courseID: firstSetCourse, isSample: false) { onboarding.advance() }
struct OnboardingPlanStep: View {
    let courseID: UUID?
    /// The first set was the sample page: no exam is made from it.
    var isSample = false
    let onDone: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: Model?
    @State private var risen = false
    @State private var asking = false

    struct Model: Equatable {
        /// "Bio 101 exam · 23 days"; nil with no exam.
        var examLine: String?
        /// Readiness now; nil with no exam (there is nothing to be ready for).
        var readiness: Double?
        /// "15 minutes a day gets you to 90% by Nov 28."
        var line: String
        var week: [PlanWeekDay]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your plan")
                        .clFont(.brandTitle(30))
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let model {
                        planCard(model)
                        choices.id("rows")
                    }
                }
                .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            .onChange(of: risen) { _, isRisen in
                guard isRisen, TestHarness.value("CRAMLESS_STEP_SCROLL") == "bottom" else { return }
                withAnimation(CLMotion.settle) { proxy.scrollTo("rows", anchor: .bottom) }
            }
            #endif
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(CLColor.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            Button(action: next) {
                ZStack {
                    Text("Continue").opacity(asking ? 0 : 1)
                    if asking { ProgressView().tint(CLColor.onFill) }
                }
            }
            .buttonStyle(.cl(.primary))
            .disabled(asking)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await appear() }
        .onChange(of: app.settings.dailyMinutes) { _, _ in model = makeModel() }
    }

    // MARK: The plan

    private func planCard(_ model: Model) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return VStack(alignment: .leading, spacing: 18) {
            layout {
                if let readiness = model.readiness {
                    ReadinessRing(value: readiness, size: 92, lineWidth: 10, caption: String(localized: "ready"),
                                  animatesFromZero: true)
                } else {
                    CapView(pose: .proud, size: 92, idle: .breathe)
                        .frame(width: 92, height: 92)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: model.examLine ?? String(localized: "No exam yet"))
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.line)
                        .clFont(.callout)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            PlanWeekStrip(days: model.week, risen: risen)
        }
        .clCard()
        .animation(CLMotion.settle, value: model)
    }

    // MARK: The two choices

    private var choices: some View {
        CLList {
            minutesRow
            reminderRow
        }
    }

    /// "15 min a day": a plain picker of 5, 10, 15, 20 and 30 minutes.
    private var minutesRow: some View {
        let minutes = app.settings.dailyMinutes
        return Menu {
            Picker(selection: Binding(get: { app.settings.dailyMinutes }, set: { value in
                CLHaptics.select()
                app.settings.dailyMinutes = value
            })) {
                ForEach(QuizContent.minuteOptions, id: \.self) { option in
                    Text("\(option) minutes").tag(option)
                }
            } label: {
                Text("Minutes a day")
            }
            .pickerStyle(.inline)
        } label: {
            CLRow(icon: "clock", tint: .tangerine, title: "\(minutes) min a day") {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CLColor.ink3)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Minutes a day"))
        .accessibilityValue(Text("\(minutes) minutes"))
    }

    /// "Remind me at 7:00 PM", with a switch: on by default, the time editable.
    private var reminderRow: some View {
        let on = app.settings.reminderMinutes != nil
        let isOn = Binding(get: { app.settings.reminderMinutes != nil }, set: { value in
            app.settings.reminderMinutes = value ? (lastReminder ?? 19 * 60) : nil
        })
        let time = Binding(get: { reminderDate }, set: { date in
            let parts = app.calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (parts.hour ?? 19) * 60 + (parts.minute ?? 0)
            lastReminder = minutes
            app.settings.reminderMinutes = minutes
        })
        let label = Text("Remind me at").clFont(.bodyEmphasis).foregroundStyle(on ? CLColor.ink : CLColor.ink3)
        let picker = DatePicker("Reminder time", selection: time, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .tint(CLColor.tangerine)
            .disabled(!on)
            .opacity(on ? 1 : 0.45)
        let toggle = Toggle("Daily reminder", isOn: isOn)
            .labelsHidden()
            .tint(CLColor.mint)
            .accessibilityHint(Text(on ? "Turns the daily reminder off" : "Turns on a daily reminder"))
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                CLIconBadge(systemImage: "bell", tint: .sky)
                    .padding(.trailing, 4)
                label.fixedSize()
                picker.fixedSize()
                Spacer(minLength: 0)
                toggle.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CLIconBadge(systemImage: "bell", tint: .sky)
                    label.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    toggle.fixedSize()
                }
                picker
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: CLMetrics.rowMinHeight)
    }

    /// The time the switch brings back after it was turned off in this screen.
    @State private var lastReminder: Int?

    private var reminderDate: Date {
        let minutes = app.settings.reminderMinutes ?? lastReminder ?? 19 * 60
        return app.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: app.now) ?? app.now
    }

    // MARK: Flow

    private func appear() async {
        guard model == nil else { return }
        let made = makeModel()
        model = made
        lastReminder = app.settings.reminderMinutes
        AccessibilityNotification.Announcement("\(made.examLine ?? String(localized: "No exam yet")). \(made.line)").post()
        if reduceMotion {
            risen = true
        } else {
            try? await nap(250)
            risen = true
        }
    }

    /// With the reminder on, iOS asks for notifications now (the person just chose the reminder); then the paywall.
    private func next() {
        guard !asking else { return }
        CLHaptics.commit()
        guard app.settings.reminderMinutes != nil else { return onDone() }
        asking = true
        Task {
            _ = await app.notifications.requestAuthorization()
            asking = false
            onDone()
        }
    }

    private func makeModel() -> Model {
        let course = app.onboardingCourse(courseID)
        let exam: Exam? = isSample ? nil
            : course?.liveExams.filter { $0.date > app.now }.min { $0.date < $1.date } ?? app.ensureOnboardingExam(courseID: courseID)
        let settings = app.settings
        let minutes = settings.dailyMinutes
        guard let exam else {
            let week = (0..<7).map { offset in
                let date = app.calendar.startOfDay(for: app.calendar.adding(days: offset, to: app.now))
                let weekday = app.calendar.component(.weekday, from: date)
                let easy = settings.easyDays.contains(weekday)
                return PlanWeekDay(id: offset, date: date, minutes: easy ? max(5, minutes / 2) : minutes,
                                   kind: easy ? .light : .study, isToday: offset == 0)
            }
            return Model(examLine: nil, readiness: nil, line: QuizContent.noExamLine(minutes: minutes), week: week)
        }
        let plan = app.plan(for: exam)
        let readiness = app.readiness(for: exam)
        let week = plan.days.prefix(7).map { day in
            PlanWeekDay(id: day.dayNumber, date: day.date,
                        minutes: day.kind == .rest || day.kind == .exam ? 0 : day.sessionMinutes,
                        kind: day.kind, isToday: day.isToday)
        }
        return Model(examLine: QuizContent.examLine(title: SessionCopy.unbroken(exam.title), days: readiness.daysLeft),
                     readiness: readiness.value,
                     line: QuizContent.planLine(minutes: minutes, target: plan.target, reachedOn: plan.targetReachedOn,
                                                projected: plan.projectedReadiness),
                     week: Array(week))
    }
}
