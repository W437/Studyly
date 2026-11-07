import SwiftUI
import UniformTypeIdentifiers

/// "Add material": every way in, each with its coloured badge and a line about what it takes, and the course it goes
/// to (the current course unless the person picks another, or makes a new one here). On the free plan, the Scan, PDF and
/// Record rows say what the free AI allowance has left before the work starts, and the footer what is always free
/// (`AllowanceCopy`; `CRAMLESS_QUOTA` sets the counts in the harness).
///
/// DEBUG hooks: `CRAMLESS_CAPTURE_SHEET=large` opens it at the large detent; `scan`, `record`, `paste`, `import` or
/// `cards` presses that row after a moment (the sheet hands over to the scanner, the recorder or the next sheet).
struct CaptureSheet: View {
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @State private var selectedCourseID: UUID?
    @State private var importingPDF = false
    @State private var detent: PresentationDetent = .height(600)
    /// The sheet fits its rows; past the screen (large text) it is a large sheet that scrolls.
    @State private var contentHeight: CGFloat = 600
    @State private var problem: String?

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
                CaptureCoursePicker(courseID: $selectedCourseID) { course in
                    CaptureCourseLabel(course: course, prefix: "For")
                }
                .padding(.top, 6)

                let scans = AllowanceCopy.scans(left: app.ai.freeCloudUsesLeft(for: .generate))
                CLList {
                    option("camera", .tangerine, "Scan pages", "Textbooks, handouts, your notes", note: scans) {
                        go(.scanner(courseID: selectedCourseID, isOnboarding: false))
                    }
                    option("mic", .rose, "Record a lecture", "Transcribed on your iPhone",
                           note: AllowanceCopy.lectures(left: app.ai.freeCloudUsesLeft(for: .lecture))) {
                        go(.record(courseID: selectedCourseID))
                    }
                    option("doc.richtext", .sky, "PDF", "Slides too, once saved as a PDF", note: scans) {
                        importingPDF = true
                    }
                    option("rectangle.stack", .mint, "Import Quizlet or Anki", "Keep every set you have") {
                        app.router.present(.importDeck(courseID: selectedCourseID))
                    }
                    option("doc.on.clipboard", .neutral, "Paste text", "From anywhere") {
                        app.router.present(.paste(courseID: selectedCourseID))
                    }
                    option("square.and.pencil", .sun, "Make cards yourself", "Always free, no limits") {
                        app.router.present(.newItem(courseID: selectedCourseID))
                    }
                }
                .padding(.top, 16)

                if scans != nil {
                    Text(AllowanceCopy.alwaysFree)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
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
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            pickedPDF(result)
        }
        .onAppear {
            if selectedCourseID == nil { selectedCourseID = app.defaultCourseID(preferring: courseID) }
            #if DEBUG
            switch TestHarness.once("CRAMLESS_CAPTURE_SHEET") {
            case "large": detent = .large
            case let row?:
                Task {
                    try? await nap(1200)
                    switch row {
                    case "scan": go(.scanner(courseID: selectedCourseID, isOnboarding: false))
                    case "record": go(.record(courseID: selectedCourseID))
                    case "paste": app.router.present(.paste(courseID: selectedCourseID))
                    case "import": app.router.present(.importDeck(courseID: selectedCourseID))
                    case "cards": app.router.present(.newItem(courseID: selectedCourseID))
                    default: break
                    }
                }
            case nil: break
            }
            #endif
        }
    }

    private func option(_ symbol: String, _ tint: CaptureTint, _ title: String, _ subtitle: String,
                        note: LocalizedStringResource? = nil, action: @escaping () -> Void) -> some View {
        Button {
            CLHaptics.tap()
            action()
        } label: {
            CaptureOptionRow(systemImage: symbol, tint: tint, title: title, subtitle: subtitle, note: note)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(Text(subtitle))
    }

    private func go(_ cover: AppCover) {
        app.router.present(cover)
    }

    /// The PDF is kept in the app at once (a file picked in Files can't be relied on later), then read.
    private func pickedPDF(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let kept = try ImportInbox.keep(url)
                go(.captureFlow(CaptureRequest(input: .pdf(kept), courseID: selectedCourseID)))
            } catch {
                problem = CaptureError.pdfUnreadable.errorDescription
            }
        case .failure:
            break
        }
    }
}
