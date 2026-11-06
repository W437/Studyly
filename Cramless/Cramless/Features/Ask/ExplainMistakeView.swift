import SwiftUI

/// "Explain my mistake": three steps, a page each, one at a time. What you wrote (the question, the person's answer beside the one expected,
/// and what was right and the one thing off), why (from their own notes, with the page), and a quick check with "Make this a card". A page
/// unlocks as Cap's answer reaches it. The exchange is kept as a chat, so it's in the Ask tab's history afterwards. Citations open inside this
/// sheet (back returns here); "Ask a follow-up" continues in the Ask tab, or right here when the sheet sits over a study session.
///
/// Harness: `CRAMLESS_ROUTE=explain` (the first own-words question, answered "Cells divide so they can make sex cells.").
/// `CRAMLESS_EXPLAIN_STEP=1|2|3` opens that step once the answer has reached it. `CRAMLESS_EXPLAIN=card` opens step 3 with the card drafted,
/// `added` with it added, `followup` with the follow-up composer open.
struct ExplainMistakeView: View {
    let itemID: UUID
    let given: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var threadID: UUID?
    @State private var page: MistakeSteps.Page = .what
    @State private var goingForward = true
    @State private var followingUp = false
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var path: [CitationGroup] = []
    @State private var missing = false
    #if DEBUG
    @State private var harnessStep: MistakeSteps.Page?
    @State private var harnessCard: MistakeCardMaker.Hook?
    #endif

    private var streams: AskStreams { AskStreams.shared }

    /// Only sessions open this sheet, and nothing is sold in the middle of studying: a free limit here is a line, never "See Pro".
    static let allowsUpgrade = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: CitationGroup.self) { group in
                    citationDestination(group)
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Sheets don't inherit the root's font choice (RootView sets it inside the modifier that presents them).
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        .task { start() }
    }

    // MARK: Content

    private var content: some View {
        let _ = app.revision
        let thread = app.thread(threadID).flatMap { $0.modelContext != nil ? $0 : nil }
        let entries = Array(ChatEntry.entries(of: thread).drop { $0.role == .user && $0.contextItemID == itemID })
        let live = threadID.flatMap { streams.live[$0] }
        let item = app.item(itemID).flatMap { $0.modelContext != nil ? $0 : nil }
        // The explanation is the first of Cap's messages; anything after it is a quick check's answer or a follow-up.
        let first = entries.first { $0.role == .assistant }
        let steps = MistakeSteps.split(first?.text ?? live?.text ?? "", streaming: first == nil, chatContext: item?.prompt ?? "")
        let shown = steps.pages.contains(page) ? page : (steps.pages.last ?? .what)
        return VStack(spacing: 0) {
            header(steps: steps, shown: shown)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 22)
                .padding(.bottom, 12)
                .frame(maxWidth: CLMetrics.readableWidth)
            ZStack {
                pageView(shown, steps: steps, first: first, entries: entries, live: live, item: item)
                    .id(shown)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .simultaneousGesture(swipe(steps: steps, shown: shown))
        }
        .safeAreaInset(edge: .bottom) { bottomBar(steps: steps, shown: shown, thread: thread, live: live) }
        .clScreenBackground()
        .captureDebugCanvas()
        #if DEBUG
        .onChange(of: steps.pages.count, initial: true) { _, _ in applyHarnessStep(steps) }
        #endif
    }

    /// The pages slide, the way they were reached; under Reduce Motion they cross-fade.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: goingForward ? .trailing : .leading),
                           removal: .move(edge: goingForward ? .leading : .trailing))
    }

    private func header(steps: MistakeSteps, shown: MistakeSteps.Page) -> some View {
        HStack(alignment: .center, spacing: 12) {
            CapFace(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(steps: steps, shown: shown)).clFont(.title3).foregroundStyle(CLColor.ink).accessibilityAddTraits(.isHeader)
                if steps.total > 1 {
                    Text("Step \(position(of: shown, in: steps)) of \(steps.total)")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                }
            }
            Spacer(minLength: 8)
            CLIconButton(systemImage: "xmark", label: "Close") { close() }
        }
    }

    private func title(steps: MistakeSteps, shown: MistakeSteps.Page) -> LocalizedStringResource {
        guard steps.total > 1 else { return "Cap explains" }
        switch shown {
        case .what: return "What you wrote"
        case .why: return "Why"
        case .check: return "Quick check"
        }
    }

    private func position(of page: MistakeSteps.Page, in steps: MistakeSteps) -> Int {
        // While the reply arrives the later pages aren't reached yet, so a page's number is its own.
        steps.total == MistakeSteps.Page.allCases.count ? page.rawValue : (steps.pages.firstIndex(of: page) ?? 0) + 1
    }

    @ViewBuilder
    private func pageView(_ shown: MistakeSteps.Page, steps: MistakeSteps, first: ChatEntry?, entries: [ChatEntry],
                          live: AskStreams.Live?, item: StudyItem?) -> some View {
        let citations = first?.citations ?? live?.citations ?? []
        let groups = CitationGroup.groups(citations)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch shown {
                    case .what:
                        if let item {
                            MistakeCard(prompt: item.prompt, given: given, expected: item.answer, kind: item.kind)
                        } else if missing {
                            Text("This question isn't in your library anymore.")
                                .clFont(.body).foregroundStyle(CLColor.ink2)
                        }
                        if first == nil, steps.what.isEmpty, !missing {
                            CapThinkingBubble()
                        } else if !steps.what.isEmpty {
                            explanation(steps.what, groups: steps.pages.contains(.why) ? [] : groups, streaming: first == nil)
                        }
                        footnotes(first: first)
                    case .why:
                        explanation(steps.why, groups: groups, streaming: first == nil)
                    case .check:
                        checkPage(steps: steps, first: first, entries: entries, live: live, item: item)
                    }
                    if !followingUp && typeSize.isAccessibilitySize {
                        // At the largest text sizes the buttons end the page instead of covering half of it.
                        pagerButtons(steps: steps, shown: shown, live: live)
                            .padding(.top, 8)
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
            // A quick check's answer and a follow-up arrive below: they scroll into view. The explanation arriving doesn't move the page.
            .onChange(of: laterEntries(entries).count) { _, _ in
                guard shown == .check else { return }
                withAnimation(CLMotion.settle) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: live?.text.count ?? 0) { _, count in
                // A stream ending counts as a change too, down to nothing: only one still arriving moves the page.
                guard shown == .check, first != nil, count > 0 else { return }
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    private func explanation(_ text: String, groups: [CitationGroup], streaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapMarkdownView(text: text, streaming: streaming)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(CapMessageView.spoken(text, groups: groups)))
                .accessibilityActions {
                    ForEach(groups) { group in
                        Button("Open \(group.label)") { path.append(group) }
                    }
                }
            if !groups.isEmpty {
                CLFlow(spacing: 6, lineSpacing: 0) {
                    ForEach(groups) { group in
                        CitationChipButton(group: group) { path.append(group) }
                    }
                }
                .padding(.vertical, -6)
                .animation(CLMotion.pop, value: groups.count)
            }
        }
        .capBubble()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 28)
    }

    /// Who answered and what a better path offers, once the answer is in.
    @ViewBuilder
    private func footnotes(first: ChatEntry?) -> some View {
        if let first {
            let note = streams.notes[first.id]
            if let origin = OriginNote.line(origin: note?.origin ?? first.origin, note: note?.note, quotesNotes: !first.citations.isEmpty) {
                OriginNote(text: origin.text, systemImage: origin.icon)
            }
            if let suggestion = note?.suggestion {
                AISuggestionCard(suggestion: suggestion, allowsUpgrade: Self.allowsUpgrade) { app.router.present(suggestion.sheet) }
                    .padding(.trailing, 28)
            }
        }
    }

    @ViewBuilder
    private func checkPage(steps: MistakeSteps, first: ChatEntry?, entries: [ChatEntry], live: AskStreams.Live?, item: StudyItem?) -> some View {
        let later = laterEntries(entries)
        let reply = later.first { $0.role == .user }?.text
        if let check = steps.check {
            QuickCheckCard(check: check, isActive: first != nil && live == nil, answered: reply, showsLabel: false) { answer in
                ask(answer, sendAs: "Quick check: \(check.question) My answer: \(answer)")
            }
        } else if !steps.checkDraft.isEmpty {
            CapMarkdownView(text: steps.checkDraft, streaming: true)
                .capBubble()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 28)
        } else {
            CapThinkingBubble()
        }
        followUps(later, live: first == nil ? nil : live)
        if first != nil, let item, !followingUp {
            MistakeCardMaker(itemID: itemID, courseName: item.course?.name ?? "", threadID: threadID, given: given, hook: cardHook)
            Button("Ask a follow-up") { followUp() }
                .buttonStyle(.cl(.ghost, size: .small))
                .disabled(threadID == nil || live != nil)
        }
    }

    private var cardHook: MistakeCardMaker.Hook? {
        #if DEBUG
        harnessCard
        #else
        nil
        #endif
    }

    /// What came after the explanation: a quick check's answer and Cap's reply, follow-ups.
    private func laterEntries(_ entries: [ChatEntry]) -> [ChatEntry] {
        guard let at = entries.firstIndex(where: { $0.role == .assistant }) else { return [] }
        return Array(entries[(at + 1)...])
    }

    @ViewBuilder
    private func followUps(_ later: [ChatEntry], live: AskStreams.Live?) -> some View {
        let lastAssistant = later.lastIndex { $0.role == .assistant }
        ForEach(Array(later.enumerated()), id: \.element.id) { index, entry in
            if entry.role == .user {
                // The first of them, when it was one of the check's buttons: the card shows which.
                if !(index == 0 && isCheckAnswer(entry)) { UserBubble(text: entry.text) }
            } else {
                let reply = later.indices.contains(index + 1) && later[index + 1].role == .user ? later[index + 1].text : nil
                CapMessageView(entry: entry, note: streams.notes[entry.id], chatContext: later.first?.text ?? "",
                               isLatest: index == lastAssistant && live == nil, reply: reply,
                               allowsUpgrade: Self.allowsUpgrade,
                               onCitation: { path.append($0) },
                               onAnswer: { answer, check in
                                   ask(answer, sendAs: "Quick check: \(check.question) My answer: \(answer)")
                               },
                               onSuggestion: { app.router.present($0.sheet) })
            }
        }
        if let live {
            LiveAnswerView(live: live, onCitation: { path.append($0) })
        }
    }

    /// Whether the check took this answer through its buttons (they show which was picked), so it needs no bubble of its own.
    private func isCheckAnswer(_ entry: ChatEntry) -> Bool {
        guard let first = threadID.flatMap({ app.thread($0) })?.sortedMessages.first(where: { $0.role == .assistant }) else { return false }
        let options = MistakeSteps.split(first.text, chatContext: app.item(itemID)?.prompt ?? "").check?.options ?? []
        return options.contains { Lexicon.normalizedAnswer($0) == Lexicon.normalizedAnswer(entry.text) }
    }

    @ViewBuilder
    private func bottomBar(steps: MistakeSteps, shown: MistakeSteps.Page, thread: ChatThread?, live: AskStreams.Live?) -> some View {
        if followingUp {
            AskDock {
                ChatComposer(text: $draft, focused: $composerFocused, isAnswering: live != nil,
                             placeholder: "Ask a follow-up…",
                             onSend: {
                                 let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                 draft = ""
                                 ask(text, sendAs: nil)
                             },
                             onStop: { if let id = threadID { streams.stop(id, app: app) } })
            }
        } else if !typeSize.isAccessibilitySize {
            pagerButtons(steps: steps, shown: shown, live: live)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(alignment: .top) {
                    CLColor.background
                        .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    /// The dots, Back and Next; on the last page, back to the session (or Done).
    private func pagerButtons(steps: MistakeSteps, shown: MistakeSteps.Page, live: AskStreams.Live?) -> some View {
        VStack(spacing: 10) {
            if steps.total > 1 {
                MistakeStepDots(current: position(of: shown, in: steps), total: steps.total)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { stepButtons(steps: steps, shown: shown) }
                VStack(spacing: 10) { stepButtons(steps: steps, shown: shown) }
            }
        }
    }

    @ViewBuilder
    private func stepButtons(steps: MistakeSteps, shown: MistakeSteps.Page) -> some View {
        if let back = previous(shown, in: steps) {
            Button("Back") { go(to: back, steps: steps) }
                .buttonStyle(.cl(.soft))
        }
        if isLast(shown, in: steps) {
            Button(isOverSession ? "Back to my session" : "Done") { close() }
                .buttonStyle(.cl(.primary))
        } else {
            let next = next(shown, in: steps)
            Button("Next") { if let next { go(to: next, steps: steps) } }
                .buttonStyle(.cl(.primary))
                .disabled(next == nil)
                .accessibilityHint(next == nil ? Text("Cap is still writing this step") : Text(""))
        }
    }

    private func previous(_ page: MistakeSteps.Page, in steps: MistakeSteps) -> MistakeSteps.Page? {
        steps.pages.firstIndex(of: page).flatMap { $0 > 0 ? steps.pages[$0 - 1] : nil }
    }

    private func next(_ page: MistakeSteps.Page, in steps: MistakeSteps) -> MistakeSteps.Page? {
        steps.pages.firstIndex(of: page).flatMap { $0 + 1 < steps.pages.count ? steps.pages[$0 + 1] : nil }
    }

    /// A finished reply's last page. While it streams, later pages are still to come.
    private func isLast(_ page: MistakeSteps.Page, in steps: MistakeSteps) -> Bool {
        steps.total == steps.pages.count && steps.pages.last == page
    }

    private func swipe(steps: MistakeSteps, shown: MistakeSteps.Page) -> some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > 70, abs(dx) > abs(value.translation.height) * 1.6, !followingUp else { return }
            if let target = dx < 0 ? next(shown, in: steps) : previous(shown, in: steps) { go(to: target, steps: steps) }
        }
    }

    private func go(to target: MistakeSteps.Page, steps: MistakeSteps) {
        CLHaptics.tap()
        goingForward = target.rawValue > page.rawValue
        withAnimation(CLMotion.settle) { page = target }
        AccessibilityNotification.Announcement(String(localized: "Step \(position(of: target, in: steps)) of \(steps.total)")).post()
    }

    @ViewBuilder
    private func citationDestination(_ group: CitationGroup) -> some View {
        if let first = group.citations.first, let id = first.sourceID, let source = app.source(id) {
            if source.kind.isDeck {
                DeckCardView(sourceID: id, quote: first.quote, label: first.label)
            } else if first.pageIndex == nil, first.start != nil {
                LectureNotesView(sourceID: id, focusTime: first.start)
            } else {
                SourcePageView(sourceID: id, pageIndex: first.pageIndex ?? 0, highlight: CitationOpener.anchors(group, app: app))
            }
        } else {
            Text("That source isn't in your library anymore.").clFont(.body).foregroundStyle(CLColor.ink2)
        }
    }

    // MARK: Actions

    private var isOverSession: Bool {
        if case .session = app.router.cover { return true }
        return false
    }

    private func start() {
        guard threadID == nil else { return }
        #if DEBUG
        AskDemo.applyLaunchState(app)
        applyHarnessHooks()
        #endif
        guard let item = app.item(itemID), item.modelContext != nil,
              let context = app.mistakeContext(itemID: itemID, given: given) else {
            missing = true
            return
        }
        let thread = app.startChat(courseID: item.course?.id, title: AppModel.chatTitle(for: item.prompt))
        threadID = thread.id
        streams.ask(AppModel.mistakeQuestion(given: given), in: thread, app: app, context: context,
                    contextItemID: itemID, preferring: item.sourceRef?.sourceID)
    }

    #if DEBUG
    private func applyHarnessHooks() {
        harnessStep = TestHarness.once("CRAMLESS_EXPLAIN_STEP").flatMap { Int($0) }.flatMap(MistakeSteps.Page.init(rawValue:))
        switch TestHarness.once("CRAMLESS_EXPLAIN") {
        case "followup":
            followingUp = true
            harnessStep = .check
        case "card":
            harnessCard = .draft
            harnessStep = .check
        case "added":
            harnessCard = .added
            harnessStep = .check
        default:
            break
        }
    }

    private func applyHarnessStep(_ steps: MistakeSteps) {
        guard let want = harnessStep, steps.pages.contains(want) else { return }
        page = want
        harnessStep = nil
    }
    #endif

    private func ask(_ text: String, sendAs: String?) {
        guard let thread = app.thread(threadID), !text.isEmpty, !streams.isAnswering(threadID) else { return }
        CLHaptics.tap()
        withAnimation(CLMotion.settle) {
            streams.ask(text, in: thread, app: app, sendAs: sendAs)
        }
    }

    /// Over a study session the follow-up happens here; otherwise the chat opens in the Ask tab.
    private func followUp() {
        CLHaptics.tap()
        guard let threadID else { return }
        if isOverSession {
            withAnimation(CLMotion.settle) { followingUp = true }
            composerFocused = true
        } else {
            app.router.dismissSheet()
            app.router.popToRoot(.ask)
            app.router.push(.chat(threadID), on: .ask)
        }
    }

    private func close() {
        dismiss()
    }
}

/// Where the sheet is: one dot a step, the current one filled. VoiceOver reads the step from the header.
private struct MistakeStepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...max(total, 1), id: \.self) { step in
                Circle()
                    .fill(step == current ? CLColor.tangerine : CLColor.surface3)
                    .frame(width: 7, height: 7)
            }
        }
        .animation(CLMotion.snap, value: current)
        .accessibilityHidden(true)
    }
}

/// "Make this a card" at the end of Explain my mistake: one card drafted from the chat, inline, with both sides editable. Nothing is added
/// before "Add to <course>". It goes to the question's course and topic, linked to the page the explanation cited (`AppModel.addMistakeCard`).
struct MistakeCardMaker: View {
    enum Hook { case draft, added }

    let itemID: UUID
    let courseName: String
    let threadID: UUID?
    let given: String
    /// Harness: start drafting at once, and add it too.
    var hook: Hook? = nil

    private enum Phase: Equatable { case idle, making, draft, added, failed }

    @Environment(AppModel.self) private var app
    @State private var phase: Phase = .idle
    @State private var front = ""
    @State private var back = ""
    @State private var card: GeneratedItem?
    @State private var origin: ItemOrigin = .rules
    @State private var hookUsed = false

    var body: some View {
        Group {
            switch phase {
            case .idle:
                Button { Task { await make() } } label: {
                    Label("Make this a card", systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(.cl(.soft))
            case .making:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Cap is writing the card…").clFont(.footnote).foregroundStyle(CLColor.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                .accessibilityElement(children: .combine)
            case .draft:
                draftCard
            case .added:
                Label("Card added from your notes", systemImage: "checkmark.circle.fill")
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.mintInk)
                    .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
            case .failed:
                Text("Cap couldn't make a card from this one.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
            }
        }
        .animation(CLMotion.settle, value: phase)
        #if DEBUG
        .task(id: hook == nil) {
            guard let hook, !hookUsed else { return }
            hookUsed = true
            await make()
            if hook == .added { add() }
        }
        #endif
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CLEyebrow(text: "Make this a card")
            field("Front", text: $front)
            field("Back", text: $back)
            Button("Add to \(courseName)") { add() }
                .buttonStyle(.cl(.primary))
                .disabled(front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .clCard()
    }

    private func field(_ title: LocalizedStringResource, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink2)
            TextField(String(localized: title), text: text, axis: .vertical)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .lineLimit(1...5)
                .padding(10)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(Text(title))
        }
    }

    private func make() async {
        CLHaptics.tap()
        phase = .making
        guard let item = app.item(itemID), item.modelContext != nil else {
            phase = .failed
            return
        }
        // The chat, with the question it is about in words of its own: the sheet shows the question, the stored chat doesn't hold it.
        let thread = app.thread(threadID).flatMap { $0.modelContext != nil ? $0 : nil }
        var messages = thread?.sortedMessages.map { TutorMessage(role: $0.role, text: $0.text) } ?? []
        if let i = messages.firstIndex(where: { $0.role == .user }) {
            messages[i].text = "\(item.prompt) I answered “\(given)”, but the answer is “\(item.answer)”. What did I miss?"
        }
        let outcome = await app.ai.cardsFromChat(course: item.course?.name, messages: messages, maxItems: 1)
        guard let first = outcome.items.first else {
            phase = .failed
            return
        }
        card = first
        origin = outcome.origin
        front = first.prompt
        back = first.answer
        phase = .draft
    }

    private func add() {
        guard var card else { return }
        card.prompt = front
        card.answer = back
        // A multiple-choice draft whose words were changed would no longer match its options: as a card it asks and answers.
        card.kind = .flashcard
        card.choices = []
        let thread = app.thread(threadID).flatMap { $0.modelContext != nil ? $0 : nil }
        guard app.addMistakeCard(card, origin: origin, itemID: itemID, from: thread) != nil else {
            phase = .failed
            return
        }
        CLFeel.play(.saved)
        phase = .added
    }
}

/// The question, what the person wrote and the answer it expects: side by side when there's room.
private struct MistakeCard: View {
    let prompt: String
    let given: String
    let expected: String
    let kind: ItemKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CLEyebrow(text: .verbatim(kind.displayName))
            Text(prompt)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { answers }
                VStack(alignment: .leading, spacing: 10) { answers }
            }
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var answers: some View {
        answer(title: "You wrote", text: given.isEmpty ? "No answer" : given, systemImage: "xmark", tint: CLColor.roseSoft, ink: CLColor.roseInk)
        answer(title: "The answer", text: expected, systemImage: "checkmark", tint: CLColor.mintSoft, ink: CLColor.mintInk)
    }

    private func answer(title: String, text: String, systemImage: String, tint: Color, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .clFont(.footnoteEmphasis)
                .foregroundStyle(ink)
            Text(text)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
