import SwiftUI
import VisionKit

/// The system document camera (VisionKit): finds the page's edges, captures automatically (the person can switch
/// to manual), flattens and deskews, and takes as many pages as the person wants before Save.
///
/// `VNDocumentCameraViewController.isSupported` is false in the Simulator and on devices without the camera
/// support it needs, so check `DocumentScannerView.isSupported` first and offer the sample page or Photos instead.
///
/// The pages come back staged (upright, ≤ 2000 px, JPEG) for a `CaptureRequest`:
///
///     DocumentScannerView { outcome in
///         if case .pages(let paths) = outcome {
///             app.router.present(.captureFlow(CaptureRequest(input: .images(paths), courseID: courseID)))
///         }
///     }
struct DocumentScannerView: UIViewControllerRepresentable {
    enum Outcome: Sendable, Equatable {
        /// Staged page images, in scan order (relative to `FileStore.root`).
        case pages([String])
        case cancelled
        /// The camera failed, or the pages couldn't be saved. A sentence the person can read.
        case failed(String)
    }

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// Called once on the main actor. The scanner stays on screen until then (staging takes about a tenth of a
    /// second a page), so dismiss it here.
    var onFinish: @MainActor (Outcome) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    /// VisionKit calls the delegate on the main thread; `@preconcurrency` checks that at run time.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        var onFinish: @MainActor (Outcome) -> Void
        private var finished = false

        init(onFinish: @escaping @MainActor (Outcome) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard !finished else { return }
            finished = true
            let pages = ScannedPages(scan: scan)
            Task {
                let outcome: Outcome
                do {
                    let paths = try await Task.detached(priority: .userInitiated) { try pages.stage() }.value
                    outcome = paths.isEmpty ? .cancelled : .pages(paths)
                } catch {
                    outcome = .failed("Couldn't save the scanned pages. Try scanning again.")
                }
                onFinish(outcome)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            guard !finished else { return }
            finished = true
            onFinish(.cancelled)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            guard !finished else { return }
            finished = true
            onFinish(.failed("The camera couldn't scan right now. Try again, or pick photos instead."))
        }
    }
}

/// A finished scan, read off the main thread one page at a time (a page from `imageOfPage(at:)` is a full-size
/// image; holding all of them at once is what runs a 20-page scan out of memory). The scan is immutable once
/// delivered, which is what makes handing it to another thread sound.
private struct ScannedPages: @unchecked Sendable {
    let scan: VNDocumentCameraScan

    func stage() throws -> [String] {
        var images: [PageImage] = []
        images.reserveCapacity(scan.pageCount)
        for index in 0..<scan.pageCount {
            let page = try autoreleasepool { try PageImagePipeline.normalize(image: scan.imageOfPage(at: index)) }
            images.append(page)
        }
        return try PageImageStore.stage(images)
    }
}
