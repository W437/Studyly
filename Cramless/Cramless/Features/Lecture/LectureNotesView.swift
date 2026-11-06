import SwiftUI

/// A lecture's notes: the summary, the moments flagged for the exam, the sections with their times, the key terms,
/// its questions, and the transcript. A time chip jumps to that moment in the transcript; `focusTime` (a tutor
/// citation, a question's timestamp) scrolls there and marks it on open.
///
/// With no notes yet it says why (the transcript is still pending, or the notes haven't been made) and offers to
/// make them.
///
/// DEBUG hook: `CRAMLESS_NOTES_FOCUS=<seconds>` opens focused on that moment (with `CRAMLESS_ROUTE=lectureNotes`).
struct LectureNotesView: View {
    let sourceID: UUID
    /// Seconds into the lecture to scroll to and mark (nil: the top).
    var focusTime: Double? = nil

    @Environment(AppModel.self) private var app
    @State private var lecture: LectureNotesSnapshot?
    @State private var making = false
    @State private var transcribing = false
    @State private var problem: String?
    @State private var showsTranscript = false
    @State private var focusedSegment: String?
    @State private var focusedTime: Double?
    @State private var reviewing = false
    @State private var position = ScrollPosition(edge: .top)
    /// Where each transcript moment sits in the scroll content, measured as it lays out.
    @State private var rowTops: [String: CGFloat] = [:]
    @State private var pendingJump: String?

    private static let contentSpace = "lecture-notes-content"
    @State private var didFocus = false
    /// The bar shows the title once the big one has scrolled away.
    @State private var titleInBar = false

    var body: some View {
        ScrollView {
            if let lecture {
                content(lecture)
                    .padding(.horizontal, CLSpace.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                    .frame(maxWidth: CLMetrics.readableWidth)
                    .frame(maxWidth: .infinity)
                    .coordinateSpace(.named(Self.contentSpace))
            }
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 90
        } action: { _, past in
            withAnimation(CLMotion.fade) { titleInBar = past }
        }
        .onChange(of: rowTops) { _, tops in
            // A jump waits for its row to be laid out (the transcript may have just opened).
            guard let id = pendingJump, let top = tops[id] else { return }
            pendingJump = nil
            withAnimation(CLMotion.settle) { position.scrollTo(y: max(0, top - 160)) }
        }
        .clScreenBackground()
        .navigationTitle(titleInBar ? (lecture?.title ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $reviewing, onDismiss: load) {
            DraftReviewView(sourceID: sourceID, isOnboarding: false, onFinish: { _ in reviewing = false })
        }
        .onAppear {
            load()
            focusOnce()
            app.noteOpened(sourceID: sourceID)
        }
        .onChange(of: app.revision) { _, _ in load() }
        .onChange(of: app.ai.hasCloudConsent) { old, new in
            // Cloud AI was allowed from this card: the notes are made at once.
            guard new, !old, lecture?.notes == nil, lecture?.offlineNotesThin == true, !making else { return }
            Task { await makeNotes() }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ lecture: LectureNotesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CLEyebrow(text: .verbatim(lecture.eyebrow))
            Text(lecture.title)
                .clFont(.largeTitle)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
            if let notes = lecture.notes {
                CaptureOriginNote(systemImage: originIcon(notes.origin), text: originText(notes.origin),
                           tone: notes.origin == ItemOrigin.rules.rawValue ? .sun : .sky)
                    .padding(.top, 14)
                if !notes.summary.isEmpty {
                    Text(notes.summary)
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
                ForEach(lecture.flags) { flag in
                    flagCard(flag, lecture: lecture).padding(.top, 14)
                }
                if !notes.sections.isEmpty { sections(notes.sections) }
                if !notes.keyTerms.isEmpty { keyTerms(notes.keyTerms) }
            } else {
                missingNotes(lecture).padding(.top, 16)
                ForEach(lecture.flags) { flag in
                    flagCard(flag, lecture: lecture).padding(.top, 14)
                }
            }
            questions(lecture)
            if !lecture.segments.isEmpty { transcript(lecture) }
        }
    }

    // MARK: Flags

    private func flagCard(_ flag: ExamFlag, lecture: LectureNotesSnapshot) -> some View {
        let text = lecture.segment(at: flag.time)?.text ?? flag.text
        return VStack(alignment: .leading, spacing: 8) {
            Label(flagLine(flag, text: text), systemImage: "star.fill")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.tangerineInk)
            if !text.isEmpty {
                Text(text)
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            timeChip(flag.time)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CLColor.tangerine, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    /// "Your lecturer said this will be on the midterm", "You flagged this for the exam".
    private func flagLine(_ flag: ExamFlag, text: String) -> String {
        guard flag.reason == .phrase else { return "You flagged this for the exam" }
        let lower = text.lowercased()
        let word = ["midterm", "final", "quiz", "test", "exam"].first { lower.contains($0) } ?? "exam"
        return "Your lecturer said this will be on the \(word)"
    }

    // MARK: Sections

    private func sections(_ sections: [LectureNotes.Section]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Notes")
            NotesCard {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    let focused = focusedTime.map { $0 >= section.start && $0 <= section.end } ?? false
                    HStack(alignment: .top, spacing: 12) {
                        timeChip(section.start)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .clFont(.headline)
                                .foregroundStyle(CLColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(section.bullets, id: \.self) { bullet in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•").clFont(.subheadline).foregroundStyle(CLColor.ink3)
                                    Text(bullet)
                                        .clFont(.subheadline)
                                        .foregroundStyle(CLColor.ink2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(focused ? CLColor.skySoft : .clear)
                    .overlay(alignment: .top) { if index > 0 { NotesHairline(inset: 16) } }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func keyTerms(_ terms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Key terms")
            CLFlow(spacing: 8, lineSpacing: 8) {
                ForEach(terms, id: \.self) { term in CLChip(title: .verbatim(term)) }
            }
        }
    }

    // MARK: Missing notes

    @ViewBuilder
    private func missingNotes(_ lecture: LectureNotesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if lecture.transcriptPending {
                Label("The transcript isn't ready yet", systemImage: "waveform.badge.magnifyingglass")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                Text("It's made on your iPhone from the recording, once the speech model for your language is there. Your recording is saved.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { Task { await transcribe() } }) {
                    ZStack {
                        Text("Make the transcript now").opacity(transcribing ? 0 : 1)
                        if transcribing { ProgressView().tint(CLColor.background) }
                    }
                }
                .buttonStyle(.cl(.dark, size: .small, fullWidth: false))
                .disabled(transcribing)
            } else {
                Label("No notes yet", systemImage: "list.bullet.rectangle")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                let askForCloud = lecture.offlineNotesThin && app.ai.cloudAvailableInThisBuild && !app.ai.hasCloudConsent
                Group {
                    if lecture.offlineNotesThin, app.ai.cloudAvailableInThisBuild {
                        Text("The offline rules can't make good notes from this lecture. Cloud AI can write them from the transcript.")
                    } else if lecture.offlineNotesThin {
                        Text("The offline rules can't make good notes from this lecture.")
                    } else {
                        Text("Notes come from the transcript: sections with their times, the moments flagged for the exam, key terms and questions.")
                    }
                }
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: {
                    // Cloud AI is the way for this lecture, and it isn't allowed yet: ask, then the notes are made.
                    if askForCloud {
                        app.router.present(.consent(.cloudAI(feature: AIJob.lecture.feature)))
                    } else {
                        Task { await makeNotes() }
                    }
                }) {
                    ZStack {
                        Group {
                            if askForCloud { Text("Use Cloud AI") } else { Text("Make notes") }
                        }
                        .opacity(making ? 0 : 1)
                        if making { ProgressView().tint(CLColor.background) }
                    }
                }
                .buttonStyle(.cl(.dark, size: .small, fullWidth: false))
                .disabled(making || lecture.segments.isEmpty)
            }
            if let problem {
                Text(problem)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.roseInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clCard(padding: 18)
    }

    // MARK: Questions

    @ViewBuilder
    private func questions(_ lecture: LectureNotesSnapshot) -> some View {
        CLSectionHeader(title: "Questions")
        if lecture.draftCount > 0 {
            HStack(alignment: .center, spacing: 12) {
                CaptureBadge(systemImage: "checklist", tint: .tangerine, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(CLFormat.count(lecture.draftCount, "question")) waiting for you")
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                    Text("Check them before they join your sessions.")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Review") {
                    CLHaptics.tap()
                    reviewing = true
                }
                .buttonStyle(.cl(.primary, size: .small, fullWidth: false))
            }
            .clCard(padding: 16)
        } else if lecture.items.isEmpty {
            Text("No questions from this lecture yet.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
        } else {
            CLList {
                ForEach(lecture.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.prompt)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let time = item.time {
                            Button { jump(to: time) } label: {
                                CLSourceChip(label: item.label, systemImage: "waveform")
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Shows that moment in the transcript"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Transcript

    private func transcript(_ lecture: LectureNotesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Transcript", actionTitle: showsTranscript ? "Hide" : "Show all") {
                CLHaptics.select()
                withAnimation(CLMotion.settle) { showsTranscript.toggle() }
            }
            let shown = showsTranscript ? lecture.segments : Array(lecture.segments.prefix(2))
            NotesCard {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, segment in
                    let flagged = lecture.flags.contains { lecture.segment(at: $0.time)?.id == segment.id }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(CLFormat.timestamp(segment.start))
                            .clFont(.number(12, .semibold))
                            .foregroundStyle(CLColor.ink3)
                        Text(segment.text)
                            .clFont(.body)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if flagged {
                            CLPill(text: "On the exam", tone: .tangerine, systemImage: "star.fill")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(focusedSegment == segment.id ? CLColor.skySoft : .clear)
                    .overlay(alignment: .top) { if index > 0 { NotesHairline(inset: 16) } }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.contentSpace)).minY } action: { top in
                        rowTops[segment.id] = top
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !showsTranscript && lecture.segments.count > 2 {
                Button("Show the whole transcript (\(lecture.segments.count) parts)") {
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) { showsTranscript = true }
                }
                .buttonStyle(.cl(.ghost, size: .small))
                .padding(.top, 6)
            }
        }
    }

    private func timeChip(_ seconds: Double) -> some View {
        Button { jump(to: seconds) } label: {
            Text(CLFormat.timestamp(seconds))
                .clFont(.number(13, .bold))
                .foregroundStyle(CLColor.skyInk)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(CLColor.skySoft, in: Capsule())
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("At \(CLFormat.timestamp(seconds))"))
        .accessibilityHint(Text("Shows that moment in the transcript"))
    }

    // MARK: Words

    private func originIcon(_ origin: String) -> String {
        switch ItemOrigin(rawValue: origin) {
        case .cloud: "cloud"
        case .onDevice: "iphone"
        default: "list.bullet.rectangle"
        }
    }

    private func originText(_ origin: String) -> String {
        let lead = switch ItemOrigin(rawValue: origin) {
        case .cloud: "Notes written by Cloud AI from your transcript."
        case .onDevice: "Notes written on your iPhone from your transcript."
        default: "Notes from the offline rules: sections, flagged moments and key terms from your transcript."
        }
        return "\(lead) Tap a time to see that moment in the transcript."
    }

    // MARK: Actions

    private func load() {
        guard let source = app.source(sourceID), source.modelContext != nil, source.deletedAt == nil else {
            lecture = nil
            return
        }
        lecture = LectureNotesSnapshot(source: source, app: app)
    }

    private func focusOnce() {
        guard !didFocus else { return }
        didFocus = true
        var time = focusTime
        #if DEBUG
        if time == nil, let hook = TestHarness.once("CRAMLESS_NOTES_FOCUS").flatMap(Double.init) { time = hook }
        #endif
        guard let time else { return }
        Task {
            try? await nap(450)
            jump(to: time)
        }
    }

    /// Opens the transcript at that moment and marks it.
    private func jump(to seconds: Double) {
        guard let lecture, let segment = lecture.segment(at: seconds) else { return }
        CLHaptics.select()
        withAnimation(CLMotion.settle) {
            showsTranscript = true
            focusedSegment = segment.id
            focusedTime = seconds
        }
        // Scroll once the row's place is known: now if it is, or as soon as the opened transcript lays it out.
        if let top = rowTops[segment.id], showsTranscript {
            withAnimation(CLMotion.settle) { position.scrollTo(y: max(0, top - 160)) }
        } else {
            pendingJump = segment.id
        }
    }

    private func makeNotes() async {
        guard let source = app.source(sourceID), !source.segments.isEmpty else { return }
        making = true
        problem = nil
        let outcome = await app.ai.lectureNotes(app.lectureInput(for: source))
        making = false
        guard let fresh = app.source(sourceID), fresh.modelContext != nil else { return }
        app.saveLectureNotes(outcome, lecture: fresh)
        if outcome.needsCloud {
            // The offline rules had nothing worth keeping: the lecture stays without notes, and the card says why.
            problem = outcome.note
        } else {
            CLHaptics.success()
        }
        load()
    }

    private func transcribe() async {
        transcribing = true
        problem = nil
        let made = await app.transcribeLecture(sourceID)
        transcribing = false
        if made {
            load()
            await makeNotes()
        } else {
            problem = "This iPhone can't make the transcript yet: the speech model for your language isn't available. The recording is saved, so it can be made later."
        }
    }
}

/// A lecture read out of the store once per change, so the view never reads a deleted model.
struct LectureNotesSnapshot: Equatable {
    struct Question: Identifiable, Equatable {
        var id: UUID
        var prompt: String
        var label: String
        var time: Double?
    }

    var title: String
    var eyebrow: String
    var notes: LectureNotes?
    var segments: [TranscriptSegment]
    var flags: [ExamFlag]
    var draftCount: Int
    var items: [Question]
    var transcriptPending: Bool
    /// There are no notes yet and the offline rules couldn't make good ones from this transcript (their section titles
    /// would be junk): only Cloud AI can (`LocalLectureNotes.make(qualityBar:)`).
    var offlineNotesThin = false

    @MainActor
    init(source: Source, app: AppModel) {
        title = source.title
        var parts: [String] = []
        if let course = source.course?.name { parts.append(course) }
        if let colon = source.title.firstIndex(of: ":") { parts.append(String(source.title[..<colon])) }
        if source.duration >= 60 { parts.append(CLFormat.minutes(Int((source.duration / 60).rounded()))) }
        eyebrow = parts.joined(separator: " · ")
        notes = source.notes
        segments = source.segments.sorted { $0.start < $1.start }
        flags = source.flags.sorted { $0.time < $1.time }
        draftCount = app.draftItems(sourceID: source.id).count
        items = app.items(fromSource: source.id).map {
            Question(id: $0.id, prompt: $0.prompt, label: $0.sourceRef?.label ?? source.title, time: $0.sourceRef?.start)
        }
        transcriptPending = app.isTranscriptPending(source)
        if notes == nil, !transcriptPending, !segments.isEmpty {
            // The offline rules write English only; and in English they need section titles worth showing.
            let spoken = LocalGenerator.dominantLanguage(String(segments.map(\.text).joined(separator: " ").prefix(4000)))
            offlineNotesThin = spoken != "en"
                || LocalLectureNotes.make(title: source.title, segments: segments, flags: flags, qualityBar: true).thin
        }
    }

    /// The segment being said at `seconds`: the one around it, else the last one before it.
    func segment(at seconds: Double) -> TranscriptSegment? {
        segments.first { seconds >= $0.start && seconds <= $0.end }
            ?? segments.last { $0.start <= seconds }
            ?? segments.first
    }
}


/// A grouped card like `CLList`, whose rows keep their own ids (so the notes can scroll to a moment).
private struct NotesCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
    }
}

private struct NotesHairline: View {
    var inset: CGFloat

    var body: some View {
        Rectangle().fill(CLColor.hairline).frame(height: 0.5).padding(.leading, inset)
    }
}
