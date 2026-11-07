import SwiftUI
import UniformTypeIdentifiers

/// Import Quizlet or Anki: a deck file (.apkg, .csv, .txt) or a Quizlet export pasted in, previewed before anything
/// is added (how many cards, a few of them, what was left out, whether Anki's scheduling comes along), then added to
/// a course. A file opened from another app ("Open in Capling") waits in `pendingImportFile` and previews at once.
///
/// DEBUG hook: `CRAMLESS_IMPORT=quizlet` (a pasted Quizlet export), `csv` (a CSV file), `link` (a pasted Quizlet link).
struct ImportDeckView: View {
    let courseID: UUID?

    private enum Mode: Hashable { case file, paste }

    @Environment(AppModel.self) private var app
    @State private var mode: Mode = .file
    @State private var pasted = ""
    @State private var preview: ImportPreview?
    @State private var file: URL?
    @State private var problem: String?
    @State private var reading = false
    @State private var picking = false
    @State private var selectedCourseID: UUID?
    @State private var title = ""
    @State private var committed = false
    /// Changes with each new preview, to bring it into view.
    @State private var previewToken = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Import from", selection: $mode) {
                        Text("A file").tag(Mode.file)
                        Text("Pasted from Quizlet").tag(Mode.paste)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in
                        CLHaptics.select()
                        clearPreview()
                        if mode == .paste { schedulePastePreview() }
                    }

                    switch mode {
                    case .file: fileInput
                    case .paste: pasteInput
                    }

                    if reading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading the cards…").clFont(.footnote).foregroundStyle(CLColor.ink2)
                        }
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.roseInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CLColor.roseSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if let preview { previewCard(preview).id("preview") }
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: previewToken) { _, _ in
                Task {
                    try? await nap(250)
                    withAnimation(CLMotion.settle) { proxy.scrollTo("preview", anchor: .top) }
                }
            }
            }
            .clScreenBackground()
            .navigationTitle("Import cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { app.router.dismissSheet() }
                }
            }
            .safeAreaBar(edge: .bottom) { bottomBar }
        }
        .presentationDragIndicator(.visible)
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.deckTypes) { result in picked(result) }
        .onAppear(perform: appear)
        // The waiting file is done with either way: imported (its copy is in the source) or put aside.
        .onDisappear { app.clearPendingImport() }
        .task(id: pasted) {
            guard mode == .paste else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            previewPasted()
        }
    }

    static let deckTypes: [UTType] = [UTType(importedAs: "net.ankiweb.apkg"), UTType(filenameExtension: "colpkg"),
                                      .commaSeparatedText, .tabSeparatedText, .plainText].compactMap { $0 }

    // MARK: Inputs

    private var fileInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            CLList {
                Button {
                    CLHaptics.tap()
                    picking = true
                } label: {
                    CaptureOptionRow(systemImage: "doc.badge.plus", tint: .mint,
                                     title: file == nil ? "Choose a file" : "Choose another file",
                                     subtitle: file?.lastPathComponent ?? "An Anki deck (.apkg), or a .csv or .txt of cards")
                }
                .buttonStyle(.pressable)
            }
            Text("From Anki: File, Export, then Anki Deck Package with scheduling included, so your review history comes along.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pasteInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pasted)
                    .clFont(.subheadline)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Quizlet export")
                if pasted.isEmpty {
                    Text("Interphase\tThe longest part of the cell cycle\nProphase\tChromosomes condense…")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink4)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
            HStack {
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    Task { @MainActor in pasted = text }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                Spacer()
            }
            Text("From Quizlet: open the set, tap the three dots, Export, then Copy text. Quizlet links can't be read directly.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Preview

    private func previewCard(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CaptureBadge(systemImage: preview.format == .anki ? "square.stack.3d.up" : "rectangle.stack",
                             tint: preview.format == .anki ? .sky : .mint, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(preview.count)")
                        .clFont(.number(30))
                        .foregroundStyle(CLColor.ink)
                    Text(preview.count == 1 ? "card from \(preview.format.displayName)" : "cards from \(preview.format.displayName)")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            TextField("Name", text: $title)
                .clFont(.bodyEmphasis)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
                .accessibilityLabel("Name of the set")
            Text(preview.summary)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if preview.scheduledCount > 0 {
                fact("clock.arrow.circlepath", CLColor.mintInk,
                     "Review history kept for \(CLFormat.count(preview.scheduledCount, "card")), so nothing starts over")
            }
            if preview.suspendedCount > 0 {
                fact("pause.circle", CLColor.ink2, "\(CLFormat.count(preview.suspendedCount, "card")) stay paused, as in Anki")
            }
            ForEach(preview.warnings, id: \.self) { warning in
                fact("exclamationmark.triangle.fill", CLColor.sunInk, warning)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(preview.sampleRows.enumerated()), id: \.offset) { index, card in
                    if index > 0 { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.cloze.map { String(draftClozeText($0.text).characters) } ?? card.front)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.ink)
                            .lineLimit(3)
                        if !card.back.isEmpty {
                            Text(card.back)
                                .clFont(.subheadline)
                                .foregroundStyle(CLColor.ink2)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                if preview.count > preview.sampleRows.count {
                    Text("and \(preview.count - preview.sampleRows.count) more")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .clCard(padding: 16)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func fact(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if preview != nil {
                CaptureCoursePicker(courseID: $selectedCourseID) { course in
                    CaptureCourseLabel(course: course, prefix: "Adding to")
                }
            }
            Button(action: commit) {
                Text(preview.map { "Import \(CLFormat.count($0.count, "card"))" } ?? "Import")
            }
            .buttonStyle(.cl(.primary))
            .disabled(preview == nil || preview?.count == 0 || selectedCourseID == nil || committed)
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 10)
    }

    // MARK: Actions

    private func appear() {
        if selectedCourseID == nil { selectedCourseID = app.defaultCourseID(preferring: courseID) }
        #if DEBUG
        // A hook's input wins over a file left waiting by an earlier run that was stopped before it closed.
        if let hook = TestHarness.once("CRAMLESS_IMPORT") {
            app.clearPendingImport()
            switch hook {
            case "quizlet":
                mode = .paste
                pasted = DebugImport.quizlet
            case "link":
                mode = .paste
                pasted = "https://quizlet.com/512345678/unit-3-cell-division-flash-cards/"
            case "csv":
                if let url = try? DebugImport.csvFile() { file = url; Task { await previewFile(url) } }
            default: break
            }
            return
        }
        #endif
        if let waiting = app.pendingImportFile {
            file = waiting
            Task { await previewFile(waiting) }
        }
    }

    private func picked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            let kept = try ImportInbox.keep(url)
            file = kept
            Task { await previewFile(kept) }
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? CaptureError.unsupportedFile(url.pathExtension).errorDescription
        }
    }

    private func previewFile(_ url: URL) async {
        reading = true
        problem = nil
        defer { reading = false }
        do {
            let result = try await app.previewImport(of: url)
            show(result)
        } catch {
            preview = nil
            problem = (error as? LocalizedError)?.errorDescription ?? "Couldn't read the cards in this file."
        }
    }

    private func schedulePastePreview() {
        if !pasted.isEmpty { previewPasted() }
    }

    private func previewPasted() {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            clearPreview()
            return
        }
        do {
            show(try app.previewImport(text: text, format: nil, title: "Quizlet set"))
        } catch {
            preview = nil
            problem = (error as? LocalizedError)?.errorDescription ?? "Couldn't read cards from this text."
        }
    }

    private func show(_ result: ImportPreview) {
        problem = result.count == 0 ? "No cards were found in this." : nil
        withAnimation(CLMotion.settle) { preview = result }
        title = result.title
        previewToken += 1
    }

    private func clearPreview() {
        withAnimation(CLMotion.fade) { preview = nil }
        problem = nil
    }

    private func commit() {
        guard let preview, let course = app.course(selectedCourseID), !committed else { return }
        committed = true
        let outcome = app.commitImport(preview, to: course, title: title, file: file)
        app.clearPendingImport()
        CLHaptics.success()
        var message = "Added \(CLFormat.count(outcome.added, "card")) to \(course.name)"
        if outcome.duplicates > 0 { message += ". \(outcome.duplicates) were already there" }
        app.router.toast(.verbatim(message), detail: app.newQuestionsNote(added: outcome.added, in: course))
        app.router.dismissSheet()
    }
}

#if DEBUG
enum DebugImport {
    static let quizlet = """
    Interphase\tThe longest part of the cell cycle, when the cell grows and copies its DNA
    Prophase\tChromosomes condense and the nuclear envelope breaks down
    Metaphase\tChromosomes line up at the equator of the cell
    Anaphase\tSister chromatids are pulled to opposite poles
    Telophase\tNuclear envelopes re-form around each set of chromosomes
    Cytokinesis\tThe division of the cytoplasm into two daughter cells
    Centromere\tWhere the two sister chromatids are joined
    Spindle fibres\tProtein fibres that pull the chromatids apart
    """

    static func csvFile() throws -> URL {
        let csv = "Front,Back,Topic\nOsmosis,Water moving across a membrane from dilute to concentrated,Cell membrane\n"
            + "Diffusion,Particles spreading from high to low concentration,Cell membrane\n"
            + "Active transport,Moving particles against the gradient using energy,Cell membrane\n"
        let url = FileManager.default.temporaryDirectory.appending(path: "Unit 4 membranes.csv")
        try Data(csv.utf8).write(to: url)
        return try ImportInbox.keep(url)
    }
}
#endif
