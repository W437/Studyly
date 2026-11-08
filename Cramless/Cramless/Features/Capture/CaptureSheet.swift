import SwiftUI
import UniformTypeIdentifiers

/// "Add material": every way in, each with its coloured badge and a line about what it takes (`AddMaterialList`). It doesn't ask for a
/// course: it carries the one it was opened for (the tab bar's + passes the course on screen, `AppModel.courseOnScreen`), and the course is
/// asked once, where the questions are added ("Adding to" on the review, the import, the question editor).
///
/// DEBUG hooks: `CRAMLESS_CAPTURE_SHEET=large` opens it at the large detent; `scan`, `record`, `paste`, `import` or
/// `cards` presses that row after a moment (the sheet hands over to the scanner, the recorder or the next sheet).
struct CaptureSheet: View {
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @State private var detent: PresentationDetent = .height(600)
    /// The sheet fits its rows; past the screen (large text) it is a large sheet that scrolls.
    @State private var contentHeight: CGFloat = 600

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Add material")
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    CLIconButton(systemImage: "xmark", label: "Close") { app.router.dismissSheet() }
                }
                AddMaterialList(courseID: courseID)
                    .padding(.top, 12)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                let fitted = height + 12
                guard abs(fitted - contentHeight) > 1 else { return }
                let wasFitted = detent != .large
                contentHeight = fitted
                if wasFitted { detent = .height(fitted) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(CLColor.background.ignoresSafeArea())
        .presentationDetents([.height(contentHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
        .onAppear {
            #if DEBUG
            switch TestHarness.once("CRAMLESS_CAPTURE_SHEET") {
            case "large": detent = .large
            case let row?:
                Task {
                    try? await nap(1200)
                    switch row {
                    case "scan": app.router.present(.scanner(courseID: courseID, isOnboarding: false))
                    case "record": app.router.present(.record(courseID: courseID))
                    case "paste": app.router.present(.paste(courseID: courseID))
                    case "import": app.router.present(.importDeck(courseID: courseID))
                    case "cards": app.router.present(.newItem(courseID: courseID))
                    default: break
                    }
                }
            case nil: break
            }
            #endif
        }
    }
}

/// The ways to bring material in, the same rows on the + sheet and on an empty Library: scan, record, a PDF, an import, pasted text, and a
/// question written by hand. On the free plan one line under them says what the week's free AI allowance has left (`AllowanceCopy.week`;
/// `CRAMLESS_QUOTA` sets the counts in the harness).
struct AddMaterialList: View {
    /// The course the material is for, when there is one (the questions are added where the person says, later).
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @State private var importingPDF = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CLList {
                option("camera", .tangerine, "Scan pages", "Textbooks, handouts, your notes") {
                    app.router.present(.scanner(courseID: courseID, isOnboarding: false))
                }
                option("mic", .rose, "Record a lecture", "Transcribed on your iPhone") {
                    app.router.present(.record(courseID: courseID))
                }
                option("doc.richtext", .sky, "PDF", "Slides too, once saved as a PDF") {
                    importingPDF = true
                }
                option("rectangle.stack", .mint, "Import Quizlet or Anki", "Keep every set you have") {
                    app.router.present(.importDeck(courseID: courseID))
                }
                option("doc.on.clipboard", .neutral, "Paste text", "From anywhere") {
                    app.router.present(.paste(courseID: courseID))
                }
                option("square.and.pencil", .sun, "Write a question", "Flashcards, multiple choice and more") {
                    app.router.present(.newItem(courseID: courseID))
                }
            }

            if let week = AllowanceCopy.week(scans: app.ai.freeCloudUsesLeft(for: .generate),
                                             lectures: app.ai.freeCloudUsesLeft(for: .lecture)) {
                AllowanceLine(text: week)
                    .padding(.top, 12)
                    .padding(.horizontal, 4)
            }

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.roseInk)
                    .padding(.top, 12)
            }
        }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            pickedPDF(result)
        }
    }

    private func option(_ symbol: String, _ tint: CaptureTint, _ title: String, _ subtitle: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            CLHaptics.tap()
            action()
        } label: {
            CaptureOptionRow(systemImage: symbol, tint: tint, title: title, subtitle: subtitle)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(Text(subtitle))
    }

    /// The PDF is kept in the app at once (a file picked in Files can't be relied on later), then read.
    private func pickedPDF(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let kept = try ImportInbox.keep(url)
                app.router.present(.captureFlow(CaptureRequest(input: .pdf(kept), courseID: courseID)))
            } catch {
                problem = CaptureError.pdfUnreadable.errorDescription
            }
        case .failure:
            break
        }
    }
}
