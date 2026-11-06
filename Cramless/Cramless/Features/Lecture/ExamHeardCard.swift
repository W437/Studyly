import SwiftUI

/// "Cap heard an exam date": at the top of a lecture's notes when the lecturer said one, with the words as they were transcribed, so a misheard date is easy to catch. "Add the exam" runs one AI check
/// when it's allowed (it can only choose among the dates read, and it can only ask, not stop the student), then adds the exam on the whole course, with Undo. A date the plan has under another day offers
/// to move it. Harness: `CRAMLESS_EXAM_HEARD=new|known|moved|added` (`AppModel+Lecture`).
struct ExamHeardCard: View {
    let heard: AppModel.ExamHeard
    /// Adding deals with the date, and the card would go with it: the notes hold on to it while it says "Exam added" and offers Undo.
    var onAdded: () -> Void = {}
    var onUndone: () -> Void = {}

    @Environment(AppModel.self) private var app
    @State private var checking = false
    @State private var doubted = false
    @State private var added: (id: UUID, days: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let added {
                Label {
                    Text(verbatim: ExamHeardCopy.added(days: added.days))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(CLColor.mintInk)
                }
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                Button("Undo") {
                    CLHaptics.tap()
                    app.undoExamHeard(heard, examID: added.id)
                    withAnimation(CLMotion.settle) { self.added = nil }
                    onUndone()
                }
                .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                .frame(minHeight: CLMetrics.minHitTarget)
            } else {
                Label { Text(ExamHeardCopy.title) } icon: { Image(systemName: "calendar.badge.plus") }
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.tangerineInk)
                Text(verbatim: "“\(heard.mention.quote)”")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                decision
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        #if DEBUG
        .task {
            guard TestHarness.once("CRAMLESS_EXAM_HEARD") == "added" else { return }
            try? await nap(500)
            add(anyway: false)
        }
        #endif
    }

    private var style: Date.FormatStyle { LibraryFormat.dateStyle(app.calendar) }
    private var heardDay: String { heard.date.formatted(style.month(.abbreviated).day()) }

    @ViewBuilder
    private var decision: some View {
        switch heard.match {
        case .new:
            Text(verbatim: "\(heard.mention.word) · \(heard.date.formatted(style.weekday(.abbreviated).month(.abbreviated).day()))")
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.ink2)
            Text(ExamHeardCopy.wholeCourse)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            if doubted {
                Label { Text(ExamHeardCopy.doubt) } icon: { Image(systemName: "questionmark.circle") }
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CaptureChips {
                Button {
                    add(anyway: doubted)
                } label: {
                    if checking {
                        ProgressView().controlSize(.small).tint(CLColor.onFill)
                    } else {
                        Text(doubted ? ExamHeardCopy.addAnyway : ExamHeardCopy.add)
                    }
                }
                .buttonStyle(.cl(.primary, size: .medium, fullWidth: false))
                .disabled(checking)
                notNow
            }
            .padding(.top, 4)
        case .known:
            HStack(spacing: 8) {
                Label { Text(ExamHeardCopy.known) } icon: { Image(systemName: "checkmark.circle") }
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.mintInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("OK") {
                    CLHaptics.tap()
                    app.dismissExamHeard(heard)
                }
                .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                .frame(minHeight: CLMetrics.minHitTarget)
            }
        case .moved(_, let title, let current):
            Text(verbatim: ExamHeardCopy.moved(title: title, current: current.formatted(style.month(.abbreviated).day()), heard: heardDay))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            CaptureChips {
                Button {
                    CLHaptics.commit()
                    app.useHeardDate(heard)
                    app.router.toast("Exam moved to \(heardDay)")
                } label: {
                    Text(verbatim: ExamHeardCopy.use(heardDay))
                }
                .buttonStyle(.cl(.primary, size: .medium, fullWidth: false))
                notNow
            }
            .padding(.top, 4)
        }
    }

    private var notNow: some View {
        Button(ExamHeardCopy.notNow) {
            CLHaptics.tap()
            app.dismissExamHeard(heard)
        }
        .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
    }

    private func add(anyway: Bool) {
        CLHaptics.commit()
        checking = true
        Task {
            let check = anyway ? AppModel.ExamHeardCheck() : await app.checkExamHeard(heard)
            checking = false
            if check.doubted {
                withAnimation(CLMotion.settle) { doubted = true }
                return
            }
            guard let exam = app.addExam(from: heard, check: check) else { return }
            onAdded()
            CLFeel.play(.saved)
            withAnimation(CLMotion.settle) { added = (exam.id, app.calendar.dayDistance(from: app.now, to: exam.date)) }
        }
    }
}
