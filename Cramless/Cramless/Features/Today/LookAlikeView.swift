import SwiftUI

/// Two questions that look alike, side by side, and the one difference: Cap's card "Show me". The sheet is the first moment Cloud AI may
/// be asked (on the relay's `extras` meter; the card said "Under 1¢"). If it may, the sheet shows that Cap is writing until the lesson is
/// ready, then shows it once; if not, the rules' lesson is there at once. Nothing is saved until "Try 2 questions" (an open mix-up with no
/// misses, and its fix drill) or "Not a look-alike" (a dismissed one, so neither finder offers it again). Closing it saves nothing, and
/// the card stays away for its 7 days. A fitted sheet: as tall as what it says.
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("One difference")
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("They look alike. One thing tells them apart.")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)
                if let draft {
                    columns(draft)
                    lessonCard
                    buttons(draft)
                } else {
                    ContentUnavailableView("These questions are gone", systemImage: "questionmark.circle")
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

    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lesson {
                Text(verbatim: lesson.lesson)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.blurReplace)
                if origin == .cloud {
                    Text("Written by Cap from your two questions")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Cap is writing it")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                }
                .frame(minHeight: CLMetrics.minHitTarget)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(padding: 14, flat: true)
    }

    private func buttons(_ draft: LookAlikeDraft) -> some View {
        VStack(spacing: 8) {
            Button("Try \(lesson?.questions.count ?? draft.rules.questions.count) questions") {
                guard let lesson else { return }
                CLHaptics.commit()
                app.tryLookAlike(draft, lesson: lesson, origin: origin)
            }
            .buttonStyle(.cl(.primary))
            .disabled(lesson == nil)
            Button("Not a look-alike") {
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
