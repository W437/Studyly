import SwiftUI

/// A four-point star with straight, concave sides: the sparkle. The mark the sky uses for a bright star, and Progress
/// for a day well studied and for where a sparkline ends. It is a different shape from the dot beside it, so the
/// meaning never rests on colour alone.
struct SparkleShape: Shape {
    /// The inner points' radius as a share of the outer: smaller is spikier.
    var inner: CGFloat = 0.36

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4 - .pi / 2
            let radius = k % 2 == 0 ? r : r * inner
            let point = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
