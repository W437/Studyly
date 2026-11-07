import SwiftUI
import UIKit

/// Study out loud, full screen, though the point is that nobody has to look at it: Cap asks, the person answers with their voice, for the bus, a
/// walk or the gym. An intro with the session's size; then who is talking, the question, the words as they're heard, how it went, and Repeat and Skip
/// for when a hand is free. The screen can go off at any point; the Live Activity carries on with the same line. The summary is a session's own.
///
/// What it reads and how it grades is `OutLoudController`. DEBUG: `CRAMLESS_ROUTE=outLoud`, `CRAMLESS_OUTLOUD=asking|listening|verdict|summary|blocked|nomodel`,
/// `CRAMLESS_OUTLOUD_SCRIPT=rpwk` (`OutLoudDebug`).
struct OutLoudView: View {
    let request: SessionRequest
    var startsAtOnce = false

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: OutLoudController?
    /// A session from the summary, or the same questions on screen, runs in this same cover: changing the cover's item would end it as the old cover leaves.
    @State private var onScreen: SessionRequest?

    var body: some View {
        ZStack {
            CLColor.background.ignoresSafeArea()
            if let onScreen {
                SessionView(request: onScreen)
                    .transition(.opacity)
            } else if let controller {
                content(controller)
            }
        }
        .captureDebugCanvas()
        .task {
            guard controller == nil else { return }
            let made = OutLoudController(app: app, request: request)
            controller = made
            CLHaptics.prepare()
            if startsAtOnce { made.start() }
        }
        .onDisappear { controller?.close() }
        .onChange(of: scenePhase) { _, phase in
            controller?.isOnScreen = phase == .active
            // Leaving the screen may be the last moment before iOS closes the app.
            if phase != .active { controller?.runner.keepCheckpoint() }
        }
    }

    @ViewBuilder
    private func content(_ controller: OutLoudController) -> some View {
        switch controller.phase {
        case .intro, .gettingReady:
            OutLoudIntroView(controller: controller, onClose: { app.router.dismissCover() })
                .transition(.opacity)
        case .blocked(let block):
            OutLoudBlockedView(block: block, onRetry: { controller.start() },
                               onScreen: { withAnimation(CLMotion.fade) { onScreen = plain(request) } },
                               onClose: { app.router.dismissCover() })
                .transition(.opacity)
        case .finished:
            if controller.runner.distinctAnswered > 0, let summary = controller.runner.summary {
                SessionSummaryView(runner: controller.runner, summary: summary, onDone: { app.router.dismissCover() },
                                   onStart: { next in withAnimation(CLMotion.fade) { onScreen = next } })
                    .transition(.opacity)
            } else {
                Color.clear.onAppear { app.router.dismissCover() }
            }
        default:
            OutLoudSessionView(controller: controller, onClose: { leave(controller) })
                .transition(.opacity)
        }
    }

    /// The same session, with every kind of question.
    private func plain(_ request: SessionRequest) -> SessionRequest {
        var plain = request
        plain.id = UUID()
        plain.spokenOnly = false
        return plain
    }

    private func leave(_ controller: OutLoudController) {
        let answered = controller.runner.distinctAnswered
        controller.close()
        app.router.dismissCover()
        if answered > 0 {
            let saved = SessionCopy.questions(answered)
            app.router.toast("\(saved.prefix(1).uppercased() + saved.dropFirst()) saved.", systemImage: "checkmark.circle.fill", tone: .neutral)
        }
    }
}

// MARK: - Intro

private struct OutLoudIntroView: View {
    let controller: OutLoudController
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CLIconButton(systemImage: "xmark", label: String(localized: "Close"), action: onClose)
                Spacer()
            }
            .padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 14) {
                    CapView(pose: .mic, size: 130, idle: .breathe)
                    VStack(spacing: 6) {
                        Text(OutLoudCopy.title)
                            .clFont(.title)
                            .foregroundStyle(CLColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(OutLoudCopy.pitch)
                            .clFont(.callout)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    if controller.hasQuestions { details } else { nothing }
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: OutLoudCopy.size(questions: controller.questionCount, minutes: controller.minutes))
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(OutLoudCopy.whyFewer)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Label(OutLoudCopy.screenOff, systemImage: "lock.fill")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text(OutLoudCopy.privacy)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard()
    }

    private var nothing: some View {
        Text(OutLoudCopy.nothingToAsk)
            .clFont(.headline)
            .foregroundStyle(CLColor.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .clCard()
    }

    @ViewBuilder private var footer: some View {
        Group {
            if case .gettingReady(let progress) = controller.phase {
                Button {} label: {
                    Text(OutLoudCopy.downloading(progress))
                }
                .buttonStyle(.cl(.soft))
                .disabled(true)
            } else if controller.hasQuestions {
                Button {
                    CLHaptics.commit()
                    controller.start()
                } label: {
                    Label { Text(OutLoudCopy.start) } icon: { Image(systemName: "mic.fill") }
                }
                .buttonStyle(.cl(.primary))
            } else {
                Button("Done", action: onClose)
                    .buttonStyle(.cl(.primary))
            }
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.bottom, 12)
    }
}

// MARK: - Blocked

private struct OutLoudBlockedView: View {
    let block: OutLoudBlock
    let onRetry: () -> Void
    let onScreen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CLIconButton(systemImage: "xmark", label: String(localized: "Close"), action: onClose)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 14) {
                    CapView(pose: .think, size: 120, idle: .breathe)
                    Text(block.title)
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(block.detail)
                        .clFont(.callout)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            if block.opensSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.cl(.primary))
            } else if block.canRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.cl(.primary))
            }
            Button("Study on screen", action: onScreen)
                .buttonStyle(.cl(.soft))
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.bottom, 12)
    }
}

// MARK: - The session

private struct OutLoudSessionView: View {
    let controller: OutLoudController
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SessionTopBar(runner: controller.runner, onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OutLoudStatus(controller: controller)
                    if let question = controller.question {
                        OutLoudQuestionCard(question: question, verdict: controller.verdict, answered: isAnswered)
                    }
                    OutLoudHeardLine(controller: controller)
                    if let verdict = controller.verdict {
                        OutLoudVerdictCard(verdict: verdict)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            OutLoudControls(controller: controller)
        }
        .overlay { SkyFlareView(flare: controller.runner.saveFlare) }
        .animation(CLMotion.settle, value: controller.verdict)
        // Your turn: a tap in the hand, as Cap stops talking.
        .onChange(of: controller.isListening) { _, listening in
            if listening { CLHaptics.select() }
        }
    }

    private var isAnswered: Bool { controller.verdict?.pickedPlace != nil }
}

/// Cap, and whose turn it is.
private struct OutLoudStatus: View {
    let controller: OutLoudController

    var body: some View {
        HStack(spacing: 14) {
            CapView(moment, size: 92, interactive: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(line)
                    .clFont(.title3)
                    .foregroundStyle(controller.isListening ? CLColor.tangerineInk : CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                if let hint {
                    Text(hint)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // One label for each state: never one word fading over the last, whatever the page around it is animating.
            .transaction { $0.animation = nil }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var moment: CapMoment {
        switch controller.phase {
        case .listening: CapMoment(pose: .listen, idle: .breathe)
        case .checking: .working
        case .paused: CapMoment(pose: .relax, idle: .breathe)
        case .verdict: controller.verdict?.moment ?? CapMoment(pose: .proud, idle: .breathe)
        default: CapMoment(pose: .ask, idle: .breathe)
        }
    }

    private var line: LocalizedStringResource {
        switch controller.phase {
        case .listening: OutLoudCopy.yourTurn
        case .checking: OutLoudCopy.checking
        case .paused(let pause): pause.line
        // Graded, or only said: a flashcard's answer, or one asked for with "I don't know".
        case .verdict: controller.verdict?.tone == .neutral ? OutLoudCopy.theAnswer : OutLoudCopy.howItWent
        default: OutLoudCopy.asking
        }
    }

    private var hint: LocalizedStringResource? {
        if case .listening(let reply) = controller.phase { return reply ? OutLoudCopy.replyHint : OutLoudCopy.hint }
        return nil
    }
}

/// The question, for whoever does look: its words, and a multiple choice's options by letter, marked once it's answered.
private struct OutLoudQuestionCard: View {
    let question: OutLoudQuestion
    let verdict: OutLoudController.Verdict?
    let answered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: question.prompt)
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !question.options.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { place, option in
                        optionRow(place, option)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard()
    }

    private func optionRow(_ place: Int, _ option: String) -> some View {
        let letter = ChoiceOrder.letters[min(place, ChoiceOrder.letters.count - 1)]
        let isRight = answered && place == question.rightPlace
        let isWrongPick = answered && place == verdict?.pickedPlace && place != question.rightPlace
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: letter)
                .clFont(.bodyEmphasis)
                .foregroundStyle(isRight ? CLColor.mintInk : isWrongPick ? CLColor.roseInk : CLColor.ink2)
            Text(verbatim: option)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isRight || isWrongPick {
                Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isRight ? CLColor.mintInk : CLColor.roseInk)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isRight ? "Right answer" : isWrongPick ? "Your answer, not right" : ""))
    }
}

/// The words as they're heard. Only this view reads them, so a word arriving redraws nothing else.
private struct OutLoudHeardLine: View {
    let controller: OutLoudController

    var body: some View {
        if controller.isListening, !controller.heard.isEmpty {
            Text(verbatim: controller.heard)
                .clFont(.body)
                .italic()
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
                .accessibilityLabel(Text("Cap heard: \(controller.heard)"))
        }
    }
}

private struct OutLoudVerdictCard: View {
    let verdict: OutLoudController.Verdict

    var body: some View {
        Text(verbatim: verdict.line)
            .clFont(.bodyEmphasis)
            .foregroundStyle(verdict.tone.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(verdict.tone.fill, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
    }
}

/// The level while the microphone is open, and the buttons for when a hand is free. The meter is its own view: only it reads the levels.
private struct OutLoudControls: View {
    let controller: OutLoudController

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            if controller.isListening {
                LectureLevelWaveform(levels: controller.levels, active: true, animated: !reduceMotion)
                    .frame(height: 44)
                    .clipped()
            }
            if controller.isPaused {
                Button {
                    CLHaptics.tap()
                    controller.perform(.resume)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.cl(.primary))
            } else {
                buttons
            }
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    /// Repeat and Skip side by side, Pause as a mark beside them, which leaves their words room on the smallest iPhone. At the largest text sizes, three marks in a row: the words
    /// won't fit, and a column of three would cover the question. VoiceOver and a long press say what they are.
    @ViewBuilder private var buttons: some View {
        if typeSize.isAccessibilitySize {
            HStack(spacing: 8) {
                markButton(OutLoudActivityCopy.repeatTitle, systemImage: "arrow.counterclockwise") {
                    CLHaptics.tap()
                    controller.perform(.repeatQuestion)
                }
                markButton(OutLoudActivityCopy.skipTitle, systemImage: "forward.end") {
                    CLHaptics.tap()
                    controller.perform(.skip)
                }
                markButton("Pause", systemImage: "pause", action: pause)
            }
        } else {
            HStack(spacing: 8) {
                repeatButton
                skipButton
                CLIconButton(systemImage: "pause.fill", label: String(localized: "Pause"), action: pause)
            }
        }
    }

    private func markButton(_ title: LocalizedStringResource, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.cl(.soft, size: .medium))
        .accessibilityLabel(Text(title))
        .accessibilityShowsLargeContentViewer { Label { Text(title) } icon: { Image(systemName: systemImage) } }
    }

    private var repeatButton: some View {
        Button {
            CLHaptics.tap()
            controller.perform(.repeatQuestion)
        } label: {
            Label(OutLoudActivityCopy.repeatTitle, systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.cl(.soft, size: .medium))
    }

    private var skipButton: some View {
        Button {
            CLHaptics.tap()
            controller.perform(.skip)
        } label: {
            Label(OutLoudActivityCopy.skipTitle, systemImage: "forward.end")
        }
        .buttonStyle(.cl(.soft, size: .medium))
    }

    private func pause() {
        CLHaptics.tap()
        controller.perform(.pause)
    }
}
