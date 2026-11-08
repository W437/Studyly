import SwiftUI

/// Two questions easy to confuse, named for themselves ("Metaphase vs telophase"), side by side, and what tells them apart: Cap's card
/// "Show me". The sheet is the first moment Cloud AI may be asked (on the relay's `extras` meter; the card said "Uses Cloud AI"). If it may,
/// the button's spinner says Cap is writing until the lesson is ready, then it shows once; if not, the rules' version is there at once (a line
/// asking for the difference, no words of its own). Nothing is saved until "Try 2 questions" (an open pair with no misses, and its fix drill)
/// or "Don't bring this up again" (a dismissed one, so neither finder offers it again). Closing it saves nothing, and the card stays away for
/// its 7 days. A fitted sheet: as tall as what it says.
///
/// DEBUG: `CRAMLESS_ROUTE=lookAlike` opens it on the demo world's best pair; `CRAMLESS_LOOKALIKE=rules|cloud|writing` shows the rules'
/// lesson, the mock relay's or the wait that never ends.
struct LookAlikeView: View {
    let a: UUID
    let b: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var draft: LookAlikeDraft?
    @State private var lesson: ConfusionOut?
    @State private var origin: ItemOrigin = .rules

    var body: some View {
        TodayFittedSheet {
            VStack(alignment: .leading, spacing: 16) {
                if let draft {
                    Text(verbatim: draft.rules.name)
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 24)
                    columns(draft)
                    if lesson != nil { lessonCard }
                    buttons(draft)
                } else {
                    ContentUnavailableView("These questions are gone", systemImage: "questionmark.circle")
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 20)
        }
        .task {
            guard draft == nil, let made = app.lookAlikeDraft(a: a, b: b) else { return }
            draft = made
            await load(made)
        }
    }

    /// The lesson: at once when no model will be asked; otherwise when the model has answered (or given up).
    private func load(_ draft: LookAlikeDraft) async {
        #if DEBUG
        switch TestHarness.value("CRAMLESS_LOOKALIKE") {
        case "rules":
            show(draft.rules, origin: .rules)
            return
        case "writing":
            return
        default:
            break
        }
        #endif
        guard app.ai.route(.confusions).usesCloud else {
            show(draft.rules, origin: .rules)
            return
        }
        let answer = await app.lookAlikeLesson(draft)
        show(answer.lesson, origin: answer.origin)
    }

    private func show(_ written: ConfusionOut, origin: ItemOrigin) {
        withAnimation(CLMotion.settle) {
            self.origin = origin
            lesson = written
        }
    }

    // MARK: Parts

    @ViewBuilder private func columns(_ draft: LookAlikeDraft) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            column(draft.a)
            column(draft.b)
        }
    }

    private func column(_ side: LookAlikeSide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: side.term)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: side.clue)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let label = side.sourceLabel {
                CLSourceChip(label: label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// What Cap wrote, or the rules' line; while Cap writes there is no card, only the button's spinner.
    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lesson, origin == .cloud {
                Text(verbatim: lesson.lesson)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.blurReplace)
                Text("Written by Cap from your two questions")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
            } else {
                // The rules' lesson only repeats the two columns above; it is kept for the pair's page, where they aren't.
                Text("Say the difference in your own words, then try them.")
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(padding: 14, flat: true)
    }

    private func buttons(_ draft: LookAlikeDraft) -> some View {
        let writing = lesson == nil
        return VStack(spacing: 8) {
            // While Cap writes, the spinner sits in the button, which waits at full strength: a tap does nothing until the lesson is in.
            Button {
                guard let lesson else { return }
                CLHaptics.commit()
                app.tryLookAlike(draft, lesson: lesson, origin: origin)
            } label: {
                HStack(spacing: 10) {
                    if writing {
                        ProgressView()
                            .tint(CLColor.onFill)
                            .accessibilityHidden(true)
                    }
                    Text("Try \(lesson?.questions.count ?? draft.rules.questions.count) questions")
                }
            }
            .buttonStyle(.cl(.primary))
            .accessibilityValue(writing ? Text("Cap is writing the difference") : Text(verbatim: ""))
            Button("Don't bring this up again") {
                CLHaptics.tap()
                app.rejectLookAlike(draft)
                dismiss()
                app.router.toast("Cap won't bring it up again", systemImage: "checkmark.circle.fill", tone: .neutral)
            }
            .buttonStyle(.cl(.ghost, size: .medium))
        }
        .padding(.top, 4)
    }
}
