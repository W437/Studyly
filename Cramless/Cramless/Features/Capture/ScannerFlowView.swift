import PhotosUI
import SwiftUI

/// The scanner: VisionKit's document camera where this iPhone supports it (it finds the page's edges, captures,
/// flattens and deskews, as many pages as the person wants). In the Simulator and on devices without it, a designed
/// fallback says so plainly and offers photos of pages, or the sample page. Either way the pages go on to the capture
/// flow.
///
/// DEBUG hooks (with `CRAMLESS_ROUTE=scanner`): `CRAMLESS_FIRSTSET=choose|processing|review` shows onboarding's
/// first-set step here instead, at that stage, since onboarding itself wires it in later; `CRAMLESS_SCANNER_SAMPLE=1`
/// presses "Use our sample page" after a moment (the scanner hands over to the capture flow).
struct ScannerFlowView: View {
    let courseID: UUID?
    let isOnboarding: Bool

    @Environment(AppModel.self) private var app
    @State private var useFallback = !ScannerSupport.canScan
    @State private var failure: String?
    @State private var picked: [PhotosPickerItem] = []
    @State private var preparing = false
    #if DEBUG
    @State private var firstSetHook = TestHarness.value("CRAMLESS_FIRSTSET")
    #endif

    var body: some View {
        #if DEBUG
        if let stage = firstSetHook {
            NavigationStack {
                OnboardingFirstSetStep(onDone: { _ in app.router.dismissCover() })
                    .environment(\.firstSetDebugStage, stage)
            }
            .captureDebugCanvas()
        } else {
            content.captureDebugCanvas()
        }
        #else
        content
        #endif
    }

    @ViewBuilder private var content: some View {
        if useFallback {
            fallback
        } else {
            DocumentScannerView { outcome in finish(outcome) }
                .ignoresSafeArea()
        }
    }

    private func finish(_ outcome: DocumentScannerView.Outcome) {
        switch outcome {
        case .pages(let paths):
            CLHaptics.success()
            app.router.present(.captureFlow(CaptureRequest(input: .images(paths), courseID: courseID, isOnboarding: isOnboarding)))
        case .cancelled:
            app.router.dismissCover()
        case .failed(let message):
            failure = message
            useFallback = true
        }
    }

    // MARK: Fallback

    private var fallback: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScannerIllustration()
                    .padding(.top, 20)
                Text("Scan pages")
                    .clFont(.title)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 22)
                Text(ScannerSupport.canScan
                     ? "The camera couldn't start, so add photos of your pages instead."
                     : "The camera scanner isn't available here, so add photos of your pages instead.")
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.roseInk)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                CLList {
                    PhotosPicker(selection: $picked, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
                        CaptureOptionRow(systemImage: "photo.on.rectangle.angled", tint: .tangerine,
                                         title: "Choose photos of pages", subtitle: "In page order, up to 20")
                    }
                    .buttonStyle(.pressable)
                    .disabled(preparing)
                    Button {
                        CLHaptics.tap()
                        app.router.present(.captureFlow(CaptureRequest(input: .sample, courseID: courseID, isOnboarding: isOnboarding)))
                    } label: {
                        CaptureOptionRow(systemImage: "book.pages", tint: .sky, title: "Use our sample page",
                                         subtitle: "A biology page about mitosis")
                    }
                    .buttonStyle(.pressable)
                    .disabled(preparing)
                }
                .padding(.top, 26)
                if preparing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Getting your photos ready…").clFont(.footnote).foregroundStyle(CLColor.ink2)
                    }
                    .padding(.top, 14)
                } else {
                    Label("Flat, in good light, with the whole page in the frame", systemImage: "camera.viewfinder")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .clScreenBackground()
        .safeAreaBar(edge: .top) {
            HStack {
                CaptureGlassButton(systemImage: "xmark", label: "Close") { app.router.dismissCover() }
                    .padding(.leading, 12)
                Spacer()
            }
            .frame(minHeight: 50)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await stage(items) }
        }
        #if DEBUG
        .task {
            guard TestHarness.once("CRAMLESS_SCANNER_SAMPLE") == "1" else { return }
            try? await nap(1200)
            app.router.present(.captureFlow(CaptureRequest(input: .sample, courseID: courseID, isOnboarding: isOnboarding)))
        }
        #endif
    }

    /// The picked photos, one at a time, upright and at most 2000 px, staged for the capture flow.
    private func stage(_ items: [PhotosPickerItem]) async {
        preparing = true
        failure = nil
        defer { preparing = false }
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
        }
        picked = []
        guard !images.isEmpty else {
            failure = "Couldn't open those photos. Try others."
            return
        }
        do {
            let paths = try await Task.detached(priority: .userInitiated) { try PageImageStore.stage(imageData: images) }.value
            CLHaptics.success()
            app.router.present(.captureFlow(CaptureRequest(input: .images(paths), courseID: courseID, isOnboarding: isOnboarding)))
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? "Couldn't open those photos. Try others."
        }
    }
}

/// Whether the document camera can run here. VisionKit can report itself supported in the Simulator, which has no
/// camera to scan with, so the Simulator always gets the fallback.
enum ScannerSupport {
    static var canScan: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        DocumentScannerView.isSupported
        #endif
    }
}

/// A page in the scanner's brackets, still: the same parts as the onboarding demo, at rest.
struct ScannerIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperLine(fraction: 0.62, height: 9, color: PaperInk.heading).padding(.bottom, 3)
            PaperLine(fraction: 0.94)
            PaperLine(fraction: 0.86, marked: true)
            PaperLine(fraction: 0.9)
            PaperLine(fraction: 0.7)
            PaperLine(fraction: 0.8)
        }
        .padding(14)
        .frame(width: 112, height: 140, alignment: .top)
        .background(CLColor.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.16), radius: 14, y: 8)
        .overlay {
            ZStack {
                ForEach([BracketCorner.Corner.topLeading, .topTrailing, .bottomLeading, .bottomTrailing], id: \.self) { corner in
                    BracketCorner(corner: corner)
                        .stroke(CLColor.skyInk, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(corner))
                        .offset(x: corner == .topLeading || corner == .bottomLeading ? -9 : 9,
                                y: corner == .topLeading || corner == .topTrailing ? -9 : 9)
                }
            }
        }
        .rotationEffect(.degrees(-3))
        .accessibilityHidden(true)
    }

    private func alignment(_ corner: BracketCorner.Corner) -> Alignment {
        switch corner {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}

#if DEBUG
private struct FirstSetDebugStageKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// DEBUG: the stage the first-set step opens at (`CRAMLESS_FIRSTSET`).
    var firstSetDebugStage: String? {
        get { self[FirstSetDebugStageKey.self] }
        set { self[FirstSetDebugStageKey.self] = newValue }
    }
}
#endif
