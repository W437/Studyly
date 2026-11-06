import CoreGraphics
import SwiftUI

/// Where a page settles when it opens on the lines a question came from: the page zoomed so those lines fill it (at most 3×, and never
/// showing past the page's edge), and a pen circle around each block of lines. Pure, in page units (0…1, top-left origin), so it's
/// tested without a view.
struct PageFocus: Equatable {
    /// How far the page is zoomed (1: not at all).
    var scale: CGFloat
    /// How far it moves from the middle, in points of a frame of the size given.
    var offset: CGSize
    /// What gets circled.
    var blocks: [CGRect]

    static let maxScale: CGFloat = 3
    /// Room around the lines, in page units.
    static let padding: CGFloat = 0.04
    /// Below this a zoom only makes the page twitch.
    static let leastZoom: CGFloat = 1.15

    /// The focus for these boxes on a page drawn in a frame of `frame`. Nil with nothing to focus on.
    static func make(boxes: [NormRect], frame: CGSize) -> PageFocus? {
        let rects = boxes.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }.filter { $0.width > 0 && $0.height > 0 }
        guard !rects.isEmpty else { return nil }
        let blocks = Self.blocks(of: rects)
        // A quote that runs across columns has no one place to zoom to: each part gets its circle.
        if Self.sitSideBySide(blocks) {
            return PageFocus(scale: 1, offset: .zero, blocks: blocks)
        }
        let union = blocks.reduce(blocks[0]) { $0.union($1) }
        let padded = union.insetBy(dx: -padding, dy: -padding)
        let fit = min(1 / max(padded.width, 0.001), 1 / max(padded.height, 0.001))
        let scale = min(maxScale, fit)
        guard scale >= leastZoom else {
            return PageFocus(scale: 1, offset: .zero, blocks: blocks)
        }
        let maxX = (frame.width * scale - frame.width) / 2
        let maxY = (frame.height * scale - frame.height) / 2
        let x = (0.5 - union.midX) * frame.width * scale
        let y = (0.5 - union.midY) * frame.height * scale
        return PageFocus(scale: scale,
                         offset: CGSize(width: min(maxX, max(-maxX, x)), height: min(maxY, max(-maxY, y))),
                         blocks: blocks)
    }

    /// Lines that sit one under the other, close together, are one block.
    static func blocks(of rects: [CGRect]) -> [CGRect] {
        var blocks: [(rect: CGRect, lineHeight: CGFloat)] = []
        for rect in rects.sorted(by: { $0.minY < $1.minY }) {
            let height = rect.height
            if let index = blocks.firstIndex(where: { block in
                let overlapsAcross = block.rect.minX < rect.maxX && rect.minX < block.rect.maxX
                let gap = rect.minY - block.rect.maxY
                return overlapsAcross && gap <= 1.5 * max(block.lineHeight, height)
            }) {
                blocks[index].rect = blocks[index].rect.union(rect)
                blocks[index].lineHeight = max(blocks[index].lineHeight, height)
            } else {
                blocks.append((rect, height))
            }
        }
        return blocks.map(\.rect)
    }

    private static func sitSideBySide(_ blocks: [CGRect]) -> Bool {
        for (index, a) in blocks.enumerated() {
            for b in blocks[(index + 1)...] where !(a.minX < b.maxX && b.minX < a.maxX) {
                return true
            }
        }
        return false
    }
}

/// A ring drawn by hand around a block of lines: a superellipse rather than an ellipse, because a true ellipse runs through the words at the
/// block's corners. It wanders a little and its end runs just past its start, as a pen's does. The same every time. Draw it with `.trim`.
struct PenCircleShape: Shape {
    /// How square its shoulders are: 2 is an ellipse. This is the roundest it gets; a taller block needs them squarer (`squareness(for:)`).
    private static let leastSquareness = 3.6
    private static let mostSquareness = 8.0
    /// The space the page leaves around the lines, on each side, inside the ring's frame.
    private static let margin = CGSize(width: 12, height: 10)
    private static let steps = 120
    /// How far the line strays in and out as it goes round, as a share of its reach.
    private static let wander = 0.012
    /// How far past its start the pen goes, in degrees.
    private static let overshoot = 26.0

    /// The roundest ring that still has the corners of its lines inside, the stroke's width to spare.
    private static func squareness(for rect: CGRect) -> Double {
        // Where a corner of the lines falls, with the line at its furthest in.
        let x = max(0, 1 - margin.width / max(rect.width / 2, 1)) / (1 - wander)
        let y = max(0, 1 - margin.height / max(rect.height / 2, 1)) / (1 - wander)
        var squareness = leastSquareness
        while squareness < mostSquareness, pow(x, squareness) + pow(y, squareness) > 0.97 { squareness += 0.2 }
        return squareness
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = -160.0
        let exponent = 2 / Self.squareness(for: rect)
        for step in 0...Self.steps {
            let progress = Double(step) / Double(Self.steps)
            let degrees = start + progress * (360 + Self.overshoot)
            let angle = degrees * .pi / 180
            // A slow wander, and the end drifting outward so it passes outside its start instead of landing on it.
            let reach = 1 + Self.wander * sin(3 * angle + 0.7) + 0.035 * max(0, progress - 0.88) / 0.12
            let x = copysign(pow(abs(cos(angle)), exponent), cos(angle)) * reach
            let y = copysign(pow(abs(sin(angle)), exponent), sin(angle)) * reach
            let point = CGPoint(x: rect.midX + CGFloat(x) * rect.width / 2, y: rect.midY + CGFloat(y) * rect.height / 2)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
