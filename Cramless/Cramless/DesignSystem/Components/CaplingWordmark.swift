import SwiftUI

/// "capling" set in the display face, with a small four-point star where the i's dot would be: a memory kept lit, the app's idea in
/// the name. The welcome starts it unlit and lights it when the cap in the sky is lit; everywhere else it is simply lit.
struct CaplingWordmark: View {
    var size: CGFloat
    var color: Color = CLColor.ink
    /// The star is gold (lit), or only a faint copy of the letters' colour (waiting to be).
    var starLit = true

    var body: some View {
        HStack(spacing: 0) {
            Text("capl")
            // A dotless i, so the star can stand where the dot was.
            Text("\u{0131}")
                .overlay(alignment: .top) {
                    Star()
                        .fill(starLit ? CLColor.sun : color.opacity(0.28))
                        .frame(width: size * 0.3, height: size * 0.3)
                        .shadow(color: CLColor.sun.opacity(starLit ? 0.55 : 0), radius: size * 0.1)
                        .offset(y: size * 0.185)
                        .animation(CLMotion.pop, value: starLit)
                }
            Text("ng")
        }
        .clFont(.display(size))
        .foregroundStyle(color)
        .lineLimit(1)
        // A logotype keeps its size: it isn't text to be reflowed, and it would run off the screen at the largest text sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Capling"))
    }

    /// A four-point star with concave sides.
    private struct Star: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = min(rect.width, rect.height) / 2
            let inner = r * 0.3
            var path = Path()
            for k in 0..<8 {
                let radius = k % 2 == 0 ? r : inner
                let angle = Double(k) * .pi / 4 - .pi / 2
                let point = CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
                if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }
}
