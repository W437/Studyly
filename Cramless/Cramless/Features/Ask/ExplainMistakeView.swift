import SwiftUI

/// "Explain my mistake": the question, the person's answer beside the one expected, then Cap's explanation from
/// their own notes, streaming with citations, its quick check, and a follow-up. The exchange is kept as a chat, so
/// it's in the Ask tab's history afterwards. Citations open inside this sheet (back returns here); "Ask a
/// follow-up" continues in the Ask tab, or right here when the sheet sits over a study session.
///
/// Harness: `CRAMLESS_ROUTE=explain` (the first own-words question, answered "Cells divide so they can make sex
/// cells."). `CRAMLESS_EXPLAIN=followup` opens the follow-up composer once the answer is in.
struct ExplainMistakeView: View {
    let itemID: UUID
    let given: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var threadID: UUID?
    @State private var followingUp = false
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var path: [CitationGroup] = []
    @State private var missing = false

    private var streams: AskStreams { AskStreams.shared }

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
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(entries: entries, live: live)
                    if let item {
                        MistakeCard(prompt: item.prompt, given: given, expected: item.answer, kind: item.kind)
                    } else if missing {
                        Text("This question isn't in your library anymore.")
                            .clFont(.body).foregroundStyle(CLColor.ink2)
                    }
                    reply(entries: entries, live: live)
                    if !followingUp && typeSize.isAccessibilitySize {
                        // At the largest text sizes the actions end the page instead of covering half of it.
                        actions(entries: entries, live: live)
                            .padding(.top, 8)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 22)
                .padding(.bottom, 12)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // The question and the mistake stay in view while the first answer arrives; a follow-up scrolls down.
            .onChange(of: entries.count) { _, _ in
                guard followingUp else { return }
                withAnimation(CLMotion.settle) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: live?.text.count ?? 0) { _, _ in
                guard followingUp else { return }
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar(entries: entries, live: live) }
        .clScreenBackground()
    }

    private func header(entries: [ChatEntry], live: AskStreams.Live?) -> some View {
        let labels = CitationGroup.groups(entries.first { $0.role == .assistant }?.citations ?? live?.citations ?? []).map(\.label)
        let subtitle = labels.isEmpty
            ? (live != nil || entries.isEmpty ? "Reading your notes" : "From your notes")
            : "From " + ListFormatter.localizedString(byJoining: Array(labels.prefix(2)))
        return HStack(alignment: .center, spacing: 12) {
            CapFace(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cap explains").clFont(.title3).foregroundStyle(CLColor.ink).accessibilityAddTraits(.isHeader)
                Text(subtitle).clFont(.footnote).foregroundStyle(CLColor.ink2).lineLimit(2)
            }
            Spacer(minLength: 8)
            CLIconButton(systemImage: "xmark", label: "Close") { close() }
        }
    }

    @ViewBuilder
    private func reply(entries: [ChatEntry], live: AskStreams.Live?) -> some View {
        let lastAssistant = entries.lastIndex { $0.role == .assistant }
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            if entry.role == .user {
                UserBubble(text: entry.text)
            } else {
                let reply = entries.indices.contains(index + 1) && entries[index + 1].role == .user ? entries[index + 1].text : nil
                CapMessageView(entry: entry, note: streams.notes[entry.id], chatContext: entries.first?.text ?? "",
                               isLatest: index == lastAssistant && live == nil, reply: reply,
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

    @ViewBuilder
    private func bottomBar(entries: [ChatEntry], live: AskStreams.Live?) -> some View {
        if followingUp {
            ChatComposer(text: $draft, focused: $composerFocused, isAnswering: live != nil,
                         placeholder: "Ask a follow-up…",
                         onSend: {
                             let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                             draft = ""
                             ask(text, sendAs: nil)
                         },
                         onStop: { if let id = threadID { streams.stop(id, app: app) } })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        } else if !typeSize.isAccessibilitySize {
            actions(entries: entries, live: live)
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

    /// "Just explain it" (after a hint), "Ask a follow-up", and back to the session (or Done).
    private func actions(entries: [ChatEntry], live: AskStreams.Live?) -> some View {
        let answered = live == nil && entries.contains { $0.role == .assistant }
        return VStack(spacing: 6) {
            if answered, app.settings.effectiveTutorMode == .hints, !app.settings.isMinor {
                Button("Just explain it") {
                    app.setTutorMode(.explain)
                    ask("Just explain it, please.", sendAs: "Just explain the answer to “\(app.item(itemID)?.prompt ?? "this question")”, please.")
                }
                .buttonStyle(.cl(.ghost, size: .small))
            }
            // Side by side when both labels fit (a wide font or a large size stacks them).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actionButtons(live: live) }
                VStack(spacing: 10) { actionButtons(live: live) }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(live: AskStreams.Live?) -> some View {
        Button("Ask a follow-up") { followUp() }
            .buttonStyle(.cl(.soft))
            .disabled(threadID == nil || live != nil)
        Button(isOverSession ? "Back to my session" : "Done") { close() }
            .buttonStyle(.cl(.primary))
    }

    @ViewBuilder
    private func citationDestination(_ group: CitationGroup) -> some View {
        if let first = group.citations.first, let id = first.sourceID, app.source(id) != nil {
            if first.pageIndex == nil, first.start != nil {
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
        #if DEBUG
        if TestHarness.once("CRAMLESS_EXPLAIN") == "followup" { followingUp = true }
        #endif
    }

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
