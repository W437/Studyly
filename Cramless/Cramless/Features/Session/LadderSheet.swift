import SwiftUI

/// "Yes, harder": Cap writes the harder question, the student reads it and adds it or doesn't. Added, the easy one takes a rest, and Undo is
/// there for a moment. Nothing joins a session until "Add it".
///
/// DEBUG hooks: `CRAMLESS_LADDER=offer` shows the card on Today, from the real engine (`AppModel+NoticeHarness`); `CRAMLESS_NOTICE_TAP=<ms>`
/// presses its button. `CRAMLESS_ROUTE=ladder` opens this sheet on a question from the demo world, with `CRAMLESS_LADDER=writing|proposal|added`
/// holding that state (`writing` waits there; `added` adds the mock relay's question).
struct LadderSheet: View {
    let parentID: UUID

    private enum Phase: Equatable {
        case writing, proposal(UUID), added(UUID), failed(String)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .writing
    @State private var showsAnswer = false
    @State private var contentHeight: CGFloat = 320
    @State private var detent: PresentationDetent = .height(320)
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The harder question on screen, to add.
    private var proposed: UUID? {
        if case .proposal(let id) = phase, app.item(id)?.modelContext != nil { return id }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CLSpace.l) {
                switch phase {
                case .writing: writing
                case .proposal(let id): proposal(id)
                case .added(let id): added(id)
                case .failed(let message): failed(message)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 26)
            .padding(.bottom, 16)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                let fitted = height + 12
                guard abs(fitted - contentHeight) > 1 else { return }
                let wasFitted = detent != .large
                contentHeight = fitted
                if wasFitted { detent = .height(fitted) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .pinnedActionAtLargeText(when: proposed != nil) {
            if let id = proposed { addButton(id) }
        }
        .captureDebugCanvas(widthOnly: true)
        .background(CLColor.background.ignoresSafeArea())
        .presentationDetents([.height(contentHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
        .task { await write() }
    }

    private var writing: some View {
        HStack(spacing: 12) {
            CapView(.working, size: 60, interactive: false)
            Text("Cap is writing a harder one…")
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func proposal(_ id: UUID) -> some View {
        if let draft = app.item(id), draft.modelContext != nil {
            Text("Here's the harder one")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                Text(draft.kind.displayName)
                    .clFont(.eyebrow)
                    .foregroundStyle(CLColor.ink3)
                Text(verbatim: LadderCopy.shownPrompt(draft))
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if showsAnswer {
                    Text(verbatim: draft.answer)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    Button("Show the answer") {
                        CLHaptics.select()
                        withAnimation(CLMotion.fade) { showsAnswer = true }
                    }
                    .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                }
                if let ref = draft.sourceRef {
                    CLSourceChip(label: ref.label, systemImage: ref.start != nil ? "mic" : "book.pages")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clCard(padding: 16)
            if !typeSize.isAccessibilitySize { addButton(id) }
            Button("Not this one") {
                CLHaptics.tap()
                app.declineRung(id)
                dismiss()
            }
            .buttonStyle(.cl(.soft))
        }
    }

    private func addButton(_ id: UUID) -> some View {
        Button("Add it") {
            CLHaptics.success()
            if app.adoptRung(id) {
                withAnimation(CLMotion.fade) { phase = .added(id) }
            }
        }
        .buttonStyle(.cl(.primary))
    }

    @ViewBuilder
    private func added(_ id: UUID) -> some View {
        HStack(alignment: .center, spacing: 12) {
            CapView(.nice, size: 60, interactive: false)
            Text("Added. The easy one takes a rest.")
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        Button("Undo") {
            CLHaptics.tap()
            app.undoRung(id)
            withAnimation(CLMotion.fade) { phase = .proposal(id) }
        }
        .buttonStyle(.cl(.soft))
        Button("Done") { dismiss() }
            .buttonStyle(.cl(.primary))
    }

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            CapView(.answerShown, size: 60, interactive: false)
            Text(verbatim: message)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        Button("Done") { dismiss() }
            .buttonStyle(.cl(.primary))
    }

    private func write() async {
        guard phase == .writing else { return }
        #if DEBUG
        let hook = TestHarness.value("CRAMLESS_LADDER")
        if hook == "writing" { return }
        #endif
        let outcome = await app.writeRung(for: parentID)
        switch outcome {
        case .proposal(let id):
            #if DEBUG
            if hook == "added", app.adoptRung(id) {
                phase = .added(id)
                return
            }
            #endif
            withAnimation(CLMotion.fade) { phase = .proposal(id) }
            AccessibilityNotification.Announcement(String(localized: "Here's the harder one")).post()
        case .failed(let message):
            withAnimation(CLMotion.fade) { phase = .failed(message) }
            CLHaptics.tap()
        }
    }
}

/// The words of a harder question's offer and its sheet.
enum LadderCopy {
    static var couldNotWrite: String { String(localized: "Cap couldn't write a harder one from these lines.") }
    static var needsConnection: String { String(localized: "Cap needs a connection for this. It can wait.") }

    /// "Limiting reagents is too easy now".
    static func noticeTitle(topic: String?) -> String {
        guard let topic, !topic.isEmpty else { return String(localized: "This one is too easy now") }
        return String(localized: "\(topic) is too easy now")
    }

    /// "Next time, the same idea in a real problem?".
    static func noticeLine(next: ItemKind) -> String {
        switch next {
        case .cloze: String(localized: "Next time, the same idea as a fill-in?")
        case .recall: String(localized: "Next time, the same idea in your own words?")
        default: String(localized: "Next time, the same idea in a real problem?")
        }
    }

    static var noticeAction: String { String(localized: "Yes, harder") }

    /// A fill-in's question is its sentence, with the blank showing.
    @MainActor
    static func shownPrompt(_ item: StudyItem) -> String {
        if item.kind == .cloze, let cloze = item.cloze { return LibraryFormat.clozeDisplay(cloze.text) }
        return item.prompt
    }
}
