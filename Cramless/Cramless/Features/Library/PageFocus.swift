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

/// A circle drawn by hand around something: a little off round, its end running past its start, as a pen's does. Draw it with `.trim`.
struct PenCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        func point(_ degrees: Double, _ stretch: CGFloat = 1) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: cx + CGFloat(cos(a)) * rx * stretch, y: cy + CGFloat(sin(a)) * ry * stretch)
        }
        // Starts at the upper left, goes clockwise, wanders a little and overshoots the start.
        let turns: [(end: Double, stretch: CGFloat)] = [(-130, 1), (-40, 1.03), (50, 0.98), (140, 1.03), (230, 0.97), (262, 1.05)]
        var path = Path()
        path.move(to: point(-160, 1))
        var from = -160.0
        for turn in turns {
            let span = turn.end - from
            let handle = CGFloat(4.0 / 3.0 * tan(span * .pi / 720))
            let a0 = from * .pi / 180, a1 = turn.end * .pi / 180
            let start = point(from, 1)
            let end = point(turn.end, turn.stretch)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x - CGFloat(sin(a0)) * rx * handle, y: start.y + CGFloat(cos(a0)) * ry * handle),
                          control2: CGPoint(x: end.x + CGFloat(sin(a1)) * rx * handle, y: end.y - CGFloat(cos(a1)) * ry * handle))
            from = turn.end
        }
        return path
    }
}
