import SwiftUI

/// One source: its pages (thumbnails decoded at the size they're drawn; typed and PDF-text pages show their text), the questions made
/// from it, and Delete. Its title is the bar's large title, so it is said once and moves into the bar as the page scrolls. A source of one
/// page opens straight on that page (`SourcePageView` with `asSource`), with the source's notes and menu, instead of a thumbnail that
/// opens a second screen with the same questions.
struct SourceView: View {
    let sourceID: UUID

    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        if let source = app.source(sourceID), source.deletedAt == nil {
            Group {
                if source.kind != .lecture, source.pages.count == 1, let page = source.pages.first {
                    SourcePageView(sourceID: sourceID, pageIndex: page.pageIndex, highlight: [], asSource: true)
                } else {
                    content(source)
                }
            }
            .task(id: sourceID) { app.noteOpened(sourceID: sourceID) }
        } else {
            ContentUnavailableView("This source is gone", systemImage: "doc.questionmark",
                                   description: Text("It was deleted on this or another device."))
                .clScreenBackground()
        }
    }

    private func content(_ source: Source) -> some View {
        let course = source.course
        let tint = course?.color ?? .sky
        let pages = source.sortedPages
        let imagePages = pages.filter { $0.imageFileName != nil }
        let textPages = pages.filter { $0.imageFileName == nil && !$0.text.clTrimmed.isEmpty }
        let all = app.questions(from: source)
        let questions = all.filter { $0.status == .active || $0.status == .suspended }
        let topicNames = Dictionary(uniqueKeysWithValues: (course?.liveTopics ?? []).map { ($0.id, $0.name) })

        return ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(source, course: course, questions: questions.count)

                if source.kind == .lecture {
                    NavigationLink(value: Route.lectureNotes(source.id)) {
                        Label("Open the lecture notes", systemImage: "text.badge.star")
                    }
                    .buttonStyle(.cl(.dark, size: .medium))
                    .padding(.top, 16)
                }

                SourceNotes(source: source)

                if !imagePages.isEmpty {
                    CLSectionHeader(title: imagePages.count == 1 ? "Page" : "\(imagePages.count) pages")
                    PageGrid(pages: imagePages.map(PageThumb.init), sourceID: source.id)
                }

                if !textPages.isEmpty {
                    CLSectionHeader(title: imagePages.isEmpty ? (textPages.count == 1 ? "Text" : "\(textPages.count) pages of text") : "Pages of text")
                    VStack(spacing: 12) {
                        ForEach(textPages) { page in
                            NavigationLink(value: Route.sourcePage(sourceID: source.id, pageIndex: page.pageIndex, highlight: [])) {
                                TextPagePreview(label: page.label, lines: page.lines.map(\.text))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                if pages.isEmpty, source.kind != .lecture {
                    ImportedNote(kind: source.kind, hasFile: source.fileName != nil)
                        .padding(.top, 16)
                }

                // The count is in the line under the title.
                CLSectionHeader(title: "Questions")
                    .id("questions")
                if questions.isEmpty {
                    Text(all.contains { $0.status == .draft && $0.rungOf == nil } ? "Its questions are waiting for your review." : "No questions from this source yet.")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clCard(padding: 16)
                } else {
                    CLList {
                        ForEach(questions) { item in
                            Button { app.router.present(.editItem(item.id)) } label: {
                                LibraryItemRow(kind: item.kind,
                                               prompt: item.kind == .cloze ? (item.cloze.map { LibraryFormat.clozeDisplay($0.text) } ?? item.prompt) : item.prompt,
                                               detail: [item.topicID.flatMap { topicNames[$0] }, item.sourceRef?.label].compactMap { $0 }.joined(separator: " · "),
                                               tint: tint, suspended: item.status == .suspended)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(LibraryRowButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 36)
        }
        .harnessScroll(proxy)
        }
        .clScreenBackground()
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.large)
        .sourceMenu(source)
    }

    /// The badge, what's in it and where it was added; the title is the bar's.
    private func header(_ source: Source, course: Course?, questions: Int) -> some View {
        ReflowStack(verticalAlignment: .center, spacing: 14) {
            CLIconBadge(systemImage: source.kind.systemImage, tint: course?.color ?? .sky, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(LibraryFormat.sourceMeta(kind: source.kind, pages: source.pages.count, duration: source.duration,
                                              questions: questions))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceAddedLine(source, course: course, calendar: app.calendar))
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }
}

/// "Added 18 Oct to Bio 101".
@MainActor
func sourceAddedLine(_ source: Source, course: Course?, calendar: Calendar) -> String {
    let added = "Added \(LibraryFormat.shortDate(source.createdAt, calendar: calendar))"
    return course.map { "\(added) to \($0.name)" } ?? added
}

/// What a source says above its questions, on its own page or a one-page source's page: drafts waiting for review, formulas a PDF's text
/// lost, and how much of it the questions cover (with a way to write more).
struct SourceNotes: View {
    let source: Source

    @Environment(AppModel.self) private var app

    var body: some View {
        let drafts = app.questions(from: source).filter { $0.status == .draft && $0.rungOf == nil }
        VStack(alignment: .leading, spacing: 0) {
            if !drafts.isEmpty {
                DraftsBanner(count: drafts.count) { app.router.present(.reviewDraft(sourceID: source.id)) }
                    .padding(.top, 16)
            }

            // A PDF whose text layer lost its typeset formulas says so (the capture flow offers to read the pages again).
            if !source.pagesWithMissingFormulas.isEmpty {
                CaptureOriginNote(systemImage: "function", text: Source.missingFormulasNote, tone: .sky)
                    .padding(.top, 16)
            }

            if let coverage = app.coverage(of: source) {
                let shown = Double(Int((coverage.share * 100).rounded())) / 100
                let canAdd = coverage.uncoveredWords > 0 && shown < ExamPresentation.wellCovered
                CoverageNoteCard(sentence: LibraryFormat.coverageLine(share: coverage.share, kind: source.kind),
                                 isThin: shown < ExamPresentation.thinCoverage, offersMore: canAdd, centered: false) {
                    // The part to write from is decided now, from what is left and what the last runs already used.
                    if let request = app.restRequest(for: source) { app.router.present(.captureFlow(request)) }
                }
                .padding(.top, 16)
            }
        }
    }
}

extension View {
    /// A source's menu (open its course, delete it) and the question that deleting asks.
    func sourceMenu(_ source: Source) -> some View {
        modifier(SourceMenu(source: source))
    }
}

private struct SourceMenu: ViewModifier {
    let source: Source

    @Environment(AppModel.self) private var app
    @State private var confirmDelete = false

    func body(content: Content) -> some View {
        let course = source.course
        let all = source.modelContext == nil ? [] : app.questions(from: source)
        let questions = all.filter { $0.status == .active || $0.status == .suspended }.count
        let drafts = all.filter { $0.status == .draft && $0.rungOf == nil }.count
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let course {
                            NavigationLink(value: Route.course(course.id)) { Label("Open \(course.name)", systemImage: "books.vertical") }
                        }
                        Divider()
                        Button("Delete source", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
            .confirmationDialog("Delete \(source.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if questions == 0 && drafts == 0 {
                    Button("Delete source", role: .destructive) { delete(keepQuestions: false) }
                } else {
                    Button("Delete it and its \(CLFormat.count(questions + drafts, "question"))", role: .destructive) {
                        delete(keepQuestions: false)
                    }
                    Button("Delete it, keep the questions") { delete(keepQuestions: true) }
                }
            } message: {
                Text("Its pages are removed from this iPhone. Kept questions lose their link to the page.")
            }
    }

    private func delete(keepQuestions: Bool) {
        let id = source.id
        app.router.pop()
        app.deleteSource(id, keepQuestions: keepQuestions)
    }
}

// MARK: - Pieces

/// A page's thumbnail values (read once; the grid never touches the model while scrolling).
struct PageThumb: Identifiable, Equatable {
    var index: Int
    var label: String
    var fileName: String?
    var aspect: CGFloat
    var id: Int { index }

    init(_ page: SourcePage) {
        index = page.pageIndex
        label = page.label
        fileName = page.imageFileName
        aspect = page.width > 0 && page.height > 0 ? page.width / page.height : 2.0 / 3.0
    }
}

/// Page thumbnails, three across, each decoded at the size it's drawn (`PageImageView`).
private struct PageGrid: View {
    let pages: [PageThumb]
    let sourceID: UUID
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 3)
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(pages) { page in
                NavigationLink(value: Route.sourcePage(sourceID: sourceID, pageIndex: page.index, highlight: [])) {
                    VStack(spacing: 8) {
                        PageImageView(fileName: page.fileName, aspect: page.aspect)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(CLColor.hairline, lineWidth: 1))
                            .shadow(color: CLColor.night.opacity(0.10), radius: 8, y: 4)
                        Text("p. \(page.label)")
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Page \(page.label)"))
                .accessibilityHint(Text("Opens the page"))
            }
        }
    }
}

/// The start of a typed or PDF-text page, as a card that opens the page.
private struct TextPagePreview: View {
    let label: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("p. \(label)").clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink3)
                Spacer()
                CLChevron()
            }
            if let first = lines.first {
                Text(first).clFont(.headline).foregroundStyle(CLColor.ink)
            }
            Text(lines.dropFirst().prefix(4).joined(separator: " "))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .clCard(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the page"))
    }
}

/// "12 questions are waiting for your review."
private struct DraftsBanner: View {
    let count: Int
    var review: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CapFace(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(CLFormat.count(count, "question")) to review").clFont(.headline).foregroundStyle(CLColor.ink)
                Text("They join your sessions once you approve them.").clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Review", action: review)
                .buttonStyle(.cl(.dark, size: .small, fullWidth: false))
                .frame(minHeight: CLMetrics.minHitTarget)
        }
        .clCard(padding: 14)
    }
}

/// A deck import or other source without pages.
private struct ImportedNote: View {
    let kind: SourceKind
    let hasFile: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: "info", tint: .sun, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).clFont(.headline).foregroundStyle(CLColor.ink)
                Text(hasFile ? "The original file is kept on this iPhone." : "Its cards became the questions below.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard(padding: 14, flat: true)
    }

    private var title: String {
        switch kind {
        case .quizlet: "Imported from Quizlet"
        case .anki: "Imported from Anki"
        case .csv: "Imported from a spreadsheet"
        case .chat: "Made from a chat with Cap"
        default: "No pages kept"
        }
    }
}
