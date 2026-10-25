import SwiftUI

/// Paste text: a title, the course, and the text itself. "Make questions" runs the capture flow on it, the same
/// processing and review as a scanned page.
///
/// DEBUG hook: `CRAMLESS_PASTE_TEXT=sample` fills in sample notes.
struct PasteTextView: View {
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @State private var title = ""
    @State private var text = ""
    @State private var selectedCourseID: UUID?
    @FocusState private var focused: Field?

    private enum Field { case title, text }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Title, like Chapter 3 notes", text: $title)
                        .clFont(.headline)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .focused($focused, equals: .title)
                        .onSubmit { focused = .text }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
                        .accessibilityLabel("Title")
                    CaptureCoursePicker(courseID: $selectedCourseID) { course in
                        CaptureCourseLabel(course: course, prefix: "For")
                    }
                    editor
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
                    Label("Questions come from this text only, and each one links back to the sentence it came from.",
                          systemImage: "link")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
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
                Button(action: go) {
                    Text(canGo ? "Make questions" : "Add a few sentences first")
                }
                .buttonStyle(.cl(.primary))
                .disabled(!canGo)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 10)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if selectedCourseID == nil { selectedCourseID = app.defaultCourseID(preferring: courseID) }
            #if DEBUG
            if TestHarness.once("CRAMLESS_PASTE_TEXT") == "sample" {
                title = "Cell division notes"
                text = DebugCapture.notes
            }
            #endif
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .scrollContentBackground(.hidden)
                .focused($focused, equals: .text)
                .frame(minHeight: 260)
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
        .padding(10)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.option, style: .continuous))
    }

    private var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    private var countLine: String { words == 0 ? "" : CLFormat.count(words, "word") }

    private var canGo: Bool { words >= 8 }

    private func go() {
        CLHaptics.tap()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        app.router.present(.captureFlow(CaptureRequest(input: .text(title: clean, body: text), courseID: selectedCourseID)))
    }
}
