import SwiftUI

/// Paste text: the text first, its box focused, and its name under it (optional). "Make questions" runs the capture flow on it, the same
/// processing and review as a scanned page; the review asks which course it's for ("Adding to"), so this sheet doesn't.
///
/// DEBUG hook: `CRAMLESS_PASTE_TEXT=sample` fills in sample notes; `=long` about 21 pages of them, for the line on what a long reading takes.
struct PasteTextView: View {
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @State private var title = ""
    @State private var text = ""
    /// What this text will take of the free scans, when it is long (worked out a moment after the typing stops).
    @State private var allowance: LocalizedStringResource?
    @FocusState private var focused: Field?

    private enum Field { case title, text }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editor
                    TextField("Name (optional)", text: $title)
                        .clFont(.body)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($focused, equals: .title)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
                        .accessibilityLabel("Name, optional")
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .clScreenBackground()
            .navigationTitle("Paste text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { app.router.dismissSheet() }
                }
            }
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 8) {
                    if let allowance {
                        AllowanceLine(text: allowance)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: go) {
                        Text(canGo ? "Make questions" : "Add a few sentences first")
                    }
                    .buttonStyle(.cl(.primary))
                    .disabled(!canGo)
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 10)
            }
            .task(id: text) {
                // Only a text longer than a scan's pages can take more than one: a short one isn't paginated at each keystroke.
                guard words >= TextPaginator.wordsPerPage else {
                    allowance = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let pageWords = TextPaginator.pages(from: text).map { page in
                    page.lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
                }
                allowance = app.ai.readingAllowance(pageWords: pageWords)
            }
            .task {
                // The box takes the keyboard once the sheet is up (focus set while it slides in is dropped).
                try? await Task.sleep(for: .milliseconds(350))
                if text.isEmpty { focused = .text }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            #if DEBUG
            let debugText = TestHarness.once("CRAMLESS_PASTE_TEXT")
            if debugText == "sample" || debugText == "long" {
                title = "Cell division notes"
                text = DebugCapture.notes
                if debugText == "long" {
                    let notesWords = max(1, words)
                    text = Array(repeating: DebugCapture.notes, count: 21 * TextPaginator.wordsPerPage / notesWords + 1).joined(separator: "\n\n")
                }
            }
            #endif
        }
    }

    /// The text box, with the paste button and the word count along its foot.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused, equals: .text)
                    .frame(minHeight: 170)
                    .accessibilityLabel("Text")
                if text.isEmpty {
                    Text("Paste or type your notes here. A page or two works best.")
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink4)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.joined(separator: "\n")
                    Task { @MainActor in
                        text = text.isEmpty ? pasted : text + "\n" + pasted
                        CLHaptics.select()
                    }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                Spacer(minLength: 8)
                Text(countLine)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .contentTransition(.numericText())
            }
        }
        .padding(10)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
    }

    private var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    private var countLine: String { words == 0 ? "" : CLFormat.count(words, "word") }

    private var canGo: Bool { words >= 8 }

    private func go() {
        CLHaptics.tap()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        app.router.present(.captureFlow(CaptureRequest(input: .text(title: clean, body: text), courseID: courseID)))
    }
}
