import SwiftUI

/// Make cards from a chat: Cap drafts cards from the conversation, the person ticks the ones to keep, edits any,
/// picks the course and adds them with one tap. Nothing is added before that tap. Cards that rest on a page the chat
/// cited link back to it.
///
/// Harness: `CRAMLESS_ROUTE=makeCards` (the latest chat). `CRAMLESS_CARDS=making` holds the drafting state;
/// `edit` opens the first draft for editing.
struct MakeCardsView: View {
    let threadID: UUID
    /// How many cards to draft at most.
    var maxItems = 6

    struct Draft: Identifiable, Equatable {
        var card: GeneratedItem
        var kept = true
        var id: String { card.id }
    }

    enum Phase: Equatable { case making, ready, empty, missing }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .making
    @State private var drafts: [Draft] = []
    @State private var origin: ItemOrigin = .rules
    @State private var suggestion: AISuggestion?
    @State private var courseID: UUID?
    @State private var editing: String?
    @State private var added = false

    private var keptCount: Int { drafts.filter(\.kept).count }

    var body: some View {
        let _ = app.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                switch phase {
                case .making: making
                case .ready: ready
                case .empty: emptyState(title: "No cards in this chat yet",
                                        text: "Ask Cap a question or two first. Cards come from what Cap explained.")
                case .missing: emptyState(title: "This chat was deleted", text: "Its cards can't be made anymore.")
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if phase == .ready { addBar }
        }
        .clScreenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Sheets don't inherit the root's font choice (RootView sets it inside the modifier that presents them).
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        .task { await make() }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: "rectangle.stack.badge.plus", tint: .tangerine, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cards from this chat").clFont(.title2).foregroundStyle(CLColor.ink).accessibilityAddTraits(.isHeader)
                Text(subtitle).clFont(.footnote).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CLIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
    }

    private var subtitle: String {
        let title = app.thread(threadID).flatMap { $0.modelContext != nil ? $0.title : nil } ?? "Your chat"
        switch phase {
        case .making: return "Cap is picking the key ideas from “\(title)”"
        case .ready:
            let who = switch origin {
            case .cloud: "Made with Cloud AI"
            case .onDevice: "Made on this iPhone"
            default: "Made from Cap's answers, no AI"
            }
            return "\(who), from “\(title)”. Keep the ones you want."
        case .empty, .missing: return title
        }
    }

    private var making: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                DraftCardView(draft: .constant(Draft(card: GeneratedItem(id: "p\(i)", kind: .flashcard, topic: "",
                                                                         prompt: "Mitosis vs cytokinesis, which comes first",
                                                                         answer: "Mitosis splits the nucleus; cytokinesis splits the cell."))),
                              isEditing: false, onEdit: {})
                    .redacted(reason: .placeholder)
                    .opacity(1 - Double(i) * 0.22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cap is making cards from your chat")
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($drafts) { $draft in
                DraftCardView(draft: $draft, isEditing: editing == draft.id) {
                    withAnimation(CLMotion.settle) { editing = editing == draft.id ? nil : draft.id }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let suggestion {
                AISuggestionCard(suggestion: suggestion) { app.router.present(suggestion.sheet) }
            }
        }
    }

    private func emptyState(title: String, text: String) -> some View {
        VStack(spacing: 12) {
            CapView(pose: .sleep, size: 150)
            Text(title).clFont(.headline).foregroundStyle(CLColor.ink)
            Text(text).clFont(.subheadline).foregroundStyle(CLColor.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    private var addBar: some View {
        let course = app.liveCourse(courseID)
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Add to").clFont(.subheadline).foregroundStyle(CLColor.ink2)
                Menu {
                    Picker("Course", selection: $courseID) {
                        ForEach(app.courses) { c in Label(c.name, systemImage: c.symbol).tag(Optional(c.id)) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(course?.name ?? "Choose a course").clFont(.subheadlineEmphasis)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(CLColor.skyInk)
                    .frame(minHeight: CLMetrics.minHitTarget)
                }
                .accessibilityLabel(Text("Course: \(course?.name ?? "none chosen")"))
                Spacer()
            }
            Button(action: add) {
                ZStack {
                    Text(addTitle(course: course)).opacity(added ? 0 : 1)
                    Label("Added", systemImage: "checkmark").opacity(added ? 1 : 0).scaleEffect(added ? 1 : 0.7)
                }
                .animation(CLMotion.pop, value: added)
            }
            .buttonStyle(.cl(.primary))
            .disabled(keptCount == 0 || course == nil || added)
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            CLColor.background
                .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func addTitle(course: Course?) -> String {
        guard keptCount > 0 else { return "Pick a card to add" }
        return "Add \(CLFormat.count(keptCount, "card")) to \(course?.name ?? "a course")"
    }

    // MARK: Actions

    private func make() async {
        guard phase == .making, drafts.isEmpty else { return }
        guard let thread = app.thread(threadID), thread.modelContext != nil else { phase = .missing; return }
        if courseID == nil { courseID = app.liveCourse(thread.courseID)?.id ?? app.defaultChatCourseID }
        let messages = thread.sortedMessages.map { TutorMessage(role: $0.role, text: $0.text) }
        #if DEBUG
        AskDemo.applyLaunchState(app)
        let hook = TestHarness.once("CRAMLESS_CARDS")
        if hook == "making" { return }
        #endif
        let outcome = await app.ai.cardsFromChat(course: app.liveCourse(thread.courseID)?.name, messages: messages, maxItems: maxItems)
        origin = outcome.origin
        suggestion = outcome.suggestion
        withAnimation(CLMotion.settle) {
            drafts = outcome.items.map { Draft(card: $0) }
            phase = drafts.isEmpty ? .empty : .ready
        }
        #if DEBUG
        if hook == "edit" { editing = drafts.first?.id }
        #endif
    }

    private func add() {
        guard let courseID, let course = app.liveCourse(courseID) else { return }
        let picked = drafts.filter(\.kept).map(\.card)
        let made = app.addCardsFromChat(picked, origin: origin, to: courseID, from: app.thread(threadID))
        guard !made.isEmpty else { return }
        CLHaptics.success()
        added = true
        let message = "Added \(CLFormat.count(made.count, "card")) to \(course.name)"
        let note = app.newQuestionsNote(added: made.count, in: course)
        Task { @MainActor in
            try? await nap(550)
            dismiss()
            app.router.toast(.verbatim(message), detail: note, systemImage: "rectangle.stack.badge.plus")
        }
    }
}

/// One draft: a tick to keep it, its kind, the question and answer (or options), and Edit.
private struct DraftCardView: View {
    @Binding var draft: MakeCardsView.Draft
    let isEditing: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                CLHaptics.select()
                draft.kept.toggle()
            } label: {
                ZStack {
                    Circle().strokeBorder(draft.kept ? CLColor.tangerine : CLColor.surface3, lineWidth: 2.5)
                    if draft.kept {
                        Circle().fill(CLColor.tangerine)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(CLColor.onFill)
                    }
                }
                .frame(width: 26, height: 26)
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .padding(.top, -9)
            .animation(CLMotion.pop, value: draft.kept)
            .accessibilityLabel(Text(draft.kept ? "Keep this card" : "Leave this card out"))
            .accessibilityValue(Text(draft.kept ? "Kept" : "Not kept"))
            .accessibilityAddTraits(draft.kept ? .isSelected : [])

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CLEyebrow(text: .verbatim(draft.card.kind.displayName))
                    Spacer()
                    if draft.card.kind != .diagram {
                        Button(isEditing ? "Done" : "Edit", action: onEdit)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.skyInk)
                            .buttonStyle(.plain)
                            .frame(minWidth: CLMetrics.minHitTarget, minHeight: CLMetrics.minHitTarget)
                            .contentShape(Rectangle())
                            .padding(.vertical, -8)
                            .accessibilityHint(Text(isEditing ? "Stops editing this card" : "Edit this card's words"))
                    }
                }
                if isEditing { editor } else { reading }
            }
        }
        .clCard(padding: 16)
        .opacity(draft.kept ? 1 : 0.6)
        .animation(CLMotion.snap, value: draft.kept)
    }

    @ViewBuilder private var reading: some View {
        Text(draft.card.prompt)
            .clFont(.headline)
            .foregroundStyle(CLColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        switch draft.card.kind {
        case .mcq:
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(draft.card.choices.enumerated()), id: \.offset) { _, choice in
                    Label {
                        Text(choice.text).clFont(.subheadline).foregroundStyle(choice.correct ? CLColor.ink : CLColor.ink2)
                    } icon: {
                        Image(systemName: choice.correct ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(choice.correct ? CLColor.mintInk : CLColor.ink4)
                    }
                    .accessibilityLabel(Text(choice.correct ? "\(choice.text), correct" : choice.text))
                }
            }
        case .cloze:
            Text((draft.card.cloze?.text ?? draft.card.answer)
                .replacingOccurrences(of: #"\{\{[^}]*\}\}"#, with: "____", options: .regularExpression))
                .clFont(.subheadline).foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text(draft.card.answer)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Question", text: $draft.card.prompt)
            if draft.card.kind == .mcq || draft.card.kind == .cloze {
                Text("You can change the options after adding, in the card's editor.")
                    .clFont(.footnote).foregroundStyle(CLColor.ink3)
            } else {
                field("Answer", text: $draft.card.answer)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink2)
            TextField(title, text: text, axis: .vertical)
                .clFont(.body)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
        }
    }
}
