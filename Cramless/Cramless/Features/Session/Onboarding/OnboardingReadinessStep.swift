import SwiftUI

/// Onboarding's readiness reveal. Makes the person's exam from the date they gave (`settings.nextExamDate`) when
/// they have none yet, titled after the course; then the ring climbs to today's honest value ("You're 10% ready for
/// your Bio 101 exam") with the same climb as the session summary, and the topics fill in. With no exam date, it
/// shows how much of the course they know instead.
///
/// Plugged into `OnboardingFlow` by the orchestrator:
///
///     OnboardingReadinessStep(courseID: firstSetCourse) { onboarding.advance() }
struct OnboardingReadinessStep: View {
    let courseID: UUID?
    let onDone: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var model: Model?
    @State private var ring: Double = 0
    @State private var told = false
    @State private var barsShown = 0

    init(courseID: UUID?, onDone: @escaping () -> Void) {
        self.courseID = courseID
        self.onDone = onDone
    }

    struct Model: Equatable {
        var value: Double
        var hasExam: Bool
        var title: String
        var detail: String
        var caption: String
        var topics: [Topic]

        struct Topic: Equatable, Identifiable {
            var id: UUID
            var name: String
            var value: Double?
            var itemCount: Int
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ReadinessRing(value: ring, size: 156, lineWidth: 16, caption: model?.caption)
                    .padding(.top, 12)
                    .accessibilityHidden(!told)
                if let model {
                    Text(model.title)
                        .clFont(.brandTitle(28))
                        .foregroundStyle(CLColor.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                        .opacity(told ? 1 : 0)
                        .offset(y: told ? 0 : 10)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.detail)
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .opacity(told ? 1 : 0)
                    if !model.topics.isEmpty {
                        topics(model)
                            .padding(.top, 24)
                            .opacity(told ? 1 : 0)
                    }
                }
            }
            .frame(maxWidth: CLMetrics.readableWidth)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(CLColor.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            Button("See my plan") {
                CLHaptics.tap()
                onDone()
            }
            .buttonStyle(.cl(.primary))
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { await reveal() }
    }

    private func topics(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CLEyebrow(text: model.hasExam ? "By topic, on exam day" : "By topic, today")
            ForEach(Array(model.topics.enumerated()), id: \.element.id) { index, topic in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(topic.name)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(valueLabel(topic))
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(topic.value.map { $0 > 0 } == true ? CLColor.ink : CLColor.ink3)
                    }
                    CLBar(value: barsShown > index ? (topic.value ?? 0) : 0,
                          color: CLColor.readiness(topic.value ?? 0), height: 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(topic.name)
                .accessibilityValue(valueLabel(topic))
            }
        }
        .clCard()
    }

    private func valueLabel(_ topic: Model.Topic) -> String {
        guard let value = topic.value else { return "No questions yet" }
        return value < 0.005 ? "Not started" : CLFormat.percent(value)
    }

    // MARK: The reveal

    private func reveal() async {
        guard model == nil else { return }
        let made = makeModel()
        model = made
        if reduceMotion {
            ring = made.value
            told = true
            barsShown = made.topics.count
        } else {
            try? await nap(350)
            withAnimation(CLMotion.fill) { ring = made.value }
            try? await nap(1150)
            withAnimation(CLMotion.settle) { told = true }
            try? await nap(300)
            for index in made.topics.indices {
                barsShown = index + 1
                try? await nap(150)
            }
        }
        AccessibilityNotification.Announcement("\(made.title). \(made.detail)").post()
    }

    private func makeModel() -> Model {
        let course = app.onboardingCourse(courseID)
        if let exam = app.ensureOnboardingExam(courseID: courseID) {
            let readiness = app.readiness(for: exam)
            let days = readiness.daysLeft
            let date = CLFormat.day(exam.date)
            let target = CLFormat.percent(readiness.target)
            let topics = readiness.topics.prefix(6).map {
                Model.Topic(id: $0.id, name: $0.name, value: $0.value, itemCount: $0.itemCount)
            }
            let daysLine = days == 1 ? "One day to go" : "\(days) days to go"
            return Model(value: readiness.value, hasExam: true,
                         title: "You're \(CLFormat.percent(readiness.value)) ready for your \(SessionCopy.unbroken(exam.title))",
                         detail: "\(daysLine), and it climbs every time you study. Next: your path to \(target) by \(date).",
                         caption: "ready", topics: Array(topics))
        }
        if let course {
            let known = app.knownShare(of: course)
            let topics = app.topicMastery(course: course).filter { $0.itemCount > 0 }.prefix(6).map {
                Model.Topic(id: $0.id, name: $0.name, value: $0.value, itemCount: $0.itemCount)
            }
            return Model(value: known, hasExam: false,
                         title: "You know about \(CLFormat.percent(known)) of \(SessionCopy.unbroken(course.name)) so far",
                         detail: "Add your exam date any time and Capling will plan backwards from it.",
                         caption: "known", topics: Array(topics))
        }
        return Model(value: 0, hasExam: false, title: "Let's get you ready",
                     detail: "Add some material and your readiness shows up here.", caption: "ready", topics: [])
    }
}
