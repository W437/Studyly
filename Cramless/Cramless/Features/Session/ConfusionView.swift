import SwiftUI

/// Two things often confused, named for themselves ("Anaphase vs telophase"), under the course's name: how often and when last they were
/// missed (counted now, never from stored words), the difference with the two terms highlighted, the questions involved with the answer the
/// person last gave, and Fix it. The bar shows the name once the header has scrolled away.
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
                ContentUnavailableView("This is gone", systemImage: "questionmark.circle",
                                       description: Text("It may have been removed on another device."))
                    .clScreenBackground()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConfusionDetail: View {
    let confusion: Confusion
    let onDismissed: () -> Void

    @Environment(AppModel.self) private var app
    @State private var lessonShown = false
    /// The header has scrolled away: the bar names the pair.
    @State private var showsTitle = false

    var body: some View {
        let items = confusion.itemIDs.compactMap { app.item($0) }.filter { $0.deletedAt == nil }
        let fixCount = (confusion.fix?.itemIDs ?? []).compactMap { app.item($0) }.filter { $0.deletedAt == nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let lesson = confusion.fix?.lesson, !lesson.isEmpty {
                    CLSectionHeader(title: lessonTitle)
                    HighlightedText(text: lesson, marks: lessonMarks(lesson), revealed: lessonShown, style: .callout)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .clCard()
                }
                if !items.isEmpty {
                    CLSectionHeader(title: confusion.missCount == 0 ? "The questions" : confusion.itemIDs.count == 1 ? "The question you missed" : "The questions you mixed up")
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
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 96 } action: { _, past in
            showsTitle = past
        }
        .navigationTitle(showsTitle ? title : "")
        .clScreenBackground()
        .safeAreaBar(edge: .bottom) {
            Button(confusion.status == .fixed ? String(localized: "Practice it again") : SessionCopy.fixTitle(questions: confusion.itemIDs.count), action: fix)
                .buttonStyle(.cl(confusion.status == .fixed ? .soft : .primary))
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Don't bring this up again", systemImage: "hand.thumbsdown", role: .destructive) {
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
                    if let course = confusion.course { CLEyebrow(text: .verbatim(course.name)) }
                    Text(verbatim: title)
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            HStack(spacing: 8) {
                if confusion.status == .fixed {
                    CLPill(text: "Fixed", tone: .mint, systemImage: "checkmark")
                }
                Text(verbatim: missLine)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
            }
        }
        .clCard()
    }

    /// "Anaphase vs telophase"; one question with no name of its own: "A question you keep missing".
    private var title: String {
        confusion.itemIDs.count == 1 && confusion.name == ConfusionCandidate.unnamed ? String(localized: "A question you keep missing") : confusion.name
    }

    /// Two terms: "The difference"; otherwise what the lesson is, the right answers.
    private var lessonTitle: LocalizedStringResource {
        if confusion.name.contains(" vs ") { return "The difference" }
        return confusion.itemIDs.count == 1 ? "The right answer" : "The right answers"
    }

    /// "Missed 3 times · last on Sat 7 Nov", counted from the confusion as it is now.
    private var missLine: String {
        // An adopted look-alike: nothing has been missed yet.
        if confusion.missCount == 0 { return String(localized: "Not missed yet") }
        return String(localized: "Missed \(confusion.missCount) times") + " · "
            + String(localized: "last on \(ExamPresentation.dayLabel(confusion.lastSeenAt, calendar: app.calendar))")
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
        if questions == 1 {
            return fixQuestions > 0 ? String(localized: "The fix: a quick choice between two answers, then this question again.")
                : String(localized: "The fix: this question again, so it sticks.")
        }
        if fixQuestions > 0 {
            return "The fix: \(SessionCopy.questions(fixQuestions)) that teach the difference, then these again."
        }
        return "The fix: these \(SessionCopy.questions(questions)) again, back to back, so the difference sticks."
    }

    private func fix() {
        CLHaptics.commit()
        guard var request = app.prepareFix(confusion.id) else { return }
        request.lessonSeen = confusion.fix?.lesson.isEmpty == false && !app.fixWillBeWritten(confusion.id)
        app.router.present(.session(request))
    }
}
