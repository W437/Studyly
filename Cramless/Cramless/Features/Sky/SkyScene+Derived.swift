import Foundation

// Smaller pictures cut from the sky: an exam's region, and one constellation as a glyph. Pure, so they're tested
// without a view. Progress shows them: a still of each exam's region on its card, and a glyph beside each
// constellation in its list.

extension SkyScene {
    /// The part of the sky `examID`'s region covers (its own constellations, not whatever else sits inside the circle),
    /// moved so the circle fills a square from (0, 0) to (2r, 2r). Nil when the exam has no region (nothing studied in
    /// its scope).
    func region(of examID: UUID) -> SkyScene? {
        guard let region = layout.regions.first(where: { $0.examID == examID }) else { return nil }
        let covered = region.covers.filter { layout.constellations.indices.contains($0) }.sorted()
        guard !covered.isEmpty else { return nil }
        let dx = region.radius - region.center.x, dy = region.radius - region.center.y
        func moved(_ p: SkyPoint) -> SkyPoint { SkyPoint(x: p.x + dx, y: p.y + dy) }

        var sub = SkyLayout()
        var subLight = SkyLight()
        for (newIndex, ci) in covered.enumerated() {
            let c = layout.constellations[ci]
            let start = sub.stars.count
            for i in c.stars {
                let star = layout.stars[i]
                sub.stars.append(.init(id: star.id, point: moved(star.point), constellation: newIndex))
                subLight.recall.append(light.recall[i])
                subLight.brightness.append(light.brightness[i])
                subLight.hollow.append(light.hollow[i])
                subLight.flicker.append(light.flicker[i])
            }
            sub.constellations.append(.init(
                id: c.id, courseID: c.courseID, topicID: c.topicID, name: c.name, center: moved(c.center), radius: c.radius,
                stars: start..<sub.stars.count,
                lines: c.lines.map { .init(a: $0.a - c.stars.lowerBound + start, b: $0.b - c.stars.lowerBound + start) }))
        }
        var shifted = region
        shifted.center = moved(region.center)
        shifted.covers = Array(covered.indices)
        sub.regions = [shifted]
        sub.width = 2 * region.radius
        sub.height = 2 * region.radius
        return SkyScene(layout: sub, light: subLight, courseColors: courseColors, courseNames: courseNames,
                        examDates: examDates, dimSeconds: Array(repeating: 0, count: sub.constellations.count), date: date)
    }

    /// One constellation drawn small: its stars in a unit square, how each shines, and its lines.
    func glyph(of constellation: Int) -> SkyGlyph? {
        guard layout.constellations.indices.contains(constellation) else { return nil }
        let c = layout.constellations[constellation]
        guard !c.stars.isEmpty else { return nil }
        let points = c.stars.map { layout.stars[$0].point }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        // Fit the stars' box into the unit square, keeping its shape, with room for the stars' own size.
        let span = max(maxX - minX, maxY - minY, 1e-6)
        let margin = 0.14
        let scale = (1 - 2 * margin) / span
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        let stars = c.stars.map { i -> SkyGlyph.Star in
            let p = layout.stars[i].point
            return .init(x: 0.5 + (p.x - midX) * scale, y: 0.5 + (p.y - midY) * scale, brightness: light.brightness[i],
                         hollow: light.hollow[i], dim: light.isDim(i))
        }
        let lines = c.lines.map { SkyGlyph.Line(a: $0.a - c.stars.lowerBound, b: $0.b - c.stars.lowerBound) }
        return SkyGlyph(stars: stars, lines: lines, color: color(of: c))
    }
}

/// A constellation as a picture a few dozen points wide.
struct SkyGlyph: Equatable, Sendable {
    struct Star: Equatable, Sendable {
        /// 0…1 across and down the glyph.
        var x: Double
        var y: Double
        var brightness: Double
        /// Never studied: a ring.
        var hollow: Bool
        var dim: Bool
    }

    struct Line: Equatable, Sendable {
        var a: Int
        var b: Int
    }

    var stars: [Star]
    var lines: [Line]
    var color: CourseColor

    /// How many of its stars are bright, dim and not yet lit.
    var counts: (bright: Int, dim: Int, hollow: Int) {
        (stars.filter { !$0.hollow && !$0.dim }.count, stars.filter(\.dim).count, stars.filter(\.hollow).count)
    }
}
