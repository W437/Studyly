import PhotosUI
import SwiftUI

/// One go at "Snap a problem": the photo being read on this iPhone, then its words to check.
struct SnapSession: Identifiable, Equatable {
    enum Phase: Equatable {
        case reading
        case ready(SnapReader.Reading)
    }

    var id = UUID()
    var phase: Phase = .reading
}

/// "Check the problem": the words read off the photo, to fix before they go to Cap. The photo stays on this iPhone and is gone by now; only
/// these words leave. A photo with nothing readable offers another try or typing it.
///
/// Harness: `CRAMLESS_ROUTE=ask CRAMLESS_SNAP=confirm|mathlike|unreadable` opens it in that state, `asked` sends the problem and
/// `notcovered` sends one the notes don't hold; `CRAMLESS_SNAP_TEXT=<words>` sets the problem (`ChatPane`).
struct SnapConfirmView: View {
    let session: SnapSession
    let onSend: (String) -> Void
    let onRetry: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var typing = false
    @FocusState private var focused: Bool

    private var reading: SnapReader.Reading? {
        if case .ready(let reading) = session.phase { return reading }
        return nil
    }

    var body: some View {
        TodayFittedSheet {
            VStack(alignment: .leading, spacing: 14) {
                if session.phase == .reading {
                    readingView
                } else if let reading, reading.hasWords || typing {
                    confirm(issue: reading.issue)
                } else {
                    unreadable
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        // Sheets don't inherit the root's font choice (RootView sets it inside the modifier that presents them).
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        .onChange(of: session.phase, initial: true) { _, phase in
            if case .ready(let reading) = phase { text = reading.text }
        }
    }

    private var readingView: some View {
        HStack(spacing: 12) {
            CapFace(size: 46)
            Text("Reading your photo on this iPhone")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            ProgressView().controlSize(.small)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func confirm(issue: PageRead.Issue?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CapFace(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Check the problem").clFont(.title3).foregroundStyle(CLColor.ink).accessibilityAddTraits(.isHeader)
                Text("Fix anything Cap misread before you send it.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CLIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
        if issue == .mathLike, !typing {
            Label("Math is hard to read from a photo. Check the numbers and symbols.", systemImage: "function")
                .clFont(.footnote)
                .foregroundStyle(CLColor.sunInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CLColor.sunSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        TextField(typing ? "Type the problem" : "The problem", text: $text, axis: .vertical)
            .clFont(.body)
            .foregroundStyle(CLColor.ink)
            .lineLimit(3...10)
            .focused($focused)
            .padding(12)
            .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("The problem")
        Label("The photo stays on this iPhone. Only the words go to Cap.", systemImage: "lock.fill")
            .clFont(.caption)
            .foregroundStyle(CLColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
        Button("Ask Cap") {
            CLHaptics.tap()
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            dismiss()
            onSend(clean)
        }
        .buttonStyle(.cl(.primary))
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CapFace(size: 46)
                Text("Cap couldn't read that photo. Try again closer, or type the problem.")
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                CLIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { unreadableButtons }
                VStack(spacing: 10) { unreadableButtons }
            }
        }
    }

    @ViewBuilder private var unreadableButtons: some View {
        Button("Type it") {
            CLHaptics.tap()
            withAnimation(CLMotion.settle) { typing = true }
            focused = true
        }
        .buttonStyle(.cl(.soft))
        Button("Try again") {
            CLHaptics.tap()
            dismiss()
            onRetry()
        }
        .buttonStyle(.cl(.primary))
    }
}

/// The student's question when it came from a photo: their bubble, with where its words came from.
struct PhotoProblemBubble: View {
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Label("From a photo", systemImage: "camera.fill")
                .clFont(.caption)
                .foregroundStyle(CLColor.ink3)
                .accessibilityHidden(true)
            UserBubble(text: text, spokenPrefix: "From a photo")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The way from the composer's camera to "Check the problem": the document camera where this iPhone has one, else (and on request) a photo
/// from the library. One page, one photo. The picture is read here and thrown away.
struct SnapFlow: ViewModifier {
    @Binding var isChoosing: Bool
    @Binding var session: SnapSession?
    let onSend: (String) -> Void

    @State private var scanning = false
    @State private var scanned: String?
    @State private var picking = false
    @State private var picked: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Snap a problem", isPresented: scanDialog, titleVisibility: .visible) {
                Button("Take a photo") { scanning = true }
                Button("Choose a photo") { picking = true }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: isChoosing) { _, choosing in
                // No camera to scan with here: straight to the library.
                if choosing, !ScannerSupport.canScan {
                    isChoosing = false
                    picking = true
                }
            }
            .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
            // The sheet follows once the picker has gone, whichever of the two the system says first.
            .onChange(of: picked) { _, _ in readPicked() }
            .onChange(of: picking) { _, _ in readPicked() }
            .fullScreenCover(isPresented: $scanning, onDismiss: {
                // After the camera has gone: a sheet can't rise while a cover is leaving.
                if let scanned { read(staged: scanned) }
                scanned = nil
            }, content: {
                DocumentScannerView(maxPages: 1) { outcome in
                    if case .pages(let paths) = outcome { scanned = paths.first }
                    scanning = false
                }
                .ignoresSafeArea()
            })
            .sheet(item: $session) { current in
                SnapConfirmView(session: current, onSend: onSend, onRetry: {
                    // After this sheet has gone.
                    Task {
                        try? await nap(450)
                        isChoosing = true
                    }
                })
            }
    }

    private var scanDialog: Binding<Bool> {
        Binding(get: { isChoosing && ScannerSupport.canScan }, set: { if !$0 { isChoosing = false } })
    }

    private func readPicked() {
        guard !picking, let item = picked else { return }
        picked = nil
        read(item)
    }

    private func read(_ item: PhotosPickerItem) {
        let id = UUID()
        session = SnapSession(id: id)
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            let path: String? = await Task.detached(priority: .userInitiated) {
                data.flatMap { try? PageImageStore.stage(imageData: [$0]).first }
            }.value
            guard let path else {
                finish(id, SnapReader.Reading(text: "", issue: .unreadable))
                return
            }
            finish(id, await SnapReader.read(stagedAt: path))
        }
    }

    private func read(staged path: String) {
        let id = UUID()
        session = SnapSession(id: id)
        Task { finish(id, await SnapReader.read(stagedAt: path)) }
    }

    /// The reading, unless the student closed the sheet meanwhile.
    private func finish(_ id: UUID, _ reading: SnapReader.Reading) {
        guard session?.id == id else { return }
        session?.phase = .ready(reading)
    }
}
