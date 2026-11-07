import SwiftUI

/// "Fill the gap": how Cap can help with an exam's topics that have no notes. Snap the chapter (the best: Cap writes from the student's own book) or, on Pro and at 18
/// or over, find it on trusted study sites. A sheet of its own, not a chat: it spends no tutor or drafts allowance, and research runs and reads the same as in Ask.
/// Nothing is added until the student says so: pages go through the usual review, and a summary becomes a note, then a draft set, on a tap.
///
/// Harness: `CRAMLESS_GAP=sheet` opens it over the exam page (with `CRAMLESS_ROUTE=exam:1`); `research` starts the web research too (with `CRAMLESS_PLAN=pro`), and a later screenshot
/// shows it done. `CRAMLESS_RESEARCH=pro` is a free account's refusal from the relay.
struct FillGapSheet: View {
    let examID: UUID
    /// The topic asked about; nil: the student picks among the gaps.
    var topicID: UUID?

    @Environment(AppModel.self) private var app
    @State private var chosen: UUID?
    @State private var run: ResearchRunState?
    @State private var worker: Task<Void, Never>?
    @State private var asksConsent = false
    /// The sheet hugs what it holds; past the screen it is a large sheet that scrolls.
    @State private var contentHeight: CGFloat = 460
    @State private var detent: PresentationDetent = .height(460)

    private struct ResearchRunState {
        var step: AssistantStep
        var result: ResearchResult
    }

    private var exam: Exam? { app.exam(examID) }
    private var courseID: UUID? { exam?.course?.id }
    private var topics: [ExamGap.Topic] {
        guard let exam else { return [] }
        return app.examGap(for: exam)?.topics ?? []
    }
    private var topic: ExamGap.Topic? {
        let id = chosen ?? topicID
        return topics.first { $0.id == id } ?? named(id) ?? topics.first
    }

    /// A topic asked about by its row that isn't in the list (its drafts were dropped since, or the exam is close): still fillable.
    private func named(_ id: UUID?) -> ExamGap.Topic? {
        guard let id, let found = exam?.course?.liveTopics.first(where: { $0.id == id }) else { return nil }
        return ExamGap.Topic(id: found.id, name: found.name)
    }

    /// Web research is on offer: never under 18, and not when it's switched off.
    private var offersResearch: Bool { !app.settings.isMinor && app.settings.assistantWeb && app.ai.cloudAvailableInThisBuild }
    private var isPaid: Bool { app.purchases.plan.isPaid }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Fill the gap")
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    CLIconButton(systemImage: "xmark", label: "Close") { close() }
                }
                if let run {
                    researchCard(run).padding(.top, 14)
                } else {
                    choosing
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                let fitted = height + 12
                guard abs(fitted - contentHeight) > 1 else { return }
                let wasFitted = detent != .large
                contentHeight = fitted
                if wasFitted { detent = .height(fitted) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(CLColor.background.ignoresSafeArea())
        .presentationDetents([.height(contentHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
        .sheet(isPresented: $asksConsent, onDismiss: { if app.ai.hasCloudConsent { startResearch() } }) {
            ConsentSheet(reason: .cloudAI(feature: String(localized: "Find it on trusted study sites")), onClose: { asksConsent = false })
                .environment(app)
        }
        .onDisappear { worker?.cancel() }
        #if DEBUG
        .task {
            if TestHarness.value("CRAMLESS_GAP") == "research", run == nil { startResearch() }
        }
        #endif
    }

    // MARK: Choosing

    @ViewBuilder
    private var choosing: some View {
        Text("How should Cap help?")
            .clFont(.callout)
            .foregroundStyle(CLColor.ink2)
            .padding(.top, 2)
        if topics.count > 1 {
            CaptureChips {
                ForEach(topics) { option in
                    let isOn = option.id == topic?.id
                    Button {
                        CLHaptics.select()
                        chosen = option.id
                    } label: {
                        Text(verbatim: option.name)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(isOn ? CLColor.onFill : CLColor.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .frame(minHeight: CLMetrics.minHitTarget)
                            // A capsule on one line; a long name on two keeps its corners off the words.
                            .background(isOn ? CLColor.tangerine : CLColor.surface2,
                                        in: RoundedRectangle(cornerRadius: CLMetrics.minHitTarget / 2, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(.top, 14)
        } else if let topic {
            Text(verbatim: topic.name)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .padding(.top, 10)
        }
        CLList {
            Button(action: snap) {
                CaptureOptionRow(systemImage: "camera", tint: .tangerine, title: String(localized: "Snap the chapter"),
                                 subtitle: String(localized: "Best: Cap writes from your own textbook"),
                                 note: AllowanceCopy.scans(left: app.ai.freeCloudUsesLeft(for: .generate)))
            }
            .buttonStyle(.pressable)
            if offersResearch {
                Button(action: askForResearch) {
                    CaptureOptionRow(systemImage: "globe", tint: .sky, title: String(localized: "Find it on trusted study sites"),
                                     subtitle: String(localized: "Up to three searches, and you see every page"), trailing: isPaid ? "chevron.right" : nil)
                        .overlay(alignment: .trailing) {
                            if !isPaid { CLPill(text: "Pro", tone: .tangerine).padding(.trailing, 14) }
                        }
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.top, 16)
        Label("Nothing is added until you say so.", systemImage: "hand.raised")
            .clFont(.footnote)
            .foregroundStyle(CLColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }

    private func snap() {
        CLHaptics.tap()
        guard let courseID, let topic else { return }
        app.router.present(.scanner(courseID: courseID, isOnboarding: false, topicID: topic.id))
    }

    private func askForResearch() {
        CLHaptics.tap()
        guard isPaid else {
            app.router.present(.paywall(.feature(String(localized: "Find it on trusted study sites"))))
            return
        }
        guard app.ai.hasCloudConsent else {
            asksConsent = true
            return
        }
        startResearch()
    }

    // MARK: The research

    private func startResearch() {
        guard let topic, let exam, let course = exam.course else { return }
        let id = UUID().uuidString
        let result = ResearchResult(topic: topic.name)
        let step = AssistantStep(id: id, tool: .researchWeb, status: .working, courseID: course.id, courseName: course.name, title: topic.name,
                                 payload: .research(result))
        run = ResearchRunState(step: step, result: result)
        let courseName = course.name, name = topic.name
        worker = Task {
            let outcome = await app.ai.research(topic: name, focus: nil, course: courseName) { progress in
                run?.result = progress
                run?.step.payload = .research(progress)
            }
            switch outcome {
            case .done(let finished):
                run?.result = finished
                run?.step.payload = .research(finished)
                run?.step.status = .proposed
            case .failed(let message, let needsPro):
                run?.step.status = .failed
                run?.step.detail = message
                run?.step.needsPro = needsPro
            }
        }
    }

    private func researchCard(_ run: ResearchRunState) -> some View {
        ResearchStepView(step: run.step, result: run.result, actions: researchActions, animated: true,
                         saveTitle: String(localized: "Save note and write questions"))
    }

    private var researchActions: AssistantStepActions {
        var actions = AssistantStepActions()
        actions.approve = { _ in saveAndWrite() }
        actions.skip = { _ in
            worker?.cancel()
            withAnimation(CLMotion.settle) { run = nil }
        }
        actions.upgrade = { app.router.present(.paywall(.feature(String(localized: "Find it on trusted study sites")))) }
        return actions
    }

    /// The note is saved, then written up like any reading: the questions go to this topic, through the usual review.
    private func saveAndWrite() {
        guard let run, let topic, let courseID else { return }
        CLFeel.play(.saved)
        if let request = app.saveResearch(run.result, forGap: topic.id, courseID: courseID) {
            app.router.present(.captureFlow(request))
        } else {
            app.router.dismissSheet()
            app.router.toast("Note saved")
        }
    }

    private func close() {
        worker?.cancel()
        app.router.dismissSheet()
    }
}
