import ImageIO
import SwiftUI
import UIKit

/// Decodes page images at the size they're drawn, never at full resolution, and caches the result. Scanned
/// pages are 2000 px tall; a thumbnail decoded at full size costs ~16 MB and a hitch.
enum PageImageLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    /// The image at `relativePath` (under FileStore.root) or an absolute file URL path, decoded so its long edge is
    /// `maxPixel` pixels. Runs off the main thread.
    static func image(at relativePath: String, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(relativePath)#\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = relativePath.hasPrefix("/") ? URL(fileURLWithPath: relativePath) : FileStore.url(for: relativePath)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }
}

/// A page image (white paper while loading), decoded at display size.
struct PageImageView: View {
    let fileName: String?
    /// Width/height of the page, so the frame is right before the pixels arrive.
    var aspect: CGFloat = 2.0 / 3.0

    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CLColor.paper
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                        .transition(.opacity)
                }
            }
            .task(id: "\(fileName ?? "")#\(Int(geo.size.width))") {
                guard let fileName, geo.size.width > 0 else { return }
                let pixels = max(geo.size.width, geo.size.height) * scale
                let loaded = await PageImageLoader.image(at: fileName, maxPixel: pixels)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

/// A page with marks drawn over its recognised lines: highlights (the lines a question came from) and slots
/// (diagram labels to fill). Boxes come from text recognition in page units, so they line up with the image at
/// any size. Lines without boxes (typed or PDF text) can't be marked; callers show the text instead.
struct PageCanvas<SlotContent: View>: View {
    let fileName: String?
    let pageSize: CGSize
    var lines: [TextLine]
    /// Line ids to highlight.
    var highlighted: Set<String> = []
    var highlightColor: Color = CLColor.markKey
    /// Line ids drawn as slots (diagram labels hidden behind a card).
    var slots: [String] = []
    @ViewBuilder var slotContent: (TextLine) -> SlotContent

    var body: some View {
        let aspect = pageSize.height > 0 ? pageSize.width / pageSize.height : 2.0 / 3.0
        PageImageView(fileName: fileName, aspect: aspect)
            .overlay {
                GeometryReader { geo in
                    let byID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
                    ForEach(Array(highlighted), id: \.self) { id in
                        if let box = byID[id]?.box {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(highlightColor)
                                .frame(width: box.w * geo.size.width + 6, height: box.h * geo.size.height + 4)
                                .position(x: (box.x + box.w / 2) * geo.size.width, y: (box.y + box.h / 2) * geo.size.height)
                                .blendMode(.multiply)
                                .allowsHitTesting(false)
                        }
                    }
                    ForEach(slots, id: \.self) { id in
                        if let line = byID[id], let box = line.box {
                            slotContent(line)
                                .frame(minWidth: box.w * geo.size.width + 12, minHeight: max(28, box.h * geo.size.height + 10))
                                .position(x: (box.x + box.w / 2) * geo.size.width, y: (box.y + box.h / 2) * geo.size.height)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.12), radius: 10, y: 4)
            .accessibilityElement(children: .contain)
    }
}

extension PageCanvas where SlotContent == EmptyView {
    init(fileName: String?, pageSize: CGSize, lines: [TextLine], highlighted: Set<String> = [],
         highlightColor: Color = CLColor.markKey) {
        self.init(fileName: fileName, pageSize: pageSize, lines: lines, highlighted: highlighted,
                  highlightColor: highlightColor, slots: []) { _ in EmptyView() }
    }
}
