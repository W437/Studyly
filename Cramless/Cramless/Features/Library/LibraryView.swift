import SwiftUI

/// The Library tab: every course with its next exam, that exam's readiness (or "Add a date") and counts; search across
/// questions, sources and lectures; and the ways to bring material in. With no courses yet, Cap invites a sample page.
///
/// Harness: `CRAMLESS_ROUTE=library` (Spanish II has no exam); `CRAMLESS_SCENARIO=past` first moves the soonest exam three days back,
/// so its course has only a past exam.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var searching = false
    @State private var entries: [LibrarySearch.Entry] = []
    @State private var courseToDelete: LibraryCourseModel?

    var body: some View {
        let _ = app.revision
        let courses = app.courses.map { LibraryCourseModel(course: $0, app: app) }
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !query.clTrimmed.isEmpty {
                    LibrarySearchResults(query: query, results: LibrarySearch.search(query, in: entries))
                } else if courses.isEmpty {
                    LibraryEmptyState()
                        .padding(.top, 8)
                    BringYourStuff()
                } else {
                    CLSectionHeader(title: "Courses", actionTitle: "New") { app.router.present(.newCourse) }
                    LazyVStack(spacing: 14) {
                        ForEach(courses) { course in
                            NavigationLink(value: Route.course(course.id)) {
                                LibraryCourseCard(model: course)
                            }
                            .buttonStyle(.pressable)
                            .addDateOverlay(courseName: course.name) { app.router.present(.newExam(courseID: course.id)) }
                            .contextMenu { menu(for: course) }
                        }
                    }
                    Text("The ring is how ready you are for each course's next exam.")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.horizontal, 4)
                    BringYourStuff()
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 36)
            .frame(maxWidth: CLMetrics.readableWidth * 1.3)
            .frame(maxWidth: .infinity)
            .animation(CLMotion.settle, value: courses.map(\.id))
        }
        .harnessScroll(proxy)
        }
        .scrollDismissesKeyboard(.immediately)
        .clScreenBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, isPresented: $searching, prompt: Text("Search questions, sources and lectures"))
        #if DEBUG
        .task {
            app.applyHarnessScenarioOnce(examID: app.upcomingExams().first?.id)
            // Harness: `CRAMLESS_SEARCH=<words>` opens the Library already searching.
            if let words = TestHarness.once("CRAMLESS_SEARCH") {
                searching = true
                query = words
            }
        }
        #endif
        .task(id: query.clTrimmed.isEmpty ? -1 : app.revision) {
            // Built once per change of the store while searching; each keystroke only filters.
            guard !query.clTrimmed.isEmpty else { return }
            entries = app.librarySearchEntries()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    searching = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New course", systemImage: "folder.badge.plus") { app.router.present(.newCourse) }
                    Button("Make a card", systemImage: "square.and.pencil") { app.router.present(.newItem(courseID: nil)) }
                    Button("Import a deck", systemImage: "rectangle.stack") { app.router.present(.importDeck(courseID: nil)) }
                    Button("Add material", systemImage: "doc.viewfinder") { app.router.present(.capture(courseID: nil)) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .alert(courseToDelete.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(
            get: { courseToDelete != nil }, set: { if !$0 { courseToDelete = nil } })) {
            Button("Delete course", role: .destructive) {
                if let id = courseToDelete?.id { withAnimation(CLMotion.settle) { app.deleteCourse(id) } }
                courseToDelete = nil
            }
            Button("Cancel", role: .cancel) { courseToDelete = nil }
        } message: {
            if let course = courseToDelete {
                Text("Its \(LibraryFormat.courseCounts(sources: course.sources, questions: course.questions)) and its exams go too.")
            }
        }
    }

    @ViewBuilder
    private func menu(for course: LibraryCourseModel) -> some View {
        Button("Edit course", systemImage: "pencil") { app.router.present(.editCourse(course.id)) }
        Button("New exam", systemImage: "calendar.badge.plus") { app.router.present(.newExam(courseID: course.id)) }
        Button("Add material", systemImage: "doc.viewfinder") { app.router.present(.capture(courseID: course.id)) }
        Divider()
        Button("Delete course", systemImage: "trash", role: .destructive) { courseToDelete = course }
    }
}

/// The ways to bring material in: imports, uploads, and cards the person writes.
private struct BringYourStuff: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CLSectionHeader(title: "Bring your stuff")
            .id("bring")
        CLList {
            Button { app.router.present(.importDeck(courseID: nil)) } label: {
                CLRow(icon: "rectangle.stack", tint: .mint, title: "Import from Quizlet",
                      subtitle: "Paste the set you exported")
            }
            Button { app.router.present(.importDeck(courseID: nil)) } label: {
                CLRow(icon: "square.and.arrow.down", tint: .sky, title: "Import from Anki",
                      subtitle: ".apkg decks, scheduling kept")
            }
            Button { app.router.present(.capture(courseID: nil)) } label: {
                CLRow(icon: "doc.richtext", tint: .tangerine, title: "Upload PDFs or slides",
                      subtitle: "Up to 300 pages at once")
            }
            Button { app.router.present(.newItem(courseID: nil)) } label: {
                CLRow(icon: "square.and.pencil", tint: .sun, title: "Make cards yourself",
                      subtitle: "Always free, no limits")
            }
        }
        .buttonStyle(LibraryRowButtonStyle())
    }
}

/// No courses yet: Cap and a sample page to try.
private struct LibraryEmptyState: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 14) {
            CapView(pose: .wave, size: 150, idle: .breathe)
            Text("Bring your first page")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
            Text("Snap a page, add slides or import a deck. Capling turns it into questions, each one linked to where it came from.")
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                Button {
                    app.router.present(.captureFlow(CaptureRequest(input: .sample, courseID: nil)))
                } label: {
                    Label("Try a sample page", systemImage: "wand.and.sparkles")
                }
                .buttonStyle(.cl(.primary))
                Button("New course") { app.router.present(.newCourse) }
                    .buttonStyle(.cl(.soft, size: .medium))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .clCard(padding: 22)
    }
}

/// Search hits by kind. Questions open their editor; sources and lectures open on the Library's stack.
private struct LibrarySearchResults: View {
    let query: String
    let results: LibrarySearch.Results
    @Environment(AppModel.self) private var app

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query.clTrimmed)
                .padding(.top, 48)
        } else {
            Text(CLFormat.count(results.total, "result"))
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
                .padding(.top, 14)
                .padding(.horizontal, 2)
                .accessibilityAddTraits(.updatesFrequently)
            section("Questions", results.questions, more: results.moreQuestions)
            section("Sources", results.sources, more: results.moreSources)
            section("Lectures", results.lectures, more: results.moreLectures)
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringResource, _ hits: [LibrarySearch.Hit], more: Int) -> some View {
        if !hits.isEmpty {
            CLSectionHeader(title: title)
            CLList {
                ForEach(hits) { hit in
                    row(hit)
                }
            }
            if more > 0 {
                Text("And \(more) more. Add a word to narrow it down.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func row(_ hit: LibrarySearch.Hit) -> some View {
        let label = HitRow(hit: hit)
        switch hit.entry.kind {
        case .question:
            Button { app.router.present(.editItem(hit.entry.id)) } label: { label }
                .buttonStyle(LibraryRowButtonStyle())
        case .source:
            NavigationLink(value: Route.source(hit.entry.id)) { label }
                .buttonStyle(LibraryRowButtonStyle())
        case .lecture:
            NavigationLink(value: Route.lectureNotes(hit.entry.id)) { label }
                .buttonStyle(LibraryRowButtonStyle())
        }
    }
}

private struct HitRow: View {
    let hit: LibrarySearch.Hit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: hit.entry.systemImage, tint: hit.entry.color, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(searchMarkedText(hit.entry.title, match: hit.titleMatch))
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(3)
                if let snippet = hit.snippet {
                    Text(searchMarkedText(snippet, match: hit.snippetMatch))
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .lineLimit(3)
                }
                Text("\(hit.entry.courseName) · \(hit.entry.detail)")
                    .clFont(.caption)
                    .foregroundStyle(CLColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A list row that greys a little while pressed, like a native cell.
struct LibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? CLColor.surface2 : Color.clear)
            .contentShape(Rectangle())
    }
}
