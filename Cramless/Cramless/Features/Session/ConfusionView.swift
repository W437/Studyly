import SwiftUI

/// A named mix-up ("Anaphase vs telophase"): what gets mixed up and why, the 2-minute lesson with the confused
/// terms highlighted, the questions involved with the answer the person last gave, and Fix it now.
struct ConfusionView: View {
    let confusionID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = app.revision
        Group {
            if let confusion = app.confusion(confusionID), confusion.deletedAt == nil, confusion.modelContext != nil {
                ConfusionDetail(confusion: confusion, onDismissed: { dismiss() })
            } else {
                ContentUnavailableView("This mix-up is gone", systemImage: "questionmark.circle",
                                       description: Text("It may have been removed on another device."))
                    .clScreenBackground()
            }
        }
        .navigationTitle("Mix-up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConfusionDetail: View {
    let confusion: Confusion
    let onDismissed: () -> Void

    @Environment(AppModel.self) private var app
    @State private var lessonShown = false

    var body: some View {
        let items = confusion.itemIDs.compactMap { app.item($0) }.filter { $0.deletedAt == nil }
        let fixCount = (confusion.fix?.itemIDs ?? []).compactMap { app.item($0) }.filter { $0.deletedAt == nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let lesson = confusion.fix?.lesson, !lesson.isEmpty {
                    CLSectionHeader(title: confusion.itemIDs.count == 1 ? "A quick look" : "The 2-minute lesson")
                    HighlightedText(text: lesson, marks: lessonMarks(lesson), revealed: lessonShown, style: .callout)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .clCard()
                }
                if !items.isEmpty {
                    CLSectionHeader(title: confusion.missCount == 0 ? "The questions that look alike" : "The questions you mixed up")
                    CLList {
                        ForEach(items, id: \.id) { item in
                            questionRow(item)
                        }
                    }
                }
                Text(drillLine(questions: items.count, fixQuestions: fixCount))
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .clScreenBackground()
        .safeAreaBar(edge: .bottom) {
            Button(confusion.status == .fixed ? String(localized: "Practice it again") : SessionCopy.fixNowTitle(questions: confusion.itemIDs.count), action: fix)
                .buttonStyle(.cl(confusion.status == .fixed ? .soft : .primary))
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Not a mix-up", systemImage: "hand.thumbsdown", role: .destructive) {
                        app.dismissConfusion(confusion.id)
                        app.router.toast("Cap won't bring it up again", systemImage: "checkmark.circle.fill", tone: .neutral)
                        onDismissed()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .task {
            try? await nap(350)
            lessonShown = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CapFace(size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    CLEyebrow(text: confusion.course.map { "Mix-up · \($0.name)" } ?? "Mix-up")
                    Text(confusion.name)
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Text(confusion.explanation)
                .clFont(.body)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if confusion.status == .fixed {
                    CLPill(text: "Fixed", tone: .mint, systemImage: "checkmark")
                }
                Text(missLine)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
            }
        }
        .clCard()
    }

    private var missLine: String {
        // An adopted look-alike: nothing has been missed yet.
        if confusion.missCount == 0 { return String(localized: "Spotted before any mix-up") }
        let last = confusion.lastSeenAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let times = confusion.missCount == 1 ? "once" : "\(confusion.missCount) times"
        return "Missed \(times) · last on \(last)"
    }

    private func questionRow(_ item: StudyItem) -> some View {
        let answer = item.kind == .mcq ? (item.choices.first(where: \.correct)?.text ?? item.answer) : item.answer
        let given = app.lastWrongAnswer(itemID: item.id)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.prompt)
                .clFont(.bodyEmphasis)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Label { Text(answer) } icon: { Image(systemName: "checkmark.circle") }
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.mintInk)
            if let given {
                Label { Text("You said: \(given)") } icon: { Image(systemName: "xmark.circle") }
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.roseInk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The confused terms, highlighted where the lesson first names each.
    private func lessonMarks(_ lesson: String) -> [HighlightMark] {
        confusion.name.components(separatedBy: " vs ").compactMap { term in
            HighlightMark.locate(term, in: lesson).map { HighlightMark(range: $0, tone: .key) }
        }
    }

    private func drillLine(questions: Int, fixQuestions: Int) -> String {
        if fixQuestions > 0 {
            return "The fix: \(SessionCopy.questions(fixQuestions)) that teach the difference, then these again."
        }
        return "The fix: these \(SessionCopy.questions(questions)) again, back to back, so the difference sticks."
    }

    private func fix() {
        CLHaptics.commit()
        if let request = app.prepareFix(confusion.id) { app.router.present(.session(request)) }
    }
}
