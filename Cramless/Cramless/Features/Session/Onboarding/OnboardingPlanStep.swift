import SwiftUI

/// Onboarding's plan: it builds itself in front of the person (topics mapped, minutes a day, when new material is
/// in, the exam eve, the reminder), then draws the projected path to the target by the exam date and the week's
/// minutes. Returns the paywall's line through `onDone` ("Your Bio 101 plan is set: 15 minutes a day until Nov 14.").
///
/// Plugged into `OnboardingFlow` by the orchestrator:
///
///     OnboardingPlanStep(courseID: firstSetCourse) { line in
///         onboarding.planLine = line
///         onboarding.advance()
///     }
struct OnboardingPlanStep: View {
    let courseID: UUID?
    let onDone: (String?) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var model: Model?
    @State private var done = 0
    @State private var working = false
    @State private var chartShown = false
    @State private var drawn: Double = 0
    @State private var risen = false

    init(courseID: UUID?, onDone: @escaping (String?) -> Void) {
        self.courseID = courseID
        self.onDone = onDone
    }

    struct Model {
        var title: String
        var steps: [String]
        var curve: [ReadinessPoint]
        var target: Double
        var examDate: Date?
        var targetReachedOn: Date?
        var week: [PlanWeekDay]
        var minutes: Int
        var line: String
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let model {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.title)
                            .clFont(.brandTitle(30))
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Built from your answers. It bends when your week does.")
                            .clFont(.body)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        CLEyebrow(text: done >= model.steps.count ? "Your plan" : "Building your plan")
                        PlanChecklist(steps: model.steps, done: done, working: working)
                    }
                    .clCard()
                    if model.curve.count > 1 {
                        pathCard(model)
                            .opacity(chartShown ? 1 : 0)
                            .offset(y: chartShown ? 0 : 14)
                    }
                    weekCard(model)
                        .opacity(chartShown ? 1 : 0)
                        .offset(y: chartShown ? 0 : 14)
                        .id("week")
                }
            }
            .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        #if DEBUG
        // `CRAMLESS_STEP_SCROLL=bottom`: once the plan has built, scroll to the week (for a screenshot).
        .onChange(of: risen) { _, isRisen in
            guard isRisen, TestHarness.value("CRAMLESS_STEP_SCROLL") == "bottom" else { return }
            withAnimation(CLMotion.settle) { proxy.scrollTo("week", anchor: .bottom) }
        }
        #endif
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(CLColor.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            Button("Start my plan") {
                CLHaptics.commit()
                onDone(model?.line)
            }
            .buttonStyle(.cl(.primary))
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { await build() }
    }

    private func pathCard(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your path to \(CLFormat.percent(model.target))")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                Spacer(minLength: 8)
                if let reached = model.targetReachedOn {
                    CLPill(text: .verbatim(reached.formatted(.dateTime.month(.abbreviated).day())), tone: .mint, systemImage: "scope")
                        .accessibilityLabel("Reaches \(CLFormat.percent(model.target)) on \(CLFormat.day(reached))")
                } else if let date = model.examDate {
                    CLPill(text: "Exam \(date.formatted(.dateTime.month(.abbreviated).day()))", tone: .tangerine,
                           systemImage: "flag.checkered")
                }
            }
            PlanPathChart(points: model.curve, target: model.target, drawn: drawn)
        }
        .clCard()
    }

    private func weekCard(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                Spacer(minLength: 8)
                CLPill(text: "\(model.minutes) min a day", tone: .tangerine, systemImage: "clock")
            }
            PlanWeekStrip(days: model.week, risen: risen)
        }
        .clCard()
    }

    // MARK: Building

    private func build() async {
        guard model == nil else { return }
        let made = makeModel()
        model = made
        if reduceMotion {
            done = made.steps.count
            chartShown = true
            drawn = 1
            risen = true
            AccessibilityNotification.Announcement(made.line).post()
            return
        }
        try? await nap(300)
        for index in made.steps.indices {
            withAnimation(CLMotion.snap) { working = true }
            try? await nap(index == 0 ? 520 : 420)
            withAnimation(CLMotion.pop) {
                done = index + 1
                working = false
            }
            try? await nap(120)
        }
        withAnimation(CLMotion.settle) { chartShown = true }
        try? await nap(200)
        withAnimation(CLMotion.fill) { drawn = 1 }
        risen = true
        AccessibilityNotification.Announcement(made.line).post()
    }

    private func makeModel() -> Model {
        let course = app.onboardingCourse(courseID)
        let exam = course?.liveExams.first { $0.date > app.now } ?? app.ensureOnboardingExam(courseID: courseID)
        let plan = exam.map { app.plan(for: $0) }
        let settings = app.settings
        let minutes = settings.dailyMinutes

        var steps: [String] = []
        if let course {
            let active = course.activeItems
            let topics = course.liveTopics.filter { topic in active.contains { $0.topicID == topic.id } }.count
            steps.append(topics == 1 ? "Mapped 1 topic from your first set"
                         : "Mapped \(max(topics, 1)) topics from your first set")
        }
        var minutesLine = "\(minutes) minutes a day"
        if !settings.easyDays.isEmpty {
            let names = settings.easyDays.sorted().map { Calendar.current.weekdaySymbols[max(0, min(6, $0 - 1))] }
            minutesLine += ", lighter on \(ListFormatter.localizedString(byJoining: names))"
        }
        if let suggested = plan?.suggestedMinutes, suggested > minutes {
            minutesLine += ". A few days need about \(suggested)"
        }
        steps.append(minutesLine)
        if let plan {
            if let intro = plan.lastIntroDay { steps.append("New material in by \(CLFormat.day(intro))") }
            if let eve = plan.examEve { steps.append("Exam eve on \(CLFormat.day(eve)): weak spots, then sleep") }
        } else {
            steps.append("A few new questions each day, and reviews right before you'd forget")
        }
        if let reminder = settings.reminderMinutes,
           let time = app.calendar.date(bySettingHour: reminder / 60, minute: reminder % 60, second: 0, of: app.now) {
            steps.append("A reminder every day at \(time.formatted(.dateTime.hour().minute()))")
        } else {
            steps.append("No reminders. Open it when you're ready")
        }

        let week: [PlanWeekDay]
        if let plan {
            week = plan.days.prefix(7).map { day in
                PlanWeekDay(id: day.dayNumber, date: day.date,
                            minutes: day.kind == .rest || day.kind == .exam ? 0 : day.sessionMinutes,
                            kind: day.kind, isToday: day.isToday)
            }
        } else {
            week = (0..<7).map { offset in
                let date = app.calendar.startOfDay(for: app.calendar.adding(days: offset, to: app.now))
                let weekday = app.calendar.component(.weekday, from: date)
                let easy = settings.easyDays.contains(weekday)
                return PlanWeekDay(id: offset, date: date, minutes: easy ? max(5, minutes / 2) : minutes,
                                   kind: easy ? .light : .study, isToday: offset == 0)
            }
        }
        let name = course?.name
        return Model(title: name.map { "Your \($0) plan" } ?? "Your plan", steps: steps, curve: plan?.curve ?? [],
                     target: plan?.target ?? 0.9, examDate: exam?.date, targetReachedOn: plan?.targetReachedOn,
                     week: week, minutes: minutes,
                     line: PaywallCopy.planLine(courseName: name, minutes: minutes, examDate: exam?.date, now: app.now))
    }
}
