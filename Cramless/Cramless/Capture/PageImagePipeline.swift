import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A page image ready to keep: upright, at most 2000 px on the long edge, JPEG at 0.8, no metadata (a photo's
/// location never rides along with a page).
struct PageImage: Sendable {
    var jpeg: Data
    var width: Int
    var height: Int
}

/// Turns whatever the camera, the scanner or Photos hands over into a `PageImage`. Safe off the main thread.
enum PageImagePipeline {
    static let maxPixelSize = 2000
    static let jpegQuality = 0.8

    /// From encoded image data (Photos, Files; JPEG, HEIC, PNG). ImageIO decodes straight to at most 2000 px with
    /// the EXIF orientation applied, so a 48 MP photo is never decoded at full size.
    static func normalize(data: Data) throws -> PageImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw CaptureError.unreadableImage }
        return try normalize(source: source)
    }

    static func normalize(url: URL) throws -> PageImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw CaptureError.unreadableImage }
        return try normalize(source: source)
    }

    /// From a `UIImage` (the document scanner's pages). Drawing applies `imageOrientation`; the renderer works at
    /// scale 1 so the result is measured in pixels.
    static func normalize(image: UIImage) throws -> PageImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth >= 1, pixelHeight >= 1 else { throw CaptureError.unreadableImage }
        let size = fittedSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = rendered.cgImage else { throw CaptureError.unreadableImage }
        return try encode(cgImage)
    }

    /// From an upright `CGImage` (a rendered PDF page).
    static func normalize(cgImage: CGImage) throws -> PageImage {
        let size = fittedSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        if Int(size.width) == cgImage.width, Int(size.height) == cgImage.height { return try encode(cgImage) }
        return try encode(redraw(cgImage, to: size))
    }

    /// The size that fits `maxPixelSize` on the long edge, never larger than the original.
    static func fittedSize(width: CGFloat, height: CGFloat) -> CGSize {
        let scale = min(1, CGFloat(maxPixelSize) / max(width, height))
        return CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
    }

    private static func normalize(source: CGImageSource) throws -> PageImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw CaptureError.unreadableImage }
        return try encode(image)
    }

    /// JPEG without metadata. Images with transparency are flattened onto white first (JPEG would make it black).
    static func encode(_ image: CGImage) throws -> PageImage {
        let opaque = hasAlpha(image) ? redraw(image, to: CGSize(width: image.width, height: image.height)) : image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CaptureError.unreadableImage }
        CGImageDestinationAddImage(destination, opaque, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.unreadableImage }
        return PageImage(jpeg: data as Data, width: opaque.width, height: opaque.height)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    private static func redraw(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

/// Where page images live: staged under `staging/<batch>/` while the capture flow runs, then moved into the
/// source's folder, `sources/<sourceID>/page-<n>.jpg`. Paths are relative to `FileStore.root`.
enum PageImageStore {
    static let stagingFolder = "staging"

    static func sourceFolder(_ sourceID: UUID) -> String { "sources/\(sourceID.uuidString)" }

    static func pageFileName(_ index: Int) -> String { "page-\(index).jpg" }

    /// Writes page images for a capture request (`CaptureRequest.Input.images`), in order.
    static func stage(_ images: [PageImage]) throws -> [String] {
        removeStaleStaging()
        let folder = "\(stagingFolder)/\(UUID().uuidString)"
        return try images.enumerated().map { index, image in
            try FileStore.write(image.jpeg, folder: folder, name: pageFileName(index))
        }
    }

    /// Stages encoded images (Photos, Files) one at a time, so only one decoded page is in memory.
    static func stage(imageData: [Data]) throws -> [String] {
        removeStaleStaging()
        let folder = "\(stagingFolder)/\(UUID().uuidString)"
        var paths: [String] = []
        for (index, data) in imageData.enumerated() {
            let image = try autoreleasepool { try PageImagePipeline.normalize(data: data) }
            paths.append(try FileStore.write(image.jpeg, folder: folder, name: pageFileName(index)))
        }
        return paths
    }

    /// Moves staged pages into the source's folder as `page-<n>.jpg`, numbered from `startIndex`, and returns the
    /// new paths. A path that isn't a staged page (any other image under the file store) is normalised and copied.
    static func adopt(_ paths: [String], sourceID: UUID, startIndex: Int = 0) throws -> [String] {
        let folder = sourceFolder(sourceID)
        let manager = FileManager.default
        try manager.createDirectory(at: FileStore.url(for: folder), withIntermediateDirectories: true)
        var adopted: [String] = []
        for (offset, path) in paths.enumerated() {
            let relative = "\(folder)/\(pageFileName(startIndex + offset))"
            let target = FileStore.url(for: relative)
            let origin = FileStore.url(for: path)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            if path.hasPrefix(stagingFolder + "/") {
                try manager.moveItem(at: origin, to: target)
            } else {
                let image = try autoreleasepool { try PageImagePipeline.normalize(url: origin) }
                try image.jpeg.write(to: target, options: .atomic)
            }
            adopted.append(relative)
        }
        removeEmptyStagingFolders(for: paths)
        return adopted
    }

    /// Throws away staged pages the person didn't keep (the capture flow was cancelled).
    static func discard(_ paths: [String]) {
        for path in paths where path.hasPrefix(stagingFolder + "/") {
            try? FileManager.default.removeItem(at: FileStore.url(for: path))
        }
        removeEmptyStagingFolders(for: paths)
    }

    /// Staging older than a day belongs to a flow that never finished.
    static func removeStaleStaging(olderThan age: TimeInterval = 86_400, now: Date = Date()) {
        let root = FileStore.url(for: stagingFolder)
        guard let batches = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for batch in batches {
            let modified = (try? batch.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(modified) > age { try? FileManager.default.removeItem(at: batch) }
        }
    }

    /// Deletes staged pages that won't be kept (a problem read off a photo), and their folders once empty.
    static func discardStaged(_ paths: [String]) {
        for path in paths where path.hasPrefix(stagingFolder + "/") {
            try? FileManager.default.removeItem(at: FileStore.url(for: path))
        }
        removeEmptyStagingFolders(for: paths)
    }

    private static func removeEmptyStagingFolders(for paths: [String]) {
        let folders = Set(paths.filter { $0.hasPrefix(stagingFolder + "/") }.map { ($0 as NSString).deletingLastPathComponent })
        for folder in folders {
            let url = FileStore.url(for: folder)
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
