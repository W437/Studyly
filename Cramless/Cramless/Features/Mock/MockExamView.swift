import SwiftUI
import UIKit

/// A mock exam, full screen: a short intro, the questions one at a time with no marks until the end (Back, Next and Flag; a countdown
/// unless "Time limit" is off), a grid to look over them and hand in, "Time's up." when the clock runs out, marking, and the summary.
/// Never on the eve or the exam day: tonight is for weak spots and sleep.
///
/// DEBUG: `CRAMLESS_ROUTE=mock[:n]` opens it for the nth upcoming exam (without a number, the first that has enough questions).
/// `CRAMLESS_MOCK=intro|mcq|short|review|timeup|marking|summary|selfcheck` opens on that state (`selfcheck` with `CRAMLESS_CONSENT=0`: the
/// own-words answers are the person's to mark); `CRAMLESS_MOCK_AUTOPLAY=rrwpk…` answers by that pattern (`r` right, `p` partly right, `w`
/// wrong, `k` left blank), `CRAMLESS_AUTOPLAY_BEAT` ms apart, then hands in; `CRAMLESS_MOCK_ELAPSED=<s>` starts the clock that far gone.
struct MockExamView: View {
    let examID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var runner: MockRunner?
    @State private var loaded = false
    @State private var timed = true
    @State private var confirmStop = false
    /// Practice from the summary runs in this same cover: changing the cover's item ends the new session as the old cover leaves.
    @State private var practice: SessionRequest?

    var body: some View {
        ZStack {
            CLColor.background.ignoresSafeArea()
            if let practice {
                SessionView(request: practice)
                    .transition(.opacity)
            } else if let runner {
                content(runner)
            } else if loaded {
                MockUnavailableView(examID: examID)
            }
        }
        .captureDebugCanvas()
        .task {
            guard !loaded else { return }
            #if DEBUG
            app.applyHarnessScenarioOnce(examID: examID)
            #endif
            // Never on the eve or the day, however it was reached.
            if let exam = app.exam(examID), case .ready = app.mockOffer(for: exam) {
                runner = MockRunner(app: app, examID: examID)
            }
            loaded = true
            CLHaptics.prepare()
            CLFeel.prepare()
            #if DEBUG
            if let runner { await MockDebug.play(runner: runner, timed: $timed) }
            #endif
        }
        .onDisappear { runner?.abandon() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { runner?.checkTime() }
        }
        .confirmationDialog("Stop the mock exam?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop and mark", role: .destructive) { handIn() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your answers so far are marked. The rest are left out.")
        }
    }

    @ViewBuilder
    private func content(_ runner: MockRunner) -> some View {
        switch runner.phase {
        case .intro:
            MockIntroView(runner: runner, timed: $timed, onStart: { start(runner) }, onClose: { app.router.dismissCover() })
                .transition(.opacity)
        case .answering, .timeUp:
            MockSittingView(runner: runner, onClose: { close(runner) }, onHandIn: handIn)
                .overlay {
                    if runner.phase == .timeUp {
                        MockTimeUpCard(runner: runner, onUntimed: {
                            CLHaptics.tap()
                            withAnimation(CLMotion.settle) { runner.finishUntimed() }
                        }, onScore: handIn)
                        .transition(.opacity)
                    }
                }
                .animation(CLMotion.settle, value: runner.phase == .timeUp)
                .transition(.opacity)
        case .review:
            MockReviewView(runner: runner, onHandIn: handIn)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        case .marking:
            MockMarkingView(runner: runner)
                .transition(.opacity)
        case .summary:
            MockSummaryView(runner: runner, onDone: { app.router.dismissCover() }, onPractice: { request in
                withAnimation(CLMotion.fade) { practice = request }
            })
            .transition(.opacity)
        }
    }

    private func start(_ runner: MockRunner) {
        CLHaptics.commit()
        withAnimation(CLMotion.fade) { runner.start(timed: timed) }
    }

    private func close(_ runner: MockRunner) {
        if runner.answeredCount > 0 {
            confirmStop = true
        } else {
            runner.abandon()
            app.router.dismissCover()
        }
    }

    private func handIn() {
        guard let runner else { return }
        CLHaptics.commit()
        Task { await runner.handIn() }
    }
}

/// Nothing to sit: the exam has too few questions, or it is too close (or the exam has gone).
private struct MockUnavailableView: View {
    let examID: UUID

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            CapView(pose: .study, size: 130)
            Text(MockCopy.title)
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
            Text(verbatim: message)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Done") { app.router.dismissCover() }
                .buttonStyle(.cl(.primary))
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.bottom, 12)
    }

    private var message: String {
        guard let exam = app.exam(examID) else { return String(localized: "This exam is gone.") }
        if case .tooFew(let have) = app.mockOffer(for: exam) { return MockCopy.tooFew(have: have, format: exam.format) }
        return String(localized: "Not this close to the exam. Tonight is for your weak spots, then sleep.")
    }
}

// MARK: - Intro

private struct MockIntroView: View {
    let runner: MockRunner
    @Binding var timed: Bool
    let onStart: () -> Void
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
                    CapView(pose: .study, size: 130)
                    VStack(spacing: 6) {
                        Text(MockCopy.title)
                            .clFont(.title)
                            .foregroundStyle(CLColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: runner.examTitle)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.ink2)
                    }
                    .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 10) {
                        let words = MockCopy.offer(runner.plan, format: runner.format)
                        Text(verbatim: words.line)
                            .clFont(.headline)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: words.mix)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("No marks until the end, like the real thing.")
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(isOn: $timed) {
                            Text("Time limit").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                        }
                        .tint(CLColor.tangerine)
                        .frame(minHeight: CLMetrics.minHitTarget)
                        .padding(.top, 4)
                    }
                    .clCard()
                }
                .frame(maxWidth: CLMetrics.readableWidth)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(action: onStart) {
                Text("Start")
            }
            .buttonStyle(.cl(.primary))
            .frame(maxWidth: CLMetrics.readableWidth)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - The sitting

/// The top bar, the question and the footer. The question reads and writes only its own answer, so typing touches nothing else.
private struct MockSittingView: View {
    let runner: MockRunner
    let onClose: () -> Void
    let onHandIn: () -> Void

    @Environment(\.clReduceMotion) private var reduceMotion
    /// Which way the last move went, for the slide.
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            MockTopBar(runner: runner, onClose: onClose)
            ZStack {
                if let entry = runner.current {
                    if let item = runner.item(entry) {
                        MockQuestionPage(runner: runner, entry: entry, item: item) { secondary }
                            .id(entry.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    } else {
                        // The question was deleted on another device: it stays blank.
                        Color.clear.onAppear { if !runner.isLast { runner.next() } }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sessionFooter {
            footer
        } secondary: {
            secondary
        }
        .background { MockClock(runner: runner) }
    }

    @ViewBuilder private var footer: some View {
        if runner.isLast {
            Button {
                CLHaptics.tap()
                withAnimation(CLMotion.settle) { runner.openReview() }
            } label: {
                Text("Review and hand in")
            }
            .buttonStyle(.cl(.primary))
        } else {
            Button {
                CLHaptics.select()
                forward = true
                withAnimation(CLMotion.settle) { runner.next() }
            } label: {
                Text("Next")
            }
            .buttonStyle(.cl(.primary))
        }
    }

    @ViewBuilder private var secondary: some View {
        Button {
            CLHaptics.select()
            forward = false
            withAnimation(CLMotion.settle) { runner.back() }
        } label: {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.cl(.ghost, size: .medium))
        .disabled(runner.isFirst)
        .opacity(runner.isFirst ? 0.4 : 1)
        Button {
            CLHaptics.select()
            runner.toggleFlag()
        } label: {
            Label("Flag", systemImage: runner.isFlagged ? "flag.fill" : "flag")
        }
        .buttonStyle(.cl(.ghost, size: .medium))
        .accessibilityValue(runner.isFlagged ? Text("Flagged") : Text("Not flagged"))
        Button {
            CLHaptics.tap()
            withAnimation(CLMotion.settle) { runner.openReview() }
        } label: {
            Label("All", systemImage: "square.grid.3x3")
        }
        .buttonStyle(.cl(.ghost, size: .medium))
        .accessibilityLabel("Look over every question")
    }
}

/// Close, how far along, and the countdown.
private struct MockTopBar: View {
    let runner: MockRunner
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CLIconButton(systemImage: "xmark", label: String(localized: "Stop the mock exam"), action: onClose)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: MockCopy.position(runner.position + 1, of: runner.total))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .contentTransition(.numericText())
                CLBar(value: Double(runner.answeredCount) / Double(max(1, runner.total)), color: CLColor.tangerine, height: 6)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: MockCopy.position(runner.position + 1, of: runner.total)))
            .accessibilityValue(Text(verbatim: MockCopy.tally(answered: runner.answeredCount, flagged: runner.flaggedCount)))
            if let deadline = runner.deadline {
                MockCountdown(deadline: deadline)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// The time left in a glass pill. The system counts it down on its own: nothing here re-runs each second.
private struct MockCountdown: View {
    let deadline: Date

    var body: some View {
        // A range that ended stops at 0:00 rather than trapping.
        let now = Date()
        Text(timerInterval: min(now, deadline)...deadline, countsDown: true)
            .clFont(.number(15, .bold))
            .foregroundStyle(CLColor.ink2)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .frame(minWidth: 62, minHeight: 32)
            .glassEffect(.regular, in: Capsule())
            .accessibilityLabel("Time left")
    }
}

/// Fires when the time is up, and says so to VoiceOver with 5 and 1 minutes left. Holds no state a body reads: nothing redraws for it.
private struct MockClock: View {
    let runner: MockRunner

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .task(id: runner.deadline) {
                guard let deadline = runner.deadline else { return }
                for mark in [300.0, 60.0] {
                    let wait = deadline.timeIntervalSinceNow - mark
                    guard wait > 0 else { continue }
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                    let left = Int(mark / 60)
                    AccessibilityNotification.Announcement(String(localized: "\(left) minutes left")).post()
                }
                let wait = deadline.timeIntervalSinceNow
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                }
                withAnimation(CLMotion.settle) { runner.checkTime() }
            }
    }
}

// MARK: - The grid

/// Every question at a glance, answered, flagged or blank, and "Hand it in".
private struct MockReviewView: View {
    let runner: MockRunner
    let onHandIn: () -> Void

    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CLIconButton(systemImage: "chevron.left", label: String(localized: "Back to the questions")) {
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) { runner.closeReview() }
                }
                Text("Look it over")
                    .clFont(.title3)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let deadline = runner.deadline { MockCountdown(deadline: deadline) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: MockCopy.tally(answered: runner.answeredCount, flagged: runner.flaggedCount))
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                    if let blanks = MockCopy.blanksLine(runner.blankCount) {
                        Text(verbatim: blanks)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tile), spacing: 10)], spacing: 10) {
                        ForEach(Array(runner.plan.entries.enumerated()), id: \.element.id) { index, entry in
                            tileView(index: index, entry: entry)
                        }
                    }
                }
                .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(action: onHandIn) {
                Text("Hand it in")
            }
            .buttonStyle(.cl(.primary))
            .frame(maxWidth: CLMetrics.readableWidth)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
        }
        .background { MockClock(runner: runner) }
    }

    private func tileView(index: Int, entry: SessionEntry) -> some View {
        let answered = runner.isAnswered(entry)
        let flagged = runner.flagged.contains(entry.itemID)
        return Button {
            CLHaptics.select()
            withAnimation(CLMotion.settle) { runner.go(to: index) }
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: "\(index + 1)")
                    .clFont(.number(17, .bold))
                    .foregroundStyle(answered ? CLColor.ink : CLColor.ink3)
                HStack(spacing: 4) {
                    Image(systemName: answered ? "checkmark" : "minus")
                        .foregroundStyle(answered ? CLColor.mintInk : CLColor.ink4)
                    if flagged {
                        Image(systemName: "flag.fill").foregroundStyle(CLColor.tangerineInk)
                    }
                }
                .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: tile)
            .background(answered ? CLColor.surface : CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(flagged ? CLColor.tangerine : CLColor.hairline, lineWidth: flagged ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Question \(index + 1)"))
        .accessibilityValue(Text(flagged ? (answered ? "Answered, flagged" : "Blank, flagged") : (answered ? "Answered" : "Blank")))
    }
}

// MARK: - Time's up and marking

private struct MockTimeUpCard: View {
    let runner: MockRunner
    let onUntimed: () -> Void
    let onScore: () -> Void

    var body: some View {
        ZStack {
            CLColor.night.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                CapView(pose: .think, size: 96)
                Text("Time's up.")
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: MockCopy.timeUpLine(answered: runner.answeredCount, total: runner.total))
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onUntimed) {
                    Text("Finish untimed")
                }
                .buttonStyle(.cl(.primary))
                .padding(.top, 6)
                Button(action: onScore) {
                    Text("See my score")
                }
                .buttonStyle(.cl(.soft))
            }
            .frame(maxWidth: 360)
            .clCard(padding: 22)
            .padding(.horizontal, CLSpace.gutter)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            CLHaptics.commit()
            AccessibilityNotification.Announcement(String(localized: "Time's up.")).post()
        }
    }
}

private struct MockMarkingView: View {
    let runner: MockRunner

    var body: some View {
        VStack(spacing: 12) {
            CapView(pose: .study, size: 130)
            Text("Marking your answers…")
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            if runner.markingTotal > 0 {
                Text(verbatim: MockCopy.markingLine(done: runner.markingDone, total: runner.markingTotal, hasEssays: runner.plan.essayCount > 0))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .contentTransition(.numericText())
                    .animation(CLMotion.snap, value: runner.markingDone)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, CLSpace.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DEBUG

#if DEBUG
/// Puts a sitting in the state `CRAMLESS_MOCK` names, and plays `CRAMLESS_MOCK_AUTOPLAY` (see `MockExamView`).
@MainActor
enum MockDebug {
    static func play(runner: MockRunner, timed: Binding<Bool>) async {
        let elapsed = TestHarness.value("CRAMLESS_MOCK_ELAPSED").flatMap(TimeInterval.init) ?? 0
        if let raw = TestHarness.once("CRAMLESS_MOCK_AUTOPLAY") {
            let pattern = Array(raw.lowercased())
            let beat = TestHarness.value("CRAMLESS_AUTOPLAY_BEAT").flatMap(Int.init) ?? 1100
            do { try await nap(beat) } catch { return }
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            guard !pattern.isEmpty else { return }
            for (index, entry) in runner.plan.entries.enumerated() {
                runner.debugAnswer(entry, step: pattern[index % pattern.count])
                do { try await nap(beat) } catch { return }
                if index < runner.total - 1 { withAnimation(CLMotion.settle) { runner.next() } }
                do { try await nap(beat / 3) } catch { return }
            }
            withAnimation(CLMotion.settle) { runner.openReview() }
            do { try await nap(beat * 2) } catch { return }
            await runner.handIn()
            return
        }
        let answers = Array("rrwrrkrprrwrrrprrwrk")
        switch TestHarness.once("CRAMLESS_MOCK") {
        case "mcq":
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            if let first = runner.current { runner.debugAnswer(first, step: "r") }
        case "short":
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            if let index = runner.plan.entries.firstIndex(where: { $0.kind.isOwnWords }) {
                runner.go(to: index)
                runner.debugAnswer(runner.plan.entries[index], step: "p")
            }
        case "cloze":
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            if let index = runner.plan.entries.firstIndex(where: { $0.kind == .cloze }) { runner.go(to: index) }
        case "review":
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            runner.debugAnswer(pattern: answers, through: runner.total - 2)
            runner.debugFlag(2)
            runner.debugFlag(5)
            runner.openReview()
        case "timeup":
            runner.debugAnswerAfterStart(pattern: answers, through: max(1, runner.total - 3))
        case "marking":
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            runner.debugAnswer(pattern: answers)
            runner.debugHoldsMarking = true
            await runner.handIn()
        case "summary", "selfcheck":
            runner.start(timed: timed.wrappedValue, elapsed: elapsed)
            runner.debugAnswer(pattern: answers)
            await runner.handIn()
        default:
            break
        }
    }
}

private extension MockRunner {
    /// Starts a clock that has already run out, with some answers given.
    func debugAnswerAfterStart(pattern: [Character], through: Int) {
        start(timed: true, elapsed: 0)
        debugAnswer(pattern: pattern, through: through)
        debugRunOutTheClock()
    }
}
#endif
