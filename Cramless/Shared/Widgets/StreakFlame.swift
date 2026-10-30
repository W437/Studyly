import SwiftUI

/// The streak's flame, drawn in code, in the stage the streak has reached (`StreakStage`):
/// - **spark** (1 to 6 days): a small flame;
/// - **week** (7 to 29): the full flame, a bright heart in it;
/// - **month** (30 to 99): the same, with a warm glow and a couple of embers;
/// - **hundred** (100 to 364): gold, with glints;
/// - **year** (365 and more): gold, a wider glow, and a star over the tip.
///
/// A flame that is not lit (no streak, or today not done where the place wants to say so) is an outline. It is square and
/// takes `size`; it is decoration, so it hides from VoiceOver (the text beside it says the number).
///
/// `bounce` is a counter: each change plays one bounce, the flame squashing and springing from its base. Leave it nil where
/// nothing should move (Reduce Motion, and widgets).
struct StreakFlame: View {
    var stage: StreakStage
    var size: CGFloat
    var lit = true
    var bounce: Int?

    var body: some View {
        FlameArt(stage: stage, lit: lit && stage != .none, size: size)
            .frame(width: size, height: size)
            .modifier(FlameBounce(trigger: bounce))
            .accessibilityHidden(true)
    }
}

// MARK: - Bounce

private struct FlameBounce: ViewModifier {
    var trigger: Int?

    private struct Pulse {
        var squash = 1.0
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let trigger {
            content.keyframeAnimator(initialValue: Pulse(), trigger: trigger) { view, pulse in
                view.scaleEffect(x: 1 / sqrt(pulse.squash), y: pulse.squash, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack(\.squash) {
                    SpringKeyframe(0.84, duration: 0.10, spring: .snappy)
                    SpringKeyframe(1.16, duration: 0.18, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.40, spring: .bouncy)
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Art

/// What a stage looks like: colours bottom to top for each part, and what is drawn around the flame.
private struct FlameStyle {
    var outer: [Gradient.Stop]
    var inner: [Gradient.Stop]
    var core: [Gradient.Stop]?
    /// A soft glow behind the flame: its colour and how far it spreads (as a share of the frame's half width).
    var glow: (color: Color, spread: Double)?
    /// The flame's footprint: 1 is full size, a spark is smaller and stands on the same base.
    var scale: Double = 1
    var embers = false
    var glints: [(x: Double, y: Double, r: Double, color: Color)] = []
    var star = false

    private static func stops(_ colors: [(Double, UInt32)]) -> [Gradient.Stop] {
        colors.map { Gradient.Stop(color: Color(hex: $0.1), location: $0.0) }
    }

    private static let warmOuter = stops([(0, 0xFF6A0F), (0.55, 0xFF8A1F), (1, 0xFFB02E)])
    private static let warmInner = stops([(0, 0xFFB02E), (1, 0xFFE27A)])
    private static let warmCore = stops([(0, 0xFFE27A), (1, 0xFFF6D6)])
    private static let brightOuter = stops([(0, 0xFF7A1A), (0.5, 0xFFA21F), (1, 0xFFD24A)])
    private static let brightInner = stops([(0, 0xFFC53D), (1, 0xFFF0A8)])
    private static let goldOuter = stops([(0, 0xD98A00), (0.5, 0xF5B320), (1, 0xFFE48A)])
    private static let goldInner = stops([(0, 0xF5B320), (1, 0xFFF3C2)])
    private static let goldCore = stops([(0, 0xFFE48A), (1, 0xFFFFFF)])

    init(_ stage: StreakStage) {
        switch stage {
        case .none, .spark:
            outer = Self.warmOuter
            inner = Self.warmInner
            scale = 0.72
        case .week:
            outer = Self.warmOuter
            inner = Self.warmInner
            core = Self.warmCore
        case .month:
            outer = Self.brightOuter
            inner = Self.brightInner
            core = Self.warmCore
            glow = (Color(hex: 0xFFB02E).opacity(0.55), 0.46)
            embers = true
        case .hundred:
            outer = Self.goldOuter
            inner = Self.goldInner
            core = Self.goldCore
            glow = (Color(hex: 0xFFD76A).opacity(0.65), 0.5)
            glints = [(84, 20, 9, Color(hex: 0xFFF6D6)), (15, 34, 6, Color(hex: 0xFFF6D6))]
        case .year:
            outer = Self.goldOuter
            inner = Self.goldInner
            core = Self.goldCore
            glow = (Color(hex: 0xFFD76A).opacity(0.7), 0.54)
            glints = [(86, 24, 10, .white), (13, 36, 7, Color(hex: 0xFFF6D6))]
            star = true
        }
    }
}

/// The three parts of the flame, as paths in a 100 by 100 box (an SVG's commands, so they can be drawn and redrawn in a
/// design tool): the outer flame with its two tips, the lighter flame inside it and the bright heart.
private enum FlamePaths {
    static let outer = "M50 96 C27 96 13 79 13 61 C13 46 24 38 30 25 C33 32 37 36 41 37 C39 24 43 11 55 3 C54 17 65 27 73 39 C81 51 87 59 87 67 C87 83 73 96 50 96 Z"
    static let inner = "M50 91 C38 91 30 82 30 72 C30 63 37 58 42 48 C45 55 48 58 51 58 C53 52 56 48 61 43 C65 53 70 62 70 73 C70 83 62 91 50 91 Z"
    static let core = "M50 91 C43 91 39 85 39 79 C39 73 44 70 47 65 C49 68 51 70 53 70 C55 67 57 65 60 62 C62 68 63 72 63 78 C63 85 57 91 50 91 Z"

    /// What the drawing is mapped from: the 100 by 100 box with room around it for the glints and the star.
    static let box = CGRect(x: -6, y: -12, width: 112, height: 112)

    /// Draws the commands (M, C and Z only) into `rect`, shrunk by `scale` about the flame's base.
    static func path(_ commands: String, in rect: CGRect, scale: Double) -> Path {
        var path = Path()
        var numbers: [Double] = []
        var command: Character = "M"
        func map(_ x: Double, _ y: Double) -> CGPoint {
            // The footprint shrinks toward the bottom middle of the 100 by 100 box.
            let sx = 50 + (x - 50) * scale
            let sy = 96 + (y - 96) * scale
            return CGPoint(x: rect.minX + (sx - box.minX) / box.width * rect.width,
                           y: rect.minY + (sy - box.minY) / box.height * rect.height)
        }
        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: map(numbers[0], numbers[1]))
            case "C" where numbers.count >= 6:
                path.addCurve(to: map(numbers[4], numbers[5]), control1: map(numbers[0], numbers[1]),
                              control2: map(numbers[2], numbers[3]))
            default: break
            }
            numbers = []
        }
        var token = ""
        for ch in commands + " " {
            if ch.isLetter {
                if !token.isEmpty, let n = Double(token) { numbers.append(n) }
                token = ""
                flush()
                command = ch
                if ch == "Z" { path.closeSubpath() }
            } else if ch == " " {
                if !token.isEmpty, let n = Double(token) { numbers.append(n) }
                token = ""
            } else {
                token.append(ch)
            }
        }
        flush()
        return path
    }

    /// A four-point glint of radius `r` around (`x`, `y`) in the box's units.
    static func glint(x: Double, y: Double, r: Double, in rect: CGRect) -> Path {
        func p(_ dx: Double, _ dy: Double) -> CGPoint {
            CGPoint(x: rect.minX + (x + dx - box.minX) / box.width * rect.width,
                    y: rect.minY + (y + dy - box.minY) / box.height * rect.height)
        }
        var path = Path()
        path.move(to: p(0, -r))
        path.addQuadCurve(to: p(r, 0), control: p(r * 0.18, -r * 0.18))
        path.addQuadCurve(to: p(0, r), control: p(r * 0.18, r * 0.18))
        path.addQuadCurve(to: p(-r, 0), control: p(-r * 0.18, r * 0.18))
        path.addQuadCurve(to: p(0, -r), control: p(-r * 0.18, -r * 0.18))
        path.closeSubpath()
        return path
    }

    /// A five-point star of outer radius `r` around (`x`, `y`).
    static func star(x: Double, y: Double, r: Double, in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * .pi / 5
            let radius = i.isMultiple(of: 2) ? r : r * 0.45
            let point = CGPoint(x: rect.minX + (x + cos(angle) * radius - box.minX) / box.width * rect.width,
                                y: rect.minY + (y + sin(angle) * radius - box.minY) / box.height * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct FlameShape: Shape {
    var commands: String
    var scale: Double

    func path(in rect: CGRect) -> Path {
        FlamePaths.path(commands, in: rect, scale: scale)
    }
}

private struct FlameArt: View {
    let stage: StreakStage
    let lit: Bool
    let size: CGFloat

    var body: some View {
        let style = FlameStyle(stage)
        ZStack {
            if lit {
                if let glow = style.glow {
                    Ellipse()
                        .fill(RadialGradient(colors: [glow.color, glow.color.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: size * glow.spread))
                        .frame(width: size * 1.1, height: size * 1.1)
                        .offset(y: size * 0.02)
                }
                FlameShape(commands: FlamePaths.outer, scale: style.scale)
                    .fill(LinearGradient(stops: style.outer, startPoint: .bottom, endPoint: .top))
                FlameShape(commands: FlamePaths.inner, scale: style.scale)
                    .fill(LinearGradient(stops: style.inner, startPoint: .bottom, endPoint: .top))
                if let core = style.core {
                    FlameShape(commands: FlamePaths.core, scale: style.scale)
                        .fill(LinearGradient(stops: core, startPoint: .bottom, endPoint: .top))
                }
                Canvas { g, canvas in
                    let rect = CGRect(origin: .zero, size: canvas)
                    if style.embers {
                        for (x, y, r, color) in [(22.0, 30.0, 2.0, 0xFFB02E), (80.0, 22.0, 1.6, 0xFFCF3F)] as [(Double, Double, Double, UInt32)] {
                            let cx = rect.width * (x - FlamePaths.box.minX) / FlamePaths.box.width
                            let cy = rect.height * (y - FlamePaths.box.minY) / FlamePaths.box.height
                            let rr = rect.width * r / FlamePaths.box.width
                            g.fill(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: 2 * rr, height: 2 * rr)),
                                   with: .color(Color(hex: color)))
                        }
                    }
                    for glint in style.glints {
                        g.fill(FlamePaths.glint(x: glint.x, y: glint.y, r: glint.r, in: rect), with: .color(glint.color))
                    }
                    if style.star {
                        g.fill(FlamePaths.star(x: 55, y: -3, r: 7, in: rect), with: .color(Color(hex: 0xFFF3C2)))
                    }
                }
            } else {
                // Not lit: the same flame as a line.
                let line = max(1.2, size * 0.065)
                FlameShape(commands: FlamePaths.outer, scale: style.scale)
                    .stroke(CLColor.ink3, style: StrokeStyle(lineWidth: line, lineJoin: .round))
                FlameShape(commands: FlamePaths.inner, scale: style.scale)
                    .stroke(CLColor.ink4, style: StrokeStyle(lineWidth: line * 0.8, lineJoin: .round))
            }
        }
    }
}
