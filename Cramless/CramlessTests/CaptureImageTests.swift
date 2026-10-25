import ImageIO
import UIKit
import XCTest
@testable import Cramless

/// The page-image pipeline: upright, ≤ 2000 px, JPEG without metadata; staging and adoption into a source's folder.
@MainActor
final class CaptureImageTests: CaptureTestCase {
    private func properties(_ data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    func testPhotoDataIsTurnedUprightAndDownscaled() throws {
        // A 3000×2000 landscape bitmap tagged "rotate right" (how a portrait iPhone photo is stored).
        let wide = Render.textImage(["Sideways page"], size: CGSize(width: 3000, height: 2000))
        let data = Render.jpeg(wide, orientation: .right)
        let page = try PageImagePipeline.normalize(data: data)
        XCTAssertEqual(Double(page.width), 1333, accuracy: 1)
        XCTAssertEqual(page.height, 2000, "turned upright: portrait, long edge 2000")
        let props = properties(page.jpeg)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 2000)
        let orientation = props[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1, "no orientation left to apply")
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "no location in a stored page")
    }

    func testSmallImagesAreNotUpscaled() throws {
        let small = Render.textImage(["Small"], size: CGSize(width: 800, height: 600))
        let page = try PageImagePipeline.normalize(data: Render.jpeg(small))
        XCTAssertEqual(page.width, 800)
        XCTAssertEqual(page.height, 600)
    }

    func testScannerImagesHonourTheirOrientation() throws {
        let base = Render.textImage(["Scanned"], size: CGSize(width: 2400, height: 1600))
        let rotated = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)
        let page = try PageImagePipeline.normalize(image: rotated)
        XCTAssertEqual(page.width, 1333)
        XCTAssertEqual(page.height, 2000)
    }

    func testTransparencyIsFlattenedOntoWhite() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let clear = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { _ in }
        let page = try PageImagePipeline.normalize(cgImage: clear.cgImage!)
        let decoded = try XCTUnwrap(UIImage(data: page.jpeg)?.cgImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(rgba[0], 240, "white, not black: \(rgba)")
        XCTAssertGreaterThan(rgba[1], 240)
        XCTAssertGreaterThan(rgba[2], 240)
    }

    func testGarbageIsNotAnImage() {
        XCTAssertThrowsError(try PageImagePipeline.normalize(data: Data("not an image".utf8))) {
            XCTAssertEqual($0 as? CaptureError, .unreadableImage)
        }
    }

    func testStagingThenAdoptionMovesPagesIntoTheSourceFolder() throws {
        let images = try [Render.textImage(["One"]), Render.textImage(["Two"])].map { try PageImagePipeline.normalize(image: $0) }
        let staged = try PageImageStore.stage(images)
        XCTAssertEqual(staged.count, 2)
        XCTAssertTrue(staged.allSatisfy { $0.hasPrefix("staging/") && FileManager.default.fileExists(atPath: FileStore.url(for: $0).path) })
        let id = UUID()
        let adopted = try PageImageStore.adopt(staged, sourceID: id)
        XCTAssertEqual(adopted, ["sources/\(id.uuidString)/page-0.jpg", "sources/\(id.uuidString)/page-1.jpg"])
        XCTAssertTrue(adopted.allSatisfy { FileManager.default.fileExists(atPath: FileStore.url(for: $0).path) })
        XCTAssertFalse(staged.contains { FileManager.default.fileExists(atPath: FileStore.url(for: $0).path) }, "moved, not copied")
        let batch = (staged[0] as NSString).deletingLastPathComponent
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: batch).path), "the empty batch folder is gone")
    }

    func testDiscardRemovesStagedPagesOnly() throws {
        let staged = try PageImageStore.stage(imageData: [Render.jpeg(Render.textImage(["x"]))])
        PageImageStore.discard(staged + ["sources/keep/page-0.jpg"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: staged[0]).path))
    }

    func testStaleStagingIsCleared() throws {
        let staged = try PageImageStore.stage(imageData: [Render.jpeg(Render.textImage(["old"]))])
        PageImageStore.removeStaleStaging(olderThan: 60, now: Date().addingTimeInterval(3600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: staged[0]).path))
    }
}
