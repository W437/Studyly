import SwiftUI

/// The last look on an exam's eve: the ideas the student is shakiest on, to read once and go to bed. No quiz and no score, and nothing is recorded. Each idea is a plain sentence when Cap
/// wrote one ahead of time (`AppModel.prepareLastLooks()`), else its question and its answer, so it reads the same with no connection; a chip opens the page or the lecture it came from.
///
/// "Good night" ends the evening: it closes this and whatever session it came from. The finale that closes an exam's eve belongs here too, when it comes: eve session → summary →
/// last look → Good night → the finale.
///
/// Opened from a card on the eve's summary, and from Today once tonight's session is done.
///
/// DEBUG: `CRAMLESS_ROUTE=lastLook`; `CRAMLESS_LASTLOOK=offline` shows it with nothing prepared (questions and answers), `=cloud` with the mock relay's sentences.
struct LastLookView: View {
    let examID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var look: LastLook?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if let look {
                    page(look)
                } else if loaded {
                    ContentUnavailableView("Nothing to look at tonight", systemImage: "moon.stars")
                } else {
                    Color.clear
                }
            }
            .clScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            guard !loaded else { return }
            #if DEBUG
            if TestHarness.once("CRAMLESS_LASTLOOK") == "cloud" { await app.debugPrepareLastLook(examID) }
            #endif
            look = app.lastLook(for: examID)
            loaded = true
        }
    }

    private func page(_ look: LastLook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(look)
                ForEach(look.ideas) { idea in
                    card(idea)
                }
                if look.isWritten {
                    Text(verbatim: LastLookCopy.written)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                Text(verbatim: LastLookCopy.closing)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 4)
                Button("Good night", action: goodNight)
                    .buttonStyle(.cl(.primary))
                    .padding(.top, 2)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ look: LastLook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: LastLookCopy.title)
                        .clFont(.brandTitle(30))
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: LastLookCopy.line(ideas: look.ideas.count, minutes: look.minutes))
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                CapView(.asleep, size: 72, interactive: false)
                    .accessibilityHidden(true)
            }
            Text(verbatim: LastLookCopy.subtitle(ideas: look.ideas.count))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func card(_ idea: LastLookIdea) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let topic = idea.topic {
                Text(verbatim: topic)
                    .clFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sentence = idea.sentence {
                Text(verbatim: sentence)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !idea.question.isEmpty {
                    Text(verbatim: idea.question)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: idea.answer)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ref = idea.ref { sourceLink(ref) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(padding: 14)
    }

    /// Opens the page, zoomed to the lines and circled, or the lecture at that moment, inside this sheet.
    private func sourceLink(_ ref: SourceRef) -> some View {
        let isLecture = ref.start != nil || app.source(ref.sourceID)?.kind == .lecture
        return NavigationLink {
            if isLecture {
                LectureNotesView(sourceID: ref.sourceID, focusTime: ref.start)
            } else {
                SourcePageView(sourceID: ref.sourceID, pageIndex: ref.pageIndex ?? 0, highlight: ref.anchorIDs)
            }
        } label: {
            CLSourceChip(label: ref.label, systemImage: isLecture ? "mic" : "book.pages")
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// The end of the evening: this, and the session it came from.
    private func goodNight() {
        CLHaptics.commit()
        app.router.dismissSheet()
        app.router.dismissCover()
    }
}

#if DEBUG
extension AppModel {
    /// `CRAMLESS_LASTLOOK=cloud`: the ideas prepared now, whatever the exam's date, with the mock relay's sentences.
    func debugPrepareLastLook(_ examID: UUID) async {
        guard let exam = examSnapshots(upcomingOnly: true).first(where: { $0.id == examID }) else { return }
        await prepareLastLooks(of: [exam])
    }
}
#endif
