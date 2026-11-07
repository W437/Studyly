import SwiftUI
import UIKit

/// Recording a lecture: a big calm timer, the live level, the transcript as it's heard (the words still being heard
/// in a lighter style than the settled ones), an "On the exam" flag, pause and resume, and an honest line about the
/// transcript (live on this iPhone, a speech model downloading, not available on this device). Stop saves the lecture,
/// makes its notes (`ai.lectureNotes`) and shows them, with its questions waiting for review.
///
/// The recording screen is night-coloured in both appearances: it's glanced at in a dim lecture hall, like a camera.
///
/// DEBUG hooks (with `CRAMLESS_ROUTE=record`; the harness records with the demo transcriber, see `LectureDemo.swift`):
/// `CRAMLESS_RECORD_FLAG=<seconds>` taps the flag after that long, `CRAMLESS_RECORD_PAUSE=<seconds>` pauses, and
/// `CRAMLESS_RECORD_STOP=<seconds>` stops (to see the notes being made, then the notes).
struct RecordView: View {
    let courseID: UUID?

    enum Stage: Equatable {
        case recording
        case makingNotes(UUID)
        case notes(UUID)
        case pending(UUID)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var session: LectureSession?
    @State private var stage: Stage = .recording
    @State private var marked: ExamFlag?
    @State private var markTask: Task<Void, Never>?
    @State private var confirmingClose = false
    @State private var reviewing = false
    @State private var transcribingNow = false
    /// The free AI lecture notes left when the person pressed stop, before this lecture's notes use one (nil on a paid plan).
    @State private var lecturesLeftAtStop: Int?

    var body: some View {
        ZStack {
            switch stage {
            case .recording:
                recorder
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            case .makingNotes:
                makingNotes
                    .transition(.opacity)
            case .notes(let id):
                notes(id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .pending(let id):
                pending(id)
                    .transition(.opacity)
                    .task(id: id) { await waitForTranscript(id) }
            }
        }
        .animation(CLMotion.settle, value: stage)
        // While recording, the status bar and the system's dialogs go night too, whatever the app's theme. After, the notes follow the theme: said outright,
        // because a cover that has been dark stays dark when the preference just goes away.
        .preferredColorScheme(stage == .recording ? .dark : app.themeColorScheme)
        .captureDebugCanvas()
        .task { await begin() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            markTask?.cancel()
        }
    }

    // MARK: Recording

    private var recorder: some View {
        VStack(spacing: 0) {
            topBar
            // At the largest text sizes the header scrolls away with the transcript, so the words have room.
            if !typeSize.isAccessibilitySize {
                header
                    .padding(.top, 6)
            }
            transcript
        }
        .background(CLColor.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) { controls }
        .confirmationDialog("Stop recording?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Stop and save") { Task { await stop() } }
            Button("Discard recording", role: .destructive) { discard() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("Saving keeps the recording and makes notes from it.")
        }
    }

    private var topBar: some View {
        ZStack {
            statusPill
            HStack {
                CaptureGlassButton(systemImage: "xmark", label: "Close") {
                    CLHaptics.tap()
                    if session?.isActive == true { confirmingClose = true } else { close() }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
    }

    @ViewBuilder private var statusPill: some View {
        switch session?.state {
        case .recording:
            HStack(spacing: 6) {
                Circle().fill(CLColor.rose).frame(width: 8, height: 8)
                Text("Recording").font(.system(.caption, design: .rounded, weight: .bold))
            }
            .foregroundStyle(CLColor.roseInk)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(CLColor.roseSoft, in: Capsule())
            .accessibilityElement(children: .combine)
        case .paused(let reason):
            CLPill(text: reason == .interruption ? "Paused for a call" : reason == .lostInput ? "Microphone lost" : "Paused",
                   tone: .sun, systemImage: "pause.fill")
        case .finishing:
            CLPill(text: "Saving", tone: .neutral, systemImage: "arrow.down.circle")
        case .failed:
            CLPill(text: "Not recording", tone: .rose, systemImage: "mic.slash")
        default:
            CLPill(text: "Starting", tone: .neutral, systemImage: "mic")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            CLEyebrow(text: .verbatim(eyebrow), color: CLColor.ink3)
            Text(session?.elapsedText ?? "0:00")
                .clFont(.number(64))
                .foregroundStyle(session?.isPaused == true ? CLColor.ink3 : CLColor.ink)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                .animation(CLMotion.snap, value: session?.elapsedText)
                .accessibilityLabel(Text("Recorded \(spokenDuration)"))
            LectureLevelWaveform(levels: session?.levels ?? [], active: session?.state == .recording, animated: !reduceMotion)
                .frame(height: 64)
                .padding(.horizontal, CLSpace.gutter)
            statusLine
                .padding(.horizontal, CLSpace.gutter + 4)
        }
    }

    private var eyebrow: String {
        let course = app.course(courseID)?.name
        let title = session?.title ?? app.nextLectureTitle(courseID: courseID)
        return [course, title].compactMap { $0 }.joined(separator: " · ")
    }

    private var spokenDuration: String {
        let seconds = Int(session?.elapsed ?? 0)
        let minutes = seconds / 60
        return minutes > 0 ? "\(minutes) minutes \(seconds % 60) seconds" : "\(seconds) seconds"
    }

    @ViewBuilder private var statusLine: some View {
        if let session {
            if case .failed(let failure) = session.state {
                VStack(spacing: 10) {
                    Text(failure.message)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if failure == .microphoneDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { UIApplication.shared.open(url) }
                            .buttonStyle(.cl(.white, size: .small, fullWidth: false))
                    }
                }
                .padding(.top, 6)
            } else {
                VStack(spacing: 6) {
                    Label {
                        Text(session.statusLine)
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: statusSymbol(session.transcription))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(statusTint(session.transcription))
                    }
                    if case .downloading(_, let progress) = session.transcription {
                        CLBar(value: progress, color: CLColor.sky, height: 4)
                            .frame(maxWidth: 220)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func statusSymbol(_ transcription: LectureSession.Transcription) -> String {
        switch transcription {
        case .checking: "ellipsis"
        case .live: "iphone"
        case .downloading: "arrow.down.circle"
        case .afterStop: "clock"
        case .modelUnavailable, .unavailableOnDevice, .unavailableLanguage, .failed: "exclamationmark.triangle"
        case .demo: "play.rectangle"
        }
    }

    private func statusTint(_ transcription: LectureSession.Transcription) -> Color {
        switch transcription {
        case .live: CLColor.mintInk
        case .modelUnavailable, .unavailableOnDevice, .unavailableLanguage, .failed: CLColor.sunInk
        default: CLColor.ink3
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if typeSize.isAccessibilitySize { header.padding(.bottom, 12) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let session {
                        ForEach(session.segments) { segment in
                            TranscriptLine(time: segment.start, text: segment.text, flag: flag(for: segment, in: session))
                        }
                        if !session.liveText.isEmpty {
                            LiveTranscriptLine(text: session.liveText, flagged: liveFlag(in: session))
                        } else if session.segments.isEmpty, session.state == .recording, session.transcription.showsListening {
                            Text("Listening…")
                                .clFont(.body)
                                .italic()
                                .foregroundStyle(CLColor.ink3)
                                .padding(.vertical, 12)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                       .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            }
            .onChange(of: transcriptKey) { _, _ in
                withAnimation(CLMotion.settle) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .padding(.top, 12)
    }

    private var transcriptKey: String {
        guard let session else { return "" }
        return "\(session.segments.count)-\(session.liveText.count / 12)-\(session.flags.count)"
    }

    /// The flag on a settled line: one made while it was being said.
    private func flag(for segment: TranscriptSegment, in session: LectureSession) -> ExamFlag? {
        session.flags.first { flag in
            flag.time >= segment.start - 1 && flag.time <= segment.end + 1.5
        }
    }

    /// A flag made while the current words are still being heard.
    private func liveFlag(in session: LectureSession) -> ExamFlag? {
        let settled = session.segments.last?.end ?? -1
        return session.flags.last { $0.reason == .tapped && $0.time > settled + 1.5 }
    }

    // MARK: Controls

    /// Stop in the middle; the flag and pause share what's left either side, so neither is squeezed. At the largest
    /// text sizes the flag gets a row of its own.
    @ViewBuilder private var controls: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    flagButton.frame(maxWidth: .infinity)
                    HStack(spacing: 16) {
                        pauseButton.frame(maxWidth: .infinity, alignment: .leading)
                        stopButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    flagButton.frame(maxWidth: .infinity, alignment: .leading)
                    stopButton
                    pauseButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .disabled(session?.isActive != true)
    }

    private var flagButton: some View {
        let isMarked = marked != nil
        return Button(action: flag) {
            // Marked: the time it was marked, on tangerine (VoiceOver hears "Marked at 12:58").
            Label(isMarked ? LectureSession.clock(marked?.time ?? 0) : "On the exam",
                  systemImage: isMarked ? "star.fill" : "star")
                .clFont(.subheadlineEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isMarked ? CLColor.onFill : CLColor.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(isMarked ? CLColor.tangerine : CLColor.surface3, in: Capsule())
                .scaleEffect(isMarked && !reduceMotion ? 1.04 : 1)
                .animation(CLMotion.pop, value: isMarked)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Mark this moment as on the exam"))
    }

    private var stopButton: some View {
        Button { Task { await stop() } } label: {
            ZStack {
                Circle().strokeBorder(CLColor.ink.opacity(0.9), lineWidth: 4)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CLColor.rose)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 74, height: 74)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Stop and save"))
    }

    private var pauseButton: some View {
        let paused = session?.isPaused == true
        return Button {
            CLHaptics.tap()
            if paused { session?.resume() } else { session?.pause() }
        } label: {
            Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                .clFont(.subheadlineEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(CLColor.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(CLColor.surface3, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: After stop

    private var makingNotes: some View {
        VStack(spacing: 16) {
            CapView(.working, size: 150)
            Text("Making notes from your lecture")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
            Text(AllowanceCopy.makingNotes(cloud: app.ai.hasCloudConsent && app.ai.cloudAvailableInThisBuild
                                               && app.settings.ageBand != .under13,
                                           lecturesLeft: lecturesLeftAtStop))
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .padding(.top, 6)
        }
        .padding(.horizontal, CLSpace.gutter + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clScreenBackground()
        .accessibilityElement(children: .combine)
    }

    private func notes(_ id: UUID) -> some View {
        NavigationStack {
            LectureNotesView(sourceID: id)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { close() }
                    }
                }
                .safeAreaBar(edge: .bottom) {
                    let drafts = app.draftItems(sourceID: id).count
                    if drafts > 0 {
                        Button("Review \(CLFormat.count(drafts, "question"))") {
                            CLHaptics.tap()
                            reviewing = true
                        }
                        .buttonStyle(.cl(.primary))
                        .padding(.horizontal, CLSpace.gutter)
                        .padding(.top, 10)
                    }
                }
                .sheet(isPresented: $reviewing) {
                    DraftReviewView(sourceID: id, isOnboarding: false, onFinish: { _ in reviewing = false })
                }
        }
    }

    private func pending(_ id: UUID) -> some View {
        VStack(spacing: 14) {
            CapView(transcribingNow ? .working : CapMoment(pose: .sleep), size: 150)
            Text(transcribingNow ? "Making the transcript" : "Saved. The transcript comes next.")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
            Text(transcribingNow ? "On your iPhone, from the recording. The notes come straight after." : pendingReason)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if transcribingNow { ProgressView().padding(.top, 4) }
            Button(transcribingNow ? "Finish later" : "Done") { close() }
                .buttonStyle(.cl(.primary))
                .padding(.top, 10)
        }
        .padding(.horizontal, CLSpace.gutter + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clScreenBackground()
    }

    /// Why there's no transcript yet, from what the session found.
    private var pendingReason: String {
        switch session?.transcription {
        case .downloading(let language, _), .modelUnavailable(let language):
            "Your recording is safe. The \(language) transcript is made on your iPhone once its speech model has downloaded, then the notes follow."
        case .unavailableOnDevice:
            "Your recording is safe. This iPhone can't make transcripts yet, so it stays pending until it can."
        case .unavailableLanguage(let name):
            "Your recording is safe. Transcripts in \(name) aren't available on this iPhone yet, so it stays pending."
        default:
            "Your recording is safe. Its transcript is made on your iPhone when it can be; then open the lecture in your Library to make its notes."
        }
    }

    /// A transcript being made from the recording (the speech model is here, live transcription wasn't): wait for it,
    /// then make the notes. Gives up quietly (the lecture stays pending) when no transcript is being made.
    private func waitForTranscript(_ id: UUID) async {
        var idle = 0
        while !Task.isCancelled, idle < 4 {
            if let source = app.source(id), !source.segments.isEmpty {
                transcribingNow = false
                await makeNotes(id)
                return
            }
            let busy = LectureJobs.transcribing.contains(id)
            if transcribingNow != busy { withAnimation(CLMotion.fade) { transcribingNow = busy } }
            idle = busy ? 0 : idle + 1
            try? await Task.sleep(for: .seconds(1))
        }
        transcribingNow = false
    }

    // MARK: Actions

    private func begin() async {
        guard session == nil else { return }
        let session = app.makeLectureSession(courseID: courseID)
        self.session = session
        UIApplication.shared.isIdleTimerDisabled = true
        await session.start()
        #if DEBUG
        await runDebugHooks(session)
        #endif
    }

    private func flag() {
        guard let session else { return }
        if let flag = session.flag() {
            CLHaptics.commit()
            AccessibilityNotification.Announcement("Marked at \(LectureSession.clock(flag.time))").post()
            show(flag)
        } else if let last = session.flags.last(where: { $0.reason == .tapped }) {
            CLHaptics.select()
            show(last)
        }
    }

    private func show(_ flag: ExamFlag) {
        markTask?.cancel()
        marked = flag
        markTask = Task {
            try? await nap(1600)
            guard !Task.isCancelled else { return }
            marked = nil
        }
    }

    private func stop() async {
        guard let session, session.isActive else { return }
        CLHaptics.commit()
        UIApplication.shared.isIdleTimerDisabled = false
        guard let id = await session.stop(), let source = app.source(id) else { return }
        guard !source.segments.isEmpty else {
            stage = .pending(id)
            return
        }
        await makeNotes(id)
    }

    private func makeNotes(_ id: UUID) async {
        guard let source = app.source(id), !source.segments.isEmpty else { return }
        lecturesLeftAtStop = app.ai.freeCloudUsesLeft(for: .lecture)
        stage = .makingNotes(id)
        let outcome = await app.ai.lectureNotes(app.lectureInput(for: source))
        guard let fresh = app.source(id), fresh.modelContext != nil else { return close() }
        app.saveLectureNotes(outcome, lecture: fresh, course: app.course(courseID))
        CLHaptics.success()
        stage = .notes(id)
    }

    private func discard() {
        CLHaptics.tap()
        session?.discard()
        close()
    }

    private func close() {
        UIApplication.shared.isIdleTimerDisabled = false
        app.router.dismissCover()
    }

    #if DEBUG
    private func runDebugHooks(_ session: LectureSession) async {
        var hooks: [(Double, String)] = []
        if let t = TestHarness.once("CRAMLESS_RECORD_FLAG").flatMap(Double.init) { hooks.append((t, "flag")) }
        if let t = TestHarness.once("CRAMLESS_RECORD_PAUSE").flatMap(Double.init) { hooks.append((t, "pause")) }
        if let t = TestHarness.once("CRAMLESS_RECORD_STOP").flatMap(Double.init) { hooks.append((t, "stop")) }
        var waited = 0.0
        for (time, action) in hooks.sorted(by: { $0.0 < $1.0 }) {
            try? await Task.sleep(for: .seconds(max(0, time - waited)))
            waited = time
            switch action {
            case "flag": flag()
            case "pause": session.pause()
            default: await stop()
            }
        }
    }
    #endif
}

extension LectureSession.Transcription {
    /// Words are expected on screen while recording (live transcription or the demo).
    var showsListening: Bool {
        switch self {
        case .live, .demo, .checking: true
        default: false
        }
    }
}

/// The live input level as bars, newest on the right. Flat and grey while paused.
struct LectureLevelWaveform: View {
    let levels: [Float]
    let active: Bool
    var animated = true

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(active ? CLColor.rose : CLColor.ink4)
                    // A gentle curve spreads quiet and loud apart, as an ear hears them.
                    .frame(width: 5, height: active ? 5 + pow(CGFloat(min(1, max(0, level))), 1.6) * 62 : 5)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(animated ? CLMotion.snap : nil, value: levels)
        .animation(CLMotion.fade, value: active)
        .accessibilityElement()
        .accessibilityLabel(Text("Sound level"))
        .accessibilityValue(Text(active ? "Hearing sound" : "Paused"))
    }
}

/// A settled line of the transcript, with its time and the exam flag made while it was said.
private struct TranscriptLine: View {
    let time: Double
    let text: String
    let flag: ExamFlag?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(CLFormat.timestamp(time))
                .clFont(.number(12, .semibold))
                .foregroundStyle(CLColor.ink3)
            Text(text)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let flag {
                CLPill(text: flag.reason == .tapped ? "You flagged this: on the exam" : "Said: on the exam",
                       tone: .tangerine, systemImage: "star.fill")
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

/// The words still being heard: lighter and in italics, until they settle into a line.
private struct LiveTranscriptLine: View {
    let text: String
    let flagged: ExamFlag?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(CLColor.sky).frame(width: 6, height: 6)
                Text("Hearing now")
                    .clFont(.caption)
                    .foregroundStyle(CLColor.skyInk)
            }
            Text(text)
                .clFont(.body)
                .italic()
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if flagged != nil {
                CLPill(text: "You flagged this: on the exam", tone: .tangerine, systemImage: "star.fill")
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Still hearing: \(text)"))
    }
}
