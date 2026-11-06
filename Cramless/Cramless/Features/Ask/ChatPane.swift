import SwiftUI

/// One message of a chat, as plain values (read once from the model, so a deleted chat can't trap a view).
struct ChatEntry: Identifiable, Equatable {
    var id: UUID
    var role: ChatRole
    var text: String
    var citations: [Citation]
    var origin: ItemOrigin?
    var contextItemID: UUID?
    /// What Cap's assistant did in this reply.
    var steps: [AssistantStep]
    /// A question whose words were read off a photo.
    var fromPhoto: Bool
    /// A question Cap is keeping for later.
    var isWaiting: Bool
    /// An answer that came later.
    var isLateAnswer: Bool

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role
        text = message.text
        citations = message.citations
        origin = message.origin.flatMap(ItemOrigin.init(rawValue:))
        contextItemID = message.contextItemID
        steps = message.steps
        fromPhoto = message.fromPhoto
        isWaiting = message.waitingSince != nil
        isLateAnswer = message.answersQuestionID != nil
    }

    static func entries(of thread: ChatThread?) -> [ChatEntry] {
        guard let thread, thread.modelContext != nil else { return [] }
        return thread.sortedMessages.map(ChatEntry.init)
    }

    /// Cap's reply for a question the notes don't cover (the offline tutor's words, or the cloud's), or when there is nothing
    /// in the notes yet: either way, adding notes is the way on.
    var isNotCovered: Bool { role == .assistant && LocalTutor.isNotCoveredReply(text) }

    /// Cap declined: an essay, an exam, homework.
    var isRefusal: Bool { role == .assistant && TutorPolicy.isDecline(text) }
}

/// The tutor chat: the title with its course menu, the messages (Cap's streaming in), the follow-ups and, pinned above the keyboard on a
/// solid dock (`AskDock`) so the chat never shows through behind it, one row of starter chips while the chat is empty and the composer
/// with Cap's style in it. Used by the Ask tab (a new chat until the first question) and by a chat pushed from history.
struct ChatPane: View {
    @Binding var threadID: UUID?
    /// The course for a chat that hasn't started yet (the Ask tab).
    @Binding var pendingCourseID: UUID?
    var showsEmptyState = true
    /// The title over the course menu: "Ask Cap", or a pushed chat's own.
    var title: String = String(localized: "Ask Cap")

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var starters: [String]?
    /// The chat follows Cap's reply down as it is made, until the student scrolls away from the end (and again once they are back).
    @State private var following = true
    @State private var endGap: CGFloat = 0
    @State private var choosingSnap = false
    @State private var snapSession: SnapSession?
    /// The camera shows when a problem's words could reach Cap (a relay, an account that isn't under 13) and there are notes for it to rest on. Read
    /// once per change of the library: this body runs for every word of an answer, and the notes are a fetch away.
    @State private var canSnap = false

    private struct SnapGate: Equatable {
        var courseID: UUID?
        var revision: Int
        var age: AppSettings.AgeBand
    }

    private var streams: AskStreams { AskStreams.shared }

    private var thread: ChatThread? {
        guard let thread = app.thread(threadID), thread.modelContext != nil else { return nil }
        return thread
    }

    private var courseID: UUID? { thread.map(\.courseID) ?? pendingCourseID }

    var body: some View {
        let _ = app.revision
        let thread = self.thread
        let entries = ChatEntry.entries(of: thread)
        let live = threadID.flatMap { streams.live[$0] }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if entries.isEmpty && live == nil {
                        if showsEmptyState { emptyState }
                    } else {
                        conversation(entries, live: live, thread: thread)
                        suggestions(entries, thread: thread, isAnswering: live != nil)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(HarnessScroll.anchor(entries.isEmpty ? .top : .bottom), for: .initialOffset)
            .defaultScrollAnchor(HarnessScroll.anchor(.bottom), for: .sizeChanges)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height - $0.visibleRect.maxY } action: { _, gap in endGap = gap }
            .onScrollPhaseChange { old, new in
                // A finger on the scroll view takes it over; it follows Cap again once the student lets go at the end.
                if new == .idle, old == .interacting || old == .decelerating { following = endGap < 80 }
            }
            .onChange(of: entries.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: live == nil) { _, ended in
                if !ended { following = true }
                scrollToEnd(proxy)
            }
            // Cards written, pages found, a note growing: the new work stays in view above the composer.
            .onChange(of: live?.progress) { _, _ in if following { scrollToEnd(proxy) } }
        }
        .safeAreaInset(edge: .bottom) {
            AskDock {
                VStack(alignment: .leading, spacing: 8) {
                    FreeAnswersNote()
                    if showsEmptyState, entries.isEmpty, live == nil, draft.isEmpty, hasMaterial {
                        AskDockChipRow(chips: dockChips, onTap: tap)
                    }
                    ChatComposer(text: $draft, focused: $composerFocused, isAnswering: live != nil,
                                 placeholder: "Ask about your notes…", thread: thread, showsMode: true,
                                 onCamera: canSnap ? { snap() } : nil,
                                 onSend: { send(draft) },
                                 onStop: { if let id = threadID { streams.stop(id, app: app) } })
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                AskTitleMenu(title: title, courseID: courseID) { picked in
                    if let thread { app.setChatCourse(thread, to: picked) } else { pendingCourseID = picked }
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .clScreenBackground()
        .modifier(SnapFlow(isChoosing: $choosingSnap, session: $snapSession) { text in
            ask(text, sendAs: nil, fromPhoto: true)
        })
        .onChange(of: SnapGate(courseID: courseID, revision: app.revision, age: app.settings.ageBand), initial: true) { _, _ in
            let can = app.ai.canSnapProblem && hasMaterial
            if can != canSnap { canSnap = can }
        }
        .task(id: courseID) {
            guard showsEmptyState else { return }
            starters = nil
            starters = await app.chatStarters(courseID: courseID)
        }
        #if DEBUG
        .task { applySnapHarness() }
        #endif
    }

    private func snap() {
        CLHaptics.tap()
        composerFocused = false
        choosingSnap = true
    }

    #if DEBUG
    /// `CRAMLESS_SNAP=confirm|mathlike|unreadable` opens "Check the problem" in that state; `asked` and `notcovered` send a problem.
    private func applySnapHarness() {
        guard let hook = TestHarness.once("CRAMLESS_SNAP") else { return }
        AskDemo.applyLaunchState(app)
        let covered = "Problem 3. A cell with 46 chromosomes goes through mitosis. How many chromosomes does each daughter cell have?"
        let text = TestHarness.value("CRAMLESS_SNAP_TEXT")
        switch hook {
        case "confirm":
            snapSession = SnapSession(phase: .ready(SnapReader.Reading(text: text ?? covered, issue: nil)))
        case "mathlike":
            snapSession = SnapSession(phase: .ready(SnapReader.Reading(text: text ?? "Solve for x: 2x² + 3x − 5 = 0\nThen find ∫ x dx from 0 to 3", issue: .mathLike)))
        case "unreadable":
            snapSession = SnapSession(phase: .ready(SnapReader.Reading(text: "", issue: .unreadable)))
        case "asked":
            if pendingCourseID == nil { pendingCourseID = app.defaultChatCourseID }
            ask(text ?? covered, sendAs: nil, fromPhoto: true)
        case "notcovered":
            if pendingCourseID == nil { pendingCourseID = app.defaultChatCourseID }
            ask(text ?? "Find the integral of x² from 0 to 3.", sendAs: nil, fromPhoto: true)
        default:
            break
        }
    }
    #endif

    // MARK: Parts

    @ViewBuilder
    private func conversation(_ entries: [ChatEntry], live: AskStreams.Live?, thread: ChatThread?) -> some View {
        let context = entries.first { $0.role == .user }?.text ?? ""
        let lastAssistant = entries.lastIndex { $0.role == .assistant }
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            if entry.role == .user {
                // A question rises into place; under Reduce Motion it only fades in.
                Group {
                    if entry.fromPhoto { PhotoProblemBubble(text: entry.text) } else { UserBubble(text: entry.text) }
                }
                .transition(.asymmetric(insertion: reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity),
                                        removal: .identity))
            } else {
                let reply = entries.indices.contains(index + 1) && entries[index + 1].role == .user ? entries[index + 1].text : nil
                let question = entries[..<index].last { $0.role == .user }
                let isLatest = index == lastAssistant && live == nil
                CapMessageView(entry: entry, note: streams.notes[entry.id], chatContext: context,
                               isLatest: isLatest, reply: reply,
                               later: laterState(for: entry, question: question, isLatest: isLatest),
                               onKeepForLater: { keepForLater(question) },
                               stepActions: stepActions(for: entry),
                               onCitation: open, onAnswer: { answer, check in answerQuickCheck(answer, check: check) },
                               onSuggestion: { app.router.present($0.sheet) })
                    .transition(.identity)
            }
        }
        if let live {
            LiveAnswerView(live: live, onCitation: open)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
        }
    }

    @ViewBuilder
    private func suggestions(_ entries: [ChatEntry], thread: ChatThread?, isAnswering: Bool) -> some View {
        if !isAnswering, let last = entries.last, last.role == .assistant {
            let lastQuestion = entries.last { $0.role == .user }?.text ?? ""
            CLFlow(spacing: 8, lineSpacing: 0) {
                if last.isRefusal {
                    let topic = declinedTopic(lastQuestion)
                    SuggestionChip(title: topic.map { "Explain \($0) from my notes" } ?? "Explain the key ideas",
                                   systemImage: "text.book.closed") {
                        ask(topic.map { "Explain \($0) from my notes" } ?? "Explain the key ideas", sendAs: nil)
                    }
                    SuggestionChip(title: topic.map { "Quiz me on \($0)" } ?? "Quiz me on my notes", systemImage: "checklist") {
                        quiz(hint: topic ?? "")
                    }
                } else if last.isNotCovered {
                    SuggestionChip(title: "Add notes on this", systemImage: "doc.viewfinder") {
                        app.router.present(.capture(courseID: courseID))
                    }
                } else {
                    SuggestionChip(title: "Quiz me on this", systemImage: "checklist") { quiz(hint: chatText(entries)) }
                    let simpler = String(localized: "Explain it simpler")
                    SuggestionChip(title: simpler, systemImage: "lightbulb") {
                        ask(simpler, sendAs: "Explain \(subject(thread, entries)) more simply, using my notes.")
                    }
                    if let thread {
                        SuggestionChip(title: String(localized: "Make 3 flashcards"), systemImage: "rectangle.stack.badge.plus") {
                            makeThreeFlashcards(thread, entries)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// What's said under a reply about answering its question later: nothing, the offer (the cloud couldn't be reached, and it may be asked again), or
    /// that it's kept.
    private func laterState(for entry: ChatEntry, question: ChatEntry?, isLatest: Bool) -> AnswerLaterCard.State? {
        guard let question else { return nil }
        if question.isWaiting { return .saved }
        guard isLatest, streams.notes[entry.id]?.offersLater == true, app.ai.cloudStillAllowed() else { return nil }
        return app.waitingQuestions().count < AnswerLater.maxWaiting ? .offer : .full
    }

    private func keepForLater(_ question: ChatEntry?) {
        guard let question else { return }
        CLHaptics.commit()
        withAnimation(CLMotion.settle) { _ = app.keepForLater(questionID: question.id) }
    }

    private var emptyState: some View {
        let recent = app.chatThreads().first { $0.id != threadID && !$0.messages.isEmpty }
        return AskEmptyState(courseName: app.liveCourse(courseID)?.name,
                             sourceCount: app.readableSources(courseID: courseID).count,
                             recent: recent.map { RecentChat(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) },
                             now: app.now,
                             onOpen: { id in withAnimation(CLMotion.settle) { threadID = id } },
                             onAddMaterial: { app.router.present(.capture(courseID: courseID)) })
    }

    private var hasMaterial: Bool { !app.readableSources(courseID: courseID).isEmpty }

    /// The dock's chips; nil until the questions drawn from the notes are ready, so the row never swaps under a finger.
    private var dockChips: [AskDockChips.Chip]? {
        guard let starters else { return nil }
        return AskDockChips.make(quickStarts: app.ai.assistantReady ? AssistantQuickStart.available(app) : [], starters: starters)
    }

    private func tap(_ chip: AskDockChips.Chip) {
        switch chip.action {
        case .compose(let prefix): compose(prefix)
        case .ask(let question): ask(question, sendAs: nil)
        case .quiz: quiz(hint: "")
        }
    }

    // MARK: Actions

    /// Puts the start of a request in the composer, for the student to finish.
    private func compose(_ prefix: String) {
        CLHaptics.tap()
        draft = prefix
        composerFocused = true
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft = ""
        ask(clean, sendAs: nil)
    }

    /// Asks Cap. `sendAs` is what the tutor reads when the shown words lean on the chat ("Explain with an
    /// analogy", a quick-check answer), so the question finds the notes it's about.
    private func ask(_ text: String, sendAs: String?, fromPhoto: Bool = false) {
        guard !streams.isAnswering(threadID) else { return }
        let thread = self.thread ?? app.startChat(courseID: pendingCourseID)
        if threadID != thread.id { threadID = thread.id }
        CLHaptics.tap()
        withAnimation(CLMotion.settle) {
            streams.ask(text, in: thread, app: app, sendAs: sendAs, fromPhoto: fromPhoto)
        }
    }

    /// Three cards from the chat: Cap's assistant drafts them in the chat when it can; otherwise the sheet that picks them out of the answer.
    private func makeThreeFlashcards(_ thread: ChatThread, _ entries: [ChatEntry]) {
        // A chat from a photo stays with the tutor, so the sheet picks them out of its answers there too.
        if app.ai.assistantReady, !thread.isFromPhoto {
            ask(String(localized: "Make 3 flashcards"), sendAs: "Make 3 flashcards on \(subject(thread, entries)), from my notes.")
        } else {
            CLHaptics.tap()
            app.router.present(.makeCards(threadID: thread.id, maxItems: 3))
        }
    }

    /// What the student can do with the steps of one saved reply.
    private func stepActions(for entry: ChatEntry) -> AssistantStepActions {
        let id = entry.id
        let app = self.app
        return AssistantStepActions(
            approve: { step in
                CLHaptics.commit()
                guard let done = app.approveAssistantStep(messageID: id, stepID: step.id) else { return }
                if done.status == .applied {
                    CLHaptics.success()
                    CLFeel.play(.saved)
                } else if let why = done.detail {
                    app.router.toast(.verbatim(why), systemImage: "exclamationmark.triangle.fill", tone: .warning)
                }
            },
            skip: { app.skipAssistantStep(messageID: id, stepID: $0.id) },
            undo: { step in
                guard app.undoAssistantStep(messageID: id, stepID: step.id) != nil else { return }
                CLHaptics.commit()
                app.router.toast("Taken back", systemImage: "arrow.uturn.backward", tone: .neutral)
            },
            reopen: { app.reopenAssistantStep(messageID: id, stepID: $0.id) },
            edit: { step, change in app.updateAssistantStep(messageID: id, stepID: step.id, change) },
            perform: { app.perform($0) },
            upgrade: { app.router.present(.paywall(.feature("Web research is part of Capling Pro."))) })
    }

    private func answerQuickCheck(_ answer: String, check: QuickCheck) {
        ask(answer, sendAs: "Quick check: \(check.question) My answer: \(answer)")
    }

    private func open(_ group: CitationGroup) {
        CitationOpener.open(group, app: app)
    }

    /// What a declined request was about, among the course's topics and what its sources are about (nil: none, so the chips are the
    /// plain ones).
    private func declinedTopic(_ question: String) -> String? {
        let scope = app.liveCourse(courseID).map { [$0] } ?? app.courses
        let names = scope.flatMap(\.liveTopics).map(\.name)
            + app.readableSources(courseID: courseID).flatMap { AskPolicy.names(inTitle: $0.title) }
        return AskPolicy.topic(ofRefused: question, among: names)
    }

    /// A practice session on the topic the chat is about (the course's topic whose name the chat uses most).
    private func quiz(hint: String) {
        let scope = app.liveCourse(courseID).map { [$0] } ?? app.courses
        let topics = scope.flatMap(\.liveTopics)
        let topic = topics
            .map { ($0, Lexicon.overlap(of: $0.name, with: hint)) }
            .filter { $0.1 >= 0.5 }
            .max { $0.1 < $1.1 }?.0
        CLHaptics.tap()
        app.router.present(.session(SessionRequest(kind: .practice, courseID: topic?.course?.id ?? courseID,
                                                   topicID: topic?.id)))
    }

    private func chatText(_ entries: [ChatEntry]) -> String {
        entries.suffix(4).map(\.text).joined(separator: " ")
    }

    /// What the chat is about, for a follow-up that leans on it.
    private func subject(_ thread: ChatThread?, _ entries: [ChatEntry]) -> String {
        if let title = thread?.title, !title.isEmpty, !title.hasSuffix("…") { return title }
        return entries.first { $0.role == .user }?.text ?? "this"
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard HarnessScroll.anchor(nil) != .top else { return }
        withAnimation(CLMotion.settle) { proxy.scrollTo("end", anchor: .bottom) }
    }
}

// MARK: - Opening a citation

enum CitationOpener {
    /// The page with the quote's lines highlighted, the lecture at that moment, or the card of a deck, as a sheet.
    @MainActor
    static func open(_ group: CitationGroup, app: AppModel) {
        guard let first = group.citations.first, let id = first.sourceID, let source = app.source(id), source.deletedAt == nil else {
            app.router.toast("That source isn't in your library anymore.", systemImage: "questionmark.folder", tone: .warning)
            return
        }
        CLHaptics.tap()
        if source.kind.isDeck {
            // A deck has cards, not pages: the card the quote came from.
            app.router.present(.deckCard(sourceID: id, quote: first.quote, label: first.label))
        } else if source.kind == .lecture || (first.pageIndex == nil && first.start != nil) {
            app.router.present(.lectureMoment(sourceID: id, time: first.start))
        } else {
            app.router.present(.sourcePage(sourceID: id, pageIndex: first.pageIndex ?? 0, highlight: anchors(group, app: app)))
        }
    }

    @MainActor
    static func anchors(_ group: CitationGroup, app: AppModel) -> [String] {
        var out: [String] = []
        for citation in group.citations {
            for id in app.anchorIDs(for: citation) where !out.contains(id) { out.append(id) }
        }
        return out
    }
}

// MARK: - Cap's messages

/// One of Cap's saved answers: the text with its citations, the quick check it ends with (answerable when it's the
/// latest), an honest note on who answered when it wasn't the cloud, and the offer a better path carries.
struct CapMessageView: View {
    let entry: ChatEntry
    let note: AskStreams.Note?
    var chatContext: String = ""
    let isLatest: Bool
    let reply: String?
    /// Answering this reply's question later, when it's a matter.
    var later: AnswerLaterCard.State? = nil
    var onKeepForLater: () -> Void = {}
    var stepActions: AssistantStepActions = .live
    /// False in a sheet opened from a session (Explain my mistake): a free limit shows as a line, with no "See Pro" and no link
    /// out of the sheet. Nothing is sold in the middle of studying.
    var allowsUpgrade = true
    let onCitation: (CitationGroup) -> Void
    let onAnswer: (String, QuickCheck) -> Void
    let onSuggestion: (AISuggestion) -> Void

    var body: some View {
        let check = QuickCheck.split(entry.text, chatContext: chatContext)
        let lead = check?.lead ?? entry.text
        let groups = CitationGroup.groups(entry.citations)
        let origin = entry.isLateAnswer ? OriginNote.lateAnswer
            : OriginNote.line(origin: note?.origin ?? entry.origin, note: note?.note, quotesNotes: !entry.citations.isEmpty)
        VStack(alignment: .leading, spacing: 8) {
            if !entry.steps.isEmpty {
                AssistantStepList(steps: entry.steps, actions: stepActions)
            }
            if !lead.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CapMarkdownView(text: lead)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(Self.spoken(lead, groups: groups)))
                        .accessibilityActions {
                            ForEach(groups) { group in
                                Button("Open \(group.label)") { onCitation(group) }
                            }
                        }
                    if !groups.isEmpty { chips(groups) }
                }
                .capBubble(tint: entry.isNotCovered || entry.isRefusal ? CLColor.surface2 : CLColor.surface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 28)
            }
            if let check {
                QuickCheckCard(check: check, isActive: isLatest, answered: reply) { onAnswer($0, check) }
                if lead.isEmpty, !groups.isEmpty { chips(groups).padding(.leading, 4) }
            }
            if let origin { OriginNote(text: origin.text, systemImage: origin.icon) }
            if isLatest, allowsUpgrade, AIFreeLimits.isCostCapNote(note?.note) {
                HelpLink()
                    .padding(.leading, 6)
                    .padding(.top, -8)
            }
            if isLatest, let suggestion = note?.suggestion {
                AISuggestionCard(suggestion: suggestion, allowsUpgrade: allowsUpgrade) { onSuggestion(suggestion) }
                    .padding(.trailing, 28)
            }
            if let later {
                AnswerLaterCard(state: later, onKeep: onKeepForLater)
                    .padding(.trailing, 28)
                    .transition(.opacity)
            }
        }
    }

    private func chips(_ groups: [CitationGroup]) -> some View {
        CLFlow(spacing: 6, lineSpacing: 0) {
            ForEach(groups) { group in CitationChipButton(group: group) { onCitation(group) } }
        }
        .padding(.vertical, -6)
    }

    /// Cap's answer as VoiceOver reads it: the words, then where they come from.
    static func spoken(_ text: String, groups: [CitationGroup]) -> String {
        var line = "Cap: " + CapMarkdown.plain(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groups.isEmpty else { return line }
        if let last = line.last, !".!?".contains(last) { line += "." }
        return line + " Sources: " + groups.map(\.label).joined(separator: ", ") + "."
    }
}

/// The answer being written: three dots until the first words, then the text with a caret, and citations as
/// they're checked.
struct LiveAnswerView: View {
    let live: AskStreams.Live
    let onCitation: (CitationGroup) -> Void

    var body: some View {
        if live.origin == nil && live.text.isEmpty && live.steps.isEmpty {
            CapThinkingBubble()
        } else {
            let groups = CitationGroup.groups(live.citations)
            VStack(alignment: .leading, spacing: 8) {
                if !live.steps.isEmpty {
                    AssistantStepList(steps: live.steps, actions: .live, animated: true)
                }
                if !live.text.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        CapMarkdownView(text: live.text, streaming: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(CapMessageView.spoken(live.text, groups: groups)))
                        if !groups.isEmpty {
                            CLFlow(spacing: 6, lineSpacing: 0) {
                                ForEach(groups) { group in
                                    CitationChipButton(group: group) { onCitation(group) }
                                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                                }
                            }
                            .padding(.vertical, -6)
                            .animation(CLMotion.pop, value: groups.count)
                        }
                    }
                    .capBubble()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 28)
                } else if !live.steps.isEmpty, !live.steps.contains(where: { $0.status == .working }) {
                    // The work is on the table; Cap is writing its note.
                    AssistantWritingNote()
                }
                if let working = live.steps.last(where: { $0.status == .working }) {
                    AssistantWorkingBar(step: working)
                }
                if let origin = OriginNote.line(origin: live.origin, note: nil, quotesNotes: !live.citations.isEmpty) {
                    OriginNote(text: origin.text, systemImage: origin.icon)
                }
            }
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Cap at work under the card that is working, and what he is doing this second.
struct AssistantWorkingBar: View {
    let step: AssistantStep

    var body: some View {
        HStack(spacing: 10) {
            CapView(.working, size: 44, interactive: false)
            Text(verbatim: line)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .contentTransition(.opacity)
                .animation(CLMotion.fade, value: line)
            WorkingDots()
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cap is working: \(line)"))
    }

    private var line: String {
        switch step.payload {
        case .lookup: return String(localized: "Reading your notes")
        case .cards(let c):
            return c.isEmpty ? String(localized: "Choosing what to put on the cards")
                : step.checking == true ? String(localized: "Checking each card against your notes") : String(localized: "Writing the cards")
        case .questions(let q):
            return q.isEmpty ? String(localized: "Choosing what to ask")
                : step.checking == true ? String(localized: "Checking each question against your notes") : String(localized: "Writing the questions")
        case .note(let n): return n.body.isEmpty ? String(localized: "Starting your note") : String(localized: "Writing your note")
        case .research(let r):
            switch r.phase {
            case .starting, .searching: return String(localized: "Searching trusted study sites")
            case .reading: return String(localized: "Reading \(CLFormat.count(r.sources.count, "page"))")
            case .writing: return String(localized: "Writing the summary")
            case .done: return String(localized: "Almost done")
            }
        case .exam: return String(localized: "Looking at the calendar")
        default: return String(localized: "Working on it")
        }
    }
}

/// Cap is writing the short note that goes with what it made.
struct AssistantWritingNote: View {
    var body: some View {
        HStack(spacing: 10) {
            CapView(.working, size: 40)
            Text("Cap is adding a note").clFont(.footnote).foregroundStyle(CLColor.ink3)
            WorkingDots()
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cap is writing a note about what it made"))
    }
}

// MARK: - Empty

struct RecentChat: Identifiable, Equatable {
    var id: UUID
    var title: String
    var updatedAt: Date
}

/// A new chat, calm: Cap, one line on what he answers from, and the latest chat to pick up. With no material yet, a way to add some. The
/// starter chips are in the dock.
struct AskEmptyState: View {
    let courseName: String?
    let sourceCount: Int
    let recent: RecentChat?
    let now: Date
    let onOpen: (UUID) -> Void
    let onAddMaterial: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                CapView(pose: sourceCount == 0 ? .sleep : .study, size: 132)
                Text(line)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)

            if sourceCount == 0 {
                Button(action: onAddMaterial) {
                    Label("Add your notes", systemImage: "doc.viewfinder")
                }
                .buttonStyle(.cl(.primary))
                .padding(.top, 22)
            }

            if let recent {
                CLSectionHeader(title: "Pick up where you left off")
                CLList {
                    Button { onOpen(recent.id) } label: {
                        CLRow(icon: "bubble.left.and.bubble.right", tint: .tangerine, title: .verbatim(recent.title),
                              subtitle: .verbatim(Self.when(recent.updatedAt, now: now)))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var line: LocalizedStringResource {
        if sourceCount == 0 { return "Scan a page or add slides, and ask away. Every answer points to where it says so." }
        let course = courseName ?? String(localized: "your courses")
        return "Ask about \(course). I answer from your \(sourceCount) sources and show you where."
    }

    static func when(_ date: Date, now: Date) -> String {
        let days = Calendar.current.dayDistance(from: date, to: now)
        switch days {
        case 0: return "Today, " + date.formatted(.dateTime.hour().minute())
        case 1: return "Yesterday"
        case 2..<7: return date.formatted(.dateTime.weekday(.wide))
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

/// One row of chips over the composer while the chat is empty, a line that scrolls sideways at every text size (more lines of them would
/// leave no room for the chat at the largest). It keeps its height until the chips are ready.
struct AskDockChipRow: View {
    let chips: [AskDockChips.Chip]?
    let onTap: (AskDockChips.Chip) -> Void

    var body: some View {
        Group {
            if let chips {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip($0) }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } else {
                Color.clear.frame(height: CLMetrics.minHitTarget)
            }
        }
        .animation(CLMotion.fade, value: chips)
    }

    private func chip(_ chip: AskDockChips.Chip) -> some View {
        SuggestionChip(title: chip.title, systemImage: chip.icon) { onTap(chip) }
            .transition(.opacity)
            .accessibilityHint(chip.isQuestion ? Text("Asks Cap") : Text("Starts a request for you to finish"))
    }
}

/// The first words of the things Cap can make, put in the composer to be finished.
enum AssistantQuickStart {
    enum Kind: Sendable { case quiz, cards, note, exam, research }
    struct Start: Equatable { var title: String; var icon: String; var prefix: String; var kind: Kind }

    /// What this student can ask for: everything, except the web when it is off (or not for them).
    @MainActor
    static func available(_ app: AppModel) -> [Start] {
        var all = [
            Start(title: String(localized: "Make flashcards"), icon: "rectangle.stack", prefix: String(localized: "Make flashcards on "), kind: .cards),
            Start(title: String(localized: "Quiz me"), icon: "checklist", prefix: String(localized: "Quiz me on "), kind: .quiz),
            Start(title: String(localized: "Write a note"), icon: "doc.text", prefix: String(localized: "Write me a note on "), kind: .note),
            Start(title: String(localized: "Add an exam"), icon: "calendar", prefix: String(localized: "Add my exam on "), kind: .exam),
        ]
        if app.assistantTools.contains(.researchWeb) {
            all.append(Start(title: String(localized: "Research online"), icon: "globe", prefix: String(localized: "Research online: "), kind: .research))
        }
        return all
    }
}
