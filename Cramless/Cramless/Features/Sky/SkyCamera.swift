import CoreGraphics
import Foundation

/// Which part of the sky is on screen. A pure value, so panning, zooming, focusing and tapping are all tested
/// without a view. `center` is the layout point at the middle of the view and `scale` the points per layout unit
/// (one unit is the spacing between neighbouring stars).
struct SkyCamera: Equatable, Sendable {
    var center: SkyPoint
    var scale: Double

    /// The farthest in a sky may start: stars are about this many points apart. A sky of a few stars stays small and
    /// centred instead of spreading to the edges.
    static let largestFit = 30.0
    /// How far a person may zoom in past the whole-sky view, and out.
    static let zoomIn = 10.0
    static let zoomOut = 0.8

    // MARK: Framing

    /// The whole sky, centred in the part of the view the insets leave free.
    /// `largest` is how far in the camera may start (points per spacing); Today's hero lets a small sky grow bigger than the
    /// full screen does, because it has a world's worth of room and little else in it.
    static func fit(_ layout: SkyLayout, in size: CGSize, top: Double = 0, bottom: Double = 0, largest: Double = largestFit) -> SkyCamera {
        let free = CGSize(width: size.width, height: max(1, size.height - top - bottom))
        let scale = min(largest, min(free.width / max(layout.width, 1), free.height / max(layout.height, 1)))
        return SkyCamera.centred(on: SkyPoint(x: layout.width / 2, y: layout.height / 2), scale: scale, in: size, top: top, bottom: bottom)
    }

    /// One constellation, with its room, filling most of the free part of the view.
    static func focus(_ c: SkyLayout.Constellation, in size: CGSize, top: Double = 0, bottom: Double = 0) -> SkyCamera {
        let free = CGSize(width: size.width, height: max(1, size.height - top - bottom))
        let diameter = max(2 * c.radius, 1)
        let scale = min(free.width, free.height) / diameter * 0.82
        return SkyCamera.centred(on: c.center, scale: min(scale, 80), in: size, top: top, bottom: bottom)
    }

    /// A camera that frames `points` with `padding` spacings round them, or nil when that is hardly closer than the whole
    /// sky (they spread over most of it already). Used to visit the stars a session relit.
    static func framing(_ points: [SkyPoint], padding: Double, in size: CGSize, top: Double = 0, bottom: Double = 0,
                        comparedTo fit: SkyCamera, minimumGain: Double = 1.3) -> SkyCamera? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let width = maxX - minX + 2 * padding, height = maxY - minY + 2 * padding
        let free = CGSize(width: size.width, height: max(1, size.height - top - bottom))
        let scale = min(40, min(free.width / width, free.height / height))
        guard scale >= fit.scale * minimumGain else { return nil }
        return centred(on: SkyPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), scale: scale, in: size, top: top, bottom: bottom)
    }

    /// `point` at the middle of the free part of the view.
    private static func centred(on point: SkyPoint, scale: Double, in size: CGSize, top: Double, bottom: Double) -> SkyCamera {
        // The free part's middle is (top − bottom) / 2 below the view's middle, so the camera's own centre sits above `point`.
        SkyCamera(center: SkyPoint(x: point.x, y: point.y - (top - bottom) / (2 * scale)), scale: scale)
    }

    // MARK: Mapping

    func screen(_ p: SkyPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - center.x) * scale, y: size.height / 2 + (p.y - center.y) * scale)
    }

    func layoutPoint(_ s: CGPoint, in size: CGSize) -> SkyPoint {
        SkyPoint(x: center.x + (s.x - size.width / 2) / scale, y: center.y + (s.y - size.height / 2) / scale)
    }

    // MARK: Moving

    func panned(by delta: CGSize) -> SkyCamera {
        SkyCamera(center: SkyPoint(x: center.x - delta.width / scale, y: center.y - delta.height / scale), scale: scale)
    }

    /// Zoomed by `factor` about a screen point, which stays under the finger, within the limits around `fit`.
    func zoomed(by factor: Double, around s: CGPoint, in size: CGSize, fit: SkyCamera) -> SkyCamera {
        let target = min(fit.scale * Self.zoomIn, max(fit.scale * Self.zoomOut, scale * factor))
        let anchor = layoutPoint(s, in: size)
        let moved = SkyCamera(center: center, scale: target)
        let after = moved.layoutPoint(s, in: size)
        return SkyCamera(center: SkyPoint(x: center.x + anchor.x - after.x, y: center.y + anchor.y - after.y), scale: target)
    }

    /// Kept so the sky can't be dragged away: its middle stays within the view's reach of the whole sky.
    func clamped(to layout: SkyLayout) -> SkyCamera {
        SkyCamera(center: SkyPoint(x: min(layout.width, max(0, center.x)), y: min(layout.height, max(0, center.y))), scale: scale)
    }

    // MARK: Interpolating

    func mixed(with other: SkyCamera, _ t: Double) -> SkyCamera {
        // Exact at the ends, so a glide's last frame is the target itself.
        if t <= 0 { return self }
        if t >= 1 { return other }
        // Scale moves on a log curve, so a zoom feels even.
        let s = exp(log(scale) + (log(other.scale) - log(scale)) * t)
        return SkyCamera(center: SkyPoint(x: center.x + (other.center.x - center.x) * t,
                                          y: center.y + (other.center.y - center.y) * t), scale: s)
    }
}

/// Finding what a tap landed on.
enum SkyHit {
    /// The smallest target, in points, however small a constellation is drawn.
    static let minimumTarget = 22.0

    /// The constellation a tap at `point` chose: the nearest one whose circle (at least `minimumTarget` points from
    /// its middle) holds the tap. Overlapping circles go to the nearer middle. Nil for empty sky.
    static func constellation(at point: CGPoint, camera: SkyCamera, size: CGSize, layout: SkyLayout) -> Int? {
        var best: (index: Int, distance: Double)?
        for (i, c) in layout.constellations.enumerated() {
            let middle = camera.screen(c.center, in: size)
            let reach = max(minimumTarget, c.radius * camera.scale * 0.7)
            let distance = ((middle.x - point.x) * (middle.x - point.x) + (middle.y - point.y) * (middle.y - point.y)).squareRoot()
            if distance <= reach, distance < (best?.distance ?? .infinity) { best = (i, distance) }
        }
        return best?.index
    }

    /// The constellation with a star nearest a tap, within `reach` points: for a world you tap with a fingertip, where you
    /// aim at a star and not at a circle round a shape. A tap between two shapes goes to the closer star.
    static func nearestStar(at point: CGPoint, camera: SkyCamera, size: CGSize, layout: SkyLayout, reach: Double = 40) -> Int? {
        var best: (index: Int, distance: Double)?
        for (i, c) in layout.constellations.enumerated() {
            // Only constellations whose circle comes within reach of the tap have a star that can.
            let middle = camera.screen(c.center, in: size)
            let roughly = ((middle.x - point.x) * (middle.x - point.x) + (middle.y - point.y) * (middle.y - point.y)).squareRoot()
            guard roughly <= c.radius * camera.scale + reach else { continue }
            for s in c.stars {
                let p = camera.screen(layout.stars[s].point, in: size)
                let distance = ((p.x - point.x) * (p.x - point.x) + (p.y - point.y) * (p.y - point.y)).squareRoot()
                if distance <= reach, distance < (best?.distance ?? .infinity) { best = (i, distance) }
            }
        }
        return best?.index
    }
}
